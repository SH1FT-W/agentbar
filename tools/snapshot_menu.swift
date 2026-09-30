// Rendert Dropdown, Einstellungen und Menüleisten-Symbole als PNG nach build/ – mit echtem Liquid Glass.
// Bauen (ohne tools/snapshot.swift, das hat ein eigenes @main):
//   swiftc -swift-version 5 -parse-as-library -D SNAPSHOT -sdk …/MacOSX26.5.sdk -target arm64-apple-macos14 \
//       Sources/*.swift tools/snapshot_menu.swift -o build/snapshot_menu
// Aufruf: build/snapshot_menu [--flat]   (--flat: zusätzlich Offscreen-Bilder ohne Glas)
import SwiftUI

@main
struct SnapMenu {
    /// Der echte Monitor veröffentlicht alle 2 s neu – beim Warten die Demo-Daten immer wieder drüberlegen.
    @MainActor static var keep: (() -> Void)?

    @MainActor static func wait(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            keep?()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Prefs.register()
        // Kein Schlüsselbund-Zugriff im Snapshot – das Kontingent kommt aus festen Demo-Werten
        UserDefaults.standard.set(false, forKey: Prefs.quotaEnabled)
        let now = Date()
        QuotaSection.demo = (QuotaWindow(percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 13 * 60)),
                             QuotaWindow(percent: 18, resetsAt: now.addingTimeInterval(4 * 86400)),
                             "Max 20×", nil)

        func s(_ id: String, _ cwd: String, _ title: String?, _ st: AgentStatus, _ act: String, _ ago: Double, helpers: Int = 0) -> AgentSession {
            AgentSession(id: id, source: .cli, cwd: "\(NSHomeDirectory())/\(cwd)", title: title, model: "claude-opus-5-5", permissionMode: "auto",
                         status: st, activity: act, tool: "", lastText: "Build ist grün, alle 42 Tests bestanden.",
                         lastActivity: now.addingTimeInterval(-ago),
                         tokens: ["claude-opus-5-5": TokenTally(input: 1200, cacheWrite: 50000, cacheRead: 900000, output: 30000)],
                         subagents: (0..<helpers).map { SubAgent(id: "h\($0)", type: ["Explore", "Plan", "general-purpose"][$0 % 3],
                                                                   description: "Sucht Dateien", working: $0 < 2,
                                                                   activity: ["Liest App.swift", "Sucht nach „inject“", ""][$0 % 3], lastActivity: now) },
                         hostBundle: "com.apple.Terminal", tty: nil, usesHooks: true)
        }
        let demo = [
            s("1", "weather-app", "Radar-Ansicht bauen", .working, "Bearbeitet RadarView.swift", 5, helpers: 3),
            s("2", "api-server", nil, .waiting, "Terminal: git push", 20),
            s("3", "portfolio", "Dunkelmodus", .done, "", 180),
            s("4", "photo-sorter", nil, .working, "Terminal: swift build", 3),
            s("6", "home-lab", nil, .error, "", 400),
            s("5", "recipes", nil, .idle, "", 2000),
        ]

        let store = AppStore()
        UserDefaults.standard.set(true, forKey: Prefs.quotaEnabled)   // für die Einstellungen
        try? await Task.sleep(nanoseconds: 1_500_000_000)             // ersten Scan abwarten, dann Demo drüberlegen

        func menu(_ expanded: String?) -> AnyView {
            AnyView(MenuView(expanded: expanded).environmentObject(store).environmentObject(store.monitor).environmentObject(store.quota).environmentObject(store.updater))
        }

        // Menüleisten-Symbole: ruhig, arbeitet, braucht dich
        let icons: [(Bool, Bool)] = [(false, false), (false, true), (true, false), (true, true)]
        let strip = HStack(spacing: 18) {
            ForEach(0..<icons.count, id: \.self) { i in
                Image(nsImage: MenuBarIcon.make(waiting: icons[i].0, working: icons[i].1)).renderingMode(.template)
                    .scaleEffect(3).frame(width: 70, height: 60)
            }
        }.padding(10).foregroundStyle(.primary)
        shot(AnyView(strip), "build/menu-icons.png", false)

        for (name, dark) in [("light", false), ("dark", true)] {
            // Voll: Sitzungen, eine aufgeklappt, Hooks eingerichtet
            store.hooksInstalled = true
            keep = { store.monitor.inject(demo) }
            live(menu("1"), "build/menu-live-\(name).png", dark)
            // Leer: keine Sitzungen, Hooks-Hinweis sichtbar
            store.hooksInstalled = false
            keep = { store.monitor.inject([]) }
            live(menu(nil), "build/menu-empty-\(name).png", dark)
            // Einstellungen
            store.hooksInstalled = true
            liveWindow(AnyView(SettingsView(height: 1320).environmentObject(store)), "build/settings-\(name).png", dark)
            if CommandLine.arguments.contains("--flat") {
                keep = { store.monitor.inject(demo) }
                shot(menu("1"), "build/menu-flat-\(name).png", dark)
            }
        }
    }

    /// Echtes Panel kurz auf den Bildschirm (Liquid Glass zeichnet nur dort), per screencapture -l fotografiert.
    @MainActor static func live(_ view: AnyView, _ path: String, _ dark: Bool) {
        keep?()
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let win = NSPanel(contentRect: NSRect(x: 200, y: 150, width: size.width, height: size.height),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .popUpMenu
        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .menu; fx.state = .active; fx.blendingMode = .behindWindow
        fx.wantsLayer = true; fx.layer?.cornerRadius = 14; fx.layer?.masksToBounds = true
        host.frame = fx.bounds
        fx.addSubview(host)
        win.contentView = fx
        win.orderFrontRegardless()
        wait(1.0)
        capture(win, path)
        win.close()
    }

    /// Normales Fenster mit Titelleiste (für die Einstellungen).
    @MainActor static func liveWindow(_ view: AnyView, _ path: String, _ dark: Bool) {
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.setFrameOrigin(NSPoint(x: 240, y: 120))
        win.level = .floating
        win.orderFrontRegardless()
        wait(1.2)
        capture(win, path)
        win.close()
    }

    @MainActor static func capture(_ win: NSWindow, _ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", "\(win.windowNumber)", path]
        try? p.run(); p.waitUntilExit()
    }

    @MainActor static func shot(_ view: AnyView, _ path: String, _ dark: Bool) {
        keep?()
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: size.width, height: size.height),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        wait(0.8)
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        win.close()
    }
}
