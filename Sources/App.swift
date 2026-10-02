import SwiftUI
import Combine
import ServiceManagement

#if !SNAPSHOT
@main
#endif
struct AgentBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(delegate.store)
                .environmentObject(delegate.store.monitor)
                .environmentObject(delegate.store.quota)
                .environmentObject(delegate.store.updater)
                .environmentObject(delegate.store.stats)
        } label: {
            MenuBarLabel().environmentObject(delegate.store.monitor).environmentObject(delegate.store.quota)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: AppStore

    override init() {
        Prefs.register()
        store = AppStore()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--dump") { dump(); return }
        if CommandLine.arguments.contains("--hook-command") { print(Hooks.command); exit(0) }
        store.launched()
    }
}

extension AppDelegate {
    /// Diagnose: `AgentBar.app/Contents/MacOS/AgentBar --dump` listet die erkannten Sitzungen und beendet sich.
    func dump() {
        // Wartezeit für Tests überschreibbar (z. B. bis der Statistik-Scan durch ist): AGENTBAR_DUMP_WAIT=20
        let wait = Double(ProcessInfo.processInfo.environment["AGENTBAR_DUMP_WAIT"] ?? "") ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [self] in print(store.diagnostics()); exit(0) }
    }
}

extension AppStore {
    /// Diagnose-Text (wie --dump) – auch für „Diagnose kopieren“ in den Einstellungen. Ohne Pfade/Namen außer Projektnamen.
    func diagnostics() -> String {
        var out = ["AgentBar \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for s in monitor.sessions {
            out.append("\(s.status.label.padding(toLength: 13, withPad: " ", startingAt: 0)) \(s.label) | \(s.activity) | \(shortModel(s.model)) \(s.permissionMode) | helpers \(s.subagents.count)/\(s.workingHelpers) | \(formatTokens(s.totalTokens)) | ctx \(s.contextFill.map { "\(Int(($0 * 100).rounded())) % / \(s.contextWindowText)" } ?? "–") | \(ago(s.lastActivity)) | hooks \(s.usesHooks) \(s.hostBundle ?? "-")")
        }
        out.append(L("Kontingent", "Usage") + ": \(quota.session?.percent ?? -1) / \(quota.weekly?.percent ?? -1) \(quota.plan ?? "") \(quota.problem ?? "")")
        if let f = quota.forecast {
            out.append(L("Prognose", "Forecast") + ": \(String(format: "%.1f", f.percentPerHour)) %/h, " + (f.exhaustsAt.map { L("leer um", "runs out at") + " \($0.formatted(date: .omitted, time: .shortened))" } ?? L("reicht bis zum Reset", "lasts until reset")))
        }
        if let t = stats.today {
            out.append(L("Heute", "Today") + ": \(formatTokens(t.tokens.total)) · \(formatMoney(t.cost)) · \(t.sessions) " + L("Sitzungen", "sessions") + " · " + t.byModel.sorted { $0.value > $1.value }.map { "\($0.key) \(formatTokens($0.value))" }.joined(separator: ", "))
        }
        out.append(L("Statistik", "Stats") + ": \(stats.days.count) " + L("Tage", "days") + ", " + formatTokens(stats.days.reduce(0) { $0 + $1.tokens.total }))
        if let p = hotKeyProblem { out.append(p) }
        return out.joined(separator: "\n")
    }
}

/// Hält alle Dienste zusammen und verdrahtet sie.
@MainActor
final class AppStore: ObservableObject {
    let monitor = SessionMonitor()
    let quota = QuotaMonitor()
    let notifier = Notifier()
    let keepAwake = KeepAwake()
    let updater = Updater()
    let peers = PeerHub()
    let stats = StatsStore()
    private var peerWatch: AnyCancellable?
    lazy var office = OfficeWindowController(store: self)
    private var hotKey: HotKey?
    private var awakeTimer: Timer?
    @Published var hooksInstalled = Hooks.installed
    @Published var message: String?
    /// Hinweis, wenn das globale Tastenkürzel nicht registriert werden konnte (sonst nil).
    @Published private(set) var hotKeyProblem: String?
    /// „Bei Anmeldung öffnen“ – wird beim Aktivwerden neu gelesen; ändern über `setLoginItem(_:)`.
    @Published private(set) var loginItemEnabled = SMAppService.mainApp.status == .enabled

    private var mutedUntil: [String: Date] = [:]        // Sitzung → stumm bis („1 Std. stumm“)
    private var contextWarned = Set<String>()
    private var stalledWarned: [String: Date] = [:]     // Sitzung → letzte Aktivität, für die schon gewarnt wurde
    private var hintsPrimed = false
    private var remoteStatus: [String: AgentStatus] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        monitor.onTransition = { [weak self] s, old in self?.transition(s, from: old) }
        monitor.onUpdate = { [weak self] list in self?.checkHints(list) }
        monitor.stats.publish = { [weak self] days in
            MainActor.assumeIsolated { if self?.stats.days != days { self?.stats.days = days } }
        }
        peers.onChange = { [weak self] list in
            self?.monitor.remote = list
            self?.remoteTransitions(list)
        }
        notifier.onMute = { [weak self] id in self?.mutedUntil[id] = Date().addingTimeInterval(3600) }
        peerWatch = monitor.$sessions.sink { [weak self] list in self?.peers.update(local: list) }
        notifier.onOpen = { [weak self] id in
            guard let s = self?.monitor.sessions.first(where: { $0.id == id }) else { return }
            Focus.open(s)
        }
        quota.onThreshold = { [weak self] pct in
            guard UserDefaults.standard.bool(forKey: Prefs.notifyQuota) else { return }
            self?.notifier.post(title: L("Kontingent bei", "Usage at") + " " + percentText(Int(pct)),
                                body: L("Das 5-Stunden-Fenster ist fast aufgebraucht.", "The 5-hour window is almost used up.") + " \(resetText(self?.quota.session?.resetsAt)).",
                                sessionId: nil)
        }
        updater.onFound = { [weak self] version in
            guard UserDefaults.standard.bool(forKey: Prefs.notifyUpdate) else { return }
            self?.notifier.post(title: L("AgentBar \(version) ist da", "AgentBar \(version) is available"),
                                body: L("Installieren über das AgentBar-Menü.", "Install it from the AgentBar menu."), sessionId: nil)
        }
    }

    func launched() {
        let key = HotKey { [weak self] in self?.office.toggle() }
        hotKey = key
        hotKeyProblem = key.problem
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLoginItem() }
        })
        // Nach dem Ruhezustand: Ordner neu einlesen, Netz-Dienste für andere Macs neu starten
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.monitor.rescan()
                self?.peers.restart()
            }
        })
        awakeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateKeepAwake() }
        }
        if UserDefaults.standard.bool(forKey: "officeWasOpen") { office.show() }
        peers.configure()
    }

    func updateKeepAwake() {
        let mode = KeepAwakeMode(rawValue: UserDefaults.standard.string(forKey: Prefs.keepAwake) ?? "") ?? .off
        keepAwake.update(mode: mode, agentsWorking: monitor.localBusy)
    }

    func setHooks(_ on: Bool) {
        do {
            if on { try Hooks.install() } else { try Hooks.uninstall() }
            message = on ? L("Präzise Erkennung aktiv – gilt für neu gestartete Claude-Sitzungen.", "Precise detection on – applies to newly started Claude sessions.")
                          : L("Hooks entfernt.", "Hooks removed.")
        } catch {
            message = "settings.json: \(error.localizedDescription)"
        }
        hooksInstalled = Hooks.installed
    }

    func refreshLoginItem() {
        let on = SMAppService.mainApp.status == .enabled
        if on != loginItemEnabled { loginItemEnabled = on }
    }

    func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = L("Anmeldeobjekt", "Login item") + ": \(error.localizedDescription)"
        }
        refreshLoginItem()
    }

    // MARK: Mitteilungen

    /// Stummgeschaltet, App im Vordergrund oder (bei geteiltem ~/.claude) Sitzung eines anderen Macs → nichts melden.
    private func shouldNotify(_ s: AgentSession) -> Bool {
        if let until = mutedUntil[s.id] {
            if until > Date() { return false }
            mutedUntil[s.id] = nil
        }
        if s.device == nil, monitor.remote.contains(where: { $0.id == s.id }) { return false }
        if !UserDefaults.standard.bool(forKey: Prefs.notifyWhenFrontmost), let b = s.hostBundle,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == b { return false }
        return true
    }

    private func title(_ s: AgentSession) -> String { s.device.map { "\(s.displayName) · \($0)" } ?? s.displayName }

    private func transition(_ s: AgentSession, from old: AgentStatus) {
        let d = UserDefaults.standard
        guard shouldNotify(s) else { return }
        let name = title(s)
        switch s.status {
        case .waiting where d.bool(forKey: Prefs.notifyWaiting):
            // Bei einer Frage steht der echte Fragetext in der Mitteilung
            if let q = s.question {
                notifier.post(title: L("\(name) hat eine Frage", "\(name) has a question"), body: q, sessionId: s.id)
            } else {
                notifier.post(title: L("\(name) braucht dich", "\(name) needs you"),
                              body: s.activity.isEmpty ? L("Wartet auf deine Freigabe.", "Waiting for your approval.") : s.waitingReason ?? s.activity, sessionId: s.id)
            }
        case .done where old == .working && d.bool(forKey: Prefs.notifyDone):
            notifier.post(title: L("\(name) ist fertig", "\(name) is done"), body: s.lastText.isEmpty ? s.project : s.lastText, sessionId: s.id)
        case .error where d.bool(forKey: Prefs.notifyError):
            notifier.post(title: L("\(name): Fehler", "\(name): Error"), body: L("Die Sitzung ist auf einen Fehler gelaufen.", "The session ran into an error."), sessionId: s.id)
        default: break
        }
    }

    /// Statuswechsel anderer Macs – nur mit Prefs.notifyPeers.
    private func remoteTransitions(_ list: [AgentSession]) {
        let on = UserDefaults.standard.bool(forKey: Prefs.notifyPeers)
        var next: [String: AgentStatus] = [:]
        for s in list {
            if on, let old = remoteStatus[s.id], old != s.status { transition(s, from: old) }
            next[s.id] = s.status
        }
        remoteStatus = next
    }

    /// Kontext-Warnung (einmal je Sitzung ab 85 %, nach dem Zusammenfassen wieder scharf) und „Hängt?“-Hinweis
    /// (arbeitet seit über 10 Min. ohne jedes Ereignis, keine Helfer aktiv).
    private func checkHints(_ list: [AgentSession]) {
        let d = UserDefaults.standard
        let now = Date()
        let primed = hintsPrimed       // beim Start schon volle Sitzungen nicht melden
        hintsPrimed = true
        for s in list {
            if s.contextWarning {
                if contextWarned.insert(s.id).inserted, primed, d.bool(forKey: Prefs.notifyContext), shouldNotify(s) {
                    let pct = percentText(Int(((s.contextFill ?? 0) * 100).rounded()))
                    notifier.post(title: L("\(title(s)): Kontext fast voll", "\(title(s)): context almost full"),
                                  body: L("\(pct) von \(s.contextWindowText) belegt – bald wird zusammengefasst.",
                                          "\(pct) of \(s.contextWindowText) used – it will be compacted soon."),
                                  sessionId: s.id, sound: false)
                }
            } else if (s.contextFill ?? 1) < 0.5 {
                contextWarned.remove(s.id)
            }
            if s.status == .working, s.workingHelpers == 0, now.timeIntervalSince(s.lastActivity) > 600,
               stalledWarned[s.id] != s.lastActivity {
                stalledWarned[s.id] = s.lastActivity
                if primed, d.bool(forKey: Prefs.notifyStalled), shouldNotify(s) {
                    let mins = Int(now.timeIntervalSince(s.lastActivity) / 60)
                    notifier.post(title: L("\(title(s)) hängt?", "\(title(s)) stuck?"),
                                  body: L("Seit \(mins) Min. kein Lebenszeichen", "No sign of life for \(mins) min") + (s.activity.isEmpty ? "" : " – \(s.activity)"),
                                  sessionId: s.id)
                }
            }
        }
        let ids = Set(list.map(\.id))
        contextWarned.formIntersection(ids)
        stalledWarned = stalledWarned.filter { ids.contains($0.key) }
        mutedUntil = mutedUntil.filter { $0.value > now }
    }
}

// MARK: - Menüleiste

struct MenuBarLabel: View {
    @EnvironmentObject var monitor: SessionMonitor
    @EnvironmentObject var quota: QuotaMonitor
    @AppStorage(Prefs.showCount) private var showCount = true
    @AppStorage(Prefs.showQuota) private var showQuota = false

    var body: some View {
        let waiting = monitor.waitingCount, working = monitor.workingCount
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.make(waiting: waiting > 0, working: working > 0))
            // Zahl zeigt, wer dich braucht – sonst, wie viele arbeiten
            if showCount, waiting + working > 0 { Text("\(waiting > 0 ? waiting : working)").monospacedDigit() }
            if showQuota, let s = quota.session { Text(percentText(Int(s.percent.rounded()))).monospacedDigit() }
        }
    }
}

/// Monochromes Template-Symbol wie die System-Extras in macOS 26/27; Zustand als kleines Abzeichen.
enum MenuBarIcon {
    static func make(waiting: Bool, working: Bool) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let name = waiting ? "hand.raised.fill" : "sparkles"
        guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: "AgentBar")?
            .withSymbolConfiguration(cfg) else { return NSImage() }
        let badge = working && !waiting
        let size = NSSize(width: sym.size.width + (badge ? 3 : 0), height: max(sym.size.height, 16))
        let img = NSImage(size: size, flipped: false) { _ in
            let y = (size.height - sym.size.height) / 2
            sym.draw(in: NSRect(x: 0, y: y, width: sym.size.width, height: sym.size.height),
                     from: .zero, operation: .sourceOver, fraction: 1)
            if badge {
                let d: CGFloat = 6.5
                let dot = NSRect(x: size.width - d, y: size.height - d - 0.5, width: d, height: d)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

enum AppInfo {
    static var version: String {
        #if SNAPSHOT
        // Snapshot-Werkzeug läuft ohne App-Bundle – Version aus der Info.plist im Repo (Aufruf aus dem Repo-Ordner)
        return NSDictionary(contentsOfFile: "Info.plist")?["CFBundleShortVersionString"] as? String ?? "dev"
        #else
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        #endif
    }
}
