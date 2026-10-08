import SwiftUI

/// Was eine Figur heute trägt. Jede Figur würfelt selbst – fest aus Sitzungs-ID und Tag, also den ganzen Tag gleich,
/// aber anders als die Nachbarn und morgen vielleicht anders.
struct Outfit: Equatable {
    enum Theme { case none, christmas, newYear }
    enum Hat: Equatable { case none, santa, antlers, party(Int), beanie(Int) }

    var hat = Hat.none
    /// Weihnachtspulli: ersetzt die Shirtfarbe, dazu ein Muster über der Brust
    var sweater: Int?
    var scarf: Int?
    var sunglasses = false

    static let none = Outfit()

    static let sweaterColors = [rgb(0xB8323A), rgb(0x2F6A45), rgb(0x2E4A7A)]
    static let woolColors = [rgb(0xC8323C), rgb(0x3D6FB0), rgb(0xE0A93E), rgb(0x5E9C6B), rgb(0x8E6BC2), rgb(0xD9D3C7)]
    static let partyColors = [(rgb(0xE8B84A), rgb(0xFFF3C4)), (rgb(0xE97A9A), rgb(0xFFE1EA)), (rgb(0x6FA8E8), rgb(0xE2F0FF)), (rgb(0xA98FDC), rgb(0xEFE6FF))]

    /// Stabiler Hash (Swifts Hasher ist je Programmstart anders)
    private static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    static func pick(id: String, day: Int, festive: Festive, temperature: Double?, walking: Bool) -> Outfit {
        var r = SeededRandom(seed: fnv(id) ^ (UInt64(bitPattern: Int64(day)) &* 0x9E3779B97F4A7C15))
        var o = Outfit()
        let joins = Double(r.next()) < festive.outfitChance
        let k = Double(r.next()), variant = Int(r.next() * 97)
        switch festive.outfitTheme {
        case .christmas where joins:
            if k < 0.32 { o.hat = .santa }
            else if k < 0.55 { o.hat = .antlers }
            else {
                o.sweater = variant % sweaterColors.count
                if k > 0.88 { o.hat = .santa }          // ganz Eifrige: Pulli und Mütze
            }
        case .newYear where joins:
            o.hat = .party(variant % partyColors.count)
        default: break
        }
        if let t = temperature {
            let roll = Double(r.next())
            if t < 3 && roll < 0.45 { o.scarf = (variant / 3) % woolColors.count }
            // Wer gerade von draußen kommt, hat noch die Mütze auf
            if t < 3 && walking && o.hat == .none { o.hat = .beanie((variant / 7) % woolColors.count) }
            if t > 27 && roll < 0.35 { o.sunglasses = true }
        }
        return o
    }
}

// MARK: - Zeichnen

extension OfficeScene {
    /// Outfits für alle Figuren dieses Bildes (Tag aus dem Szenen-Datum).
    static func dress(_ actors: [Actor], date: Date, festive: Festive, weather: Weather?) -> [Actor] {
        guard festive.outfitTheme != .none || weather != nil else { return actors }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return actors.map { a in
            var b = a
            var walking = false
            if case .walking = a.pose { walking = true }
            b.outfit = Outfit.pick(id: a.id, day: day, festive: festive, temperature: weather?.temperature, walking: walking)
            if let c = b.outfit.sweater { b.look.shirt = Outfit.sweaterColors[c] }
            return b
        }
    }

    /// Strickmuster über der Brust: weiße Zacken, darunter Punkte – auf die Rumpf-Form beschnitten.
    func drawSweaterPattern(_ ctx: inout GraphicsContext, torso: Path, x: CGFloat, y: CGFloat, width w: CGFloat, s: CGFloat) {
        var c = ctx
        c.clip(to: torso)
        let white = rgb(0xF4EFE6, 0.9)
        c.fill(Path(CGRect(x: x - w / 2, y: y - 1.2 * s, width: w, height: 1.6 * s)), with: .color(white))
        c.fill(Path(CGRect(x: x - w / 2, y: y + 9 * s, width: w, height: 1.6 * s)), with: .color(white))
        var zig = Path()
        let step = 5 * s
        var px = x - w / 2
        zig.move(to: P(px, y + 7 * s))
        var up = true
        while px < x + w / 2 {
            px += step
            zig.addLine(to: P(px, up ? y + 2 * s : y + 7 * s))
            up.toggle()
        }
        c.stroke(zig, with: .color(white), style: StrokeStyle(lineWidth: 1.5 * s, lineJoin: .round))
        var dots = Path()
        var dx = x - w / 2 + 3 * s
        while dx < x + w / 2 {
            dots.addEllipse(in: CGRect(x: dx - 1 * s, y: y + 14 * s, width: 2 * s, height: 2 * s))
            dx += 6 * s
        }
        c.fill(dots, with: .color(white))
    }

    /// Schal um den Hals, ein Ende hängt vorn herunter.
    func drawScarf(_ ctx: inout GraphicsContext, outfit o: Outfit, x: CGFloat, shoulderY: CGFloat, s: CGFloat) {
        guard let i = o.scarf else { return }
        let col = Outfit.woolColors[i]
        let band = CGRect(x: x - 15 * s, y: shoulderY - 5 * s, width: 30 * s, height: 9 * s)
        ctx.fill(Path(roundedRect: band, cornerRadius: 4.5 * s, style: .continuous), with: vgrad([lighter(col, 0.12), darker(col, 0.12)], band.minY, band.maxY))
        let tail = CGRect(x: x + 3 * s, y: shoulderY + 1 * s, width: 8 * s, height: 20 * s)
        ctx.fill(Path(roundedRect: tail, cornerRadius: 3 * s, style: .continuous), with: .color(darker(col, 0.06)))
        for k in 0..<3 {   // Fransen
            ctx.fill(Path(CGRect(x: tail.minX + (1 + CGFloat(k) * 2.6) * s, y: tail.maxY - 0.5 * s, width: 1.2 * s, height: 3 * s)), with: .color(col))
        }
        ctx.fill(Path(CGRect(x: band.minX + 3 * s, y: band.midY - 0.4 * s, width: band.width - 6 * s, height: 0.8 * s)), with: .color(.white.opacity(0.25)))
    }

    /// Kopfbedeckung im Kopf-Koordinatensystem (Mitte des Gesichts = 0,0; r = Kopfradius).
    func drawHat(_ ctx: inout GraphicsContext, outfit o: Outfit, r: CGFloat, s: CGFloat) {
        switch o.hat {
        case .none:
            return
        case .santa:
            // Rote Zipfelmütze, Spitze fällt zur Seite, weiße Krempe und Bommel
            var cone = Path()
            cone.move(to: P(-r * 0.92, -r * 0.5))
            cone.addQuadCurve(to: P(r * 0.2, -r * 1.62), control: P(-r * 0.75, -r * 1.45))
            cone.addQuadCurve(to: P(r * 1.18, -r * 0.95), control: P(r * 0.95, -r * 1.7))
            cone.addQuadCurve(to: P(r * 0.92, -r * 0.5), control: P(r * 0.7, -r * 1.05))
            cone.closeSubpath()
            ctx.fill(cone, with: .linearGradient(Gradient(colors: [rgb(0xDA414A), rgb(0xA92A33)]), startPoint: P(-r, -r * 1.5), endPoint: P(r, -r * 0.5)))
            ctx.fill(Path(roundedRect: CGRect(x: -r * 1.02, y: -r * 0.68, width: r * 2.04, height: 9 * s), cornerRadius: 4.5 * s, style: .continuous),
                     with: vgrad([.white, rgb(0xE6E6EA)], -r * 0.68, -r * 0.68 + 9 * s))
            ctx.fill(circle(P(r * 1.2, -r * 0.9), 5 * s), with: .radialGradient(Gradient(colors: [.white, rgb(0xDDDDE2)]), center: P(r * 1.15, -r * 0.95), startRadius: 0, endRadius: 6 * s))
        case .antlers:
            // Haarreif mit Geweih und kleinen Ohren
            var band = Path()
            band.addArc(center: P(0, -r * 0.05), radius: r * 1.0, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(band, with: .color(rgb(0x3A2A20)), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
            let brown = rgb(0x9B6B43)
            for side in [-1.0, 1.0] as [CGFloat] {
                let base = P(side * r * 0.5, -r * 0.88)
                var a = Path()
                a.move(to: base)
                a.addQuadCurve(to: P(side * r * 0.82, -r * 1.75), control: P(side * r * 0.45, -r * 1.4))
                a.move(to: P(side * r * 0.56, -r * 1.22)); a.addLine(to: P(side * r * 0.95, -r * 1.38))
                a.move(to: P(side * r * 0.68, -r * 1.5)); a.addLine(to: P(side * r * 0.5, -r * 1.78))
                ctx.stroke(a, with: .color(brown), style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round, lineJoin: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: -4 * s, y: -2.5 * s, width: 8 * s, height: 5 * s))
                            .applying(CGAffineTransform(translationX: side * r * 0.95, y: -r * 0.78).rotated(by: side * 0.5)),
                         with: .color(rgb(0x7A5235)))
            }
        case .party(let i):
            let (col, stripe) = Outfit.partyColors[i % Outfit.partyColors.count]
            let tip = P(r * 0.12, -r * 1.95)
            var cone = Path()
            cone.move(to: P(-r * 0.42, -r * 0.82)); cone.addLine(to: tip); cone.addLine(to: P(r * 0.48, -r * 0.8)); cone.closeSubpath()
            ctx.fill(cone, with: .linearGradient(Gradient(colors: [lighter(col, 0.2), col]), startPoint: P(-r * 0.4, 0), endPoint: P(r * 0.5, 0)))
            var c = ctx
            c.clip(to: cone)
            for k in 0..<4 {
                let y = -r * 0.95 - CGFloat(k) * r * 0.27
                var band = Path(); band.move(to: P(-r, y + 3 * s)); band.addLine(to: P(r, y - 3 * s))
                c.stroke(band, with: .color(stripe), lineWidth: 2.4 * s)
            }
            ctx.fill(circle(tip, 3.6 * s), with: .color(stripe))
            // Gummiband
            var elastic = Path(); elastic.move(to: P(-r * 0.4, -r * 0.82)); elastic.addQuadCurve(to: P(-r * 0.7, r * 0.55), control: P(-r * 0.85, -r * 0.1))
            ctx.stroke(elastic, with: .color(.white.opacity(0.5)), lineWidth: 0.7 * s)
        case .beanie(let i):
            let col = Outfit.woolColors[i % Outfit.woolColors.count]
            var dome = Path()
            dome.addArc(center: P(0, -r * 0.45), radius: r * 1.02, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            dome.closeSubpath()
            ctx.fill(dome, with: .linearGradient(Gradient(colors: [lighter(col, 0.15), darker(col, 0.1)]), startPoint: P(-r, -r * 1.4), endPoint: P(r, -r * 0.4)))
            let cuff = CGRect(x: -r * 1.06, y: -r * 0.62, width: r * 2.12, height: 9 * s)
            ctx.fill(Path(roundedRect: cuff, cornerRadius: 4 * s, style: .continuous), with: .color(darker(col, 0.08)))
            var ribs = Path()
            var x = cuff.minX + 3 * s
            while x < cuff.maxX - 2 * s { ribs.move(to: P(x, cuff.minY + 1.5 * s)); ribs.addLine(to: P(x, cuff.maxY - 1.5 * s)); x += 3.2 * s }
            ctx.stroke(ribs, with: .color(.black.opacity(0.12)), lineWidth: 0.8 * s)
            ctx.fill(circle(P(0, -r * 1.5), 6 * s), with: .color(lighter(col, 0.3)))
        }
    }

    /// Sonnenbrille über den Augen.
    func drawSunglasses(_ ctx: inout GraphicsContext, eyeY: CGFloat, s: CGFloat) {
        for side in [-1.0, 1.0] as [CGFloat] {
            let lens = CGRect(x: side * 8.2 * s - 6.6 * s, y: eyeY - 5 * s, width: 13.2 * s, height: 10 * s)
            ctx.fill(Path(roundedRect: lens, cornerRadius: 4.5 * s, style: .continuous), with: vgrad([rgb(0x3A3D45), rgb(0x16171B)], lens.minY, lens.maxY))
            ctx.fill(Path(roundedRect: CGRect(x: lens.minX + 2 * s, y: lens.minY + 1.5 * s, width: 4.5 * s, height: 1.8 * s), cornerRadius: 0.9 * s), with: .color(.white.opacity(0.4)))
        }
        var bridge = Path(); bridge.move(to: P(-1.8 * s, eyeY - 2 * s)); bridge.addQuadCurve(to: P(1.8 * s, eyeY - 2 * s), control: P(0, eyeY - 3.6 * s))
        ctx.stroke(bridge, with: .color(rgb(0x16171B)), lineWidth: 1.4 * s)
    }
}
