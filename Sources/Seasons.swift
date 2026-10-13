import SwiftUI

/// Jahreszeit draußen vor dem Glas – fließend aus dem Datum: Frühling (frisches Grün, im April Blüten), Sommer,
/// Herbst (Laub färbt sich), Winter (kahle Äste). Auf der Südhalbkugel (Wetter-Ort) um ein halbes Jahr versetzt.
struct Season: Equatable {
    var spring = 0.0     // 0…1 frisches Hellgrün
    var blossom = 0.0    // 0…1 Blüten in den Kronen
    var autumn = 0.0     // 0…1 Laubfärbung
    var bare = 0.0       // 0…1 Kronen gelichtet (Winter)

    static let summer = Season()

    /// Eimer für den Hintergrund-Cache (Hügel und Wiese ändern sich nur grob)
    var bucket: Int { Int(spring * 4) + Int(autumn * 4) * 5 + Int(bare * 4) * 25 }

    static func of(_ date: Date, cal: Calendar = .current) -> Season {
        var doy = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 180)
        if UserDefaults.standard.bool(forKey: Prefs.weatherEnabled), UserDefaults.standard.double(forKey: Prefs.weatherLat) < -5 {
            doy = (doy + 182).truncatingRemainder(dividingBy: 365)
        }
        func ramp(_ a: Double, _ b: Double) -> Double { min(1, max(0, (doy - a) / (b - a))) }
        var s = Season()
        // Tage im Jahr: 1. März ≈ 60, 1. April ≈ 91, 15. Mai ≈ 135, 1. Juni ≈ 152, 1. Sept ≈ 244, 1. Okt ≈ 274, 1. Nov ≈ 305, 1. Dez ≈ 335
        s.bare = doy < 60 ? 1 : doy < 91 ? 1 - ramp(60, 91) : doy >= 335 ? 1 : doy >= 300 ? ramp(300, 335) : 0
        s.spring = doy < 75 ? 0 : doy < 105 ? ramp(75, 105) : doy < 135 ? 1 : doy < 160 ? 1 - ramp(135, 160) : 0
        s.blossom = doy < 92 ? 0 : doy < 102 ? ramp(92, 102) : doy < 122 ? 1 : doy < 132 ? 1 - ramp(122, 132) : 0
        s.autumn = doy < 250 ? 0 : doy < 300 ? ramp(250, 300) : doy < 340 ? 1 : 0
        if doy < 60 { s.autumn = 0 }
        return s
    }

    /// Zum Testen: AGENTBAR_FAKE_DATE gilt auch für die Jahreszeit
    static func now(_ date: Date) -> Season { of(Festive.fakeDate ?? date) }
}

extension OfficeScene {
    /// Hügel- und Wiesenfarbe je Jahreszeit (Tagfarbe; Nachtfarbe bleibt).
    func seasonal(_ day: Int, autumnTone: Int, winterTone: Int, springTone: Int) -> Color {
        var c = mix(rgb(day), rgb(springTone), season.spring * 0.7)
        c = mix(c, rgb(autumnTone), season.autumn * (1 - season.bare) * 0.75)
        return mix(c, rgb(winterTone), season.bare * 0.8)
    }

    /// Kronenfarben (Licht, Schatten) eines Baums im Jahreslauf; i wählt die Herbstfarbe.
    func crownColors(_ i: Int) -> (Color, Color) {
        var light = rgb(0x8CC474), shade = rgb(0x5E9C52)
        light = mix(light, rgb(0xB3DD84), season.spring); shade = mix(shade, rgb(0x7DB862), season.spring)
        let fall: [(Int, Int)] = [(0xF0B24A, 0xC9772E), (0xE2763E, 0xB04A2C), (0xE9C65A, 0xC0952F), (0xD4893E, 0x9E5A2A)]
        let f = fall[i % fall.count]
        light = mix(light, rgb(f.0), season.autumn); shade = mix(shade, rgb(f.1), season.autumn)
        return (light, shade)
    }

    /// Kahle Äste: Stamm teilt sich in drei Hauptäste mit kleinen Zweigen (Winter, Spätherbst).
    func bareBranches(_ ctx: inout GraphicsContext, x: CGFloat, ty: CGFloat, s: CGFloat, sway: CGFloat, color: Color, opacity: Double) {
        guard opacity > 0.02 else { return }
        var p = Path()
        let top = P(x, ty - 30 * s)
        for (dx, dy, k) in [(-17.0, -62.0, -1.0), (0, -72, 0), (16, -60, 1)] as [(CGFloat, CGFloat, CGFloat)] {
            let end = P(x + dx * s + sway, ty + dy * s)
            p.move(to: top)
            p.addQuadCurve(to: end, control: P(x + dx * 0.3 * s, ty - 46 * s))
            // zwei Zweige je Ast
            let mid = P((top.x + end.x) / 2 + dx * 0.15 * s, (top.y + end.y) / 2)
            p.move(to: mid); p.addLine(to: P(mid.x + (k == 0 ? -9 : k * 10) * s + sway * 0.6, mid.y - 9 * s))
            p.move(to: P(mid.x + dx * 0.2 * s, mid.y - 8 * s)); p.addLine(to: P(mid.x + (k == 0 ? 8 : k * 4) * s + sway * 0.8, mid.y - 19 * s))
        }
        ctx.stroke(p, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
    }

    /// Blüten (rosa/weiß) als Tupfen in der Krone.
    func blossoms(_ ctx: inout GraphicsContext, crown: CGRect, s: CGFloat, seed: Int) {
        guard season.blossom > 0.02 else { return }
        var r = SeededRandom(seed: UInt64(seed * 7 + 11))
        var pink = Path(), white = Path()
        let n = Int(14 * season.blossom)
        for k in 0..<n {
            let a = Double(r.next()) * 2 * .pi, d = sqrt(Double(r.next())) * 0.42
            let c = P(crown.midX + CGFloat(cos(a) * d) * crown.width, crown.midY + CGFloat(sin(a) * d) * crown.height * 0.9)
            let rr = (1.6 + r.next() * 1.2) * s
            let e = CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)
            if (k + seed) % 3 == 0 { white.addEllipse(in: e) } else { pink.addEllipse(in: e) }
        }
        let o = min(1, dayness + 0.35)
        ctx.fill(pink, with: .color(rgb(0xF4B6C8, o)))
        ctx.fill(white, with: .color(rgb(0xFFF4F6, o)))
    }

    /// Herbstlaub am Boden unter den Bäumen.
    func fallenLeaves(_ ctx: inout GraphicsContext, x: CGFloat, ty: CGFloat, s: CGFloat, i: Int) {
        let amount = season.autumn * (0.3 + 0.7 * season.bare) + season.autumn * 0.25
        guard amount > 0.1, snow < 0.3 else { return }
        var r = SeededRandom(seed: UInt64(i * 13 + 5))
        let (light, shade) = crownColors(i)
        var a = Path(), b = Path()
        for k in 0..<Int(10 * amount) {
            let c = P(x + (r.next() - 0.5) * 50 * s, ty - 2 * s + (r.next() - 0.5) * 6 * s)
            let e = CGRect(x: c.x - 1.8 * s, y: c.y - 1 * s, width: 3.6 * s, height: 2 * s)
            if k % 2 == 0 { a.addEllipse(in: e) } else { b.addEllipse(in: e) }
        }
        ctx.fill(a, with: .color(mix(rgb(0x2A2620), light, dayness).opacity(0.9)))
        ctx.fill(b, with: .color(mix(rgb(0x2A2620), shade, dayness).opacity(0.9)))
    }
}
