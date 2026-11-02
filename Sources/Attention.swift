import Foundation
import Darwin

// MARK: - "Agent is waiting for you" notifications

/// Decides when a session that waits for the user (permission, question, finished answer, error) is worth a
/// notification. Pure logic, no UI: the caller feeds the current sessions on every update and on a timer.
///
/// Rules:
/// - A waiting state only notifies after `delay` seconds without interruption (no ping for short pauses).
/// - Once per waiting state: staying in it never notifies again; new content (another question, a new
///   answer) is a new state, flicker back to the reported content is not.
/// - The same state coming back after a short working blip (< `rearm`) counts as the same state.
/// - A session first seen while already waiting (app launch, rescan) is treated as already handled.
/// - "Done" right after "waiting" is the user's own reaction (denied, interrupted) and stays silent.
struct WaitGate {
    enum Kind: String { case waiting, done, error }

    struct Observation {
        var id: String
        /// nil = working; the session is not waiting for anyone
        var kind: Kind?
        /// Identifies the waiting state (question text, permission, last answer) for repeat suppression
        var key: String = ""
        /// Idle sessions neither start nor end a waiting state
        var neutral = false
    }

    private struct Entry {
        var kind: Kind?
        var key = ""
        var since = Date.distantPast
        var handled = true
        var leftAt: Date?
        var lastNotifiedKey: String?
    }

    var delay: TimeInterval = 20
    var rearm: TimeInterval = 10
    private var entries: [String: Entry] = [:]

    init(delay: TimeInterval = 20, rearm: TimeInterval = 10) {
        self.delay = delay
        self.rearm = rearm
    }

    /// Feeds the current sessions and returns the ids to notify now. Sessions missing from `list` are forgotten.
    mutating func update(_ list: [Observation], now: Date = Date()) -> [String] {
        var next: [String: Entry] = [:]
        var due: [String] = []
        for o in list where next[o.id] == nil {   // a duplicate id (same session from two Macs): first one counts
            guard var e = entries[o.id] else {
                // First sight: a session that already waits is not news
                next[o.id] = Entry(kind: o.neutral ? nil : o.kind, key: o.key, since: now, handled: true,
                                   lastNotifiedKey: o.kind == nil ? nil : o.key)
                continue
            }
            if o.neutral {
                // idle: keeps the state, but a still pending notification is stale by now (idle = over 5 minutes
                // without activity, e.g. after the Mac slept) and is dropped instead of firing late
                e.handled = true
            } else if let k = o.kind {
                if e.kind == nil {
                    let blip = e.leftAt.map { now.timeIntervalSince($0) < rearm } ?? false
                    let sameAsBefore = blip && e.lastNotifiedKey == o.key
                    e.kind = k
                    e.key = o.key
                    e.since = now
                    e.handled = sameAsBefore
                    e.leftAt = nil
                } else if e.kind == k, e.key != o.key {
                    // Same kind, new content without a visible working phase (second question, new answer):
                    // a new state once the old one was reported; flicker back to the reported one stays quiet
                    if e.handled { e.since = now }
                    e.handled = o.key == e.lastNotifiedKey
                    e.key = o.key
                } else if e.kind != k {
                    // Between waiting kinds without working: "done" after "waiting" is the user's own doing,
                    // an error is always news, "waiting" again (a second question) is a new state
                    let silent = k == .done && e.kind == .waiting
                    e.kind = k
                    e.key = o.key
                    e.since = now
                    e.handled = silent || e.handled && k == .done
                }
            } else if e.kind != nil {
                e.kind = nil
                e.leftAt = now
            }
            if e.kind != nil, !e.handled, now.timeIntervalSince(e.since) >= delay {
                e.handled = true
                e.lastNotifiedKey = e.key
                due.append(o.id)
            }
            next[o.id] = e
        }
        entries = next
        return due
    }

    /// When the next pending notification becomes due (for a one-shot timer), nil if nothing is pending.
    var nextDeadline: Date? {
        entries.values.filter { $0.kind != nil && !$0.handled }.map { $0.since.addingTimeInterval(delay) }.min()
    }
}

// MARK: - Usage warnings (5-hour and 7-day window)

/// Warns once per threshold and usage window. A window is identified by its reset time; the server's reset
/// time jitters a little between fetches, so resets less than 10 minutes apart count as the same window.
struct QuotaAlerts {
    enum Window: String, CaseIterable { case fiveHour = "5h", sevenDay = "7d" }

    struct Alert: Equatable {
        var window: Window
        var threshold: Double
        var percent: Double
    }

    /// Per window: reset time of the window and the thresholds already reported in it
    private(set) var fired: [Window: (reset: Double, thresholds: Set<Double>)] = [:]

    init(stored: [String: Any] = [:]) {
        for w in Window.allCases {
            guard let m = stored[w.rawValue] as? [String: Any], let r = m["r"] as? Double,
                  let t = m["t"] as? [Double] else { continue }
            fired[w] = (r, Set(t))
        }
    }

    /// For UserDefaults
    var stored: [String: Any] {
        var out: [String: Any] = [:]
        for (w, f) in fired { out[w.rawValue] = ["r": f.reset, "t": f.thresholds.sorted()] }
        return out
    }

    /// Returns at most one alert per window: the highest threshold newly crossed. Lower thresholds crossed in
    /// the same jump are marked as done as well, so 70 % → 96 % gives a single "96 %" warning.
    mutating func check(_ window: Window, percent: Double, resetsAt: Date?, thresholds: [Double]) -> Alert? {
        guard let reset = resetsAt?.timeIntervalSince1970 else { return nil }
        var f = fired[window] ?? (reset, [])
        if abs(f.reset - reset) >= 600 { f = (reset, []) }
        f.reset = reset
        let crossed = Set(thresholds.filter { $0 > 0 && $0 <= 100 && percent >= $0 })
        let fresh = crossed.subtracting(f.thresholds)
        f.thresholds.formUnion(crossed)
        fired[window] = f
        guard let top = fresh.max() else { return nil }
        return Alert(window: window, threshold: top, percent: percent)
    }
}

// MARK: - Terminal of a session

/// Finds the terminal app and tty of a Claude process from the process tree – used when no hook has reported them.
enum TerminalProcess {
    /// "/Applications/iTerm.app/Contents/MacOS/iTerm2" → "/Applications/iTerm.app". Takes the outermost app,
    /// so a helper inside an app (VS Code's "Code Helper.app") resolves to the app itself.
    static func appBundlePath(fromExecutable path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }

    /// Controlling terminal of a process as "/dev/ttys003", nil without one.
    static func tty(of pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { return nil }
        return ttyPath(dev_t(bitPattern: info.e_tdev))
    }

    static func ttyPath(_ dev: dev_t) -> String? {
        guard dev != -1, dev != 0, let name = devname(dev, S_IFCHR) else { return nil }
        let s = String(cString: name)
        guard s.range(of: #"^ttys?[0-9]{1,4}$"#, options: .regularExpression) != nil else { return nil }
        return "/dev/" + s
    }

    static func startTime(of pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    /// Parent pid via sysctl: unlike proc_pidinfo this also works for processes of other users
    /// (the chain to Terminal.app runs through /usr/bin/login, which belongs to root).
    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// Bundle id of the first app among the ancestors of `pid` (Terminal, iTerm2, Ghostty, VS Code …).
    static func hostApp(of pid: pid_t) -> String? {
        var p = pid
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for _ in 0..<16 {
            guard p > 1, let parent = parent(of: p), parent > 1 else { return nil }
            if proc_pidpath(parent, &path, UInt32(path.count)) > 0,
               let app = appBundlePath(fromExecutable: String(cString: path)) {
                return Bundle(path: app)?.bundleIdentifier
            }
            p = parent
        }
        return nil
    }
}

// MARK: - Scripts that bring a terminal tab to the front

enum TerminalScripts {
    static let terminal = "com.apple.Terminal"
    static let iTerm = "com.googlecode.iterm2"
    static let ghostty = "com.mitchellh.ghostty"

    /// Only harmless tty names reach a script.
    static func cleanTTY(_ tty: String?) -> String? {
        guard let tty else { return nil }
        let dev = tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
        return dev.range(of: #"^/dev/ttys?[0-9]{1,4}$"#, options: .regularExpression) != nil ? dev : nil
    }

    /// AppleScript string literal; nil for text with control characters (cwd comes from logs).
    static func quoted(_ s: String) -> String? {
        guard !s.isEmpty, !s.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Script that selects the session's tab and returns true, or nil if this terminal can't be targeted.
    /// Terminal.app and iTerm2 match the tty. Ghostty has no tty in its dictionary: it matches the working
    /// directory and only acts if exactly one terminal is there (rather no jump than the wrong tab).
    static func focus(bundle: String, tty: String?, cwd: String) -> String? {
        switch bundle {
        case terminal:
            guard let dev = cleanTTY(tty) else { return nil }
            return """
            tell application id "\(terminal)"
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
        case iTerm:
            guard let dev = cleanTTY(tty) else { return nil }
            return """
            tell application id "\(iTerm)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(dev)" then
                                select w
                                tell t to select
                                tell s to select
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        case ghostty:
            guard cwd.hasPrefix("/"), let dir = quoted(cwd) else { return nil }
            return """
            tell application id "\(ghostty)"
                set hits to (every terminal whose working directory is \(dir))
                if (count of hits) is not 1 then return false
                focus (item 1 of hits)
                activate
                return true
            end tell
            """
        default:
            return nil
        }
    }
}
