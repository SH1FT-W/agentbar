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
            MenuBarLabel(state: delegate.store.menuBar)
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
            out.append("\(s.status.label.padding(toLength: 13, withPad: " ", startingAt: 0)) \(s.label) | \(s.activity) | \(shortModel(s.model)) \(s.permissionMode) | helpers \(s.subagents.count)/\(s.workingHelpers) | \(formatTokens(s.totalTokens)) | ctx \(s.contextFill.map { "\(Int(($0 * 100).rounded())) % / \(s.contextWindowText)" } ?? "–") | \(ago(s.lastActivity)) | hooks \(s.usesHooks) \(s.terminalApp ?? "-") \(s.tty ?? "-")")
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
    let menuBar = MenuBarState()
    private var peerWatch: AnyCancellable?
    lazy var office = OfficeWindowController(store: self)
    private let updatePrompt = UpdatePromptController()
    private var hotKey: HotKey?
    private lazy var awakeFollower = KeepAwakeFollower { [keepAwake] mode, busy in keepAwake.update(mode: mode, agentsWorking: busy) }
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
    private var gate = WaitGate()
    private var gateTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        menuBar.follow(monitor, quota)
        monitor.onUpdate = { [weak self] list in
            self?.checkHints(list)
            self?.checkWaits()
        }
        monitor.stats.publish = { [weak self] days in
            MainActor.assumeIsolated { if self?.stats.days != days { self?.stats.days = days } }
        }
        peers.onChange = { [weak self] list in
            self?.monitor.remote = list
            self?.checkWaits()
        }
        notifier.onMute = { [weak self] id in self?.mutedUntil[id] = Date().addingTimeInterval(3600) }
        peerWatch = monitor.$sessions.sink { [weak self] list in self?.peers.update(local: list) }
        notifier.onOpen = { [weak self] id in
            guard let s = self?.monitor.sessions.first(where: { $0.id == id }) else { return }
            Focus.open(s)
        }
        quota.onThreshold = { [weak self] alert, window in
            guard UserDefaults.standard.bool(forKey: Prefs.notifyQuota) else { return }
            let pct = percentText(Int(alert.percent.rounded(.down)))
            let title = alert.window == .fiveHour ? L("5-Stunden-Kontingent bei \(pct)", "5-hour usage at \(pct)")
                                                  : L("Wochen-Kontingent bei \(pct)", "Weekly usage at \(pct)")
            let body = alert.window == .fiveHour ? L("Das 5-Stunden-Fenster wird knapp.", "The 5-hour window is running low.")
                                                 : L("Das 7-Tage-Fenster wird knapp.", "The 7-day window is running low.")
            self?.notifier.post(title: title, body: body + (window.resetsAt.map { " " + freshWindowText($0) } ?? ""),
                                sessionId: nil, replacing: "quota-\(alert.window.rawValue)")
        }
        updater.onLaunchFound = { [weak self] _ in
            guard let self, UserDefaults.standard.bool(forKey: Prefs.notifyUpdate) else { return }
            self.updatePrompt.show(self.updater)
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
        updateKeepAwake()
        if UserDefaults.standard.bool(forKey: "officeWasOpen") { office.show() }
        peers.configure()
    }

    func updateKeepAwake() {
        let mode = KeepAwakeMode(rawValue: UserDefaults.standard.string(forKey: Prefs.keepAwake) ?? "") ?? .off
        awakeFollower.update(mode: mode, busyNow: monitor.localBusy,
                             busy: self.monitor.$sessions.map(SessionMonitor.busy).eraseToAnyPublisher())
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
        if s.device == nil, !s.runsHere, monitor.remote.contains(where: { $0.id == s.id }) { return false }
        // The session's terminal (or app) is already in front: the user sees it anyway
        if !UserDefaults.standard.bool(forKey: Prefs.notifyWhenFrontmost), let b = s.terminalApp,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == b { return false }
        return true
    }

    private func title(_ s: AgentSession) -> String { s.device.map { "\(s.displayName) · \($0)" } ?? s.displayName }

    /// Waiting sessions ("needs you", question, done, error): notify only after the set delay (permission prompts
    /// after at most WaitGate.approvalDelay) and once per waiting state (WaitGate). Runs on every monitor/peer update and on a one-shot timer for the next deadline.
    private func checkWaits() {
        let d = UserDefaults.standard
        gate.delay = max(0, d.double(forKey: Prefs.notifyDelay))
        // With other Macs: `all` prefers the reporting Mac's version over a local mirror (shared ~/.claude).
        // Without: local mirrors of other Macs' sessions are left out, they never notify here.
        let remoteIds = Set(monitor.remote.map(\.id))
        let list = d.bool(forKey: Prefs.notifyPeers) ? monitor.all
            : monitor.sessions.filter { $0.runsHere || !remoteIds.contains($0.id) }
        for id in gate.update(list.map(Self.observation)) {
            if let s = list.first(where: { $0.id == id }) { notifyWaiting(s) }
        }
        gateTimer?.invalidate()
        gateTimer = gate.nextDeadline.map { due in
            Timer.scheduledTimer(withTimeInterval: max(0.5, due.timeIntervalSinceNow + 0.1), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkWaits() }
            }
        }
    }

    nonisolated static func observation(_ s: AgentSession) -> WaitGate.Observation {
        switch s.status {
        case .working: return .init(id: s.id, kind: nil)
        case .idle: return .init(id: s.id, kind: nil, neutral: true)
        case .waiting: return .init(id: s.id, kind: .waiting, key: s.question ?? s.waitingReason ?? "", approval: s.waitsForApproval)
        case .done: return .init(id: s.id, kind: .done, key: String(s.lastText.prefix(300)))
        case .error: return .init(id: s.id, kind: .error, key: "error")
        }
    }

    private func notifyWaiting(_ s: AgentSession) {
        let d = UserDefaults.standard
        guard shouldNotify(s) else { return }
        // Project name first, the session's own title (if different) below it
        var name = s.project == "Home" ? s.label : s.project
        if let dev = s.device { name += " · \(dev)" }
        let subtitle = s.displayName != s.project ? s.displayName : nil
        let id = "waiting-\(s.id)"
        switch s.status {
        case .waiting where d.bool(forKey: Prefs.notifyWaiting):
            if let q = s.question {
                notifier.post(title: L("\(name) hat eine Frage", "\(name) has a question"), subtitle: subtitle, body: q, sessionId: s.id, replacing: id)
            } else {
                notifier.post(title: L("\(name) braucht dich", "\(name) needs you"), subtitle: subtitle,
                              body: s.waitingReason ?? L("Wartet auf deine Freigabe.", "Waiting for your approval."), sessionId: s.id, replacing: id)
            }
        case .done where d.bool(forKey: Prefs.notifyDone):
            notifier.post(title: L("\(name) ist fertig", "\(name) is done"), subtitle: subtitle,
                          body: s.lastText.isEmpty ? L("Wartet auf deine nächste Eingabe.", "Waiting for your next message.") : s.lastText,
                          sessionId: s.id, replacing: id)
        case .error where d.bool(forKey: Prefs.notifyError):
            notifier.post(title: L("\(name): Fehler", "\(name): Error"), subtitle: subtitle,
                          body: L("Die Sitzung ist auf einen Fehler gelaufen.", "The session ran into an error."), sessionId: s.id, replacing: id)
        default: break
        }
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

/// What the menu bar shows. The label used to observe the whole monitor and quota, so every session event
/// redrew the status item; this publishes only when the counts or the shown percentage change.
@MainActor
final class MenuBarState: ObservableObject {
    @Published private(set) var waiting = 0
    @Published private(set) var working = 0
    @Published private(set) var quotaPercent: Int?
    private var watch: AnyCancellable?

    func follow(_ monitor: SessionMonitor, _ quota: QuotaMonitor) {
        let defaults = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }
        // objectWillChange fires before the change: read the new values on the next main-queue turn
        watch = Publishers.Merge3(monitor.objectWillChange.map { _ in () }, quota.objectWillChange.map { _ in () }, defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak monitor, weak quota] in
                guard let self, let monitor, let quota else { return }
                MainActor.assumeIsolated { self.set(monitor.waitingCount, monitor.workingCount, quota.shownSession.map { Int($0.percent.rounded()) }) }
            }
        set(monitor.waitingCount, monitor.workingCount, quota.shownSession.map { Int($0.percent.rounded()) })
    }

    private func set(_ waiting: Int, _ working: Int, _ quota: Int?) {
        if self.waiting != waiting { self.waiting = waiting }
        if self.working != working { self.working = working }
        if quotaPercent != quota { quotaPercent = quota }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: MenuBarState
    @AppStorage(Prefs.showCount) private var showCount = true
    @AppStorage(Prefs.showQuota) private var showQuota = false

    var body: some View {
        let waiting = state.waiting, working = state.working
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.make(waiting: waiting > 0, working: working > 0))
            // Zahl zeigt, wer dich braucht – sonst, wie viele arbeiten
            if showCount, waiting + working > 0 { Text("\(waiting > 0 ? waiting : working)").monospacedDigit() }
            if showQuota, let p = state.quotaPercent { Text(percentText(p)).monospacedDigit() }
        }
        // VoiceOver: das Symbol allein verrät den Zustand nicht
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["AgentBar",
                             waiting > 0 ? L("\(waiting) braucht dich", "\(waiting) need you") : nil,
                             working > 0 ? L("\(working) arbeiten", "\(working) working") : nil].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Monochromes Template-Symbol wie die System-Extras in macOS 26/27; Zustand als kleines Abzeichen.

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
