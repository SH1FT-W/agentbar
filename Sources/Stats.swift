import Foundation
import Darwin

/// Tagesstatistik: zählt die Usage-Zeilen aller lokalen Sitzungen je Kalendertag (lokale Zeit), Projekt und Modell.
/// Eigene Queue. Der Stand liegt samt Leseposition je Datei in stats.json – nach einem Neustart wird nur Neues
/// gelesen, nichts doppelt gezählt. Beim ersten Start werden die letzten 30 Tage gekappt nachgeholt.
final class StatsCollector: @unchecked Sendable {
    /// Neue Tagesliste (letzte 30 Tage, ältester zuerst) – wird auf dem Main-Thread aufgerufen.
    var publish: (([DayStats]) -> Void)?

    private struct FileProgress: Codable {
        var offset: UInt64 = 0
        var born: Double = 0                  // Anlage der Datei; ältere Nachrichten sind Kopien (Fortsetzen/Abzweigen)
        var cwd: String?
        var recent: [String: [Int]] = [:]     // letzte message.ids → schon gezählte Tokens (eine Zeile je Inhaltsblock)
        var order: [String] = []
    }
    private struct Saved: Codable {
        var v = 1
        var days: [DayStats]
        var sessions: [String: [String]]
        var files: [String: FileProgress]
    }

    private let queue = DispatchQueue(label: "agentbar.stats", qos: .utility)
    private var days: [String: DayStats] = [:]
    private var daySessions: [String: Set<String>] = [:]
    private var files: [String: FileProgress] = [:]
    private var seenIds = Set<Int>()            // message.ids dieser Laufzeit (Hash) – gegen Doppelte über Dateigrenzen
    private var excluded = Set<String>()        // Sitzungen anderer Macs (geteiltes ~/.claude)
    private var pending: [URL] = []             // Start-Scan, eine Datei je Durchgang
    private var scanBudget: UInt64 = 0
    private var saveScheduled = false, publishScheduled = false, dirty = false
    private var rootCache: [String: String] = [:]

    static let keepDays = 30
    static let fileTail: UInt64 = 32_000_000         // je Datei höchstens die letzten 32 MB nachholen
    static let scanBytes: UInt64 = 300_000_000       // Start-Scan insgesamt
    static let scanFiles = 400
    private static let url = Paths.support.appendingPathComponent("stats.json")
    private static let needles = [Data("\"usage\"".utf8), Data("\"type\":\"assistant\"".utf8)]

    init() { queue.async { [self] in load() } }

    // MARK: Schnittstelle (beliebiger Thread)

    /// Start-Scan über die Protokoll-Wurzeln (Dateien der letzten 30 Tage, neueste zuerst, gekappt).
    func start(roots: [URL]) {
        queue.asyncAfter(deadline: .now() + (readOnlyRun ? 0 : 5)) { [self] in
            pending = candidates(roots)
            scanBudget = Self.scanBytes
            publishSoon()
            scanNext()
        }
    }

    /// Eine Protokolldatei hat sich geändert.
    func touched(_ url: URL) {
        queue.async { [self] in ingest(url, tail: Self.fileTail) }
    }

    func exclude(_ ids: Set<String>) { queue.async { [self] in excluded = ids } }

    // MARK: Start-Scan

    private func candidates(_ roots: [URL]) -> [URL] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(Self.keepDays) * 86400)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        var found: [(URL, Date, UInt64)] = []
        var present = Set<String>()
        func consider(_ f: URL) {
            guard f.pathExtension == "jsonl", let v = try? f.resourceValues(forKeys: Set(keys)),
                  let m = v.contentModificationDate, m > cutoff else { return }
            present.insert(f.path)
            let size = UInt64(v.fileSize ?? 0)
            guard isLocal(f), size > (files[f.path]?.offset ?? 0) else { return }
            found.append((f, m, size))
        }
        for root in roots {
            for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)) ?? [] {
                for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? [] {
                    if item.pathExtension == "jsonl" { consider(item); continue }
                    let sub = item.appendingPathComponent("subagents")
                    for a in (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: keys)) ?? [] { consider(a) }
                }
            }
        }
        // Lesepositionen alter/gelöschter Dateien vergessen (ausgelagerte bleiben, sonst zählten sie später doppelt)
        files = files.filter { present.contains($0.key) }
        return found.sorted { $0.1 > $1.1 }.prefix(Self.scanFiles).map(\.0)
    }

    /// Eine Datei je Durchgang – Live-Änderungen dazwischen kommen nicht hinter den ganzen Scan.
    private func scanNext() {
        guard !pending.isEmpty, scanBudget > 0 else { pending = []; publishSoon(); return }
        let url = pending.removeFirst()
        scanBudget -= min(scanBudget, ingest(url, tail: min(Self.fileTail, scanBudget)))
        queue.async { [self] in scanNext() }
    }

    // MARK: Lesen

    /// Liest neue Zeilen ab der gemerkten Position. Rückgabe: gelesene Bytes.
    @discardableResult
    private func ingest(_ url: URL, tail: UInt64) -> UInt64 {
        let path = url.path
        guard let sid = sessionId(url), let fh = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        var p = files[path] ?? FileProgress(born: created(path).timeIntervalSince1970)
        // Neu geschrieben: lieber nichts als doppelt zählen
        if size < p.offset { p.offset = size; files[path] = p; return 0 }
        guard size > p.offset else { return 0 }
        var skipFirst = false
        if size - p.offset > tail { p.offset = size - tail; skipFirst = true }
        try? fh.seek(toOffset: p.offset)
        let start = p.offset
        var carry = Data(), pos = p.offset
        while pos < size {
            guard let block = try? fh.read(upToCount: Int(min(1 << 20, size - pos))), !block.isEmpty else { break }
            pos += UInt64(block.count)
            carry.append(block)
            guard let nl = carry.lastIndex(of: 0x0A) else { continue }
            let complete = carry[carry.startIndex...nl]
            p.offset += UInt64(complete.count)
            for line in complete.split(separator: 0x0A) where !line.isEmpty {
                if skipFirst { skipFirst = false; continue }
                guard Self.needles.allSatisfy({ line.range(of: $0) != nil }),
                      let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                count(j, &p, session: sid)
            }
            carry.removeSubrange(carry.startIndex...nl)
        }
        files[path] = p
        dirty = true
        saveSoon()
        publishSoon()
        return p.offset - start
    }

    private func count(_ j: [String: Any], _ p: inout FileProgress, session: String) {
        if let cwd = j["cwd"] as? String, !cwd.isEmpty { p.cwd = cwd }
        guard j["type"] as? String == "assistant", j["isApiErrorMessage"] as? Bool != true,
              let msg = j["message"] as? [String: Any], let id = msg["id"] as? String,
              let model = msg["model"] as? String, model != "<synthetic>",
              let u = msg["usage"] as? [String: Any] else { return }
        let ts = (j["timestamp"] as? String).flatMap(statsDate) ?? Date()
        if p.born > 0, ts.timeIntervalSince1970 < p.born - 120 { return }   // kopierte ältere Nachricht
        guard !excluded.contains(session) else { return }
        let t = TokenTally(input: u["input_tokens"] as? Int ?? 0, cacheWrite: u["cache_creation_input_tokens"] as? Int ?? 0,
                           cacheRead: u["cache_read_input_tokens"] as? Int ?? 0, output: u["output_tokens"] as? Int ?? 0)
        let before = p.recent[id].map { TokenTally(input: $0[0], cacheWrite: $0[1], cacheRead: $0[2], output: $0[3]) }
        if before == nil {
            guard seenIds.insert(id.hashValue).inserted else { return }   // schon in einer anderen Datei gezählt
            if seenIds.count > 300_000 { seenIds.removeAll() }
            p.order.append(id)
            if p.order.count > 16 { p.recent[p.order.removeFirst()] = nil }
        }
        p.recent[id] = [t.input, t.cacheWrite, t.cacheRead, t.output]
        let delta = t - (before ?? TokenTally())
        guard delta != TokenTally() else { return }
        let key = statsDayKey(ts)
        var d = days[key] ?? DayStats(day: key)
        d.tokens.input += delta.input; d.tokens.cacheWrite += delta.cacheWrite
        d.tokens.cacheRead += delta.cacheRead; d.tokens.output += delta.output
        d.cost += Pricing.cost(model: model, delta) ?? 0
        d.byProject[project(p.cwd), default: 0] += delta.total
        d.byModel[shortModel(model), default: 0] += delta.total
        if before == nil {
            daySessions[key, default: []].insert(session)
            d.sessions = daySessions[key]?.count ?? 0
        }
        days[key] = d
    }

    // MARK: Ausgabe & Speichern

    private var window: [DayStats] {
        let first = statsDayKey(Date().addingTimeInterval(-Double(Self.keepDays - 1) * 86400))
        return days.values.filter { $0.day >= first }.sorted { $0.day < $1.day }
    }

    private func publishSoon() {
        guard !publishScheduled else { return }
        publishScheduled = true
        queue.asyncAfter(deadline: .now() + 1) { [self] in
            publishScheduled = false
            let list = window
            DispatchQueue.main.async { self.publish?(list) }
        }
    }

    private func saveSoon() {
        guard !saveScheduled, !readOnlyRun else { return }
        saveScheduled = true
        queue.asyncAfter(deadline: .now() + 20) { [self] in
            saveScheduled = false
            save()
        }
    }

    /// Tage und Lesepositionen zusammen speichern – sonst würde nach einem Absturz doppelt oder gar nicht gezählt.
    private func save() {
        guard dirty, !readOnlyRun else { return }
        dirty = false
        let keep = window
        let keys = Set(keep.map(\.day))
        days = days.filter { keys.contains($0.key) }
        daySessions = daySessions.filter { keys.contains($0.key) }
        let out = Saved(days: keep, sessions: daySessions.mapValues { Array($0) }, files: files)
        guard let data = try? JSONEncoder().encode(out) else { return }
        try? data.write(to: Self.url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
    }

    private func load() {
        guard let d = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Saved.self, from: d), s.v == 1 else { return }
        for day in s.days { days[day.day] = day }
        daySessions = s.sessions.mapValues { Set($0) }
        files = s.files
        publishSoon()
    }

    // MARK: Hilfen

    /// Hauptsitzung einer Datei: <sitzung>.jsonl bzw. <sitzung>/subagents/<helfer>.jsonl
    private func sessionId(_ url: URL) -> String? {
        let dir = url.deletingLastPathComponent()
        let id = dir.lastPathComponent == "subagents" ? dir.deletingLastPathComponent().lastPathComponent : url.deletingPathExtension().lastPathComponent
        return id.isEmpty ? nil : id
    }

    /// Projektname wie in der Liste: Git-Wurzel des Arbeitsordners, im Home-Ordner „Home“.
    private func project(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "–" }
        if let hit = rootCache[cwd] { return hit }
        let home = NSHomeDirectory()
        var root = cwd
        if cwd.hasPrefix(home + "/") {
            var d = cwd
            while d.count > home.count {
                if FileManager.default.fileExists(atPath: d + "/.git") { root = d; break }
                d = (d as NSString).deletingLastPathComponent
            }
        }
        let name = root == home ? "Home" : URL(fileURLWithPath: root).lastPathComponent
        if rootCache.count > 500 { rootCache.removeAll() }
        rootCache[cwd] = name
        return name
    }

    private func isLocal(_ url: URL) -> Bool {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return false }
        return st.st_flags & UInt32(SF_DATALESS) == 0
    }

    private func created(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.creationDate] as? Date) ?? .distantPast
    }
}

/// "yyyy-MM-dd" in lokaler Zeit (wie StatsStore.key, aber ohne Main-Actor).
func statsDayKey(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

private let statsISOFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()
private func statsDate(_ s: String) -> Date? { statsISOFrac.date(from: s) ?? ISO8601DateFormatter().date(from: s) }
