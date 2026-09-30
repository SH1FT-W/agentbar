import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt
import UserNotifications

// MARK: - Claude-Code-Hooks (präzise Erkennung)

/// Trägt kleine Hook-Befehle in ~/.claude/settings.json ein. Jeder Befehl hängt das Ereignis als eine Zeile an
/// ~/Library/Application Support/AgentBar/hooks.log – kein Netzwerk, kein Prozess von AgentBar, läuft auch ohne die App.
/// Damit weiß AgentBar exakt, wann Claude auf eine Freigabe wartet oder fertig ist (statt aus Pausen zu raten).
enum Hooks {
    static let marker = "agentbar-hook"
    static let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "Notification", "PermissionRequest", "Stop", "SubagentStart", "SubagentStop", "PreCompact"]
    /// Eine Zeile je Ereignis: Zeit, App, TTY, Claude-PID und nur die nötigen JSON-Felder (keine Prompts, keine Befehle,
    /// keine Dateiinhalte). Ein einziges printf = ein write(), damit sich parallele Hooks nicht vermischen.
    /// Datei nur für den eigenen Benutzer (umask 077) und nie größer als 5 MB – auch wenn AgentBar gelöscht wurde.
    static let command = #"d="$HOME/Library/Application Support/AgentBar"; f="$d/hooks.log"; if [ -d "$d" ] && [ "$(stat -f%z "$f" 2>/dev/null || echo 0)" -lt 5000000 ]; then umask 077; printf '%s\t%s\t%s\t%s\t{%s}\n' "$(date +%s)" "$(printf %s "$__CFBundleIdentifier" | tr -cd 'A-Za-z0-9.-')" "$(ps -o tty= -p $PPID 2>/dev/null | tr -cd 'a-z0-9')" "$PPID" "$(head -c 65536 | tr -d '\n' | grep -oE '"(session_id|hook_event_name|tool_name|notification_type|message|cwd|file_path|description|subagent_type)" *: *"[^"\\]{0,200}"' | paste -sd, -)" >> "$f"; fi; cat >/dev/null; true # "# + marker

    static var installed: Bool {
        guard let s = try? String(contentsOf: Paths.claudeSettings, encoding: .utf8) else { return false }
        return s.contains(marker)
    }

    static func install() throws { try edit(add: true) }
    static func uninstall() throws { try edit(add: false) }

    private static func edit(add: Bool) throws {
        let fm = FileManager.default
        let url = Paths.claudeSettings
        var root: [String: Any] = [:]
        var perms: Any?
        var stamp: Date?
        // Nur bei wirklich fehlender Datei leer anfangen – jeder Lesefehler (z. B. iCloud offline) bricht ab,
        // sonst würden alle anderen Einstellungen überschrieben.
        if fm.fileExists(atPath: url.path) {
            let d = try Data(contentsOf: url)
            guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                throw NSError(domain: "AgentBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json ist kein JSON-Objekt"])
            }
            root = j
            let attrs = try fm.attributesOfItem(atPath: url.path)
            perms = attrs[.posixPermissions]
            stamp = attrs[.modificationDate] as? Date
            // Sicherung nur einmal: das ist der Stand vor AgentBar
            let backup = url.deletingLastPathComponent().appendingPathComponent("settings.json.agentbar-backup")
            if !fm.fileExists(atPath: backup.path) {
                try d.write(to: backup)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // Zuerst eigene Einträge entfernen (idempotent) – fremde Gruppen bleiben unangetastet
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { g in
                let inner = g["hooks"] as? [[String: Any]] ?? []
                let mine = inner.filter { (($0["command"] as? String) ?? "").contains(marker) }
                guard !mine.isEmpty else { return g }
                var g = g
                let rest = inner.filter { !(($0["command"] as? String) ?? "").contains(marker) }
                if rest.isEmpty { return nil }
                g["hooks"] = rest
                return g
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        if add {
            for event in events {
                var groups = hooks[event] as? [[String: Any]] ?? []
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
                hooks[event] = groups
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        // Hat Claude Code die Datei inzwischen selbst geändert? Dann lieber abbrechen als dessen Änderung überschreiben.
        if let stamp, let now = try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, now != stamp {
            throw NSError(domain: "AgentBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "settings.json wurde gerade geändert – bitte nochmal versuchen"])
        }
        try out.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: perms ?? 0o600], ofItemAtPath: url.path)
    }
}

// MARK: - Kontingent (5-Stunden-Fenster, Woche)

struct QuotaWindow: Equatable {
    var percent: Double
    var resetsAt: Date?
}

@MainActor
final class QuotaMonitor: ObservableObject {
    @Published private(set) var session: QuotaWindow?
    @Published private(set) var weekly: QuotaWindow?
    @Published private(set) var weeklyOpus: QuotaWindow?
    @Published private(set) var plan: String?
    @Published private(set) var problem: String?
    @Published private(set) var lastFetch: Date?
    @Published private(set) var loading = false
    var onThreshold: ((Double) -> Void)?

    private var timer: Timer?
    private var notifiedWindow: Date?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    func refreshIfStale() {
        if (lastFetch.map { Date().timeIntervalSince($0) > 45 } ?? true) { Task { await refresh() } }
    }

    func refresh() async {
        guard UserDefaults.standard.bool(forKey: Prefs.quotaEnabled), !loading else { return }
        loading = true
        defer { loading = false }
        // Token nur lesen, nie erneuern: ein Refresh würde Claude Codes eigenen Refresh-Token ungültig machen können.
        guard let creds = await Task.detached(operation: { Self.readCredentials() }).value else {
            problem = "Kein Claude-Code-Login im Schlüsselbund gefunden"
            return
        }
        if let exp = creds.expires, exp < Date() {
            problem = "Anmeldung abgelaufen – Claude Code einmal benutzen, dann aktualisiert es sich"
            return
        }
        do {
            let json = try await get("https://api.anthropic.com/api/oauth/usage", token: creds.token)
            session = window(json["five_hour"])
            weekly = window(json["seven_day"])
            weeklyOpus = window(json["seven_day_opus"])
            problem = nil
            lastFetch = Date()
            if plan == nil, let acc = try? await get("https://api.anthropic.com/api/oauth/account", token: creds.token) {
                plan = Self.planName(acc)
            }
            checkThreshold()
        } catch {
            problem = (error as NSError).code == 401 ? "Anmeldung abgelaufen – Claude Code einmal benutzen" : "Kontingent nicht abrufbar (\(error.localizedDescription))"
        }
    }

    private func checkThreshold() {
        guard let s = session, let reset = s.resetsAt else { return }
        let limit = UserDefaults.standard.double(forKey: Prefs.quotaThreshold)
        let window = Date(timeIntervalSince1970: (reset.timeIntervalSince1970 / 60).rounded() * 60)   // Server-Zeit schwankt im Sub-Sekundenbereich
        if s.percent >= limit, notifiedWindow != window {
            notifiedWindow = window
            onThreshold?(s.percent)
        }
    }

    private func window(_ any: Any?) -> QuotaWindow? {
        guard let d = any as? [String: Any], let u = d["utilization"] as? Double else { return nil }
        return QuotaWindow(percent: u, resetsAt: (d["resets_at"] as? String).flatMap(parseISO))
    }

    private func get(_ url: String, token: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func planName(_ acc: [String: Any]) -> String? {
        for m in acc["memberships"] as? [[String: Any]] ?? [] {
            guard let org = m["organization"] as? [String: Any], let tier = org["rate_limit_tier"] as? String else { continue }
            if tier.contains("max_20x") { return "Max 20×" }
            if tier.contains("max_5x") { return "Max 5×" }
            if tier.contains("max") { return "Max" }
            if tier.contains("team") { return "Team" }
            if tier.contains("pro") { return "Pro" }
        }
        return nil
    }

    /// Über das security-Werkzeug lesen: Claude Code hat es in der Zugriffsliste seines Eintrags,
    /// dadurch gibt es keine Schlüsselbund-Abfrage bei jedem Rebuild dieser (ad-hoc signierten) App.
    nonisolated private static func readCredentials() -> (token: String, expires: Date?)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = j["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        let exp = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return (token, exp)
    }
}

private func parseISO(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}

func resetText(_ date: Date?) -> String {
    guard let date else { return "" }
    let s = Int(date.timeIntervalSinceNow)
    if s <= 0 { return "gleich neu" }
    if s < 3600 { return "neu in \(s / 60) Min." }
    if s < 86400 { return "neu in \(s / 3600):\(String(format: "%02d", (s % 3600) / 60)) Std." }
    let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEEE, HH:mm"
    return "neu am \(f.string(from: date))"
}

// MARK: - Mitteilungen

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((String) -> Void)?

    override init() {
        super.init()
        guard Bundle.main.bundleIdentifier != nil else { return }   // ohne App-Bundle (Snapshot) stürzt UNUserNotificationCenter ab
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, sessionId: String?, sound: Bool = true) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        if let sessionId { content.userInfo = ["session": sessionId]; content.threadIdentifier = sessionId }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["session"] as? String {
            DispatchQueue.main.async { self.onOpen?(id) }
        }
        completionHandler()
    }
}

// MARK: - Wach bleiben

final class KeepAwake {
    private var assertion: IOPMAssertionID = 0
    private(set) var active = false

    func update(mode: KeepAwakeMode, agentsWorking: Bool) {
        let want = mode == .always || (mode == .auto && agentsWorking)
        guard want != active else { return }
        if want {
            active = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "AgentBar: Agenten arbeiten" as CFString, &assertion) == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertion)
            active = false
        }
    }
}

// MARK: - Globales Tastenkürzel (⌃⌥A = Büro ein/aus; ⌥⇧A wäre auf deutscher Tastatur „Å“)

final class HotKey {
    private var ref: EventHotKeyRef?
    private static var action: (() -> Void)?

    init(action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4147_4254), id: 1)   // "AGBT"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(optionKey | controlKey), id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("AgentBar: Tastenkürzel ⌃⌥A ist belegt (\(status))") }
    }
}

// MARK: - Zur Sitzung springen

enum Focus {
    static let claudeApp = "com.anthropic.claudefordesktop"

    static func open(_ s: AgentSession) {
        if s.hostBundle == "com.apple.Terminal", let tty = s.tty, selectTerminalTab(tty) { return }
        if let b = s.hostBundle, !b.isEmpty, activate(bundle: b) { return }
        if s.source == .desktop || s.source == .cowork, activate(bundle: claudeApp, launch: true) { return }
        if s.source == .xcode, activate(bundle: "com.apple.dt.Xcode") { return }
        if activate(bundle: "com.apple.Terminal") { return }
        showInFinder(s.cwd)
    }

    /// Nur echte Ordner – cwd stammt aus Protokollen; eine .app oder .command dürfte sonst gestartet werden.
    static func isFolder(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
            && !["app", "command", "tool", "sh"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    static func showInFinder(_ path: String) {
        guard isFolder(path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @discardableResult
    static func activate(bundle: String, launch: Bool = false) -> Bool {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            return app.activate()
        }
        guard launch, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    /// Holt genau das Terminal-Fenster/den Tab nach vorn, in dem die Sitzung läuft.
    private static func selectTerminalTab(_ tty: String) -> Bool {
        let clean = tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
        // Doppelt abgesichert: schon beim Einlesen geprüft, hier nochmal nur harmlose Zeichen
        guard clean.range(of: #"^/dev/ttys?[0-9]{1,4}$"#, options: .regularExpression) != nil else { return false }
        let dev = clean
        let src = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(dev)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        var err: NSDictionary?
        let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return r?.booleanValue == true
    }

    static func openTerminal(at path: String) {
        guard isFolder(path), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
