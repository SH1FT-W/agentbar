import AppKit

/// Updates aus den GitHub-Releases von SH1FT-W/agentbar (öffentlich, ohne Anmeldung).
/// Installiert wird nur, wenn die Ed25519-Signatur mit dem fest einkompilierten Schlüssel stimmt, so kann selbst
/// ein fremdes Release im Repo nichts einschleusen. Dazu Bundle-ID, Version und gültige Code-Signatur.
/// Die Schritte selbst (Laden, Prüfen, Tauschen) liegen in Shared/Sources/UpdateCore.swift.
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
    nonisolated static let appName = "AgentBar"
    /// Öffentlicher Teil des Release-Schlüssels (Shared/tools/release-key.swift). Der private Teil liegt nie im Repo.
    static let publicKey = "TBkvdyuhlknBwhMjJ0a6/oQVPp6ZOATnqaHcHm62P8M="
    private var release: Release?
    private var timer: Timer?
    /// Meldet eine neu gefundene Version (je Version nur einmal, auch über Neustarts hinweg).
    var onFound: ((String) -> Void)?
    /// Beim Start gefunden und nicht übersprungen → Fenster mit „Jetzt installieren / Später“ zeigen.
    var onLaunchFound: ((String) -> Void)?

    struct Release { let version: String; let zip: URL; let signature: URL }

    private var userAgent: String { "AgentBar/\(AppInfo.version)" }

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
            let (data, http) = try await UpdateCore.fetchLatestRelease(repo: Self.repo, userAgent: userAgent)
            switch http?.statusCode ?? 0 {
            case 200: break
            case 404: release = nil; state = .upToDate; return
            case 403, 429: throw UpdateError(L("GitHub-Abfragelimit erreicht – später nochmal", "GitHub rate limit reached – try again later"))
            case let c: throw UpdateError(L("GitHub antwortet mit \(c)", "GitHub responded with \(c)"))
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UpdateError(L("Unerwartete Antwort", "Unexpected response")) }
            let found = try GitHubRelease(json: json)
            guard let zip = found.downloadURL("AgentBar.zip"), let sig = found.downloadURL("AgentBar.zip.sig") else {
                throw UpdateError(L("Release ohne AgentBar.zip/.sig", "Release without AgentBar.zip/.sig"))
            }
            let tag = found.version
            if UpdateCore.isNewer(tag, than: AppInfo.version) {
                release = Release(version: tag, zip: zip, signature: sig)
                state = .available(version: tag, notes: found.notes)
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
            let msg = (error as? UpdateError)?.text ?? L("GitHub nicht erreichbar", "Can’t reach GitHub")
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
            let zipData = try await UpdateCore.download(release.zip, userAgent: userAgent)
            let sigText = String(decoding: try await UpdateCore.download(release.signature, userAgent: userAgent), as: UTF8.self)

            state = .installing(L("Prüfe …", "Verifying…"))
            try UpdateCore.verifyEd25519(zipData, signatureText: sigText, publicKey: Self.publicKey)
            // Entpacken, Bundle-ID, Version, Code-Signatur; Quarantäne erst nach bestandener Prüfung weg
            let newApp = try await UpdateCore.unpackAndVerify(zip: zipData, in: work, appName: Self.appName,
                                                              bundleID: Bundle.main.bundleIdentifier ?? "", version: release.version)
            if let problem = Self.targetProblem(Bundle.main.bundleURL) { throw UpdateError(problem) }

            state = .installing(L("Starte neu …", "Relaunching…"))
            try UpdateCore.launchSwapScript(target: Bundle.main.bundleURL, newApp: newApp, work: work)
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: work)
            let msg = (error as? UpdateError)?.text ?? error.localizedDescription
            state = .failed(L("Update fehlgeschlagen", "Update failed") + ": \(msg)")
        }
    }

    /// nil = AgentBar.app lässt sich an ihrem Ort ersetzen; sonst ein verständlicher Hinweis.
    nonisolated static func targetProblem(_ app: URL) -> String? {
        UpdateCore.targetProblem(app, appName: appName, requireWritable: true)
    }
}
