// Rendert Büro + Dropdown als PNG nach build/ (ohne Menüleiste). Aufruf: ./build.sh snapshot [--live]
import SwiftUI

@main
struct Snap {
    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Prefs.register()
        let now = Date()
        // Aktivität kommt wie in der App aus describeTool – Werkzeugname explizit, damit nichts an der Sprache hängt
        func s(_ id: String, _ cwd: String, _ title: String?, _ st: AgentStatus, _ tool: String, _ input: [String: Any], _ ago: Double, helpers: Int = 0, ctx: Double = 0.2) -> AgentSession {
            AgentSession(id: id, source: .cli, cwd: "/Users/x/\(cwd)", title: title, model: "claude-opus-5-5", permissionMode: "auto",
                         status: st, activity: tool.isEmpty ? "" : describeTool(tool, input), tool: tool,
                         lastText: L("Build ist grün, alle 42 Tests bestanden.", "Build is green, all 42 tests passed."), lastActivity: now.addingTimeInterval(-ago),
                         tokens: ["claude-sonnet-4-5": TokenTally(input: 1200, cacheWrite: 50000, cacheRead: 900000, output: 30000)],
                         subagents: (0..<helpers).map { SubAgent(id: "h\($0)", type: "Explore", description: L("Sucht Dateien", "Finding files"), working: true,
                                                                activity: describeTool("Read", ["file_path": "/x/App.swift"]), lastActivity: now) },
                         hostBundle: "com.apple.Terminal", tty: nil, usesHooks: true,
                         contextUsed: Int(ctx * 1_000_000), contextWindow: 1_000_000)
        }
        // Kontext-Füllstände so gewählt, dass alle Müdigkeitsstufen vorkommen
        var demo = [
            s("1", "weather-app", L("Radar-Ansicht bauen", "Build radar view"), .working, "Edit", ["file_path": "/x/RadarView.swift"], 5, helpers: 3, ctx: 0.22),
            s("2", "api-server", nil, .waiting, "Bash", ["command": "git push"], 20, ctx: 0.62),
            s("3", "portfolio", L("Dunkelmodus", "Dark mode"), .done, "", [:], 30, ctx: 0.35),
            s("4", "photo-sorter", nil, .working, "Bash", ["command": "swift build"], 3, ctx: 0.82),
            s("5", "recipes", nil, .idle, "", [:], 2000, ctx: 0.58),
            s("6", "home-lab", nil, .error, "", [:], 40, ctx: 0.93),
            s("7", "blog", nil, .idle, "", [:], 400, ctx: 0.4),
            s("8", "chess-engine", nil, .working, "WebSearch", [:], 50, ctx: 0.96),
        ]
        // Zwei Sitzungen von einem anderen Mac (Andere Macs)
        for i in [3, 6] { demo[i].device = "iMac" }
        let model = OfficeModel()
        let cal = Calendar.current
        func render(_ name: String, _ date: Date, _ t: Double, dark: Bool, sessions: [AgentSession], hovered: String? = nil) {
            let (actors, overflow) = model.actors(for: sessions, now: t)
            let scene = OfficeScene(time: t, date: date, dark: dark, daylight: true, actors: actors, overflow: overflow,
                                    hovered: hovered, session: 42, weekly: 18, plan: "Max 20×", cpu: 0.3,
                                    vacuum: OfficeScene.lightsOn(date: date, dark: dark, daylight: true) ? .docked : VacuumState(loop: t * 40, spur: 0), working: 3, waiting: 1)
            let view = Canvas { ctx, size in scene.draw(&ctx) }.frame(width: 1000, height: 600)
            let r = ImageRenderer(content: view); r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/office-\(name).png"))
            }
        }
        for (name, hour, dark) in [("day", 11, false), ("dusk", 19, false), ("night", 23, true), ("dawn", 7, false), ("day-dark", 13, true)] {
            let date = cal.date(bySettingHour: hour, minute: 20, second: 0, of: now)!
            render(name, date, date.timeIntervalSinceReferenceDate, dark: dark, sessions: demo)
        }
        // Überfahren + Laufwege
        let date = cal.date(bySettingHour: 15, minute: 5, second: 0, of: now)!
        let t = date.timeIntervalSinceReferenceDate
        render("hover", date, t, dark: false, sessions: demo, hovered: "2")
        // Volle Lounge: 7 von 8 machen Pause, einer geht gerade (vordere Reihe → Kaffee-Ecke/Hocker)
        var lounge = demo
        for i in [0, 1, 2, 4, 5, 6] { lounge[i].status = .idle }
        let settle = t + 100
        _ = model.actors(for: lounge, now: t + 1)
        render("lounge", date, settle, dark: false, sessions: lounge)
        var walk = lounge
        walk[3].status = .idle
        _ = model.actors(for: walk, now: settle)
        for (i, dt) in [0.6, 1.8, 3.2, 4.6].enumerated() { render("walk\(i + 1)", date, settle + dt, dark: false, sessions: walk) }
        render("lounge-full", date, settle + 30, dark: false, sessions: walk)
        // Neue Sitzung kommt hinten rechts herein
        var arrive = Array(demo.prefix(7))
        _ = model.actors(for: arrive, now: settle + 40)
        arrive.append(demo[7])
        _ = model.actors(for: arrive, now: settle + 41)
        for (i, dt) in [0.8, 2.5, 4.5, 6.5].enumerated() { render("arrive\(i + 1)", date, settle + 41 + dt, dark: false, sessions: arrive) }
        // Dropdown mit Demo-Daten
        let store = AppStore()
        store.monitor.inject(demo)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        for (name, dark) in [("light", false), ("dark", true)] {
            shot(AnyView(MenuView(expanded: "1").environmentObject(store).environmentObject(store.monitor).environmentObject(store.quota).environmentObject(store.updater)), "build/menu-\(name).png", dark)
        }
    }

    @MainActor static func shot(_ view: AnyView, _ path: String, _ dark: Bool) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: size.width, height: size.height), styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        win.close()
    }
}
