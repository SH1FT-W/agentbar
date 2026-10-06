import AppKit
import CryptoKit
import Security

/// Updates aus den GitHub-Releases von SH1FT-W/agentbar (öffentlich, ohne Anmeldung).
/// Installiert wird nur, wenn die Ed25519-Signatur mit dem fest einkompilierten Schlüssel stimmt – so kann selbst
/// ein fremdes Release im Repo nichts einschleusen. Dazu Prüfsumme, Bundle-ID, Version und gültige Code-Signatur.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String, notes: String)
        case installing(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    static let repo = "SH1FT-W/agentbar"
    /// Öffentlicher Teil des Release-Schlüssels (tools/release-key.swift). Der private Teil liegt nie im Repo.
    static let publicKey = "TBkvdyuhlknBwhMjJ0a6/oQVPp6ZOATnqaHcHm62P8M="
    private var release: Release?
    private var timer: Timer?
    /// Meldet eine neu gefundene Version (je Version nur einmal, auch über Neustarts hinweg).
    var onFound: ((String) -> Void)?
    /// Beim Start gefunden und nicht übersprungen → Fenster mit „Jetzt installieren / Später“ zeigen.
    var onLaunchFound: ((String) -> Void)?

    struct Release { let version: String; let zip: URL; let signature: URL }

    init() {
        // Kurz nach dem Start nachsehen – findet sich etwas, fragt ein Fenster statt nur einer Mitteilung
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            Task { await self?.check(silent: true, launch: true) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(silent: true) }
        }
    }

    #if SNAPSHOT
    func demo(_ s: State) { state = s }
    #endif

    // MARK: Prüfen

    func check(silent: Bool = false, launch: Bool = false) async {
        if case .installing = state { return }
        if case .available = state, silent { return }
        state = .checking
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!, timeoutInterval: 20)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("AgentBar/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: break
            case 404: release = nil; state = .upToDate; return
            case 403, 429: throw Fail(L("GitHub-Abfragelimit erreicht – später nochmal", "GitHub rate limit reached – try again later"))
            case let c: throw Fail(L("GitHub antwortet mit \(c)", "GitHub responded with \(c)"))
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Fail(L("Unerwartete Antwort", "Unexpected response")) }
            let tag = String((json["tag_name"] as? String ?? "").drop(while: { $0 == "v" }))
            guard tag.range(of: #"^[0-9]+(\.[0-9]+){0,3}$"#, options: .regularExpression) != nil else { throw Fail(L("Ungültige Versionsnummer", "Invalid version number")) }
            let assets = json["assets"] as? [[String: Any]] ?? []
            func asset(_ name: String) -> URL? {
                guard let s = assets.first(where: { $0["name"] as? String == name })?["browser_download_url"] as? String,
                      let u = URL(string: s), u.scheme == "https", u.host == "github.com" else { return nil }
                return u
            }
            guard let zip = asset("AgentBar.zip"), let sig = asset("AgentBar.zip.sig") else { throw Fail(L("Release ohne AgentBar.zip/.sig", "Release without AgentBar.zip/.sig")) }
            if Self.isNewer(tag, than: AppInfo.version) {
                release = Release(version: tag, zip: zip, signature: sig)
                state = .available(version: tag, notes: (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                let d = UserDefaults.standard
                if d.string(forKey: Prefs.updateSkipped) == tag {
                    // Übersprungen: weder Fenster noch Mitteilung, im Menü bleibt der Eintrag
                } else if launch {
                    d.set(tag, forKey: "updateNotified")
                    onLaunchFound?(tag)
                } else if d.string(forKey: "updateNotified") != tag {
                    d.set(tag, forKey: "updateNotified")
                    onFound?(tag)
                }
            } else {
                release = nil
                state = .upToDate
            }
        } catch {
            let msg = (error as? Fail)?.text ?? L("GitHub nicht erreichbar", "Can’t reach GitHub")
            if silent { state = .idle } else { state = .failed(msg) }
        }
    }

    // MARK: Installieren

    func install() async {
        // Nur einmal gleichzeitig (Menü und Einstellungen haben beide einen Knopf)
        guard let release else { return }
        if case .installing = state { return }
        // Ziel muss ersetzbar sein – sonst endet jeder Versuch in derselben Schleife (z. B. Start aus „Downloads“ mit
        // App-Translocation oder von einem schreibgeschützten Volume)
        if let problem = Self.targetProblem(Bundle.main.bundleURL) {
            state = .failed(problem)
            return
        }
        state = .installing(L("Lade v\(release.version) …", "Downloading v\(release.version)…"))
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("AgentBar-Update-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zipData = try await Self.download(release.zip)
            let sigText = String(decoding: try await Self.download(release.signature), as: UTF8.self)

            state = .installing(L("Prüfe …", "Verifying…"))
            guard let key = Data(base64Encoded: Self.publicKey).flatMap({ try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }),
                  let sig = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  key.isValidSignature(sig, for: zipData) else {
                throw Fail(L("Signatur des Updates stimmt nicht – verworfen", "Update signature doesn’t match – discarded"))
            }

            let zipURL = work.appendingPathComponent("AgentBar.zip")
            let newApp = work.appendingPathComponent("AgentBar.app")
            let bundleID = Bundle.main.bundleIdentifier, version = release.version
            // Entpacken und Signaturprüfung dauern – nicht auf dem Main-Thread
            try await Task.detached(priority: .userInitiated) {
                try zipData.write(to: zipURL)
                guard Self.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, work.path]) else { throw Fail(L("Entpacken fehlgeschlagen", "Unzipping failed")) }
                let b = Bundle(url: newApp)
                guard b?.bundleIdentifier == bundleID else { throw Fail(L("Falsche App im Release", "Wrong app in release")) }
                guard b?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
                    throw Fail(L("Versionsnummer passt nicht zum Release", "Version number doesn’t match the release"))
                }
                try Self.verifySignature(newApp)
                // Erst nach bestandener Prüfung die Quarantäne entfernen
                _ = Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
            }.value
            if let problem = Self.targetProblem(Bundle.main.bundleURL) { throw Fail(problem) }

            state = .installing(L("Starte neu …", "Relaunching…"))
            try launchSwapScript(newApp: newApp, work: work)
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: work)
            let msg = (error as? Fail)?.text ?? error.localizedDescription
            state = .failed(L("Update fehlgeschlagen", "Update failed") + ": \(msg)")
        }
    }

    /// nil = AgentBar.app lässt sich an ihrem Ort ersetzen; sonst ein verständlicher Hinweis.
    nonisolated static func targetProblem(_ app: URL) -> String? {
        let move = L("Bitte AgentBar in den Ordner „Programme“ ziehen, von dort öffnen und das Update dann erneut starten.",
                     "Please move AgentBar to the Applications folder, open it from there and start the update again.")
        if app.path.contains("/AppTranslocation/") {
            return L("AgentBar läuft aus einem vorübergehenden Ort (macOS-Schutz für geladene Apps).", "AgentBar is running from a temporary location (macOS app translocation).") + " " + move
        }
        let fm = FileManager.default
        if !fm.isWritableFile(atPath: app.deletingLastPathComponent().path) || !fm.isWritableFile(atPath: app.path) {
            return L("Der Ordner mit AgentBar ist nicht beschreibbar.", "The folder containing AgentBar isn’t writable.") + " " + move
        }
        return nil
    }

    /// Gültige (ad-hoc-)Code-Signatur – die Echtheit sichert die Ed25519-Prüfung oben.
    nonisolated private static func verifySignature(_ app: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw Fail(L("Signatur nicht lesbar", "Can’t read signature")) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { throw Fail(L("Code-Signatur ungültig – Update verworfen", "Invalid code signature – update discarded")) }
    }

    /// Statisches Skript, Pfade nur als Argumente – nichts wird in den Skripttext eingesetzt.
    private func launchSwapScript(newApp: URL, work: URL) throws {
        let script = work.appendingPathComponent("swap.sh")
        let body = #"""
        #!/bin/zsh
        # $1 = PID der alten App, $2 = Ziel (.app), $3 = neue App, $4 = Arbeitsordner
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        OLD="$2.alt"
        rm -rf "$OLD"
        if mv "$2" "$OLD" && mv "$3" "$2"; then
            rm -rf "$OLD"
        else
            [[ -d "$OLD" && ! -d "$2" ]] && mv "$OLD" "$2"
        fi
        open "$2"
        rm -rf "$4"
        """#
        try body.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path, newApp.path, work.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }

    // MARK: Hilfen

    nonisolated private static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func download(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.setValue("AgentBar/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Fail(L("Download fehlgeschlagen", "Download failed")) }
        return data
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private struct Fail: Error, Sendable { let text: String; init(_ t: String) { text = t } }
}
