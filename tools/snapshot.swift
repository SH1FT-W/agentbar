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
        if CommandLine.arguments.contains("--bench") { bench(demo, cached: !CommandLine.arguments.contains("--nocache")); return }
        let backdrop = OfficeBackdrop()
        let forecast = QuotaForecast(percentPerHour: 9, exhaustsAt: cal.date(bySettingHour: 16, minute: 40, second: 0, of: now))
        func render(_ name: String, _ date: Date, _ t: Double, dark: Bool, sessions: [AgentSession], hovered: String? = nil, weather: Weather? = Weather.fake, festive: Festive = .none) {
            let (actors, overflow) = model.actors(for: sessions, now: t)
            let bg = backdrop.images(dark: dark, dayness: OfficeScene.dayness(date: date, dark: dark, daylight: true), scale: 2, now: t, weather: weather)
            let scene = OfficeScene(time: t, date: date, dark: dark, daylight: true, actors: actors, overflow: overflow,
                                    hovered: hovered, session: 42, weekly: 18, plan: "Max 20×", cpu: 0.3,
                                    vacuum: OfficeScene.lightsOn(date: date, dark: dark, daylight: true) ? .docked : VacuumState(loop: t * 40, spur: 0), working: 3, waiting: 1,
                                    forecast: forecast, todayTokens: 12_400_000, backdrop: bg, weather: weather, festive: festive)
            let view = Canvas { ctx, size in scene.draw(&ctx) }.frame(width: 1000, height: 600)
            let r = ImageRenderer(content: view); r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name.hasPrefix("weather-") || name.hasPrefix("festive-") ? "build/\(name).png" : "build/office-\(name).png"))
            }
        }
        // ./build.sh snapshot --festive → build/festive-*.png (Advent bis Neujahr)
        if CommandLine.arguments.contains("--festive") {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
            let shots: [(String, String, Bool, String?)] = [
                ("1-advent", "2026-11-30 10:30", false, nil), ("2-nikolaus", "2026-12-06 17:40", false, "cloudy"),
                ("3-advent3", "2026-12-14 21:00", true, nil), ("4-heiligabend", "2026-12-24 19:00", true, "snow"),
                ("4-heiligabend-tag", "2026-12-24 12:00", false, "snow"),
                ("5-silvester", "2026-12-31 23:58", true, "clear"), ("6-neujahr", "2027-01-01 10:30", false, "partly"),
            ]
            OfficeScene.sunTimes = (8.3, 16.4)     // Mitteleuropa im Dezember
            for (name, ds, dark, wk) in shots {
                let d = f.date(from: ds)!
                var t = d.timeIntervalSinceReferenceDate
                let fest = Festive.compute(d, cal: cal)
                if fest.fireworks >= 1 { t += 1.4 }
                render("festive-\(name)", d, t, dark: dark, sessions: demo, weather: wk.flatMap { Weather.fake($0) }, festive: fest)
            }
            print("Festbilder in build/")
            return
        }
        // ./build.sh snapshot --weather → build/weather-<art>-<tag|nacht>.png (Vergleichsbilder fürs Wetter)
        if CommandLine.arguments.contains("--weather") {
            for kind in Weather.Kind.allCases {
                for (label, hour, dark) in [("tag", 11, false), ("nacht", 22, true)] {
                    let d = cal.date(bySettingHour: hour, minute: 20, second: 0, of: now)!
                    var t = d.timeIntervalSinceReferenceDate
                    if kind == .thunder { while !OfficeScene.flashActive(time: t) { t += 0.05 } }   // Moment mit Blitz
                    render("weather-\(kind.rawValue)-\(label)", d, t, dark: dark, sessions: demo, weather: Weather.fake(kind.rawValue))
                }
            }
            // Echte Sonnenzeiten im Dezember (Aufgang 8:20, Untergang 16:20): um 16:45 ist es schon Abend
            OfficeScene.sunTimes = (8.33, 16.33)
            let dec = cal.date(bySettingHour: 16, minute: 45, second: 0, of: now)!
            render("weather-dezember-1645", dec, dec.timeIntervalSinceReferenceDate, dark: false, sessions: demo, weather: Weather.fake("snow"))
            OfficeScene.sunTimes = nil
            print("Wetterbilder in build/")
            return
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
        // Beendete Sitzung (vordere Reihe) geht zur Tür, eine andere wechselt den Status (kurzer Lichtring)
        var leave = arrive
        leave.remove(at: 3)
        leave[0].status = .waiting
        _ = model.actors(for: leave, now: settle + 60)
        for (i, dt) in [0.3, 2.0, 4.0, 6.5].enumerated() { render("leave\(i + 1)", date, settle + 60 + dt, dark: false, sessions: leave) }
        // Pause gibt den Tisch frei: zwei gehen in die Lounge, zwei neue arbeitende bekommen deren Tische
        let free = OfficeModel()
        var busy = Array(demo.prefix(8))
        for i in busy.indices { busy[i].status = .working }
        _ = free.actors(for: busy, now: settle)
        busy[0].status = .idle; busy[1].status = .idle
        _ = free.actors(for: busy, now: settle + 1)
        var more = busy
        more.append(s("9", "notes", nil, .working, "Read", ["file_path": "/x/a.md"], 1))
        more.append(s("10", "maps", nil, .working, "Grep", [:], 1))
        let (fa, fo) = free.actors(for: more, now: settle + 40)
        print("Tischvergabe: \(fa.count) Figuren, \(fo) im Nebenraum (erwartet 10/0)")
        // Dropdown mit Demo-Daten
        let store = AppStore()
        store.monitor.inject(demo)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        for (name, dark) in [("light", false), ("dark", true)] {
            shot(AnyView(MenuView(expanded: "1").environmentObject(store).environmentObject(store.monitor).environmentObject(store.quota).environmentObject(store.updater).environmentObject(store.stats)), "build/menu-\(name).png", dark)
        }
    }

    /// Grobe Frame-Zeit: rendert die Szene wiederholt offscreen (1000×600 @2x) und misst die Zeit je Bild.
    @MainActor static func bench(_ demo: [AgentSession], cached: Bool) {
        let model = OfficeModel()
        let cal = Calendar.current
        let backdrop = OfficeBackdrop()
        do {
            let date = cal.date(bySettingHour: 11, minute: 20, second: 0, of: Date())!
            let t = date.timeIntervalSinceReferenceDate
            let (actors, overflow) = OfficeModel().actors(for: demo, now: t)
            func png() -> Data? {
                let scene = OfficeScene(time: t, date: date, dark: false, daylight: true, actors: actors, overflow: overflow, hovered: nil,
                                        session: 42, weekly: 18, plan: nil, cpu: 0.3, vacuum: .docked, working: 3, waiting: 1)
                let r = ImageRenderer(content: Canvas { ctx, _ in scene.draw(&ctx) }.frame(width: 1000, height: 600)); r.scale = 2
                return r.nsImage?.tiffRepresentation
            }
            let a = png(), b = png(); print("Namensschild-Cache über Bilder hinweg identisch: \(a != nil && a == b) (\(a?.count ?? 0) Bytes)")
        }
        for (name, hour, dark) in [("day", 11, false), ("night", 23, true)] {
            let date = cal.date(bySettingHour: hour, minute: 20, second: 0, of: Date())!
            let t0 = date.timeIntervalSinceReferenceDate
            _ = model.actors(for: demo, now: t0)
            let n = 120
            var start = Date()
            for i in 0..<n + 5 {
                if i == 5 { start = Date() }   // Aufwärmen (Caches)
                let t = t0 + Double(i) / 30
                let (actors, overflow) = model.actors(for: demo, now: t)
                let bg = cached ? backdrop.images(dark: dark, dayness: OfficeScene.dayness(date: date, dark: dark, daylight: true), scale: 2, now: t, weather: Weather.fake) : nil
                let scene = OfficeScene(time: t, date: date.addingTimeInterval(Double(i) / 30), dark: dark, daylight: true, actors: actors, overflow: overflow,
                                        hovered: nil, session: 42, weekly: 18, plan: "Max 20×", cpu: 0.3,
                                        vacuum: VacuumState(loop: t * 40, spur: 0), working: 3, waiting: 1, backdrop: bg, weather: Weather.fake)
                let r = ImageRenderer(content: Canvas { ctx, size in scene.draw(&ctx) }.frame(width: 1000, height: 600)); r.scale = 2
                _ = r.cgImage
            }
            print("\(name): \(String(format: "%.1f", Date().timeIntervalSince(start) / Double(n) * 1000)) ms/Bild")
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
