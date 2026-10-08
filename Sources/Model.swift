import Foundation
import SwiftUI

// MARK: - Status

enum AgentStatus: Int, Comparable {
    case waiting    // braucht dich (Freigabe/Frage)
    case error
    case working
    case done       // Antwort fertig, wartet auf deine nächste Eingabe
    case idle       // länger nichts passiert

    static func < (a: AgentStatus, b: AgentStatus) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .waiting: return L("Braucht dich", "Needs you")
        case .error: return L("Fehler", "Error")
        case .working: return L("Arbeitet", "Working")
        case .done: return L("Fertig", "Done")
        case .idle: return L("Pause", "Idle")
        }
    }

    var symbol: String {
        switch self {
        case .waiting: return "hand.raised.fill"
        case .error: return "exclamationmark"
        case .working: return "ellipsis"
        case .done: return "checkmark"
        case .idle: return "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .waiting: return Color(nsColor: .systemOrange)
        case .error: return Color(nsColor: .systemRed)
        case .working: return .accentColor
        case .done: return Color(nsColor: .systemGreen)
        case .idle: return Color.primary.opacity(0.12)
        }
    }

    var glyph: Color { self == .idle ? .primary : .white }
}

enum SessionSource: String {
    case cli, desktop, cowork, xcode

    var label: String {
        switch self {
        case .cli: return "Terminal"
        case .desktop: return L("Claude-App", "Claude app")
        case .cowork: return "Cowork"
        case .xcode: return "Xcode"
        }
    }
}

// MARK: - Tokens & Kosten

struct TokenTally: Equatable {
    var input = 0, cacheWrite = 0, cacheRead = 0, output = 0
    var total: Int { input + cacheWrite + cacheRead + output }
    static func - (a: TokenTally, b: TokenTally) -> TokenTally {
        TokenTally(input: a.input - b.input, cacheWrite: a.cacheWrite - b.cacheWrite,
                   cacheRead: a.cacheRead - b.cacheRead, output: a.output - b.output)
    }
    static func + (a: TokenTally, b: TokenTally) -> TokenTally {
        TokenTally(input: a.input + b.input, cacheWrite: a.cacheWrite + b.cacheWrite,
                   cacheRead: a.cacheRead + b.cacheRead, output: a.output + b.output)
    }
}

/// API-Listenpreise (USD je 1 Mio. Tokens). Nur bekannte Modelle – unbekannte zeigen keine Kosten statt geratener Zahlen.
/// Anders als das Original: Cache-Lesen kostet 10 %, Cache-Schreiben 125 % – sonst sind die Werte um ein Vielfaches zu hoch.
enum Pricing {
    private static let table: [(match: String, input: Double, output: Double)] = [
        ("fable", 10, 50), ("mythos", 10, 50),
        ("opus-5-5", 4, 20), ("opus-5", 5, 25),
        ("opus-4-0", 15, 75), ("opus-4-1", 15, 75), ("claude-opus-4-2", 15, 75),
        ("opus-4", 5, 25),              // Opus 4.5 und neuer
        ("sonnet-5", 2, 10),            // Sonnet 5 und 5.5
        ("sonnet", 3, 15),
        ("haiku-4", 1, 5), ("haiku", 0.8, 4),
    ]

    static func cost(model: String, _ t: TokenTally) -> Double? {
        let m = model.lowercased()
        guard let p = table.first(where: { m.contains($0.match) }) else { return nil }
        let i = p.input / 1_000_000, o = p.output / 1_000_000
        return Double(t.input) * i + Double(t.cacheWrite) * i * 1.25 + Double(t.cacheRead) * i * 0.1 + Double(t.output) * o
    }
}

func shortModel(_ model: String) -> String {
    let m = model.lowercased()
    for name in ["fable", "opus", "sonnet", "haiku"] where m.contains(name) {
        // "claude-opus-5-5" → "Opus 5.5"
        let parts = m.components(separatedBy: "-").filter { Int($0) != nil && $0.count <= 2 }
        let version = parts.prefix(2).joined(separator: ".")
        return name.capitalized + (version.isEmpty ? "" : " \(version)")
    }
    return model.isEmpty ? "" : model
}

func modeLabel(_ mode: String) -> String? {
    switch mode {
    case "auto": return "Auto"
    case "acceptEdits": return L("Edits ok", "Edits OK")
    case "plan": return "Plan"
    case "bypassPermissions": return L("Ohne Rückfrage", "No prompts")
    default: return nil
    }
}

// MARK: - Sitzung (für die Oberfläche)

struct SubAgent: Identifiable, Equatable {
    let id: String
    var type: String
    var description: String
    var working: Bool
    var activity: String
    var lastActivity: Date
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var source: SessionSource
    var cwd: String
    var title: String?
    var model: String
    var permissionMode: String
    var status: AgentStatus
    var activity: String          // "Bearbeitet App.swift", "Denkt nach …"
    var tool: String              // Werkzeugname des laufenden Schritts ("Bash", "Edit", …) – für das Symbol im Büro
    var lastText: String          // letzte Antwort (Vorschau)
    var lastActivity: Date
    var tokens: [String: TokenTally]
    var subagents: [SubAgent]
    var hostBundle: String?       // App, in der die Sitzung läuft (aus den Hooks)
    var tty: String?
    var usesHooks: Bool
    var contextUsed = 0           // Token im Kontext (letzte Antwort der Hauptkette)
    var contextWindow = 0         // 200k oder 1M (abgeleitet), 0 = unbekannt
    var device: String?           // Name des anderen Macs, nil = läuft auf diesem Mac
    var deviceIsLaptop = false
    var question: String? = nil   // Fragetext, solange die Sitzung auf eine Antwort (AskUserQuestion) wartet

    var deviceSymbol: String { deviceIsLaptop ? "laptopcomputer" : "desktopcomputer" }

    var contextWindowText: String { contextWindow >= 1_000_000 ? L("1 Mio.", "1M") : "\(contextWindow / 1000)k" }

    /// Kontext-Füllstand 0…1, nil ohne Daten.
    var contextFill: Double? {
        guard contextWindow > 0 else { return nil }   // 0 % direkt nach dem Zusammenfassen
        return min(1, Double(contextUsed) / Double(contextWindow))
    }

    var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name == NSUserName() ? "Home" : name
    }
    /// Kurzname fürs Büro: Projektordner, ohne Projekt (nur im Home-Ordner) der gekürzte Sitzungstitel.
    var label: String {
        guard project == "Home", let t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return project }
        var out = ""
        for w in t.split(separator: " ") {
            let next = out.isEmpty ? String(w) : out + " " + w
            if next.count > 20 { break }
            out = next
        }
        if out.isEmpty { return String(t.prefix(19)) + "…" }
        return out.count < t.count ? out + "…" : out
    }
    var displayName: String {
        if let t = title, !t.isEmpty { return t }
        return project
    }
    var totalTokens: Int { tokens.values.reduce(0) { $0 + $1.total } + 0 }
    var cost: Double? {
        let c = tokens.compactMap { Pricing.cost(model: $0.key, $0.value) }
        return c.isEmpty ? nil : c.reduce(0, +)
    }
    var workingHelpers: Int { subagents.filter(\.working).count }
    /// Kontext fast voll (≥ 85 %) – Warnung in Zeile, Büro und Mitteilung.
    var contextWarning: Bool { (contextFill ?? 0) >= 0.85 }

    /// Fertiger Text, worauf eine wartende Sitzung wartet – ohne weiteres Präfix anzeigen.
    /// „Frage: <Text>“ bei AskUserQuestion, „Plan prüfen“ bei ExitPlanMode, sonst „Freigabe: <Tätigkeit>“. nil, wenn nicht wartend.
    var waitingReason: String? {
        guard status == .waiting else { return nil }
        if let q = question, !q.isEmpty { return L("Frage", "Question") + ": " + q }
        switch tool {
        case "AskUserQuestion": return L("Hat eine Frage", "Has a question")
        case "ExitPlanMode": return L("Plan prüfen", "Review the plan")
        default:
            let what = activity.isEmpty ? tool : activity
            return what.isEmpty ? L("Wartet auf deine Freigabe", "Waiting for your approval") : L("Freigabe", "Approve") + " · " + what
        }
    }
}

// MARK: - Statistik & Prognose (2.0)

/// Verbrauch eines Kalendertags (lokale Zeit), aus den Usage-Zeilen aller Sitzungen dieses Macs.
struct DayStats: Codable, Equatable, Identifiable {
    var day: String                       // "yyyy-MM-dd"
    var tokens = TokenCount()
    var cost: Double = 0                  // API-Gegenwert in USD (nur bekannte Modelle)
    var byProject: [String: Int] = [:]    // Projektname → Tokens
    var byModel: [String: Int] = [:]      // shortModel → Tokens
    var sessions = 0
    var id: String { day }
}

struct TokenCount: Codable, Equatable {
    var input = 0, cacheWrite = 0, cacheRead = 0, output = 0
    var total: Int { input + cacheWrite + cacheRead + output }
}

/// Wird von SessionMonitor gefüllt (Paket A), von Menü/Büro nur gelesen.
@MainActor
final class StatsStore: ObservableObject {
    /// Letzte 30 Tage, ältester zuerst, Tage ohne Verbrauch fehlen.
    @Published var days: [DayStats] = []
    var today: DayStats? { days.last { $0.day == StatsStore.key(Date()) } }
    func last(_ n: Int) -> [DayStats] {
        (0..<n).reversed().map { off in
            let k = StatsStore.key(Calendar.current.date(byAdding: .day, value: -off, to: Date())!)
            return days.first { $0.day == k } ?? DayStats(day: k)
        }
    }
    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

/// Hochrechnung für das 5-Stunden-Fenster aus den letzten Kontingent-Abrufen.
struct QuotaForecast: Equatable {
    var percentPerHour: Double
    var exhaustsAt: Date?                 // nil = reicht bis zum Reset
}

// MARK: - Einstellungen

enum KeepAwakeMode: String, CaseIterable, Identifiable {
    case off, auto, always
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return L("Aus", "Off")
        case .auto: return L("Wenn Agenten arbeiten", "While agents work")
        case .always: return L("Immer", "Always")
        }
    }
}

enum Prefs {
    static let notifyWaiting = "notifyWaiting"
    static let notifyDone = "notifyDone"
    static let notifyError = "notifyError"
    static let notifyQuota = "notifyQuota"
    static let notifyUpdate = "notifyUpdate"
    static let quotaThreshold = "quotaThreshold"
    static let notifyWhenFrontmost = "notifyWhenFrontmost"
    static let showCount = "menuShowCount"
    static let showQuota = "menuShowQuota"
    static let visibleHours = "visibleHours"
    static let officeFloating = "officeFloating"
    static let officeOpacity = "officeOpacity"
    static let officeDaylight = "officeDaylight"
    static let keepAwake = "keepAwake"
    static let quotaEnabled = "quotaEnabled"
    static let peersEnabled = "peersEnabled"
    static let peerCode = "peerCode"
    static let notifyContext = "notifyContext"
    static let notifyStalled = "notifyStalled"     // „hängt?“ – working ohne Ereignis > 10 Min.
    static let quietHours = "quietHours"           // Ruhezeiten an/aus
    static let quietFrom = "quietFrom"             // Stunde 0…23
    static let quietTo = "quietTo"
    static let updateSkipped = "updateSkipped"         // „Diese Version überspringen“ im Update-Fenster
    static let hookHintDismissed = "hookHintDismissed" // Karte „Präzise Erkennung“ im Menü weggeklickt
    static let notifyPeers = "notifyPeers"         // Mitteilungen auch für andere Macs
    static let weatherEnabled = "weatherEnabled"   // echtes Wetter hinter dem Glas (erst mit Ort)
    static let weatherPlace = "weatherPlace"       // Anzeigename des Orts
    static let weatherLat = "weatherLat"
    static let weatherLon = "weatherLon"
    static let weatherCache = "weatherCache"       // letztes Wetter (JSON), damit es nach dem Start sofort da ist

    static func register() {
        UserDefaults.standard.register(defaults: [
            notifyWaiting: true, notifyDone: true, notifyError: true, notifyQuota: true, notifyUpdate: true,
            quotaThreshold: 80.0, notifyWhenFrontmost: false,
            showCount: true, showQuota: false, visibleHours: 2.0,
            officeFloating: true, officeOpacity: 1.0, officeDaylight: true,
            keepAwake: KeepAwakeMode.off.rawValue, quotaEnabled: true, peersEnabled: false,
            notifyContext: true, notifyStalled: false, quietHours: false, quietFrom: 22, quietTo: 7, notifyPeers: false,
            weatherEnabled: false,
        ])
    }
}

// MARK: - Hilfen

enum Paths {
    static let home = URL(fileURLWithPath: NSHomeDirectory())
    /// ~/.claude kann ein Symlink sein (z. B. nach iCloud Drive) – FSEvents braucht den echten Pfad.
    static var claudeProjects: URL { home.appendingPathComponent(".claude/projects").resolvingSymlinksInPath() }
    static var claudeSessions: URL { home.appendingPathComponent(".claude/sessions").resolvingSymlinksInPath() }
    static var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json").resolvingSymlinksInPath() }
    static let xcodeProjects = home.appendingPathComponent("Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects")
    static let desktopMeta = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    static let coworkRoot = home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")
    static let support = home.appendingPathComponent("Library/Application Support/AgentBar")
    static let hookLog = support.appendingPathComponent("hooks.log")
}

func ago(_ date: Date?) -> String {
    guard let date, date > .distantPast else { return "–" }
    let s = Int(Date().timeIntervalSince(date))
    if s < 10 { return L("gerade eben", "just now") }
    if s < 60 { return L("vor \(s) Sek.", "\(s)s ago") }
    if s < 3600 { return L("vor \(s / 60) Min.", "\(s / 60)m ago") }
    if s < 86400 { return L("vor \(s / 3600) Std.", "\(s / 3600)h ago") }
    return L("vor \(s / 86400) T.", "\(s / 86400)d ago")
}

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 {
        let v = String(format: "%.1f", Double(n) / 1_000_000)
        return L(v.replacingOccurrences(of: ".", with: ",") + " Mio.", v + "M")
    }
    if n >= 1000 { return L("\(n / 1000) Tsd.", "\(n / 1000)k") }
    return "\(n)"
}

func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency; f.currencyCode = "USD"; f.locale = Lang.locale
    f.maximumFractionDigits = v < 10 ? 2 : 0
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
