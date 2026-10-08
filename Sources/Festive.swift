import SwiftUI

/// Was im Büro gerade an Deko steht – aus dem Datum abgeleitet. Die Weihnachtszeit wächst Woche für Woche:
/// 1. Advent Kranz und Papiersterne, 2. Advent Lichterkette, 3. Advent Baum, 4. Advent erste Geschenke, Heiligabend alles.
struct Festive: Equatable {
    var wreath = false
    /// Brennende Kerzen am Adventskranz (1–4)
    var candles = 0
    var stars = false
    var lights = false
    var tree = false
    var gifts = 0
    /// Nikolaus: Stiefel auf den Tischen
    var boots = false
    var vacuumHat = false
    /// Silvester/Neujahr: Wimpelkette unter der Decke, Feuerwerk hinter dem Glas (0 = keins, 1 = Mitternacht), Konfetti am Boden
    var bunting = false
    var fireworks = 0.0
    var confetti = false
    /// Verkleidung der Figuren: welches Thema und wie viele mitmachen (0…1)
    var outfitTheme = Outfit.Theme.none
    var outfitChance = 0.0

    static let none = Festive()
    var animated: Bool { fireworks > 0 }

    private static var cache: (minute: Int, value: Festive)?

    static func at(_ date: Date) -> Festive {
        let minute = Int(date.timeIntervalSinceReferenceDate / 60)
        if let c = cache, c.minute == minute { return c.value }
        let v = compute(date, cal: .current)
        cache = (minute, v)
        return v
    }

    /// Erster Advent: vier Sonntage vor Weihnachten (27.11.–3.12.)
    static func firstAdvent(year: Int, cal: Calendar) -> Date {
        let xmas = cal.date(from: DateComponents(year: year, month: 12, day: 25))!
        let wd = cal.component(.weekday, from: xmas)            // 1 = Sonntag
        let back = wd == 1 ? 7 : wd - 1                         // letzter Sonntag vor dem 25.
        return cal.date(byAdding: .day, value: -back - 21, to: xmas)!
    }

    static func compute(_ date: Date, cal: Calendar) -> Festive {
        var f = Festive()
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return f }
        let h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        let day = cal.startOfDay(for: date)

        // Weihnachtszeit: vom 1. Advent bis Heilige Drei Könige
        let season = m == 1 ? y - 1 : y
        let adv1 = firstAdvent(year: season, cal: cal)
        let sinceAdv1 = cal.dateComponents([.day], from: adv1, to: day).day ?? -1
        let xmasEnd = cal.date(from: DateComponents(year: season + 1, month: 1, day: 6))!
        if sinceAdv1 >= 0 && day <= xmasEnd {
            let week = min(4, sinceAdv1 / 7 + 1)                  // 1…4
            let beforeBoxingDayEnd = m == 11 || (m == 12 && d <= 26)
            f.stars = true
            f.lights = week >= 2 || m == 1
            f.tree = week >= 3 || m == 1
            if beforeBoxingDayEnd {
                f.wreath = true
                f.candles = week
                f.vacuumHat = true
            }
            if m == 12 && d >= 24 && d <= 26 { f.gifts = 6 }
            else if week == 4 && m == 12 && d < 24 { f.gifts = 2 }
            // Je näher Weihnachten, desto mehr Mützen und Pullis
            if beforeBoxingDayEnd {
                f.outfitTheme = .christmas
                f.outfitChance = m == 12 && d >= 24 ? 0.85 : [0.25, 0.4, 0.55, 0.65][week - 1]
            } else if m == 12 && d < 31 {
                f.outfitTheme = .christmas
                f.outfitChance = 0.3
            }
        }
        if m == 12 && d == 6 { f.boots = true }

        // Silvester und Neujahr
        if m == 12 && d == 31 {
            f.outfitTheme = .newYear
            f.outfitChance = h >= 18 ? 0.85 : 0.45
            f.bunting = true
            if h >= 23.8 { f.fireworks = 1 } else if h >= 18 { f.fireworks = 0.15 }
        }
        if m == 1 && d == 1 {
            f.bunting = h < 12
            if h < 12 { f.outfitTheme = .newYear; f.outfitChance = 0.6 }
            f.confetti = h < 15
            if h < 0.6 { f.fireworks = 1 } else if h < 2 { f.fireworks = 0.3 }
        }
        return f
    }

    /// Zum Testen und für Screenshots: AGENTBAR_FAKE_DATE=2026-12-24T18:00 (Ortszeit) – nur die Deko richtet sich danach.
    static let fakeDate: Date? = {
        guard let v = ProcessInfo.processInfo.environment["AGENTBAR_FAKE_DATE"], !v.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = v.contains("T") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        return f.date(from: v)
    }()
}

// MARK: - Zeichnen

extension OfficeScene {
    private var warmBulb: Color { rgb(0xFFD58A) }
    private var night: Double { 1 - dayness }

    /// Wimpelkette (Silvester) quer unter der Decke – vor der Glasfront, hinter den Figuren.
    func drawBunting(_ ctx: inout GraphicsContext) {
        guard festive.bunting else { return }
        let colors = [0xE8B84A, 0xC9CED6, 0xE97A9A, 0x6FA8E8, 0xE8B84A, 0xA98FDC].map { rgb($0) }
        let swags: [(CGFloat, CGFloat)] = [(10, 250), (250, 500), (500, 740), (740, 990)]
        for (si, (x0, x1)) in swags.enumerated() {
            let sag: CGFloat = 26
            func pt(_ t: CGFloat) -> CGPoint { P(x0 + (x1 - x0) * t, 24 + sag * 4 * t * (1 - t)) }
            var cord = Path(); cord.move(to: pt(0)); cord.addQuadCurve(to: pt(1), control: P((x0 + x1) / 2, 24 + sag * 2))
            ctx.stroke(cord, with: .color(dark ? .white.opacity(0.35) : rgb(0x8A8F98, 0.6)), lineWidth: 0.8)
            let n = 9
            for i in 1..<n {
                let t = CGFloat(i) / CGFloat(n)
                let a = pt(t - 0.035), b = pt(t + 0.035)
                let tip = P((a.x + b.x) / 2, (a.y + b.y) / 2 + 15)
                var flag = Path(); flag.move(to: a); flag.addLine(to: b); flag.addLine(to: tip); flag.closeSubpath()
                let col = colors[(i + si * 2) % colors.count]
                ctx.fill(flag, with: .linearGradient(Gradient(colors: [lighter(col, 0.15), darker(col, 0.1)]), startPoint: a, endPoint: tip))
            }
        }
    }

    /// Konfetti vom Vorabend auf dem Parkett.
    func drawConfetti(_ ctx: inout GraphicsContext) {
        guard festive.confetti else { return }
        var rng = SeededRandom(seed: 2027)
        let colors = [0xE8B84A, 0xE97A9A, 0x6FA8E8, 0x6BBF8E, 0xA98FDC].map { rgb($0, 0.85) }
        var paths = Array(repeating: Path(), count: colors.count)
        for i in 0..<170 {
            let x = rng.next() * 1000, y = Self.floorY + 8 + rng.next() * (600 - Self.floorY - 10)
            let w = 2.4 + rng.next() * 2, a = rng.next() * .pi
            let r = Path(CGRect(x: -w / 2, y: -1, width: w, height: 2)).applying(CGAffineTransform(translationX: x, y: y).rotated(by: a))
            paths[i % colors.count].addPath(r)
        }
        for (p, c) in zip(paths, colors) { ctx.fill(p, with: .color(c)) }
    }

    /// Feuerwerk am Himmel (in Glas-Koordinaten, vor der Landschaft).
    func drawFireworks(_ ctx: inout GraphicsContext, _ g: CGRect) {
        let density = festive.fireworks
        guard density > 0, dayness < 0.5 else { return }
        let colors = [0xFFD27A, 0xFF6B8B, 0x7FC8FF, 0xB6F53A, 0xD9A6FF, 0xFFFFFF].map { rgb($0) }
        // Mehrere unabhängige Abschuss-Rhythmen; bei wenig Dichte nur einer und nicht jedes Mal
        let channels: [Double] = density >= 1 ? [1.3, 1.9, 2.4, 2.9, 3.5] : [9]
        for (ci, period) in channels.enumerated() {
            let slotNow = (time / period).rounded(.down)
            for back in 0...1 {
                let slot = slotNow - Double(back)
                var r = SeededRandom(seed: UInt64(bitPattern: Int64(slot)) &* 31 &+ UInt64(ci))
                if density < 1 && r.next() > CGFloat(0.4 + density) { continue }
                let start = slot * period + Double(r.next()) * period * 0.5
                let dt = time - start
                guard dt >= 0 && dt < 2.6 else { continue }
                let x = g.minX + 60 + r.next() * (g.width - 120)
                let peak = g.minY + 40 + r.next() * 90
                let base = g.maxY - 90
                let col = colors[Int(r.next() * CGFloat(colors.count)) % colors.count]
                let rise = 0.55
                if dt < rise {
                    // Aufsteigender Funke
                    let y = base + (peak - base) * CGFloat(dt / rise)
                    ctx.fill(circle(P(x, y), 1.4), with: .color(col.opacity(0.9)))
                    var trail = Path(); trail.move(to: P(x, y)); trail.addLine(to: P(x, y + 14))
                    ctx.stroke(trail, with: .color(col.opacity(0.35)), lineWidth: 1)
                    continue
                }
                let e = (dt - rise) / 2.05                      // 0…1 Explosion
                let size = 46 + r.next() * 36
                let radius = CGFloat(1 - pow(1 - e, 3)) * size
                let drop = CGFloat(e * e) * 26
                let fade = max(0, 1 - e * e)
                ctx.fill(circle(P(x, peak), radius * 1.5), with: glow(P(x, peak), radius * 1.5, col, 0.28 * fade))
                // Funken als kurze Striche nach außen (Schweif), dazu ein zweiter, innerer Ring
                var streaks = Path(), dots = Path()
                let n = 30
                for k in 0..<n {
                    let a = Double(k) / Double(n) * 2 * .pi + Double(r.next()) * 0.15
                    let dir = CGPoint(x: CGFloat(cos(a)), y: CGFloat(sin(a)))
                    let outer = P(x + dir.x * radius, peak + dir.y * radius + drop)
                    let inner = P(x + dir.x * radius * 0.72, peak + dir.y * radius * 0.72 + drop * 0.7)
                    streaks.move(to: inner); streaks.addLine(to: outer)
                    if k % 2 == 0 {
                        let p = P(x + dir.x * radius * 0.5, peak + dir.y * radius * 0.5 + drop * 0.5)
                        dots.addEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
                    }
                }
                ctx.stroke(streaks, with: .color(col.opacity(fade)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                ctx.fill(dots, with: .color(lighter(col, 0.5).opacity(fade * 0.8)))
            }
        }
    }

    /// Papiersterne an Fäden und Lichterkette oben an der Glasfront.
    func drawWindowDeco(_ ctx: inout GraphicsContext) {
        let g = Self.glass
        let pw = g.width / CGFloat(Self.panes)
        if festive.stars {
            for (pane, drop, size) in [(0, 66.0, 13.0), (2, 92, 16), (3, 58, 11), (5, 80, 14)] as [(Int, CGFloat, CGFloat)] {
                let cx = g.minX + pw * (CGFloat(pane) + 0.5) + (pane % 2 == 0 ? -12 : 10)
                let c = P(cx + CGFloat(sin(time * 0.5 + Double(pane))) * 0.8, g.minY + drop)
                var thread = Path(); thread.move(to: P(cx, g.minY)); thread.addLine(to: P(c.x, c.y - size))
                ctx.stroke(thread, with: .color(dark ? .white.opacity(0.3) : rgb(0x6A6F78, 0.5)), lineWidth: 0.6)
                paperStar(&ctx, c, size)
            }
        }
        if festive.lights {
            var wire = Path(), bulbs: [(CGPoint, Int)] = []
            for i in 0..<Self.panes {
                let x0 = g.minX + CGFloat(i) * pw + 4, x1 = x0 + pw - 8
                let y0 = g.minY + 3, sag: CGFloat = 13
                wire.move(to: P(x0, y0)); wire.addQuadCurve(to: P(x1, y0), control: P((x0 + x1) / 2, y0 + sag * 2))
                for k in 1...7 {
                    let t = CGFloat(k) / 8
                    bulbs.append((P(x0 + (x1 - x0) * t, y0 + sag * 4 * t * (1 - t) + 2.5), i * 8 + k))
                }
            }
            ctx.stroke(wire, with: .color(rgb(0x3A3C40, 0.55)), lineWidth: 0.8)
            for (p, k) in bulbs {
                let tw = 0.75 + 0.25 * sin(time * (1.2 + Double(k % 5) * 0.3) + Double(k))
                ctx.fill(oval(p.x - 1.5, p.y - 1.5, 3, 4), with: .color(mix(rgb(0xF2E2C0), warmBulb, 0.4 + 0.6 * tw)))
            }
        }
    }

    private func paperStar(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        // Sechszackiger Faltstern: jede Zacke hat eine helle und eine schattige Hälfte
        let lit = night > 0.3
        let light = lit ? rgb(0xFFF1D2) : rgb(0xFFFFFF), shade = lit ? rgb(0xF2C98A) : rgb(0xE3E6EA)
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi - .pi / 2
            let tip = P(c.x + CGFloat(cos(a)) * r, c.y + CGFloat(sin(a)) * r)
            let l = P(c.x + CGFloat(cos(a - .pi / 6)) * r * 0.42, c.y + CGFloat(sin(a - .pi / 6)) * r * 0.42)
            let rr = P(c.x + CGFloat(cos(a + .pi / 6)) * r * 0.42, c.y + CGFloat(sin(a + .pi / 6)) * r * 0.42)
            var h1 = Path(); h1.move(to: c); h1.addLine(to: l); h1.addLine(to: tip); h1.closeSubpath()
            var h2 = Path(); h2.move(to: c); h2.addLine(to: tip); h2.addLine(to: rr); h2.closeSubpath()
            ctx.fill(h1, with: .color(light))
            ctx.fill(h2, with: .color(shade))
        }
    }

    /// Weihnachtsbaum im weißen Topf (steht dann statt der Geigenfeige), darunter die Geschenke.
    func drawTree(_ ctx: inout GraphicsContext, at b: CGPoint) {
        let s: CGFloat = 1
        shadow(&ctx, CGRect(x: b.x - 52, y: b.y - 8, width: 104, height: 16), dark ? 0.3 : 0.18)
        let pot = CGRect(x: b.x - 18, y: b.y - 32, width: 36, height: 32)
        potBack(&ctx, pot, s, rim: 7)
        ctx.fill(rounded(b.x - 3, b.y - 44, 6, 14, 2), with: .color(rgb(0x6B5238)))
        // Etagen von unten nach oben
        let tiers: [(CGFloat, CGFloat, CGFloat)] = [(-40, 50, 50), (-72, 41, 44), (-101, 32, 38), (-127, 22, 32)]  // Fuß-y, halbe Breite, Höhe
        let green0 = rgb(0x2F6A45), green1 = rgb(0x4A9461)
        for (by, hw, h) in tiers {
            let y = b.y + by
            var t = Path()
            t.move(to: P(b.x, y - h))
            t.addQuadCurve(to: P(b.x + hw, y), control: P(b.x + hw * 0.35, y - h * 0.35))
            // Unterkante mit leichten Zweigbögen
            let n = 4
            for k in 0..<n {
                let xa = b.x + hw - CGFloat(k) * 2 * hw / CGFloat(n), xb = xa - 2 * hw / CGFloat(n)
                t.addQuadCurve(to: P(xb, y), control: P((xa + xb) / 2, y + 5))
            }
            t.addQuadCurve(to: P(b.x, y - h), control: P(b.x - hw * 0.35, y - h * 0.35))
            t.closeSubpath()
            ctx.fill(t, with: .linearGradient(Gradient(colors: [green1, green0]), startPoint: P(b.x - hw, y - h), endPoint: P(b.x + hw, y)))
        }
        // Kugeln und Lichter
        var rng = SeededRandom(seed: 1224)
        let ballColors = [0xC8323C, 0xD9A441, 0xC9CED6, 0xC8323C, 0xD9A441].map { rgb($0) }
        func spot() -> CGPoint {
            let tier = tiers[Int(rng.next() * 4) % 4]
            let fy = rng.next() * 0.8 + 0.15
            let y = b.y + tier.0 - tier.2 * (1 - fy)
            let half = tier.1 * fy * 0.85
            return P(b.x + (rng.next() * 2 - 1) * half, y)
        }
        for i in 0..<20 {
            let p = spot()
            let tw = 0.6 + 0.4 * sin(time * (1 + Double(i % 4) * 0.35) + Double(i) * 1.7)
            ctx.fill(circle(p, 1.6), with: .color(mix(rgb(0xF5E3BF), warmBulb, tw).opacity(0.7 + 0.3 * tw)))
        }
        for i in 0..<11 {
            let p = spot(), col = ballColors[i % ballColors.count]
            ctx.fill(circle(p, 3.4), with: .radialGradient(Gradient(colors: [lighter(col, 0.45), col, darker(col, 0.2)]),
                                                           center: P(p.x - 1.2, p.y - 1.2), startRadius: 0, endRadius: 4))
        }
        // Stern an der Spitze
        let top = P(b.x, b.y - 127 - 32 - 4)
        var star = Path()
        for k in 0..<10 {
            let a = Double(k) / 10 * 2 * .pi - .pi / 2
            let rr: CGFloat = k % 2 == 0 ? 9 : 3.8
            let p = P(top.x + CGFloat(cos(a)) * rr, top.y + CGFloat(sin(a)) * rr)
            k == 0 ? star.move(to: p) : star.addLine(to: p)
        }
        star.closeSubpath()
        ctx.fill(star, with: .linearGradient(Gradient(colors: [rgb(0xFFE6A0), rgb(0xD9A441)]), startPoint: P(top.x, top.y - 9), endPoint: P(top.x, top.y + 9)))
        potFront(&ctx, pot, s, rim: 7, corner: 8)
        drawGifts(&ctx, at: b)
    }

    private func drawGifts(_ ctx: inout GraphicsContext, at b: CGPoint) {
        guard festive.gifts > 0 else { return }
        let boxes: [(CGFloat, CGFloat, CGFloat, Int, Int)] = [   // dx, Breite, Höhe, Papier, Band
            (-34, 22, 17, 0xC8323C, 0xE9D9B0), (12, 18, 20, 0x2F6A45, 0xD9A441), (-56, 15, 12, 0xF4F1EA, 0xC8323C),
            (-12, 14, 11, 0x5B7FB8, 0xF4F1EA), (-46, 12, 8, 0xD9A441, 0xC8323C), (28, 13, 10, 0xA98FDC, 0xF4F1EA),
        ]
        for (dx, w, h, paper, ribbon) in boxes.prefix(festive.gifts) {
            let r = CGRect(x: b.x + dx - w / 2, y: b.y + 4 - h, width: w, height: h)
            shadow(&ctx, CGRect(x: r.minX - 2, y: r.maxY - 3, width: r.width + 4, height: 5), 0.18)
            ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: vgrad([lighter(rgb(paper), 0.12), darker(rgb(paper), 0.08)], r.minY, r.maxY))
            ctx.fill(Path(CGRect(x: r.midX - 1.4, y: r.minY, width: 2.8, height: r.height)), with: .color(rgb(ribbon)))
            ctx.fill(Path(CGRect(x: r.minX, y: r.minY + r.height * 0.35, width: r.width, height: 2.4)), with: .color(rgb(ribbon)))
            ctx.fill(oval(r.midX - 5, r.minY - 3.5, 5, 4), with: .color(rgb(ribbon)))
            ctx.fill(oval(r.midX, r.minY - 3.5, 5, 4), with: .color(rgb(ribbon)))
        }
    }

    /// Adventskranz auf dem Couchtisch (statt Bücher und Vase).
    func drawWreath(_ ctx: inout GraphicsContext, at c: CGPoint) {
        let rx: CGFloat = 21, ry: CGFloat = 6.5
        let candleSpots: [Double] = [225, 315, 45, 135]     // Grad; die ersten beiden hinten
        func onRing(_ deg: Double) -> CGPoint { P(c.x + CGFloat(cos(deg * .pi / 180)) * rx, c.y + CGFloat(sin(deg * .pi / 180)) * ry) }
        shadow(&ctx, CGRect(x: c.x - rx - 6, y: c.y - 2, width: 2 * rx + 12, height: 9), 0.2)
        func candle(_ i: Int) {
            let p = onRing(candleSpots[i])
            ctx.fill(rounded(p.x - 2.6, p.y - 13, 5.2, 13, 1.2), with: .linearGradient(Gradient(colors: [rgb(0xF4EFE4), rgb(0xD9D0BE)]), startPoint: P(p.x - 2.6, 0), endPoint: P(p.x + 2.6, 0)))
            guard i < festive.candles else { return }
            let fl = 1 + 0.12 * sin(time * 9 + Double(i) * 2.1)
            var flame = Path()
            let tip = P(p.x + CGFloat(sin(time * 3 + Double(i))) * 0.5, p.y - 13 - 6.5 * CGFloat(fl))
            flame.move(to: P(p.x, p.y - 13.5))
            flame.addQuadCurve(to: tip, control: P(p.x + 3, p.y - 16))
            flame.addQuadCurve(to: P(p.x, p.y - 13.5), control: P(p.x - 3, p.y - 16))
            ctx.fill(flame, with: .linearGradient(Gradient(colors: [rgb(0xFFF6D8), rgb(0xFFB547)]), startPoint: P(0, p.y - 13), endPoint: tip))
        }
        candle(0); candle(1)
        // Tannengrün als Kranz aus kleinen Büscheln, rote Beeren
        var rng = SeededRandom(seed: 4)
        for k in 0..<34 {
            let deg = Double(k) / 34 * 360
            let p = onRing(deg)
            let col = k % 3 == 0 ? rgb(0x4A9461) : rgb(0x2F6A45)
            ctx.fill(oval(p.x - 4.5, p.y - 3.2 - rng.next() * 1.5, 9, 6), with: .color(col))
        }
        for deg in stride(from: 15.0, to: 360, by: 52) {
            let p = onRing(deg)
            ctx.fill(circle(P(p.x, p.y - 2), 1.6), with: .color(rgb(0xC8323C)))
        }
        candle(2); candle(3)
    }

    /// Rote Stiefel neben dem Laptop (Nikolaus).
    func drawBoot(_ ctx: inout GraphicsContext, at b: CGPoint, _ s: CGFloat) {
        var boot = Path()
        boot.move(to: P(b.x - 4 * s, b.y - 16 * s))
        boot.addLine(to: P(b.x + 3 * s, b.y - 16 * s))
        boot.addLine(to: P(b.x + 3 * s, b.y - 5 * s))
        boot.addQuadCurve(to: P(b.x + 10 * s, b.y), control: P(b.x + 10 * s, b.y - 5 * s))
        boot.addLine(to: P(b.x - 4 * s, b.y))
        boot.closeSubpath()
        shadow(&ctx, CGRect(x: b.x - 6 * s, y: b.y - 2 * s, width: 18 * s, height: 4 * s), 0.18)
        ctx.fill(boot, with: .linearGradient(Gradient(colors: [rgb(0xD8434C), rgb(0xA92A33)]), startPoint: P(b.x - 4 * s, 0), endPoint: P(b.x + 10 * s, 0)))
        ctx.fill(rounded(b.x - 5 * s, b.y - 19 * s, 9 * s, 4 * s, 2 * s), with: .color(.white))
        // Süßes schaut heraus
        ctx.fill(circle(P(b.x - 1.5 * s, b.y - 20 * s), 2 * s), with: .color(rgb(0xD9A441)))
        ctx.fill(circle(P(b.x + 1.8 * s, b.y - 20.5 * s), 1.7 * s), with: .color(rgb(0x6BBF8E)))
    }

    /// Nikolausmütze auf dem Saugroboter.
    func drawVacuumHat(_ ctx: inout GraphicsContext, at p: CGPoint, front: CGFloat) {
        var hat = Path()
        hat.move(to: P(p.x - 7, p.y - 13))
        hat.addQuadCurve(to: P(p.x - front * 9, p.y - 22), control: P(p.x - 2, p.y - 24))
        hat.addQuadCurve(to: P(p.x + 7, p.y - 13), control: P(p.x + 4, p.y - 20))
        hat.closeSubpath()
        ctx.fill(hat, with: .color(rgb(0xC8323C)))
        ctx.fill(rounded(p.x - 8, p.y - 15, 16, 3.6, 1.8), with: .color(.white))
        ctx.fill(circle(P(p.x - front * 9, p.y - 22), 2.3), with: .color(.white))
    }

    /// Nach dem Nachtlicht: weiche Lichthöfe um Kerzen, Lichterkette, Baum und Sterne – sonst würde das Abdunkeln sie verschlucken.
    func drawDecoGlow(_ ctx: inout GraphicsContext) {
        let n = night
        guard n > 0.05 else { return }
        let g = Self.glass
        if festive.lights {
            let pw = g.width / CGFloat(Self.panes)
            for i in 0..<Self.panes {
                let cx = g.minX + (CGFloat(i) + 0.5) * pw
                ctx.fill(oval(cx - 60, g.minY - 10, 120, 50), with: glow(P(cx, g.minY + 14), 60, warmBulb, 0.28 * n))
            }
        }
        if festive.stars {
            let pw = g.width / CGFloat(Self.panes)
            for (pane, drop) in [(0, 66.0), (2, 92), (3, 58), (5, 80)] as [(Int, CGFloat)] {
                let c = P(g.minX + pw * (CGFloat(pane) + 0.5) + (pane % 2 == 0 ? -12 : 10), g.minY + drop)
                ctx.fill(circle(c, 34), with: glow(c, 34, rgb(0xFFE2A8), 0.35 * n))
            }
        }
        if festive.tree {
            let b = Self.treeBase
            ctx.fill(circle(P(b.x, b.y - 90), 90), with: glow(P(b.x, b.y - 90), 90, warmBulb, 0.22 * n))
        }
        if festive.wreath && festive.candles > 0 {
            let c = Self.wreathCenter
            ctx.fill(circle(P(c.x, c.y - 16), 46), with: glow(P(c.x, c.y - 16), 46, rgb(0xFFC27A), (0.18 + 0.06 * Double(festive.candles)) * n))
        }
    }

    static let treeBase = CGPoint(x: 712, y: 452)
    static let wreathCenter = CGPoint(x: 872 - 22, y: 556 - 6)
}
