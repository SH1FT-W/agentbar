import Foundation
import CoreServices
import Darwin

/// Liest die Sitzungs-Protokolle von Claude Code (JSONL) und – falls eingerichtet – die Hook-Ereignisse
/// und macht daraus eine Liste von Agenten mit Status. Alles Datei-IO läuft auf einer eigenen Queue.
@MainActor
final class SessionMonitor: ObservableObject {
    @Published fileprivate(set) var sessions: [AgentSession] = []
    @Published private(set) var hooksSeen = false
    /// Wird bei jedem Statuswechsel einer Hauptsitzung aufgerufen (für Mitteilungen).
    var onTransition: ((AgentSession, AgentStatus) -> Void)?

    private let core = MonitorCore()
    private var tick: Timer?

    init() {
        core.publish = { [weak self] list, hooks in
            Task { @MainActor in self?.apply(list, hooks: hooks) }
        }
        core.start()
        // Zeitabhängige Übergänge (arbeitet → wartet, fertig → Pause) auch ohne neue Dateien
        tick = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.core.recompute()
        }
    }

    func rescan() { core.fullScan() }

    private var previous: [String: AgentStatus] = [:]

    private func apply(_ list: [AgentSession], hooks: Bool) {
        if hooksSeen != hooks { hooksSeen = hooks }
        let first = previous.isEmpty && sessions.isEmpty
        for s in list {
            if let old = previous[s.id], old != s.status, !first { onTransition?(s, old) }
            previous[s.id] = s.status
        }
        if list != sessions { sessions = list }
    }

    var visible: [AgentSession] {
        let hours = UserDefaults.standard.double(forKey: Prefs.visibleHours)
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        return sessions.filter { $0.status < .done || $0.lastActivity > cutoff }
    }

    var waitingCount: Int { sessions.filter { $0.status == .waiting }.count }
    var workingCount: Int { sessions.filter { $0.status == .working }.count }
}

// MARK: - Zustand je Datei

private final class FileState {
    var offset: UInt64 = 0
    var skipPartial = false                  // Start mitten in der Datei: erste (angeschnittene) Zeile verwerfen
    var sessionId = ""
    var projectDir = ""
    var source = SessionSource.cli
    var isSubagent = false
    var parentId: String?
    var agentType = ""
    var agentDescription = ""

    var lastEvent = Date.distantPast        // Zeitstempel des letzten Ereignisses
    var lastType = ""
    var toolPending = false                  // letzte Assistant-Nachricht hat ein Werkzeug aufgerufen
    var toolName = ""
    var toolActivity = ""
    var toolTime: Date?
    var thinking = false
    var interrupted = false
    var apiError = false
    var aiTitle: String?
    var customTitle: String?
    var model = ""
    var mode = "default"
    var cwd: String?
    var lastText = ""
    var usage: [String: (model: String, tally: TokenTally)] = [:]   // je message.id – Claude schreibt pro Inhaltsblock eine Zeile mit derselben usage
    private(set) var tokens: [String: TokenTally] = [:]             // laufende Summe je Modell

    func setUsage(_ id: String, model: String, _ t: TokenTally) {
        if let old = usage[id] { tokens[old.model] = (tokens[old.model] ?? TokenTally()) - old.tally }
        usage[id] = (model, t)
        tokens[model] = (tokens[model] ?? TokenTally()) + t
    }
}

private struct HookState {
    var event = ""
    var time = Date.distantPast
    var notification = ""
    var activity = ""
    var tool = ""
    var bundle: String?
    var tty: String?
    var cwd: String?
    var pid: pid_t = 0
    var ended = false
    var childBaseline: Int?        // Zahl der Kindprozesse beim Beginn des Wartens
}

// MARK: - Kern (läuft auf eigener Queue)

private final class MonitorCore: @unchecked Sendable {
    var publish: (([AgentSession], Bool) -> Void)?

    private let queue = DispatchQueue(label: "agentbar.monitor", qos: .utility)
    private var stream: FSEventStreamRef?
    private var files: [String: FileState] = [:]          // Pfad → Zustand
    private var hooks: [String: HookState] = [:]          // session_id → letzter Hook
    private var hookOffset: UInt64 = 0
    private var desktopMeta: [String: (title: String, open: Bool)] = [:]
    private var lastFullScan = Date.distantPast
    private var pendingPaths = Set<String>()
    private var flushScheduled = false

    private var roots: [(URL, SessionSource)] = []
    private var allowed: [String] = []        // permissions.allow aus ~/.claude/settings.json (für die Schätzung ohne Hooks)

    private func refreshRoots() {
        roots = [(Paths.claudeProjects, .cli), (Paths.xcodeProjects, .xcode)] + coworkRoots().map { ($0, .cowork) }
        if let d = try? Data(contentsOf: Paths.claudeSettings),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let perms = j["permissions"] as? [String: Any] {
            allowed = perms["allow"] as? [String] ?? []
        }
    }

    func start() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        queue.async { [self] in
            refreshRoots()
            // Alte Hook-Zeilen überspringen, aber die letzten 256 KB für den aktuellen Stand lesen
            let size = (try? FileManager.default.attributesOfItem(atPath: Paths.hookLog.path)[.size] as? UInt64) ?? 0
            hookOffset = size > 262_144 ? size - 262_144 : 0
            readHooks(skipPartialFirstLine: hookOffset > 0)
            // Nur für den eigenen Benutzer lesbar (ältere Versionen legten die Datei mit 0644 an)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Paths.support.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.hookLog.path)
            try? FileManager.default.removeItem(at: Paths.support.appendingPathComponent("hooks.old.log"))
            fullScan(sync: true)
            startEvents()
        }
    }

    func fullScan() { queue.async { [self] in fullScan(sync: true) } }
    func recompute() {
        queue.async { [self] in
            if Date().timeIntervalSince(lastFullScan) > 60 { fullScan(sync: true) } else { emit() }
        }
    }

    // MARK: FSEvents

    private func startEvents() {
        let paths = ([Paths.claudeProjects, Paths.xcodeProjects, Paths.desktopMeta, Paths.coworkRoot, Paths.support]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)) as CFArray
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
            guard let info else { return }
            let me = Unmanaged<MonitorCore>.fromOpaque(info).takeUnretainedValue()
            let arr = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as NSArray
            me.changed(arr.compactMap { $0 as? String })
        }
        guard let s = FSEventStreamCreate(nil, cb, &ctx, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                          UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer))
        else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    private func changed(_ paths: [String]) {
        pendingPaths.formUnion(paths)
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + 0.25) { [self] in
            flushScheduled = false
            let batch = pendingPaths; pendingPaths.removeAll()
            var dirty = false
            for p in batch {
                if p == Paths.hookLog.path { readHooks(skipPartialFirstLine: false); dirty = true }
                else if p.hasSuffix(".jsonl") {
                    let url = URL(fileURLWithPath: p)
                    // Nur aktuelle, lokal vorhandene Dateien – sonst lädt iCloud ausgelagerte Alt-Sitzungen herunter
                    if files[p] != nil || (mtime(url) > scanCutoff && isLocal(url)), track(url) { dirty = true }
                }
                else if p.hasPrefix(Paths.desktopMeta.path) && p.hasSuffix(".json") { loadDesktopMeta(); dirty = true }
            }
            if dirty { emit() }
        }
    }

    // MARK: Scan

    private var scanCutoff: Date {
        Date().addingTimeInterval(-max(UserDefaults.standard.double(forKey: Prefs.visibleHours), 1) * 3600)
    }

    /// iCloud kann Dateien auslagern („dataless“) – die nicht anfassen, Lesen würde einen Download auslösen.
    private func isLocal(_ url: URL) -> Bool {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return false }
        return st.st_flags & UInt32(SF_DATALESS) == 0
    }

    private func fullScan(sync: Bool) {
        lastFullScan = Date()
        refreshRoots()
        loadDesktopMeta()
        let fm = FileManager.default
        let cutoff = scanCutoff
        var alive = Set<String>()
        for (root, _) in roots {
            guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for dir in dirs where isDir(dir) {
                // Nur Projektordner anfassen, die kürzlich geändert wurden (Ordner-mtime ändert sich bei neuen Dateien,
                // bei laufenden Sitzungen reicht das nicht – deshalb Dateien selbst prüfen, aber billig per Attribut)
                guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) else { continue }
                for item in items {
                    if item.pathExtension == "jsonl", mtime(item) > cutoff, isLocal(item) {
                        alive.insert(item.path)
                        track(item)
                    } else if isDir(item) {
                        let sub = item.appendingPathComponent("subagents")
                        guard let agents = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                        for a in agents where a.pathExtension == "jsonl" && mtime(a) > Date().addingTimeInterval(-1800) && isLocal(a) {
                            alive.insert(a.path)
                            track(a)
                        }
                    }
                }
            }
        }
        if ProcessInfo.processInfo.environment["AGENTBAR_DEBUG"] != nil { FileHandle.standardError.write("scan roots=\(roots.map(\.0.path)) alive=\(alive.count) files=\(files.count)\n".data(using: .utf8)!) }
        for key in files.keys where !alive.contains(key) { files.removeValue(forKey: key) }
        emit()
    }

    private func isDir(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func mtime(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Datei aufnehmen (falls neu) und neue Zeilen lesen. true = etwas hat sich geändert.
    @discardableResult
    private func track(_ url: URL) -> Bool {
        let path = url.path
        let st: FileState
        if let existing = files[path] {
            st = existing
            if st.isSubagent, st.agentType.isEmpty { loadAgentMeta(url, st) }   // .meta.json entsteht manchmal knapp nach der JSONL
        } else {
            guard let (source, projectDir) = classify(url) else { return false }
            st = FileState()
            st.source = source
            st.projectDir = projectDir
            if url.deletingLastPathComponent().lastPathComponent == "subagents" {
                st.isSubagent = true
                st.parentId = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                st.sessionId = url.deletingPathExtension().lastPathComponent
                loadAgentMeta(url, st)
            } else {
                st.sessionId = url.deletingPathExtension().lastPathComponent
            }
            // Riesige Protokolle (100 MB+) nur ab den letzten 8 MB lesen – Status und Titel stehen am Ende,
            // Token-Summen zählen dann ab dort.
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
            if size > Self.tailLimit { st.offset = size - Self.tailLimit; st.skipPartial = true }
            files[path] = st
        }
        return readNewLines(url, st)
    }

    static let tailLimit: UInt64 = 8_000_000

    private func loadAgentMeta(_ url: URL, _ st: FileState) {
        let meta = url.deletingPathExtension().appendingPathExtension("meta.json")
        if let d = try? Data(contentsOf: meta), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            st.agentType = j["agentType"] as? String ?? ""
            st.agentDescription = j["description"] as? String ?? ""
        }
    }

    private func classify(_ url: URL) -> (SessionSource, String)? {
        let p = url.resolvingSymlinksInPath().path     // /private/tmp ↔ /tmp, iCloud-Symlink usw. einheitlich
        for (root, source) in roots {
            let r = root.resolvingSymlinksInPath().path
            guard p.hasPrefix(r + "/") else { continue }
            let rest = p.dropFirst(r.count + 1)
            guard let dir = rest.split(separator: "/").first else { return nil }
            return (source, String(dir))
        }
        return nil
    }

    // MARK: JSONL

    private func readNewLines(_ url: URL, _ st: FileState) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        if size < st.offset { st.offset = 0 }             // Datei neu geschrieben
        guard size > st.offset else { return false }
        try? fh.seek(toOffset: st.offset)
        guard let data = try? fh.readToEnd(), let nl = data.lastIndex(of: 0x0A) else { return false }
        let complete = data[data.startIndex...nl]
        st.offset += UInt64(complete.count)
        var changed = false
        var lines = complete.split(separator: 0x0A)
        if st.skipPartial, !lines.isEmpty { lines.removeFirst(); st.skipPartial = false }
        for line in lines where !line.isEmpty {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            process(j, st)
            changed = true
        }
        return changed
    }

    private func process(_ j: [String: Any], _ st: FileState) {
        guard let type = j["type"] as? String else { return }
        if let cwd = j["cwd"] as? String, !cwd.isEmpty { st.cwd = cwd }
        switch type {
        case "ai-title":
            if let t = j["aiTitle"] as? String ?? j["title"] as? String, !t.isEmpty { st.aiTitle = t }
            return
        case "custom-title":
            if let t = j["customTitle"] as? String ?? j["title"] as? String, !t.isEmpty { st.customTitle = t }
            return
        case "permission-mode":
            if let m = j["permissionMode"] as? String { st.mode = m }
            return
        case "assistant", "user", "system":
            break
        default:
            return
        }
        let ts = (j["timestamp"] as? String).flatMap(parseDate) ?? Date()
        if ts > st.lastEvent { st.lastEvent = ts }
        if let m = j["permissionMode"] as? String { st.mode = m }

        if type == "system" {
            if (j["level"] as? String) == "error" { st.apiError = true; st.lastType = "system" }
            return
        }

        let msg = j["message"] as? [String: Any] ?? [:]
        let content = msg["content"] as? [[String: Any]] ?? []

        if type == "user" {
            if j["isMeta"] as? Bool == true { return }
            // Slash-Befehle (/model, /mcp …) und !-Befehle erzeugen keine Antwort – nicht als „arbeitet“ werten
            let raw = (msg["content"] as? String) ?? (content.first?["text"] as? String) ?? ""
            if raw.hasPrefix("<command-name>") || raw.hasPrefix("<local-command-") || raw.hasPrefix("<bash-") || raw.hasPrefix("<command-message>") { return }
            st.lastType = "user"
            st.toolPending = false
            st.toolTime = nil
            st.thinking = false
            st.apiError = false
            let texts = content.compactMap { $0["text"] as? String } + [msg["content"] as? String].compactMap { $0 }
            st.interrupted = texts.contains { $0.hasPrefix("[Request interrupted") }
            return
        }

        // assistant
        if j["isApiErrorMessage"] as? Bool == true { st.apiError = true; st.lastType = "assistant"; st.toolPending = false; return }
        if let model = msg["model"] as? String, model != "<synthetic>" { st.model = model }
        if let id = msg["id"] as? String, let u = msg["usage"] as? [String: Any], !st.model.isEmpty {
            st.setUsage(id, model: st.model, TokenTally(
                input: u["input_tokens"] as? Int ?? 0,
                cacheWrite: u["cache_creation_input_tokens"] as? Int ?? 0,
                cacheRead: u["cache_read_input_tokens"] as? Int ?? 0,
                output: u["output_tokens"] as? Int ?? 0))
        }
        let kinds = Set(content.compactMap { $0["type"] as? String })
        st.interrupted = false
        st.apiError = false
        st.lastType = "assistant"
        if kinds == ["thinking"] || kinds == ["redacted_thinking"] {
            st.thinking = true
            st.toolPending = false
            return
        }
        st.thinking = false
        if let text = content.last(where: { $0["type"] as? String == "text" })?["text"] as? String, !text.isEmpty {
            st.lastText = preview(text)
        }
        if let tool = content.last(where: { $0["type"] as? String == "tool_use" }) {
            st.toolPending = true
            st.toolName = tool["name"] as? String ?? ""
            st.toolActivity = describeTool(st.toolName, tool["input"] as? [String: Any] ?? [:])
            st.toolTime = ts
        } else if kinds.contains("text") {
            st.toolPending = false
        }
        if (msg["stop_reason"] as? String) == "tool_use" { st.toolPending = true }
    }

    // MARK: Hooks

    private func readHooks(skipPartialFirstLine: Bool) {
        guard let fh = try? FileHandle(forReadingFrom: Paths.hookLog) else { return }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        if size < hookOffset { hookOffset = 0 }
        guard size > hookOffset else { return }
        try? fh.seek(toOffset: hookOffset)
        guard var data = try? fh.readToEnd(), let nl = data.lastIndex(of: 0x0A) else { return }
        data = data[data.startIndex...nl]
        hookOffset += UInt64(data.count)
        // Log klein halten: der Stand steckt jetzt in `hooks`, die Datei darf weg (der Hook legt sie neu an)
        if hookOffset > 1_000_000, hookOffset == size {
            try? FileManager.default.removeItem(at: Paths.hookLog)
            hookOffset = 0
        }
        var lines = data.split(separator: 0x0A)
        if skipPartialFirstLine, !lines.isEmpty { lines.removeFirst() }
        for line in lines {
            // Format: <epoch>\t<bundle-id>\t<tty>\t[<pid>\t]<json, evtl. auf 4 KB gekürzt>
            let parts = line.split(separator: 0x09, maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count >= 4, let epoch = Double(String(decoding: parts[0], as: UTF8.self)) else { continue }
            let hasPid = parts.count == 5
            let payload = String(decoding: parts[hasPid ? 4 : 3], as: UTF8.self)
            let j = (try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]) ?? Self.looseFields(payload)
            guard let sid = j["session_id"] as? String, let event = j["hook_event_name"] as? String else { continue }
            var h = hooks[sid] ?? HookState()
            let time = Date(timeIntervalSince1970: epoch)
            if time < h.time { continue }
            h.time = time
            h.event = event
            let bundle = String(decoding: parts[1], as: UTF8.self)
            let tty = String(decoding: parts[2], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            // Nur plausible Werte übernehmen – das tty landet später in einem AppleScript
            if bundle.range(of: #"^[A-Za-z0-9.-]{1,255}$"#, options: .regularExpression) != nil { h.bundle = bundle }
            if tty.range(of: #"^(/dev/)?ttys?[0-9]{1,4}$"#, options: .regularExpression) != nil { h.tty = tty }
            if hasPid, let pid = Int32(String(decoding: parts[3], as: UTF8.self)), pid > 1 { h.pid = pid }
            h.childBaseline = nil
            if let cwd = j["cwd"] as? String { h.cwd = cwd }
            h.ended = event == "SessionEnd"
            if event == "Notification" {
                h.notification = (j["notification_type"] as? String) ?? ((j["message"] as? String)?.lowercased().contains("permission") == true ? "permission_prompt" : "")
            } else {
                h.notification = ""
            }
            h.tool = event == "PreToolUse" ? (j["tool_name"] as? String ?? "") : ""
            if event == "PreToolUse", let tool = j["tool_name"] as? String {
                // Seit dem schlanken Hook stehen file_path/description direkt auf oberster Ebene
                h.activity = describeTool(tool, (j["tool_input"] as? [String: Any]) ?? j)
            } else if event == "UserPromptSubmit" {
                h.activity = L("Denkt nach …", "Thinking …")
            }
            hooks[sid] = h
        }
    }

    /// Notfall-Parser für gekürzte Hook-Zeilen: holt einfache String-Felder per Regex.
    static func looseFields(_ s: String) -> [String: Any] {
        var out: [String: Any] = [:]
        var input: [String: Any] = [:]
        for key in ["session_id", "hook_event_name", "tool_name", "notification_type", "message", "cwd",
                    "file_path", "command", "description", "subagent_type", "notebook_path"] {
            guard let r = s.range(of: "\"\(key)\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", options: .regularExpression) else { continue }
            let m = String(s[r])
            guard let q = m.range(of: ":\\s*\"", options: .regularExpression) else { continue }
            let v = String(m[q.upperBound...].dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: " ")
            if ["file_path", "command", "description", "subagent_type", "notebook_path"].contains(key) { input[key] = v } else { out[key] = v }
        }
        if !input.isEmpty { out["tool_input"] = input }
        return out
    }

    /// Läuft der Claude-Prozess noch? (Sitzungen ohne SessionEnd, z. B. Terminal hart geschlossen)
    private func alive(_ pid: pid_t) -> Bool { pid <= 1 || kill(pid, 0) == 0 || errno != ESRCH }

    /// Claude Code (ab ~2.1) meldet jeden laufenden Terminal-Prozess in ~/.claude/sessions/<pid>.json an und
    /// löscht die Datei beim Beenden. `complete` nur, wenn jede Datei lesbar ist; `unregistered` = Startzeiten
    /// lokaler claude-Prozesse ohne Anmeldung (ältere Versionen).
    private func sessionRegistry() -> (ids: Set<String>, complete: Bool, unregistered: [Date]) {
        let fm = FileManager.default
        var ids = Set<String>(), pids = Set<pid_t>(), complete = true
        guard let items = try? fm.contentsOfDirectory(at: Paths.claudeSessions, includingPropertiesForKeys: nil) else { return ([], false, []) }
        for f in items where f.pathExtension == "json" {
            if let pid = pid_t(f.deletingPathExtension().lastPathComponent) { pids.insert(pid) }
            guard isLocal(f), let d = try? Data(contentsOf: f),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let sid = j["sessionId"] as? String else { complete = false; continue }
            ids.insert(sid)
        }
        let unregistered = claudePids().filter { !pids.contains($0) }.compactMap(processStart)
        return (ids, complete, unregistered)
    }

    /// Nicht angemeldete Sitzungen, die noch laufen dürften: je alter Prozess die eine Sitzung, deren Datei kurz nach
    /// dem Prozessstart angelegt wurde. Passt das nicht eindeutig (z. B. --resume, /clear) → nil = alle behalten.
    private func unregisteredOwners(_ starts: [Date], _ candidates: [String: Date]) -> Set<String>? {
        var keep = Set<String>()
        for start in starts {
            let hits = candidates.filter { $0.value >= start.addingTimeInterval(-10) && $0.value <= start.addingTimeInterval(600) }
            guard hits.count == 1, let sid = hits.first?.key else { return nil }
            keep.insert(sid)
        }
        return keep
    }

    private func processStart(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    private func created(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.creationDate] as? Date) ?? .distantPast
    }

    private func claudePids() -> [pid_t] {
        var buf = [pid_t](repeating: 0, count: 4096)
        let n = Int(proc_listallpids(&buf, Int32(buf.count * MemoryLayout<pid_t>.size)))
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        // Native Installation: …/claude/versions/<version>; sonst heißt das Programm selbst „claude“
        return buf.prefix(max(0, n)).filter { pid in
            guard pid > 1, proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
            let p = String(cString: path)
            return p.contains("/claude/versions/") || (p as NSString).lastPathComponent == "claude"
        }
    }

    private func childCount(_ pid: pid_t) -> Int {
        guard pid > 1 else { return 0 }
        var buf = [pid_t](repeating: 0, count: 256)
        let n = proc_listchildpids(pid, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
        return max(0, Int(n))
    }

    // MARK: Status

    private func heuristicStatus(_ st: FileState, now: Date, hooksActive: Bool) -> AgentStatus {
        let age = now.timeIntervalSince(st.lastEvent)
        if st.apiError { return age > 300 ? .idle : .error }
        if st.interrupted || (st.lastType == "assistant" && !st.toolPending && !st.thinking) { return age > 300 ? .idle : .done }
        if st.toolPending, let t = st.toolTime {
            let since = now.timeIntervalSince(t)
            // Rückfragen warten, bis du antwortest (aber nicht ewig – nach 2 Std. ist die Sitzung wohl verlassen)
            if Self.askTools.contains(st.toolName) { return since > 7200 ? .idle : (since > 2 ? .waiting : .working) }
            if !hooksActive, !autoApproved(st.toolName, mode: st.mode), since > 8, age > 8 { return .waiting }
            // Laufendes Werkzeug (Build, Tests …) bis 30 Min. als „arbeitet“ werten
            return age > 1800 ? .idle : .working
        }
        return age > 300 ? .idle : .working
    }

    static let askTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    private func autoApproved(_ tool: String, mode: String) -> Bool {
        let safe: Set<String> = ["Read", "Glob", "Grep", "Agent", "Task", "TodoWrite", "LS", "ToolSearch", "Skill",
                                 "WebSearch", "BashOutput", "KillShell", "TaskOutput"]
        if safe.contains(tool) { return true }
        // Freigaben aus settings.json: "WebFetch", "mcp__server", "mcp__server__tool"; Bash(...)-Muster lassen sich ohne Befehl nicht prüfen
        if allowed.contains(where: { $0 == tool || (tool.hasPrefix("mcp__") && tool.hasPrefix($0 + "__")) || ($0.hasPrefix(tool + "(") && tool != "Bash") }) { return true }
        switch mode {
        case "auto", "bypassPermissions": return true
        case "acceptEdits": return ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(tool)
        default: return false
        }
    }

    private func emit() {
        let now = Date()
        var mains: [String: FileState] = [:]
        var mainPaths: [String: String] = [:]
        var subs: [String: [FileState]] = [:]
        for (path, st) in files {
            if st.isSubagent { if let p = st.parentId { subs[p, default: []].append(st) } }
            else { mains[st.sessionId] = st; mainPaths[st.sessionId] = path }
        }
        var out: [AgentSession] = []
        let registry = sessionRegistry()
        // Terminal-Sitzung ohne Anmeldung → Prozess beendet, außer ein alter (nicht anmeldender) Prozess gehört dazu
        var unregisteredKeep: Set<String>? = []
        if registry.complete, !registry.unregistered.isEmpty {
            var candidates: [String: Date] = [:]
            for (sid, st) in mains where st.source == .cli && !registry.ids.contains(sid) { candidates[sid] = created(mainPaths[sid] ?? "") }
            unregisteredKeep = unregisteredOwners(registry.unregistered, candidates)
        }
        for (sid, st) in mains {
            let h = hooks[sid]
            if h?.ended == true { continue }
            if let pid = h?.pid, !alive(pid) { continue }
            if st.source == .cli, registry.complete, let keep = unregisteredKeep, !registry.ids.contains(sid), !keep.contains(sid),
               now.timeIntervalSince(st.lastEvent) > 30 { continue }   // kurze Schonfrist für den Start
            let hooksActive = h != nil
            var status = heuristicStatus(st, now: now, hooksActive: hooksActive)
            var activity = st.thinking ? L("Denkt nach …", "Thinking …") : (st.toolPending ? st.toolActivity : "")
            var tool = st.thinking ? "thinking" : (st.toolPending ? st.toolName : "")
            if let h, h.time.addingTimeInterval(1.5) >= st.lastEvent {
                // Hook ist das jüngste Signal → genauer als die Schätzung
                let hookAge = now.timeIntervalSince(h.time)
                switch h.event {
                case "Notification" where h.notification == "permission_prompt", "PermissionRequest":
                    // Nach „Erlauben“ meldet sich Claude erst beim Ende des Werkzeugs. Startet der Befehl einen
                    // neuen Kindprozess (z. B. ein Build), ist die Freigabe erteilt → arbeitet.
                    let kids = childCount(h.pid)
                    let baseline = h.childBaseline ?? kids
                    if h.childBaseline == nil { hooks[sid]?.childBaseline = kids }
                    status = (h.pid > 1 && kids > baseline) ? .working : .waiting
                    if !h.activity.isEmpty { activity = h.activity }
                case "Notification" where h.notification == "idle_prompt", "Stop", "SessionStart":
                    status = hookAge > 300 ? .idle : .done
                case "StopFailure":
                    status = .error
                case "Notification":
                    break
                default:
                    status = hookAge > 1800 ? .idle : .working
                    if h.event == "PreToolUse" { activity = h.activity; tool = h.tool }
                    if h.event == "UserPromptSubmit" { activity = h.activity; tool = "thinking" }
                    if h.event == "PreToolUse", Self.askTools.contains(h.tool) { status = .waiting }
                }
            }
            if status != .working && status != .waiting { activity = "" }
            if status == .working && activity.isEmpty { activity = L("Arbeitet …", "Working …") }

            let helpers = (subs[sid] ?? []).map { a -> SubAgent in
                let age = now.timeIntervalSince(a.lastEvent)
                let finished = a.lastType == "assistant" && !a.toolPending && !a.thinking
                let working = !finished && age < 180
                return SubAgent(id: a.sessionId, type: a.agentType.isEmpty ? L("Helfer", "Helper") : a.agentType,
                                description: a.agentDescription, working: working,
                                activity: working ? (a.thinking ? L("Denkt nach …", "Thinking …") : a.toolActivity) : L("Fertig", "Done"),
                                lastActivity: a.lastEvent)
            }
            .filter { $0.working || now.timeIntervalSince($0.lastActivity) < 600 }
            .sorted { $0.lastActivity > $1.lastActivity }
            // Wartet die Hauptsitzung nur auf ihre Helfer, gilt sie als arbeitend
            if status == .done || status == .idle, helpers.contains(where: \.working), st.toolName == "Agent" || st.toolName == "Task" {
                status = .working
                let n = helpers.filter(\.working).count
                activity = L("Wartet auf \(n) Helfer", n == 1 ? "Waiting for 1 helper" : "Waiting for \(n) helpers")
                tool = "Agent"
            }

            var source = st.source
            var title = st.customTitle ?? st.aiTitle
            if let meta = desktopMeta[sid] {
                if meta.open { source = .desktop }
                if title == nil, !meta.title.isEmpty { title = meta.title }
            }
            var tokens = st.tokens
            for a in subs[sid] ?? [] { for (m, t) in a.tokens { tokens[m, default: TokenTally()] = tokens[m, default: TokenTally()] + t } }

            out.append(AgentSession(
                id: sid, source: source, cwd: st.cwd ?? h?.cwd ?? decodeProjectDir(st.projectDir),
                title: title, model: st.model, permissionMode: st.mode, status: status, activity: activity, tool: tool,
                lastText: st.lastText, lastActivity: max(st.lastEvent, h?.time ?? .distantPast),
                tokens: tokens, subagents: helpers, hostBundle: h?.bundle, tty: h?.tty, usesHooks: hooksActive))
        }
        out.sort { a, b in
            let ra = a.status == .idle ? 1 : 0, rb = b.status == .idle ? 1 : 0
            return ra != rb ? ra < rb : a.lastActivity > b.lastActivity
        }
        publish?(out, !hooks.isEmpty)
    }

    // MARK: Claude-App-Metadaten

    private func loadDesktopMeta() {
        let fm = FileManager.default
        var meta: [String: (title: String, open: Bool)] = [:]
        for user in (try? fm.contentsOfDirectory(at: Paths.desktopMeta, includingPropertiesForKeys: nil)) ?? [] {
            for win in (try? fm.contentsOfDirectory(at: user, includingPropertiesForKeys: nil)) ?? [] {
                for f in (try? fm.contentsOfDirectory(at: win, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" {
                    guard let d = try? Data(contentsOf: f),
                          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let id = j["cliSessionId"] as? String else { continue }
                    let open = !(j["isArchived"] as? Bool ?? true)
                    if meta[id] == nil || open { meta[id] = (j["title"] as? String ?? "", open) }
                }
            }
        }
        desktopMeta = meta
    }

    private func coworkRoots() -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for user in (try? fm.contentsOfDirectory(at: Paths.coworkRoot, includingPropertiesForKeys: nil)) ?? [] where user.hasDirectoryPath {
            for sess in (try? fm.contentsOfDirectory(at: user, includingPropertiesForKeys: nil)) ?? [] where sess.hasDirectoryPath {
                for local in (try? fm.contentsOfDirectory(at: sess, includingPropertiesForKeys: nil)) ?? [] where local.hasDirectoryPath {
                    let candidates = local.lastPathComponent == "agent"
                        ? ((try? fm.contentsOfDirectory(at: local, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("local_") }
                        : (local.lastPathComponent.hasPrefix("local_") ? [local] : [])
                    for c in candidates {
                        let p = c.appendingPathComponent(".claude/projects")
                        if fm.fileExists(atPath: p.path) { out.append(p) }
                    }
                }
            }
        }
        return out
    }
}

// MARK: - Hilfsfunktionen

private let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()
private let isoPlain = ISO8601DateFormatter()

private func parseDate(_ s: String) -> Date? { isoFrac.date(from: s) ?? isoPlain.date(from: s) }

/// "-Users-name-projekt" → "/Users/name/projekt" (verlustbehaftet, nur Notlösung ohne cwd)
private func decodeProjectDir(_ dir: String) -> String { dir.replacingOccurrences(of: "-", with: "/") }

private func preview(_ text: String) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: "#", with: "")
    return String(flat.trimmingCharacters(in: .whitespaces).prefix(240))
}

/// Macht aus einem Werkzeug-Aufruf einen kurzen deutschen Satz.
func describeTool(_ name: String, _ input: [String: Any]) -> String {
    func file(_ key: String = "file_path") -> String {
        (input[key] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
    }
    switch name {
    case "Bash":
        if let d = input["description"] as? String, !d.isEmpty { return d }
        let cmd = (input["command"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? ""
        return "Terminal: " + String(cmd.prefix(40))
    case "Edit", "MultiEdit": return L("Bearbeitet \(file())", "Editing \(file())")
    case "Write": return L("Schreibt \(file())", "Writing \(file())")
    case "Read": return L("Liest \(file())", "Reading \(file())")
    case "NotebookEdit": return L("Bearbeitet \(file("notebook_path"))", "Editing \(file("notebook_path"))")
    case "Grep", "Glob": return L("Durchsucht Code", "Searching code")
    case "WebFetch", "WebSearch": return L("Recherchiert im Web", "Researching the web")
    case "Agent", "Task":
        let t = input["subagent_type"] as? String ?? ""
        return t.isEmpty ? L("Delegiert an Helfer", "Delegating to a helper") : L("Delegiert an \(t)", "Delegating to \(t)")
    case "TodoWrite": return L("Plant nächste Schritte", "Planning next steps")
    case "Skill": return L("Lädt Skill", "Loading skill") + " \(input["skill"] as? String ?? "")"
    case "AskUserQuestion": return L("Hat eine Frage", "Has a question")
    case "ExitPlanMode": return L("Plan fertig", "Plan ready")
    default:
        if name.hasPrefix("mcp__") {
            let parts = name.components(separatedBy: "__")
            let server = parts.count > 1 ? parts[1].replacingOccurrences(of: "claude_ai_", with: "") : "MCP"
            return L("Nutzt \(server)", "Using \(server)")
        }
        return name
    }
}

#if SNAPSHOT
extension SessionMonitor {
    func inject(_ list: [AgentSession]) { sessions = list }
}
#endif
