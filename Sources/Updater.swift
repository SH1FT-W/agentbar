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

    struct Release { let version: String; let zip: URL; let signature: URL }

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            Task { await self?.check(silent: true) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(silent: true) }
        }
    }

    // MARK: Prüfen

    func check(silent: Bool = false) async {
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
            case 403, 429: throw Fail("GitHub-Abfragelimit erreicht – später nochmal")
            case let c: throw Fail("GitHub antwortet mit \(c)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Fail("Unerwartete Antwort") }
            let tag = String((json["tag_name"] as? String ?? "").drop(while: { $0 == "v" }))
            guard tag.range(of: #"^[0-9]+(\.[0-9]+){0,3}$"#, options: .regularExpression) != nil else { throw Fail("Ungültige Versionsnummer") }
            let assets = json["assets"] as? [[String: Any]] ?? []
            func asset(_ name: String) -> URL? {
                guard let s = assets.first(where: { $0["name"] as? String == name })?["browser_download_url"] as? String,
                      let u = URL(string: s), u.scheme == "https", u.host == "github.com" else { return nil }
                return u
            }
            guard let zip = asset("AgentBar.zip"), let sig = asset("AgentBar.zip.sig") else { throw Fail("Release ohne AgentBar.zip/.sig") }
            if Self.isNewer(tag, than: AppInfo.version) {
                release = Release(version: tag, zip: zip, signature: sig)
                state = .available(version: tag, notes: (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                release = nil
                state = .upToDate
            }
        } catch {
            let msg = (error as? Fail)?.text ?? "GitHub nicht erreichbar"
            if silent { state = .idle } else { state = .failed(msg) }
        }
    }

    // MARK: Installieren

    func install() async {
        guard let release else { return }
        state = .installing("Lade v\(release.version) …")
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("AgentBar-Update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zipData = try await Self.download(release.zip)
            let sigText = String(decoding: try await Self.download(release.signature), as: UTF8.self)

            state = .installing("Prüfe …")
            guard let key = Data(base64Encoded: Self.publicKey).flatMap({ try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }),
                  let sig = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  key.isValidSignature(sig, for: zipData) else {
                throw Fail("Signatur des Updates stimmt nicht – verworfen")
            }

            let zipURL = work.appendingPathComponent("AgentBar.zip")
            try zipData.write(to: zipURL)
            guard Self.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, work.path]) else { throw Fail("Entpacken fehlgeschlagen") }
            let newApp = work.appendingPathComponent("AgentBar.app")
            let b = Bundle(url: newApp)
            guard b?.bundleIdentifier == Bundle.main.bundleIdentifier else { throw Fail("Falsche App im Release") }
            guard b?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.version else {
                throw Fail("Versionsnummer passt nicht zum Release")
            }
            try Self.verifySignature(newApp)
            // Erst nach bestandener Prüfung die Quarantäne entfernen
            _ = Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            state = .installing("Starte neu …")
            try launchSwapScript(newApp: newApp, work: work)
            NSApp.terminate(nil)
        } catch {
            let msg = (error as? Fail)?.text ?? error.localizedDescription
            state = .failed("Update fehlgeschlagen: \(msg)")
        }
    }

    /// Gültige (ad-hoc-)Code-Signatur – die Echtheit sichert die Ed25519-Prüfung oben.
    private static func verifySignature(_ app: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw Fail("Signatur nicht lesbar") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { throw Fail("Code-Signatur ungültig – Update verworfen") }
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

    private static func run(_ tool: String, _ args: [String]) -> Bool {
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
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Fail("Download fehlgeschlagen") }
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

    private struct Fail: Error { let text: String; init(_ t: String) { text = t } }
}
