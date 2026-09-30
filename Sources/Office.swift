import SwiftUI

// MARK: - Figuren-Aussehen (stabil je Projekt, damit man „seinen“ Agenten wiedererkennt)

struct Look {
    var skin: Color
    var hair: Color
    var hairStyle: Int
    var shirt: Color
    var glasses: Bool
    var pants: Color

    // Zurückhaltende Töne wie in Apples Illustrationen – nichts Knalliges
    static let skins: [Color] = [rgb(0xF7D9C0), rgb(0xECC3A0), rgb(0xD6A077), rgb(0xAD7652), rgb(0x74503A)]
    static let hairs: [Color] = [rgb(0x2E241D), rgb(0x5E3F28), rgb(0x9C6A3C), rgb(0xDDBB82), rgb(0xA5A5AA), rgb(0xA8513A)]
    static let shirts: [Color] = [rgb(0x5B9FE3), rgb(0x6BBF8E), rgb(0xF2A766), rgb(0xE97A84), rgb(0xA98FDC),
                                  rgb(0x5DBCCF), rgb(0x7482DB), rgb(0xEFCB5E), rgb(0x86CFB8), rgb(0xC7A383)]
    static let pantsList: [Color] = [rgb(0x3A4354), rgb(0x2E3A4F), rgb(0x6A6259), rgb(0xCFC4B2), rgb(0x4C5A4A), rgb(0x2F3033)]

    static func of(_ key: String) -> Look {
        var h: UInt64 = 1469598103934665603
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        func pick(_ n: Int, _ shift: UInt64) -> Int { Int((h >> shift) % UInt64(n)) }
        return Look(skin: skins[pick(skins.count, 3)], hair: hairs[pick(hairs.count, 11)], hairStyle: pick(6, 19),
                    shirt: shirts[pick(shirts.count, 27)], glasses: pick(4, 37) == 0,
                    pants: pantsList[pick(pantsList.count, 45)])
    }
}

func rgb(_ hex: Int, _ a: Double = 1) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
}

// MARK: - Wer sitzt wo (mit Laufwegen)

/// Plätze im Büro. Pause-Plätze: Sofa (3), Kaffee-Ecke neben der Lounge (2), am Fenster zwischen den hinteren Tischen (3).
enum Place: Equatable {
    case desk(Int), napAtDesk(Int), sofa(Int), stand(Int)
}

enum Pose: Equatable {
    case typing, raiseHand, relaxed, upset, napping, sofa(sleep: Bool), standing, walking(Double)
}

struct Actor: Identifiable {
    let id: String
    let session: AgentSession
    let look: Look
    var point: CGPoint          // sitzend: Tischkante unter dem Oberkörper · laufend: Füße
    var scale: CGFloat
    var pose: Pose
    var place: Place
    var statusAge: Double       // Sekunden seit dem letzten Statuswechsel
    var depth: CGFloat
}

final class OfficeModel {
    static let deskCount = 8
    static let sofaCount = 3
    static let standCount = 5

    private struct Move { let path: [CGPoint]; let lengths: [CGFloat]; let total: CGFloat; let start: Double; let duration: Double }

    private var desk: [String: Int] = [:]
    private var lounge: [String: Place] = [:]
    private var at: [String: Place] = [:]
    private var moves: [String: Move] = [:]
    private var since: [String: (status: AgentStatus, t: Double)] = [:]
    private var started = false

    static func deskSeat(_ i: Int) -> (CGPoint, CGFloat) {
        let front = i < 4
        let col = CGFloat(i % 4)
        return front ? (CGPoint(x: 92 + col * 156, y: 552), 1.0) : (CGPoint(x: 170 + col * 156, y: 436), 0.8)
    }
    static func sofaSeat(_ j: Int) -> (CGPoint, CGFloat) { (CGPoint(x: 782 + CGFloat(j) * 76, y: 472), 0.88) }
    /// Stehplätze (Füße als Anker): 0–1 Kaffee-Ecke neben der Lounge, 2–4 am Fenster in den Lücken der hinteren Reihe.
    static func standSpot(_ k: Int) -> (CGPoint, CGFloat) {
        [(CGPoint(x: 674, y: 506), CGFloat(0.9)), (CGPoint(x: 646, y: 540), 0.95),
         (CGPoint(x: 404, y: 414), 0.76), (CGPoint(x: 560, y: 414), 0.76), (CGPoint(x: 248, y: 414), 0.76)][k]
    }

    // MARK: Laufwege
    //
    // Zwei Gänge: Mittelgang zwischen den Tischreihen und Lounge-Gang vor dem Sofa (vor der ersten Reihe stehen Tischbeine).
    // Verbunden über einen senkrechten Verbindungsweg bei x = 730. Jeder Platz hat einen Zugang (Folge von Punkten
    // vom Platz bis in seinen Gang): aufstehen, seitlich durch die Lücke zwischen den Tischen, in den Gang.

    private enum Lane: Int { case middle, lounge }
    private static func laneY(_ l: Lane) -> CGFloat { [494, 524][l.rawValue] }
    private static let hubX: CGFloat = 730
    /// Eingang hinten rechts: hinter Sofa und hinteren Stühlen am Fenster entlang, dann durch die Lücke
    /// zwischen den hinteren Tischen (x = doorGapX) in den Mittelgang.
    static let door = CGPoint(x: 1040, y: 392)
    private static let doorGapX: CGFloat = 560

    /// Zugang: Punkte vom Platz (Füße) bis zum Gang, plus der Gang.
    private static func access(_ p: Place) -> ([CGPoint], Lane) {
        switch p {
        case .desk(let i), .napAtDesk(let i):
            let (pt, s) = deskSeat(i)
            let stand = CGPoint(x: pt.x, y: pt.y - 4 * s)          // hinter dem Tisch aufgestanden
            let gapX = pt.x + 78 * s                                // Lücke rechts neben dem Tisch
            // Auch die vordere Reihe geht über den Mittelgang – vorn stehen die Tischbeine im Weg
            let lane = Lane.middle
            return ([stand, CGPoint(x: gapX, y: stand.y), CGPoint(x: gapX, y: laneY(lane))], lane)
        case .sofa(let j):
            let (pt, _) = sofaSeat(j)
            return ([CGPoint(x: pt.x, y: 512), CGPoint(x: pt.x, y: laneY(.lounge))], .lounge)
        case .stand(let k):
            let (pt, _) = standSpot(k)
            return ([pt, CGPoint(x: pt.x, y: laneY(.middle))], .middle)
        }
    }

    /// Fußpunkt, an dem die Figur ankommt bzw. losgeht.
    private static func feet(_ p: Place) -> CGPoint { access(p).0[0] }

    /// Figurgröße aus der Tiefe (hinten kleiner).
    private static func depthScale(_ y: CGFloat) -> CGFloat { min(1.0, max(0.74, 0.8 + (y - 470) / 128 * 0.2)) }

    private static func route(from start: CGPoint, startLane: Lane, lead: [CGPoint], to target: Place, jitter: CGFloat) -> [CGPoint] {
        let (acc, lane) = access(target)
        var path = [start] + lead
        let entryA = CGPoint(x: (lead.last ?? start).x, y: laneY(startLane) + jitter)
        let entryB = CGPoint(x: acc.last!.x, y: laneY(lane) + jitter)
        path.append(entryA)
        if startLane != lane {
            path.append(CGPoint(x: hubX + jitter, y: laneY(startLane) + jitter))
            path.append(CGPoint(x: hubX + jitter, y: laneY(lane) + jitter))
        }
        path.append(entryB)
        path += acc.reversed().dropFirst()
        // doppelte Punkte entfernen
        var clean: [CGPoint] = []
        for p in path where clean.last.map({ hypot($0.x - p.x, $0.y - p.y) > 1 }) ?? true { clean.append(p) }
        return clean
    }

    private func startMove(_ id: String, path: [CGPoint], now: Double) {
        var lengths: [CGFloat] = [0]
        for i in 1..<max(path.count, 1) { lengths.append(lengths[i - 1] + hypot(path[i].x - path[i - 1].x, path[i].y - path[i - 1].y)) }
        let total = lengths.last ?? 0
        guard path.count > 1, total > 4 else { moves[id] = nil; return }
        moves[id] = Move(path: path, lengths: lengths, total: total, start: now, duration: max(0.8, Double(total / 115)))
    }

    /// Position auf dem Laufweg (mit sanftem Anfahren/Abbremsen).
    private func point(on m: Move, now: Double) -> CGPoint {
        let p = min(1, max(0, (now - m.start) / m.duration))
        let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
        let d = m.total * CGFloat(e)
        var i = 1
        while i < m.lengths.count - 1 && m.lengths[i] < d { i += 1 }
        let seg = m.lengths[i] - m.lengths[i - 1]
        let t = seg > 0 ? (d - m.lengths[i - 1]) / seg : 1
        let a = m.path[i - 1], b = m.path[i]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    // MARK: Zuordnung

    func actors(for sessions: [AgentSession], now: Double) -> (actors: [Actor], overflow: Int) {
        let ids = Set(sessions.map(\.id))
        for k in desk.keys where !ids.contains(k) { desk[k] = nil; lounge[k] = nil; at[k] = nil; moves[k] = nil; since[k] = nil }

        // Tische vergeben: aktive zuerst, der Rest nach Aktualität
        var overflow = 0
        for s in sessions.sorted(by: { ($0.status == .idle ? 1 : 0, -$0.lastActivity.timeIntervalSince1970) < ($1.status == .idle ? 1 : 0, -$1.lastActivity.timeIntervalSince1970) })
        where desk[s.id] == nil {
            let taken = Set(desk.values)
            if let free = (0..<Self.deskCount).first(where: { !taken.contains($0) }) { desk[s.id] = free } else { overflow += 1 }
        }

        let allLounge: [Place] = (0..<Self.sofaCount).map { .sofa($0) } + (0..<Self.standCount).map { .stand($0) }
        var out: [Actor] = []
        for s in sessions {
            guard let d = desk[s.id] else { continue }
            if since[s.id]?.status != s.status { since[s.id] = (s.status, now) }

            // Ziel: Pause → freier Platz in der Lounge (Sofa, dann Hocker, dann Kaffee-Ecke), sonst Nickerchen am Tisch
            var target: Place = .desk(d)
            if s.status == .idle {
                if lounge[s.id] == nil {
                    let taken = Set(lounge.values.map { "\($0)" })
                    lounge[s.id] = allLounge.first { !taken.contains("\($0)") }
                }
                target = lounge[s.id] ?? .napAtDesk(d)
            } else {
                lounge[s.id] = nil
            }

            let jitter = CGFloat(abs(s.id.hashValue % 3) - 1) * 5
            if let cur = at[s.id] {
                if cur != target {
                    if let m = moves[s.id] {
                        // Richtungswechsel unterwegs: vom aktuellen Punkt in den nächstgelegenen Gang
                        let here = point(on: m, now: now)
                        let lane = [Lane.middle, .lounge].min { abs(Self.laneY($0) - here.y) < abs(Self.laneY($1) - here.y) }!
                        startMove(s.id, path: Self.route(from: here, startLane: lane, lead: [], to: target, jitter: jitter), now: now)
                    } else {
                        let (acc, lane) = Self.access(cur)
                        startMove(s.id, path: Self.route(from: acc[0], startLane: lane, lead: Array(acc.dropFirst().dropLast()), to: target, jitter: jitter), now: now)
                    }
                    at[s.id] = target
                }
            } else {
                at[s.id] = target
                if started {   // neu dazugekommen: kommt hinten rechts herein
                    startMove(s.id, path: Self.route(from: Self.door, startLane: .middle, lead: [CGPoint(x: Self.doorGapX + jitter, y: Self.door.y)],
                                                     to: target, jitter: jitter), now: now)
                }
            }

            let age = now - (since[s.id]?.t ?? now)
            let look = Look.of(s.project == "Home" ? s.id : s.project)   // ohne Projekt: je Sitzung eigenes Aussehen
            if let m = moves[s.id] {
                if now - m.start < m.duration {
                    let pt = point(on: m, now: now)
                    out.append(Actor(id: s.id, session: s, look: look, point: pt, scale: Self.depthScale(pt.y),
                                     pose: .walking(now - m.start), place: target, statusAge: age, depth: pt.y))
                    continue
                }
                moves[s.id] = nil
            }
            let pose: Pose
            switch (target, s.status) {
            case (.sofa, _): pose = .sofa(sleep: age > 900)
            case (.stand, _): pose = .standing
            case (.napAtDesk, _): pose = .napping
            case (_, .working): pose = .typing
            case (_, .waiting): pose = .raiseHand
            case (_, .error): pose = .upset
            default: pose = .relaxed
            }
            let (pt, sc): (CGPoint, CGFloat)
            switch target {
            case .desk(let i), .napAtDesk(let i): (pt, sc) = Self.deskSeat(i)
            case .sofa(let j): (pt, sc) = Self.sofaSeat(j)
            case .stand(let k): (pt, sc) = Self.standSpot(k)
            }
            out.append(Actor(id: s.id, session: s, look: look, point: pt, scale: sc, pose: pose, place: target,
                             statusAge: age, depth: pt.y))
        }
        started = true
        return (out, overflow)
    }
}

// MARK: - Ansicht

struct OfficeView: View {
    let model: OfficeModel
    let load: SystemLoad
    @EnvironmentObject var monitor: SessionMonitor
    @EnvironmentObject var quota: QuotaMonitor
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.officeDaylight) private var daylight = true
    @State private var hovered: String?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let now = tl.date.timeIntervalSinceReferenceDate
                let (actors, overflow) = model.actors(for: Array(monitor.visible.prefix(12)), now: now)
                let k = geo.size.width / OfficeScene.size.width
                let scene = OfficeScene(time: now, date: tl.date, dark: scheme == .dark, daylight: daylight,
                                        actors: actors, overflow: overflow, hovered: hovered,
                                        session: quota.session?.percent, weekly: quota.weekly?.percent,
                                        plan: quota.plan, cpu: load.cpu, vacuum: load.vacuum(at: now, dock: OfficeScene.lightsOn(date: tl.date, dark: scheme == .dark, daylight: daylight)),
                                        working: monitor.workingCount, waiting: monitor.waitingCount)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        ctx.scaleBy(x: size.width / OfficeScene.size.width, y: size.height / OfficeScene.size.height)
                        scene.draw(&ctx)
                    }
                    ForEach(actors) { a in
                        let r = OfficeScene.hitRect(a)
                        Color.clear
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                            .frame(width: r.width * k, height: r.height * k)
                            // Vor .position anhängen: .position füllt das ganze Fenster, sonst reagiert die
                            // zuletzt gezeichnete Figur überall auf Maus und Klick
                            .onHover { hovered = $0 ? a.id : (hovered == a.id ? nil : hovered) }
                            .onTapGesture { Focus.open(a.session) }
                            .help(tooltip(a.session))
                            .position(x: r.midX * k, y: r.midY * k)
                    }
                }
            }
        }
        .aspectRatio(OfficeScene.size.width / OfficeScene.size.height, contentMode: .fit)
        .ignoresSafeArea()
        .background(Color.black)
    }

    private func tooltip(_ s: AgentSession) -> String {
        var t = "\(s.displayName)\n\(s.status.label)"
        if !s.activity.isEmpty { t += ": \(s.activity)" }
        t += "\n\(s.cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
        if !s.model.isEmpty { t += " · \(shortModel(s.model))" }
        t += "\n" + L("Klicken, um zur Sitzung zu springen", "Click to go to the session")
        return t
    }
}
