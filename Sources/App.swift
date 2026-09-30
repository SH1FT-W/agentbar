import SwiftUI
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
            for s in store.monitor.sessions {
                print("\(s.status.label.padding(toLength: 13, withPad: " ", startingAt: 0)) \(s.label) | \(s.displayName) | \(s.activity) | \(shortModel(s.model)) \(s.permissionMode) | helpers \(s.subagents.count)/\(s.workingHelpers) | \(formatTokens(s.totalTokens)) | \(ago(s.lastActivity)) | hooks \(s.usesHooks) \(s.hostBundle ?? "-")")
            }
            print(L("Kontingent", "Usage") + ": \(store.quota.session?.percent ?? -1) / \(store.quota.weekly?.percent ?? -1) \(store.quota.plan ?? "") \(store.quota.problem ?? "")")
            exit(0)
        }
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
    lazy var office = OfficeWindowController(store: self)
    private var hotKey: HotKey?
    private var awakeTimer: Timer?
    @Published var hooksInstalled = Hooks.installed
    @Published var message: String?

    init() {
        monitor.onTransition = { [weak self] s, old in self?.transition(s, from: old) }
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
    }

    func launched() {
        hotKey = HotKey { [weak self] in self?.office.toggle() }
        awakeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateKeepAwake() }
        }
        if UserDefaults.standard.bool(forKey: "officeWasOpen") { office.show() }
    }

    func updateKeepAwake() {
        let mode = KeepAwakeMode(rawValue: UserDefaults.standard.string(forKey: Prefs.keepAwake) ?? "") ?? .off
        keepAwake.update(mode: mode, agentsWorking: monitor.workingCount + monitor.waitingCount > 0)
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

    private func transition(_ s: AgentSession, from old: AgentStatus) {
        let d = UserDefaults.standard
        if !d.bool(forKey: Prefs.notifyWhenFrontmost), let b = s.hostBundle,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == b { return }
        switch s.status {
        case .waiting where d.bool(forKey: Prefs.notifyWaiting):
            notifier.post(title: L("\(s.displayName) braucht dich", "\(s.displayName) needs you"), body: s.activity.isEmpty ? L("Wartet auf deine Freigabe.", "Waiting for your approval.") : s.activity, sessionId: s.id)
        case .done where old == .working && d.bool(forKey: Prefs.notifyDone):
            notifier.post(title: L("\(s.displayName) ist fertig", "\(s.displayName) is done"), body: s.lastText.isEmpty ? s.project : s.lastText, sessionId: s.id)
        case .error where d.bool(forKey: Prefs.notifyError):
            notifier.post(title: L("\(s.displayName): Fehler", "\(s.displayName): Error"), body: L("Die Sitzung ist auf einen Fehler gelaufen.", "The session ran into an error."), sessionId: s.id)
        default: break
        }
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
        return "1.2"   // Snapshot-Werkzeug läuft ohne App-Bundle
        #else
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        #endif
    }
}
