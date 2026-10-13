import SwiftUI

/// Seltene Momente: Sternschnuppe, Vogelschwarm, Regenbogen bei Sonnenschauer, Schneemann, Freitags-Pizza.
/// Alles fest aus der Uhrzeit gewürfelt (gleich auf allen Macs, im Snapshot reproduzierbar).
enum Moments {
    /// Zeitfenster der Länge period; in pct % der Fenster passiert es einmal für dur Sekunden. Rückgabe: Fortschritt 0…1 und Würfel.
    static func window(_ time: Double, period: Double, dur: Double, pct: UInt64, salt: UInt64) -> (t: Double, seed: UInt64)? {
        let n = UInt64(max(0, time / period))
        var h = (n &* 0x9E3779B97F4A7C15) ^ salt
        h = (h ^ (h >> 31)) &* 0xBF58476D1CE4E5B9
        h ^= h >> 29
        guard h % 100 < pct else { return nil }
        let start = Double(n) * period + Double((h >> 8) % UInt64(max(1, period - dur)))
        let t = (time - start) / dur
        return t >= 0 && t <= 1 ? (t, h) : nil
    }

    static func shootingStar(_ time: Double) -> (t: Double, seed: UInt64)? { window(time, period: 200, dur: 1.2, pct: 55, salt: 0x51) }
    static func birds(_ time: Double) -> (t: Double, seed: UInt64)? { window(time, period: 360, dur: 11, pct: 45, salt: 0xB1) }

    /// Braucht gerade die flüssige Bildrate?
    static func animating(_ time: Double) -> Bool { shootingStar(time) != nil || birds(time) != nil }

    /// Freitag 12–14 Uhr: Pizza auf dem Couchtisch
    static func pizza(_ date: Date) -> Bool {
        let c = Calendar.current.dateComponents([.weekday, .hour], from: date)
        return c.weekday == 6 && (12..<14).contains(c.hour ?? 0)
    }
}

extension OfficeScene {
    /// Sternschnuppe quer über den Nachthimmel (nur bei klarem Himmel).
    func drawShootingStar(_ ctx: inout GraphicsContext, _ f: CGRect, clear: Double) {
        guard dayness < 0.3, clear > 0.6, let (t, h) = Moments.shootingStar(time) else { return }
        let x0 = f.minX + 80 + CGFloat(h % 380), y0 = f.minY + 30 + CGFloat((h >> 12) % 60)
        let dir = (h >> 20) % 2 == 0 ? CGFloat(1) : -1
        let len: CGFloat = 150
        let head = P(x0 + dir * len * CGFloat(t), y0 + len * 0.42 * CGFloat(t))
        let tail = P(head.x - dir * 46, head.y - 46 * 0.42)
        let fade = t < 0.15 ? t / 0.15 : t > 0.75 ? (1 - t) / 0.25 : 1
        var streak = Path(); streak.move(to: tail); streak.addLine(to: head)
        ctx.stroke(streak, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.9 * fade * clear)]), startPoint: tail, endPoint: head),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        ctx.fill(circle(head, 1.6), with: .color(.white.opacity(fade * clear)))
    }

    /// Vogelschwarm in V-Formation zieht tagsüber am Glas vorbei.
    func drawBirds(_ ctx: inout GraphicsContext, _ f: CGRect) {
        guard dayness > 0.6, weather?.raining != true, weather?.kind != .snow, let (t, h) = Moments.birds(time) else { return }
        let ltr = h % 2 == 0
        let lead = P(ltr ? f.minX - 60 + CGFloat(t) * (f.width + 120) : f.maxX + 60 - CGFloat(t) * (f.width + 120),
                     f.minY + 70 + CGFloat((h >> 9) % 60) + CGFloat(sin(t * 3)) * 6)
        let n = 5 + Int((h >> 16) % 3)
        var birds = Path()
        for i in 0..<n {
            let row = CGFloat((i + 1) / 2), side: CGFloat = i % 2 == 0 ? 1 : -1
            let c = P(lead.x + (ltr ? -1 : 1) * row * 13, lead.y + side * row * 7 + (i == 0 ? 0 : 0))
            let flap = CGFloat(sin(time * 9 + Double(i) * 1.3)) * 2.6
            birds.move(to: P(c.x - 5, c.y - flap))
            birds.addQuadCurve(to: c, control: P(c.x - 2.5, c.y - 2.5 - flap))
            birds.addQuadCurve(to: P(c.x + 5, c.y - flap), control: P(c.x + 2.5, c.y - 2.5 - flap))
        }
        ctx.stroke(birds, with: .color(rgb(0x3A4250, 0.7)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
    }

    /// Regenbogen bei Sonnenschauer: tagsüber Niesel oder leichter Regen, nicht jede Stunde.
    func drawRainbow(_ ctx: inout GraphicsContext, _ f: CGRect) {
        guard let w = weather, dayness > 0.75, w.kind == .drizzle || (w.kind == .rain && w.intensity <= 0.5) else { return }
        let hourIndex = UInt64(max(0, time / 3600))
        guard (hourIndex &* 0x2545F4914F6CDD1D) >> 60 < 6 else { return }    // ~ 3 von 8 Stunden
        let c = P(f.minX + f.width * 0.62, f.maxY + 40)
        let cols = [0xE8565A, 0xF29A4A, 0xF2D25A, 0x7CC46A, 0x5AA6E0, 0x7A6AD0].map { rgb($0) }
        for (i, col) in cols.enumerated() {
            var arc = Path()
            arc.addArc(center: c, radius: 250 - CGFloat(i) * 6, startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false)
            ctx.stroke(arc, with: .color(col.opacity(0.22)), lineWidth: 6.5)
        }
    }

    /// Schneemann auf der Wiese, wenn genug Schnee liegt.
    func drawSnowman(_ ctx: inout GraphicsContext, _ f: CGRect) {
        guard snow > 0.55 else { return }
        let b = P(f.minX + 418, f.maxY - 34)
        let white = mix(rgb(0x48516A), rgb(0xFAFBFD), dayness)
        let shade = mix(rgb(0x343B4E), rgb(0xD5DCE6), dayness)
        shadow(&ctx, CGRect(x: b.x - 16, y: b.y - 3, width: 32, height: 6), 0.15 * dayness)
        for (dy, r) in [(-11.0, 12.0), (-29, 9), (-43, 6.5)] as [(CGFloat, CGFloat)] {
            ctx.fill(circle(P(b.x, b.y + dy), r), with: .radialGradient(Gradient(colors: [white, shade]), center: P(b.x - r * 0.35, b.y + dy - r * 0.4), startRadius: 0, endRadius: r * 1.4))
        }
        // Hut, Karottennase, Augen, Schal, Arme
        ctx.fill(rounded(b.x - 6.5, b.y - 50, 13, 2, 1), with: .color(rgb(0x26272B)))
        ctx.fill(rounded(b.x - 4.5, b.y - 57, 9, 7.5, 1.5), with: .color(rgb(0x26272B)))
        var nose = Path(); nose.move(to: P(b.x, b.y - 44)); nose.addLine(to: P(b.x + 6.5, b.y - 42.5)); nose.addLine(to: P(b.x, b.y - 42)); nose.closeSubpath()
        ctx.fill(nose, with: .color(rgb(0xEE8A2C)))
        for dx in [-2.4, 2.4] as [CGFloat] { ctx.fill(circle(P(b.x + dx, b.y - 45.5), 0.9), with: .color(rgb(0x26272B))) }
        ctx.fill(rounded(b.x - 7.5, b.y - 38, 15, 3, 1.5), with: .color(rgb(0xC8323C)))
        ctx.fill(rounded(b.x + 2, b.y - 37, 3, 7, 1.2), with: .color(rgb(0xC8323C)))
        var arms = Path()
        arms.move(to: P(b.x - 8, b.y - 30)); arms.addLine(to: P(b.x - 19, b.y - 37)); arms.move(to: P(b.x - 16, b.y - 35)); arms.addLine(to: P(b.x - 18, b.y - 40))
        arms.move(to: P(b.x + 8, b.y - 30)); arms.addLine(to: P(b.x + 19, b.y - 35))
        ctx.stroke(arms, with: .color(rgb(0x6B5238)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    /// Freitags-Pizza: offener Karton auf dem Couchtisch, zwei Stücke fehlen schon.
    func drawPizza(_ ctx: inout GraphicsContext, at c: CGPoint) {
        let card = rgb(0xD9B48A), cardDark = rgb(0xB98F62)
        // Deckel hochgeklappt (hinten)
        var lid = Path()
        lid.move(to: P(c.x - 22, c.y - 9)); lid.addLine(to: P(c.x + 22, c.y - 9)); lid.addLine(to: P(c.x + 20, c.y - 36)); lid.addLine(to: P(c.x - 20, c.y - 36)); lid.closeSubpath()
        ctx.fill(lid, with: vgrad([lighter(card, 0.1), card], c.y - 36, c.y - 9))
        ctx.fill(circle(P(c.x, c.y - 23), 6), with: .color(rgb(0xC8323C, 0.8)))
        // Unterteil
        var box = Path()
        box.move(to: P(c.x - 24, c.y - 9)); box.addLine(to: P(c.x + 24, c.y - 9)); box.addLine(to: P(c.x + 27, c.y + 1)); box.addLine(to: P(c.x - 27, c.y + 1)); box.closeSubpath()
        ctx.fill(box, with: .color(card))
        ctx.fill(rounded(c.x - 27, c.y + 0.5, 54, 2.5, 1), with: .color(cardDark))
        // Pizza: Oval, zwei Stücke fehlen (Keil ausgespart)
        let pie = CGRect(x: c.x - 20, y: c.y - 8.5, width: 40, height: 9)
        var slices = Path()
        slices.addEllipse(in: pie)
        var gap = Path()
        gap.move(to: P(pie.midX, pie.midY)); gap.addLine(to: P(pie.maxX + 2, pie.minY - 1)); gap.addLine(to: P(pie.maxX + 2, pie.midY + 1)); gap.closeSubpath()
        let pizza = slices.subtracting(gap)
        ctx.fill(pizza, with: .color(rgb(0xE6B25E)))
        ctx.fill(pizza.applying(CGAffineTransform(translationX: pie.midX, y: pie.midY).scaledBy(x: 0.86, y: 0.8).translatedBy(x: -pie.midX, y: -pie.midY)), with: .color(rgb(0xD9553A)))
        var r = SeededRandom(seed: 21)
        for _ in 0..<9 {
            let p = P(pie.minX + 5 + r.next() * 28, pie.minY + 2 + r.next() * 5)
            if gap.contains(p) { continue }
            ctx.fill(oval(p.x - 1.6, p.y - 0.9, 3.2, 1.8), with: .color(rgb(0xB8323A)))
        }
        // Basilikum
        for (dx, dy) in [(-8.0, -5.0), (5, -3), (-2, -2)] as [(CGFloat, CGFloat)] {
            ctx.fill(oval(c.x + dx - 1.5, c.y + dy - 0.8, 3, 1.6), with: .color(rgb(0x4F9A55)))
        }
    }
}
