import SwiftUI

/// Zeichnet das Büro in einem festen 1000×600-Koordinatensystem (wird aufs Fenster skaliert).
/// Stil: helle Apple-Büros – Glasfassade, Eichenparkett, weiße Tische, Aluminium, sanftes Licht.
/// Alles ist aus einfachen Formen mit Verläufen gebaut; keine Filter über große Flächen (30 fps).
struct OfficeScene {
    static let size = CGSize(width: 1000, height: 600)
    static let floorY: CGFloat = 360
    /// Glasfassade (raumhoch) hinter den Tischen
    static let glass = CGRect(x: 22, y: 30, width: 672, height: 330)
    static let panes = 6

    let time: Double
    let date: Date
    let dark: Bool
    let daylight: Bool
    let actors: [Actor]
    let overflow: Int
    let hovered: String?
    let session: Double?
    let weekly: Double?
    let plan: String?
    let cpu: Double
    let working: Int
    let waiting: Int

    // MARK: Farben

    private var wallTop: Color { dark ? rgb(0x2A2B2F) : rgb(0xF6F3EE) }
    private var wallBottom: Color { dark ? rgb(0x222326) : rgb(0xECE7E0) }
    private var ceiling: Color { dark ? rgb(0x1C1D20) : rgb(0xE9E5DE) }
    private var floorTop: Color { dark ? rgb(0x4A3C2F) : rgb(0xE2CCA8) }
    private var floorBottom: Color { dark ? rgb(0x3B3027) : rgb(0xD5B78F) }
    private var plank: Color { dark ? rgb(0x000000, 0.28) : rgb(0xA8845A, 0.30) }
    private var deskTop: Color { dark ? rgb(0xE4E4E7) : rgb(0xFDFDFD) }
    private var deskTop2: Color { dark ? rgb(0xCFCFD4) : rgb(0xF0F0F2) }
    private var deskEdge: Color { dark ? rgb(0xB9B9BF) : rgb(0xDEDEE3) }
    private var frame: Color { dark ? rgb(0x4B4E54) : rgb(0xD8DBE0) }
    private var oak: Color { dark ? rgb(0x8A6D4E) : rgb(0xCDA97C) }
    private var ink: Color { dark ? .white : rgb(0x1D1D1F) }
    private let alu = rgb(0xC5C9CF)
    private let aluDark = rgb(0x9A9FA6)

    /// Stunde als Kommazahl; ohne Tageszeit-Himmel: hell = Mittag, dunkel = Nacht.
    private var hour: Double {
        guard daylight else { return dark ? 23 : 12 }
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    /// 0 = Nacht, 1 = Tag
    private var dayness: Double {
        let h = hour
        if h < 5 || h > 21 { return 0 }
        if h < 7.5 { return (h - 5) / 2.5 }
        if h > 18.5 { return 1 - (h - 18.5) / 2.5 }
        return 1
    }

    /// 0 = Mittag, 1 = tief stehende Sonne (Morgen-/Abendröte)
    private var golden: Double {
        let h = hour
        guard h > 5.5 && h < 21 else { return 0 }
        let fromEdge = min(h - 5.5, 21 - h)
        return max(0, 1 - fromEdge / 3.2)
    }

    // MARK: Einstieg

    func draw(_ ctx: inout GraphicsContext) {
        drawWall(&ctx)
        drawGlass(&ctx)
        drawFloor(&ctx)
        drawSunlight(&ctx)

        // Tiefensortiert: Tischgruppen, Lounge, Pflanzen, Laufende, Saugroboter
        var items: [(CGFloat, (inout GraphicsContext) -> Void)] = []
        let seated = Dictionary(grouping: actors.filter { if case .walking = $0.pose { return false }; return true }) { a -> String in
            switch a.place {
            case .desk(let i), .napAtDesk(let i): return "d\(i)"
            case .sofa: return "sofa"
            case .stand: return "stand"
            }
        }
        for i in 0..<OfficeModel.deskCount {
            let (p, s) = OfficeModel.deskSeat(i)
            let who = seated["d\(i)"]?.first
            items.append((p.y + 5, { c in drawDesk(&c, index: i, at: p, scale: s, actor: who) }))
        }
        items.append((400, { c in drawFloorLamp(&c) }))
        items.append((492, { c in drawSofa(&c, actors: seated["sofa"] ?? []) }))
        items.append((452, { c in drawFig(&c, at: CGPoint(x: 712, y: 452), scale: 0.95) }))
        items.append((474, { c in drawSnakePlant(&c, at: CGPoint(x: 44, y: 474), scale: 1.0) }))
        items.append((566, { c in drawCoffeeTable(&c) }))
        for a in seated["stand"] ?? [] { items.append((a.point.y, { c in drawStanding(&c, a, walk: 0) })) }
        for a in actors { if case .walking(let t) = a.pose { items.append((a.depth, { c in drawStanding(&c, a, walk: t) })) } }
        items.append((592, { c in drawVacuum(&c) }))
        for (_, f) in items.sorted(by: { $0.0 < $1.0 }) { f(&ctx) }

        drawLighting(&ctx, seated: seated)
        drawDisplay(&ctx)
        for a in actors { drawLabels(&ctx, a) }
        if let h = hovered, let a = actors.first(where: { $0.id == h }) { drawHover(&ctx, a) }
    }

    static func hitRect(_ a: Actor) -> CGRect {
        let s = a.scale
        if case .walking = a.pose { return CGRect(x: a.point.x - 26 * s, y: a.point.y - 138 * s, width: 52 * s, height: 140 * s) }
        return CGRect(x: a.point.x - 38 * s, y: a.point.y - 118 * s, width: 76 * s, height: 142 * s)
    }

    // MARK: Hilfen

    private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)) }
    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
    private func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: min(r, w / 2, h / 2), style: .continuous)
    }
    private func vgrad(_ colors: [Color], _ y0: CGFloat, _ y1: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: P(0, y0), endPoint: P(0, y1))
    }
    private func glow(_ c: CGPoint, _ r: CGFloat, _ color: Color, _ o: Double) -> GraphicsContext.Shading {
        .radialGradient(Gradient(colors: [color.opacity(o), color.opacity(o * 0.35), color.opacity(0)]), center: c, startRadius: 0, endRadius: r)
    }
    private func blob(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color, _ o: Double) {
        ctx.fill(circle(c, r), with: glow(c, r, color, o))
    }
    /// Weicher Bodenschatten (Radialverlauf statt Blur-Filter)
    private func shadow(_ ctx: inout GraphicsContext, _ r: CGRect, _ o: Double = 0.12) {
        ctx.fill(Path(ellipseIn: r), with: .radialGradient(Gradient(colors: [.black.opacity(o), .black.opacity(o * 0.4), .clear]),
                                                          center: P(r.midX, r.midY), startRadius: 0, endRadius: r.width / 2))
    }
    /// Farbmischung (0 = a, 1 = b)
    private func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let na = NSColor(a).usingColorSpace(.sRGB) ?? .gray, nb = NSColor(b).usingColorSpace(.sRGB) ?? .gray
        return Color(nsColor: na.blended(withFraction: CGFloat(max(0, min(1, t))), of: nb) ?? na)
    }
    private func darker(_ c: Color, _ t: Double) -> Color { mix(c, .black, t) }
    private func lighter(_ c: Color, _ t: Double) -> Color { mix(c, .white, t) }

    // MARK: Raum

    private func drawWall(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 1000, height: Self.floorY)), with: vgrad([wallTop, wallBottom], 0, Self.floorY))
        // Rechte Wandfläche bekommt etwas Streiflicht vom Glas
        let g = Self.glass
        ctx.fill(Path(CGRect(x: g.maxX, y: 0, width: 1000 - g.maxX, height: Self.floorY)),
                 with: .linearGradient(Gradient(colors: [.white.opacity(dark ? 0.03 : 0.35), .clear]), startPoint: P(g.maxX, 0), endPoint: P(g.maxX + 180, 0)))
        ctx.fill(Path(CGRect(x: g.maxX + 4, y: 0, width: 10, height: Self.floorY)),
                 with: .linearGradient(Gradient(colors: [.black.opacity(dark ? 0.25 : 0.06), .clear]), startPoint: P(g.maxX + 4, 0), endPoint: P(g.maxX + 14, 0)))
        // Decke mit eingelassenen Lichtfugen
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 1000, height: 22)), with: vgrad([darker(ceiling, 0.04), ceiling], 0, 22))
        ctx.fill(Path(CGRect(x: 0, y: 22, width: 1000, height: 1)), with: .color(.black.opacity(dark ? 0.3 : 0.06)))
        let lit = 1 - dayness
        for x in stride(from: 100.0, through: 900, by: 200) {
            ctx.fill(rounded(x - 56, 15, 112, 4, 2), with: .color(dark || lit > 0.3 ? rgb(0xFFE8C2, 0.75 + 0.25 * lit) : .white))
        }
        // Sockelleiste an der Wand rechts
        ctx.fill(Path(CGRect(x: g.maxX, y: Self.floorY - 7, width: 1000 - g.maxX, height: 7)), with: .color(dark ? rgb(0x303135) : .white))
    }

    private func drawGlass(_ ctx: inout GraphicsContext) {
        let g = Self.glass
        let sky = skyColors()
        ctx.drawLayer { c in
            c.clip(to: Path(g))
            c.fill(Path(g), with: vgrad([sky.0, sky.1], g.minY, g.minY + 250))
            drawSkyObjects(&c, g)
            drawLandscape(&c, g)
            // Dunst: Himmel färbt die Landschaft leicht (Abendrot, Nacht)
            c.fill(Path(g), with: vgrad([sky.1.opacity(0), sky.1.opacity(0.10 + 0.15 * golden)], g.minY + 150, g.maxY))
            // Leichte Tönung und Spiegelungen im Glas
            c.fill(Path(g), with: .color(rgb(0x9FB8C8, dark ? 0.05 : 0.06)))
            let sheen = dark || dayness < 0.4 ? 0.035 : 0.09
            for (x0, w) in [(g.minX + 40, 70.0), (g.minX + 150, 26.0), (g.minX + 380, 90.0), (g.minX + 500, 30.0)] as [(CGFloat, CGFloat)] {
                var p = Path()
                p.move(to: P(x0 + 90, g.minY)); p.addLine(to: P(x0 + 90 + w, g.minY))
                p.addLine(to: P(x0 + w - 60, g.maxY)); p.addLine(to: P(x0 - 60, g.maxY)); p.closeSubpath()
                c.fill(p, with: .linearGradient(Gradient(colors: [.white.opacity(sheen), .white.opacity(0)]), startPoint: P(0, g.minY), endPoint: P(0, g.maxY)))
            }
            // Nachts spiegelt das Glas den warmen Innenraum
            let night = 1 - dayness
            if night > 0.05 {
                c.fill(Path(g), with: vgrad([.clear, rgb(0xFFC77A, 0.10 * night)], g.midY, g.maxY))
            }
        }
        // Aluminium-Profile: Kopfprofil, Pfosten, Bodenschiene
        let fr = frame
        let hi = Color.white.opacity(dark ? 0.12 : 0.7)
        ctx.fill(Path(CGRect(x: g.minX - 5, y: g.minY - 6, width: g.width + 10, height: 7)), with: .color(fr))
        ctx.fill(Path(CGRect(x: g.minX - 5, y: g.minY, width: g.width + 10, height: 1.5)), with: .color(.black.opacity(0.08)))
        for i in 0...Self.panes {
            let x = g.minX + g.width * CGFloat(i) / CGFloat(Self.panes)
            let w: CGFloat = (i == 0 || i == Self.panes) ? 6 : 4
            ctx.fill(Path(CGRect(x: x - w / 2, y: g.minY, width: w, height: g.height)), with: .color(fr))
            ctx.fill(Path(CGRect(x: x - w / 2, y: g.minY, width: 1, height: g.height)), with: .color(hi))
        }
        ctx.fill(Path(CGRect(x: g.minX - 5, y: g.maxY - 5, width: g.width + 10, height: 5)), with: .color(darker(fr, 0.08)))
    }

    private func skyColors() -> (Color, Color) {
        typealias C = (Double, Double, Double)
        let keys: [(Double, C, C)] = [
            (0, (0.05, 0.07, 0.16), (0.13, 0.16, 0.30)),
            (5, (0.06, 0.08, 0.19), (0.16, 0.18, 0.33)),
            (6.4, (0.47, 0.53, 0.78), (0.99, 0.78, 0.62)),
            (8.5, (0.42, 0.66, 0.93), (0.84, 0.92, 0.98)),
            (17, (0.40, 0.64, 0.92), (0.86, 0.93, 0.98)),
            (19.3, (0.36, 0.38, 0.64), (0.99, 0.70, 0.52)),
            (21, (0.07, 0.09, 0.21), (0.18, 0.20, 0.36)),
            (24, (0.05, 0.07, 0.16), (0.13, 0.16, 0.30)),
        ]
        let h = hour
        var i = 0
        while i < keys.count - 2 && keys[i + 1].0 <= h { i += 1 }
        let a = keys[i], b = keys[i + 1]
        let t = max(0, min(1, (h - a.0) / (b.0 - a.0)))
        func m(_ x: C, _ y: C) -> Color { Color(red: x.0 + (y.0 - x.0) * t, green: x.1 + (y.1 - x.1) * t, blue: x.2 + (y.2 - x.2) * t) }
        return (m(a.1, b.1), m(a.2, b.2))
    }

    private func drawSkyObjects(_ ctx: inout GraphicsContext, _ f: CGRect) {
        let h = hour
        if dayness < 0.6 {
            var rng = SeededRandom(seed: 7)
            for _ in 0..<55 {
                let x = f.minX + rng.next() * f.width, y = f.minY + rng.next() * 190
                let sz = 0.8 + rng.next() * 1.3
                let tw = 0.5 + 0.5 * sin(time * (0.8 + Double(rng.next()) * 1.6) + Double(rng.next()) * 6)
                ctx.fill(oval(x, y, sz, sz), with: .color(.white.opacity((1 - dayness) * (0.35 + 0.55 * tw))))
            }
        }
        // Sonne 6–20:30 Uhr, sonst Mond
        let isSun = h >= 6 && h <= 20.5
        let p = isSun ? (h - 6) / 14.5 : ((h < 6 ? h + 24 : h) - 20.5) / 9.5
        let x = f.minX + 50 + CGFloat(p) * (f.width - 100)
        let y = f.minY + 210 - CGFloat(sin(p * .pi)) * 165
        if isSun {
            let tint = mix(rgb(0xFFF6D6), rgb(0xFFC48A), golden)
            blob(&ctx, P(x, y), 110, tint, 0.55)
            ctx.fill(circle(P(x, y), 17), with: .radialGradient(Gradient(colors: [.white, tint]), center: P(x - 4, y - 4), startRadius: 0, endRadius: 20))
        } else {
            blob(&ctx, P(x, y), 60, rgb(0xDDE6FF), 0.18)
            let moon = circle(P(x, y), 12).subtracting(circle(P(x + 7, y - 4), 11))
            ctx.fill(moon, with: .color(rgb(0xF4F1E8)))
        }
        // Wolken ziehen langsam
        let cloudTop = mix(rgb(0x5A6380), .white, dayness)
        let cloudBottom = mix(rgb(0x3A4260), mix(rgb(0xDCE6F2), rgb(0xFFCFB0), golden), dayness)
        for (i, c) in [(0.0, 1.0), (0.42, 0.75), (0.7, 0.9)].enumerated() {
            let speed = 3.0 + Double(i) * 1.6
            let span = Double(f.width + 240)
            let cx = f.minX - 120 + CGFloat((time * speed + c.0 * span).truncatingRemainder(dividingBy: span))
            let cy = f.minY + 50 + CGFloat(i) * 34
            let k = CGFloat(c.1)
            var cloud = Path()
            for (dx, dy, r) in [(0.0, 4.0, 15.0), (18, -6, 20), (40, -2, 17), (58, 5, 12), (26, 7, 16)] as [(CGFloat, CGFloat, CGFloat)] {
                cloud.addEllipse(in: CGRect(x: cx + dx * k - r * k, y: cy + dy * k - r * k * 0.78, width: 2 * r * k, height: 1.56 * r * k))
            }
            ctx.fill(cloud, with: vgrad([cloudTop.opacity(0.9), cloudBottom.opacity(0.85)], cy - 22 * k, cy + 16 * k))
        }
    }

    private func drawLandscape(_ ctx: inout GraphicsContext, _ f: CGRect) {
        let d = dayness
        func tone(_ day: Int, _ night: Int) -> Color { mix(rgb(night), rgb(day), d) }
        let b = f.maxY
        func hill(_ y0: CGFloat, _ c1: CGPoint, _ c2: CGPoint, _ y1: CGFloat) -> Path {
            var p = Path()
            p.move(to: P(f.minX, y0))
            p.addCurve(to: P(f.maxX, y1), control1: c1, control2: c2)
            p.addLine(to: P(f.maxX, b)); p.addLine(to: P(f.minX, b)); p.closeSubpath()
            return p
        }
        // Ferne Berge (bläulich, Luftperspektive)
        ctx.fill(hill(b - 128, P(f.minX + 180, b - 170), P(f.maxX - 260, b - 105), b - 140), with: .color(tone(0xB4C7CF, 0x1C2436)))
        // Hügel mit Baumreihe
        ctx.fill(hill(b - 104, P(f.minX + 220, b - 132), P(f.maxX - 180, b - 88), b - 110), with: .color(tone(0xA9C99A, 0x19282A)))
        var rng = SeededRandom(seed: 3)
        var line = Path()
        for i in 0..<56 {
            let x = f.minX + CGFloat(i) * 12.5 + rng.next() * 6
            let y = b - 106 + CGFloat(sin(Double(i) * 0.35)) * 4
            let r = 5 + rng.next() * 4
            line.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r * 1.1))
        }
        ctx.fill(line, with: .color(tone(0x93B98A, 0x162322)))
        // Wiese vorn mit sanftem Lichtverlauf
        let meadow = hill(b - 66, P(f.minX + 240, b - 92), P(f.maxX - 200, b - 44), b - 70)
        ctx.fill(meadow, with: vgrad([tone(0x9DCB7E, 0x16241E), tone(0x7FB266, 0x121E19)], b - 90, b))
        // Bäume (Obstgarten-Anmutung): runde Kronen mit Licht oben links
        let trees: [(CGFloat, CGFloat, CGFloat)] = [(30, 0, 1.0), (96, 6, 0.8), (168, -4, 1.2), (250, 10, 0.72), (318, 4, 0.9),
                                                    (500, 8, 0.85), (566, -2, 1.15), (626, 6, 0.8), (650, 14, 1.05)]
        for (i, (tx, dy, s)) in trees.enumerated() {
            let x = f.minX + tx
            let sway = CGFloat(sin(time * 0.7 + Double(i))) * 1.2
            let ty = b - 40 + dy
            shadow(&ctx, CGRect(x: x - 22 * s, y: ty - 4 * s, width: 44 * s, height: 8 * s), 0.18 * d)
            ctx.fill(rounded(x - 2.2 * s, ty - 30 * s, 4.4 * s, 30 * s, 2 * s), with: .color(tone(0x8A6A4C, 0x1B1714)))
            let crown = CGRect(x: x - 23 * s + sway, y: ty - 72 * s, width: 46 * s, height: 50 * s)
            ctx.fill(Path(ellipseIn: crown), with: .radialGradient(Gradient(colors: [tone(0x8CC474, 0x223B2F), tone(0x5E9C52, 0x16291F)]),
                                                                    center: P(crown.minX + crown.width * 0.35, crown.minY + crown.height * 0.3),
                                                                    startRadius: 0, endRadius: crown.width * 0.75))
        }
    }

    private func drawFloor(_ ctx: inout GraphicsContext) {
        let top = Self.floorY
        ctx.fill(Path(CGRect(x: 0, y: top, width: 1000, height: 600 - top)), with: vgrad([floorTop, floorBottom], top, 600))
        // Dielen in Fluchtperspektive, Stöße versetzt, leichte Tonvariation je Brett
        let vp = P(500, -900)
        func xAt(_ xb: CGFloat, _ y: CGFloat) -> CGFloat { vp.x + (xb - vp.x) * (y - vp.y) / (600 - vp.y) }
        var rng = SeededRandom(seed: 11)
        let pw: CGFloat = 46
        var xb: CGFloat = -340
        while xb < 1340 {
            let v = Double(rng.next())
            var strip = Path()
            strip.move(to: P(xAt(xb, top), top)); strip.addLine(to: P(xAt(xb + pw, top), top))
            strip.addLine(to: P(xb + pw, 600)); strip.addLine(to: P(xb, 600)); strip.closeSubpath()
            ctx.fill(strip, with: .color((v > 0.5 ? Color.white : Color.black).opacity((dark ? 0.03 : 0.045) * abs(v - 0.5) * 2)))
            var seam = Path(); seam.move(to: P(xAt(xb, top), top)); seam.addLine(to: P(xb, 600))
            ctx.stroke(seam, with: .color(plank), lineWidth: 0.7)
            var y = top + rng.next() * 40
            while y < 600 {
                ctx.fill(Path(CGRect(x: xAt(xb, y), y: y, width: xAt(xb + pw, y) - xAt(xb, y), height: 0.7)), with: .color(plank))
                y += (44 + rng.next() * 46) * (y - vp.y) / (600 - vp.y)
            }
            xb += pw
        }
        // Übergang zur Wand: Kontaktschatten
        ctx.fill(Path(CGRect(x: 0, y: top, width: 1000, height: 14)), with: vgrad([.black.opacity(dark ? 0.25 : 0.08), .clear], top, top + 14))
        // Teppich unter der Lounge (Wolle, weiche Kante)
        let rug = CGRect(x: 718, y: 500, width: 278, height: 92)
        shadow(&ctx, rug.insetBy(dx: -6, dy: -2), dark ? 0.2 : 0.06)
        ctx.fill(Path(roundedRect: rug, cornerRadius: 45, style: .continuous),
                 with: vgrad([dark ? rgb(0x5E5A55) : rgb(0xF4EFE7), dark ? rgb(0x524E4A) : rgb(0xE8E1D6)], rug.minY, rug.maxY))
        ctx.stroke(Path(roundedRect: rug.insetBy(dx: 7, dy: 6), cornerRadius: 39, style: .continuous),
                   with: .color(dark ? .white.opacity(0.06) : rgb(0xC7B69B, 0.45)), lineWidth: 1)
    }

    /// Sonnenflecken, die durch die Glasfassade aufs Parkett fallen – Länge und Farbe folgen dem Sonnenstand.
    private func drawSunlight(_ ctx: inout GraphicsContext) {
        let h = hour
        guard h > 6.2 && h < 20.2 else { return }
        let p = (h - 6) / 14.5
        let elev = sin(p * .pi)
        let strength = min(1, (h - 6.2) / 0.8, (20.2 - h) / 0.8)
        let color = mix(rgb(0xFFF8E6), rgb(0xFFB870), golden)
        let len = CGFloat(110 + (1 - elev) * 120)
        let dx = CGFloat(0.5 - p) * 2 * 150
        let g = Self.glass
        let pw = g.width / CGFloat(Self.panes)
        let top = Self.floorY
        let o = (dark ? 0.10 : 0.26) * strength
        for i in 0..<Self.panes {
            let x0 = g.minX + CGFloat(i) * pw + 3, x1 = x0 + pw - 6
            var q = Path()
            q.move(to: P(x0, top)); q.addLine(to: P(x1, top)); q.addLine(to: P(x1 + dx, top + len)); q.addLine(to: P(x0 + dx, top + len)); q.closeSubpath()
            ctx.fill(q, with: vgrad([color.opacity(o), color.opacity(o * 0.45), color.opacity(0)], top, top + len))
        }
    }

    /// Wand-Display: Uhr, Aktivitätsringe fürs Kontingent, Teamstatus.
    private func drawDisplay(_ ctx: inout GraphicsContext) {
        let r = CGRect(x: 728, y: 72, width: 246, height: 146)
        shadow(&ctx, CGRect(x: r.minX + 10, y: r.maxY - 6, width: r.width - 20, height: 14), dark ? 0.3 : 0.10)
        ctx.fill(Path(roundedRect: r, cornerRadius: 12, style: .continuous), with: vgrad([mix(rgb(0xD9DCE0), rgb(0x55585E), 1 - dayness), mix(rgb(0xA9AEB5), rgb(0x3A3C41), 1 - dayness)], r.minY, r.maxY))
        let bezel = r.insetBy(dx: 2, dy: 2)
        ctx.fill(Path(roundedRect: bezel, cornerRadius: 10.5, style: .continuous), with: .color(rgb(0x0B0B0D)))
        let screen = bezel.insetBy(dx: 6, dy: 6)
        ctx.fill(Path(roundedRect: screen, cornerRadius: 6, style: .continuous),
                 with: .linearGradient(Gradient(colors: [rgb(0x16181D), rgb(0x08090C)]), startPoint: P(screen.minX, screen.minY), endPoint: P(screen.maxX, screen.maxY)))
        // Ringe
        let center = P(screen.minX + 64, screen.midY)
        ring(&ctx, center: center, radius: 47, width: 15, pct: session ?? 0, colors: [rgb(0xE5114A), rgb(0xFF5C8A)])
        ring(&ctx, center: center, radius: 30, width: 15, pct: weekly ?? 0, colors: [rgb(0x7DDC00), rgb(0xCDFF4F)])
        // Texte
        let tx = screen.minX + 130
        let clock = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        ctx.draw(Text(clock).font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundColor(.white),
                 at: P(tx, screen.minY + 26), anchor: .leading)
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Lang.locale))
        ctx.draw(Text(day).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.5)),
                 at: P(tx + 1, screen.minY + 47), anchor: .leading)
        ctx.draw(Text(L("5 Std.", "5 h") + "  " + (session.map { percentText(Int($0.rounded())) } ?? "–")).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundColor(rgb(0xFF4F7E)),
                 at: P(tx, screen.minY + 70), anchor: .leading)
        ctx.draw(Text(L("Woche", "Week") + "  " + (weekly.map { percentText(Int($0.rounded())) } ?? "–")).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundColor(rgb(0xB6F53A)),
                 at: P(tx, screen.minY + 86), anchor: .leading)
        let team: String
        if actors.isEmpty { team = L("Alle im Feierabend", "Everyone’s off") }
        else if waiting > 0 { team = waiting == 1 ? L("1 braucht dich", "1 needs you") : L("\(waiting) brauchen dich", "\(waiting) need you") }
        else if working > 0 { team = working == 1 ? L("1 arbeitet", "1 working") : L("\(working) arbeiten", "\(working) working") }
        else { team = L("Alle haben Pause", "Everyone’s on break") }
        ctx.draw(Text(team).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundColor(waiting > 0 ? rgb(0xFFAA33) : .white.opacity(0.8)),
                 at: P(tx, screen.maxY - (overflow > 0 ? 28 : 16)), anchor: .leading)
        if overflow > 0 {
            ctx.draw(Text(L("+\(overflow) im Nebenraum", "+\(overflow) next door")).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.5)),
                     at: P(tx, screen.maxY - 13), anchor: .leading)
        }
        // Glanz auf dem Glas
        var sheen = Path()
        sheen.move(to: P(screen.minX, screen.minY)); sheen.addLine(to: P(screen.minX + 110, screen.minY))
        sheen.addLine(to: P(screen.minX + 40, screen.maxY)); sheen.addLine(to: P(screen.minX, screen.maxY)); sheen.closeSubpath()
        ctx.fill(sheen, with: .color(.white.opacity(0.035)))
    }

    private func ring(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, width: CGFloat, pct: Double, colors: [Color]) {
        let base = Path { p in p.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false) }
        ctx.stroke(base, with: .color(colors[0].opacity(0.22)), lineWidth: width)
        let v = max(0.002, min(pct, 100) / 100)
        let arc = Path { p in p.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 359.9 * v), clockwise: false) }
        ctx.stroke(arc, with: .conicGradient(Gradient(colors: colors), center: center, angle: .degrees(-90)),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
        // Leuchtender Anfangspunkt wie auf der Watch
        let a = -Double.pi / 2
        ctx.fill(circle(P(center.x + CGFloat(cos(a)) * radius, center.y + CGFloat(sin(a)) * radius), width / 2), with: .color(colors[0]))
    }

    /// Nachtlicht: Raum wird dunkler, warme Lichtinseln, Bildschirmschein auf Gesichtern.
    private func drawLighting(_ ctx: inout GraphicsContext, seated: [String: [Actor]]) {
        let night = 1 - dayness
        // Abendröte färbt den Raum warm
        if golden > 0.05 && dayness > 0.2 {
            ctx.fill(Path(CGRect(origin: .zero, size: Self.size)), with: .color(rgb(0xFF9A4D, 0.06 * golden * dayness)))
        }
        guard night > 0.05 else { return }
        ctx.fill(Path(CGRect(origin: .zero, size: Self.size)), with: .color(rgb(0x0A0E20, 0.26 * night)))
        let warm = rgb(0xFFC27A)
        // Deckenleuchten: weicher Schein unter der Decke
        for x in stride(from: 100.0, through: 900, by: 200) {
            ctx.fill(oval(x - 110, 0, 220, 90), with: glow(P(x, 18), 110, warm, 0.22 * night))
        }
        // Warmer Grundton im Innenraum (Boden heller als die Wand)
        ctx.fill(Path(CGRect(x: 0, y: Self.floorY, width: 1000, height: 600 - Self.floorY)), with: vgrad([warm.opacity(0.05 * night), warm.opacity(0.10 * night)], Self.floorY, 600))
        // Lichtinseln auf dem Parkett unter den Tischen
        for i in 0..<OfficeModel.deskCount {
            let (p, s) = OfficeModel.deskSeat(i)
            ctx.fill(oval(p.x - 120 * s, p.y - 50 * s, 240 * s, 130 * s), with: glow(P(p.x, p.y + 12 * s), 120 * s, warm, 0.16 * night))
        }
        // Bildschirmschein auf den Gesichtern der Arbeitenden
        for a in actors {
            guard case .desk = a.place else { continue }
            switch a.pose {
            case .typing, .raiseHand, .upset, .relaxed:
                let s = a.scale
                ctx.fill(circle(P(a.point.x, a.point.y - 70 * s), 46 * s), with: glow(P(a.point.x, a.point.y - 70 * s), 46 * s, rgb(0xCFE2FF), 0.26 * night))
            default: break
            }
        }
        // Tischleuchten
        for i in 0..<OfficeModel.deskCount where deskProp(i) == .lamp {
            let (p, s) = OfficeModel.deskSeat(i)
            let c = P(p.x + 44 * s, p.y - 34 * s)
            ctx.fill(circle(c, 60 * s), with: glow(c, 60 * s, warm, 0.45 * night))
        }
        // Bogenleuchte über der Lounge
        let lamp = P(898, 304)
        ctx.fill(circle(P(lamp.x, lamp.y + 90), 190), with: glow(P(lamp.x, lamp.y + 90), 190, warm, 0.30 * night))
        ctx.fill(circle(lamp, 34), with: glow(lamp, 34, rgb(0xFFF0D0), 0.75 * night))
    }

    // MARK: Möbel

    private enum Prop { case mug, plant, lamp, books }
    private func deskProp(_ i: Int) -> Prop { [Prop.mug, .plant, .lamp, .books, .plant, .lamp, .mug, .books][i % 8] }

    private func drawDesk(_ ctx: inout GraphicsContext, index: Int, at p: CGPoint, scale s: CGFloat, actor: Actor?) {
        let w = 128 * s
        let top = p.y
        let x = p.x
        shadow(&ctx, CGRect(x: x - w * 0.62, y: top + 30 * s, width: w * 1.24, height: 20 * s), dark ? 0.3 : 0.13)
        // Hintere Tischbeine
        for dx in [-w / 2 + 13 * s, w / 2 - 16 * s] {
            ctx.fill(rounded(x + dx, top - 4 * s, 3 * s, 32 * s, 1.5 * s), with: .color(aluDark))
        }
        // Stuhl
        let chairX = x + (actor == nil ? 8 * s : 0)
        drawChair(&ctx, x: chairX, top: top, s: s, occupied: actor != nil)
        // Figur
        if let a = actor { drawSeated(&ctx, a) }
        // Tischplatte in leichter Aufsicht + Kante
        var surface = Path()
        surface.move(to: P(x - w / 2 + 6 * s, top - 14 * s)); surface.addLine(to: P(x + w / 2 - 6 * s, top - 14 * s))
        surface.addLine(to: P(x + w / 2, top)); surface.addLine(to: P(x - w / 2, top)); surface.closeSubpath()
        ctx.fill(surface, with: vgrad([deskTop2, deskTop], top - 14 * s, top))
        ctx.fill(rounded(x - w / 2, top - 0.5 * s, w, 5 * s, 1.5 * s), with: vgrad([deskEdge, darker(deskEdge, 0.06)], top, top + 5 * s))
        ctx.fill(Path(CGRect(x: x - w / 2 + 2 * s, y: top + 4.5 * s, width: w - 4 * s, height: 1.2 * s)), with: .color(.black.opacity(0.08)))
        // Vordere Tischbeine (schlankes Aluminium)
        for dx in [-w / 2 + 6 * s, w / 2 - 9 * s] {
            ctx.fill(rounded(x + dx, top + 4.5 * s, 3.2 * s, 38 * s, 1.6 * s), with: .linearGradient(Gradient(colors: [alu, aluDark]), startPoint: P(x + dx, 0), endPoint: P(x + dx + 3.2 * s, 0)))
        }
        // Laptop: offen bei Anwesenheit, sonst zugeklappt
        let open: Bool = {
            guard let a = actor else { return false }
            switch a.pose { case .typing, .raiseHand, .upset, .relaxed: return true; default: return false }
        }()
        let spaceGray = index % 3 == 1
        let lidTop = spaceGray ? rgb(0x8C9096) : rgb(0xE8EAED)
        let lidBottom = spaceGray ? rgb(0x6B6F75) : rgb(0xC4C8CE)
        if open {
            let lid = CGRect(x: x - 30 * s, y: top - 42 * s, width: 60 * s, height: 35 * s)
            shadow(&ctx, CGRect(x: lid.minX - 2 * s, y: top - 10 * s, width: lid.width + 4 * s, height: 6 * s), 0.18)
            ctx.fill(Path(roundedRect: lid, cornerRadius: 4 * s, style: .continuous), with: vgrad([lidTop, lidBottom], lid.minY, lid.maxY))
            ctx.fill(rounded(lid.minX + 1.5 * s, lid.minY + 0.6 * s, lid.width - 3 * s, 0.9 * s, 0.5 * s), with: .color(.white.opacity(0.55)))
            // Bildschirmschein an der Oberkante
            if let a = actor, a.pose == .typing {
                let pulse = 0.5 + 0.5 * sin(time * 2.2 + Double(x))
                ctx.fill(rounded(lid.minX + 3 * s, lid.minY - 1.2 * s, lid.width - 6 * s, 1.2 * s, 0.6 * s), with: .color(rgb(0xBFD9FF, 0.35 + 0.25 * pulse)))
            }
            ctx.fill(rounded(x - 35 * s, top - 8 * s, 70 * s, 3.2 * s, 1.6 * s), with: vgrad([lidBottom, darker(lidBottom, 0.15)], top - 8 * s, top - 4.8 * s))
        } else {
            shadow(&ctx, CGRect(x: x - 34 * s, y: top - 8 * s, width: 68 * s, height: 5 * s), 0.12)
            ctx.fill(rounded(x - 31 * s, top - 10 * s, 62 * s, 3.6 * s, 1.8 * s), with: vgrad([lidTop, lidBottom], top - 10 * s, top - 6.4 * s))
        }
        // Deko je Tisch
        switch deskProp(index) {
        case .mug: mug(&ctx, P(x + 47 * s, top - 6 * s), s)
        case .plant: pilea(&ctx, P(x - 47 * s, top - 6 * s), s)
        case .lamp: lamp(&ctx, P(x + 50 * s, top - 7 * s), s)
        case .books: books(&ctx, P(x - 46 * s, top - 6 * s), s)
        }
    }

    /// Bürostuhl: Rückenlehne hinter der Figur, Gasfeder und Fünfsternfuß unter dem Tisch.
    private func drawChair(_ ctx: inout GraphicsContext, x: CGFloat, top: CGFloat, s: CGFloat, occupied: Bool) {
        let shell = dark ? rgb(0x3E3F44) : rgb(0xE9E9EC)
        let fabric = dark ? rgb(0x55565C) : rgb(0xD5D1CB)
        // Fuß
        ctx.fill(rounded(x - 2 * s, top + 6 * s, 4 * s, 26 * s, 2 * s), with: .color(aluDark))
        var star = Path()
        star.move(to: P(x - 24 * s, top + 36 * s)); star.addQuadCurve(to: P(x + 24 * s, top + 36 * s), control: P(x, top + 26 * s))
        ctx.stroke(star, with: .color(aluDark.opacity(0.9)), style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
        for dx in [-24.0, 24] as [CGFloat] {
            ctx.fill(oval(x + dx - 2.5 * s, top + 34.5 * s, 5 * s, 3.5 * s), with: .color(dark ? rgb(0x2A2A2D) : rgb(0x6E7075)))
        }
        // Rückenlehne
        let back = CGRect(x: x - 28 * s, y: top - 82 * s, width: 56 * s, height: 70 * s)
        ctx.fill(Path(roundedRect: back, cornerRadius: 20 * s, style: .continuous), with: vgrad([lighter(shell, 0.2), shell], back.minY, back.maxY))
        let inner = back.insetBy(dx: 3.5 * s, dy: 3.5 * s)
        ctx.fill(Path(roundedRect: inner, cornerRadius: 17 * s, style: .continuous), with: vgrad([lighter(fabric, 0.08), darker(fabric, 0.05)], inner.minY, inner.maxY))
        if !occupied {
            // Sitzfläche sichtbar, wenn niemand da ist
            ctx.fill(rounded(x - 27 * s, top - 18 * s, 54 * s, 10 * s, 5 * s), with: .color(darker(fabric, 0.08)))
        }
    }

    private func mug(_ ctx: inout GraphicsContext, _ b: CGPoint, _ s: CGFloat) {
        shadow(&ctx, CGRect(x: b.x - 8 * s, y: b.y - 2 * s, width: 16 * s, height: 4 * s), 0.18)
        ctx.stroke(Path(roundedRect: CGRect(x: b.x + 3 * s, y: b.y - 11 * s, width: 7 * s, height: 7 * s), cornerRadius: 3 * s), with: .color(rgb(0xE6E6E8)), lineWidth: 1.8 * s)
        let body = CGRect(x: b.x - 5.5 * s, y: b.y - 14 * s, width: 11 * s, height: 14 * s)
        ctx.fill(Path(roundedRect: body, cornerRadius: 3 * s, style: .continuous),
                 with: .linearGradient(Gradient(colors: [.white, rgb(0xDADADF)]), startPoint: P(body.minX, 0), endPoint: P(body.maxX, 0)))
        ctx.fill(oval(body.minX + 0.8 * s, body.minY - 1 * s, body.width - 1.6 * s, 2.4 * s), with: .color(rgb(0x6B4A33)))
    }

    /// Glückstaler-Pflanze: runde Blätter an dünnen Stielen, weißer Topf.
    private func pilea(_ ctx: inout GraphicsContext, _ b: CGPoint, _ s: CGFloat) {
        shadow(&ctx, CGRect(x: b.x - 9 * s, y: b.y - 2 * s, width: 18 * s, height: 4 * s), 0.18)
        let sway = CGFloat(sin(time * 1.1 + Double(b.x))) * 0.6 * s
        let leaves: [(CGFloat, CGFloat, CGFloat)] = [(-9, -22, 4.2), (8, -24, 4.6), (-2, -30, 4.8), (11, -15, 3.6), (-11, -14, 3.4), (3, -19, 4)]
        let pot = CGRect(x: b.x - 7 * s, y: b.y - 10 * s, width: 14 * s, height: 10 * s)
        potBack(&ctx, pot, s, rim: 3 * s)
        for (i, l) in leaves.enumerated() {
            let c = P(b.x + l.0 * s + sway, b.y + l.1 * s)
            var stem = Path(); stem.move(to: P(b.x + CGFloat(i % 3 - 1) * 2 * s, b.y - 10 * s)); stem.addLine(to: c)
            ctx.stroke(stem, with: .color(rgb(0x6E9E5C)), lineWidth: 0.8 * s)
            ctx.fill(circle(c, l.2 * s), with: .color(i % 2 == 0 ? rgb(0x4F9A55) : rgb(0x6DB566)))
        }
        potFront(&ctx, pot, s, rim: 3 * s, corner: 3 * s)
    }

    private func lamp(_ ctx: inout GraphicsContext, _ b: CGPoint, _ s: CGFloat) {
        shadow(&ctx, CGRect(x: b.x - 9 * s, y: b.y - 2 * s, width: 18 * s, height: 4 * s), 0.2)
        ctx.fill(oval(b.x - 7 * s, b.y - 3 * s, 14 * s, 4 * s), with: .color(aluDark))
        var arm = Path()
        arm.move(to: P(b.x, b.y - 2 * s)); arm.addLine(to: P(b.x + 3 * s, b.y - 30 * s)); arm.addLine(to: P(b.x - 7 * s, b.y - 38 * s))
        ctx.stroke(arm, with: .color(aluDark), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
        var head = Path()
        head.move(to: P(b.x - 3 * s, b.y - 41 * s)); head.addLine(to: P(b.x - 13 * s, b.y - 30 * s)); head.addLine(to: P(b.x - 7 * s, b.y - 27 * s)); head.closeSubpath()
        ctx.fill(head, with: .color(alu))
        if dayness < 0.8 {
            ctx.fill(oval(b.x - 14 * s, b.y - 31 * s, 8 * s, 4 * s), with: .color(rgb(0xFFF1CC, 0.9 * (1 - dayness))))
        }
    }

    private func books(_ ctx: inout GraphicsContext, _ b: CGPoint, _ s: CGFloat) {
        shadow(&ctx, CGRect(x: b.x - 13 * s, y: b.y - 2 * s, width: 26 * s, height: 4 * s), 0.18)
        let cols = [rgb(0x7D8FA8), rgb(0xE3D5BD), rgb(0xB88C6A)]
        for (i, c) in cols.enumerated() {
            let y = b.y - CGFloat(i + 1) * 3.6 * s
            ctx.fill(rounded(b.x - 11 * s + CGFloat(i) * 1.2 * s, y, 22 * s - CGFloat(i) * 2 * s, 3.4 * s, 0.8 * s), with: .color(c))
        }
        var pencil = Path(); pencil.move(to: P(b.x - 8 * s, b.y - 12.5 * s)); pencil.addLine(to: P(b.x + 7 * s, b.y - 14 * s))
        ctx.stroke(pencil, with: .color(rgb(0x3A3A3C)), style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round))
    }

    private func drawSofa(_ ctx: inout GraphicsContext, actors: [Actor]) {
        let x: CGFloat = 736, w: CGFloat = 244
        let fabric = dark ? rgb(0x5E5C59) : rgb(0xD8D3CC)
        let fabricLight = dark ? rgb(0x6C6A66) : rgb(0xE6E2DC)
        let fabricDark = dark ? rgb(0x4E4C49) : rgb(0xC6C0B8)
        shadow(&ctx, CGRect(x: x - 20, y: 486, width: w + 40, height: 24), dark ? 0.35 : 0.18)
        // Korpus + Rückenkissen
        ctx.fill(rounded(x, 402, w, 70, 22), with: vgrad([fabric, fabricDark], 402, 472))
        for i in 0..<3 {
            let c = CGRect(x: x + 7 + CGFloat(i) * 77, y: 408, width: 76, height: 54)
            ctx.fill(Path(roundedRect: c, cornerRadius: 18, style: .continuous), with: vgrad([fabricLight, fabric], c.minY, c.maxY))
        }
        // Kissen in gedeckten Tönen
        ctx.fill(Path(roundedRect: CGRect(x: x + 10, y: 426, width: 34, height: 32), cornerRadius: 10, style: .continuous).applying(rot(-0.12, P(x + 27, 442))), with: .color(dark ? rgb(0x6F7F6A) : rgb(0xA9B99E)))
        ctx.fill(Path(roundedRect: CGRect(x: x + w - 44, y: 426, width: 34, height: 32), cornerRadius: 10, style: .continuous).applying(rot(0.12, P(x + w - 27, 442))), with: .color(dark ? rgb(0x8A7658) : rgb(0xE0C79A)))
        for a in actors.sorted(by: { $0.point.x < $1.point.x }) { drawSeated(&ctx, a) }
        // Sitzkissen
        for i in 0..<3 {
            let c = CGRect(x: x + 7 + CGFloat(i) * 77, y: 462, width: 76, height: 26)
            ctx.fill(Path(roundedRect: c, cornerRadius: 10, style: .continuous), with: vgrad([lighter(fabricLight, 0.1), fabric], c.minY, c.maxY))
        }
        // Beine der Sitzenden: Oberschenkel auf dem Sitz, Knie, Unterschenkel vor dem Polster
        for a in actors {
            let s = a.scale, px = a.point.x
            let pants = a.look.pants
            let lap = CGRect(x: px - 21 * s, y: 466, width: 42 * s, height: 16)
            ctx.fill(Path(roundedRect: lap, cornerRadius: 8, style: .continuous), with: vgrad([lighter(pants, 0.12), pants], lap.minY, lap.maxY))
            for side in [-1.0, 1.0] as [CGFloat] {
                let lx = px + side * 10.5 * s
                ctx.fill(rounded(lx - 6.5 * s, 474, 13 * s, 26, 6 * s), with: vgrad([pants, darker(pants, 0.18)], 474, 500))
                ctx.fill(rounded(lx - 7.5 * s + side * 1.5, 496, 15 * s, 7.5, 3.5), with: .color(rgb(0xF6F6F8)))
                ctx.fill(rounded(lx - 7.5 * s + side * 1.5, 501.5, 15 * s, 1.6, 0.8), with: .color(rgb(0xC9CBD0)))
            }
        }
        // Armlehnen
        for ax in [x - 14, x + w - 12] {
            let arm = CGRect(x: ax, y: 430, width: 26, height: 62)
            ctx.fill(Path(roundedRect: arm, cornerRadius: 12, style: .continuous), with: vgrad([fabricLight, fabricDark], arm.minY, arm.maxY))
        }
        ctx.fill(rounded(x - 12, 486, w + 24, 5, 2.5), with: .color(.black.opacity(0.06)))
        // Eichenbeine
        for dx in [CGFloat(-6), 18, w - 22, w + 4] {
            ctx.fill(rounded(x + dx, 490, 4, 10, 1.5), with: .color(oak))
        }
    }

    private func rot(_ a: CGFloat, _ c: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a).translatedBy(x: -c.x, y: -c.y)
    }

    /// Bogenleuchte hinter dem Sofa – nachts die warme Lichtquelle der Lounge.
    private func drawFloorLamp(_ ctx: inout GraphicsContext) {
        var pole = Path()
        pole.move(to: P(982, 470)); pole.addLine(to: P(982, 282))
        pole.addQuadCurve(to: P(898, 272), control: P(978, 236))
        ctx.stroke(pole, with: .color(dark ? rgb(0x8E9299) : rgb(0xB9BDC3)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        var wire = Path(); wire.move(to: P(898, 272)); wire.addLine(to: P(898, 284))
        ctx.stroke(wire, with: .color(rgb(0x8E9299)), lineWidth: 1)
        var shade = Path()
        shade.move(to: P(872, 304)); shade.addCurve(to: P(924, 304), control1: P(874, 278), control2: P(922, 278)); shade.closeSubpath()
        ctx.fill(shade, with: .linearGradient(Gradient(colors: [dark ? rgb(0xEDE9E2) : .white, dark ? rgb(0xB7B2A9) : rgb(0xDAD6CF)]), startPoint: P(872, 0), endPoint: P(924, 0)))
        ctx.fill(oval(874, 301, 48, 6), with: .color(rgb(0xFFF1D2, 0.5 + 0.5 * (1 - dayness))))
    }

    private func drawCoffeeTable(_ ctx: inout GraphicsContext) {
        let c = P(872, 556)
        shadow(&ctx, CGRect(x: c.x - 72, y: c.y + 20, width: 144, height: 18), dark ? 0.3 : 0.16)
        ctx.fill(rounded(c.x - 2.5, c.y + 4, 5, 25, 2), with: .color(aluDark))
        ctx.fill(oval(c.x - 26, c.y + 25, 52, 8), with: .color(alu))
        ctx.fill(oval(c.x - 64, c.y - 7, 128, 19), with: .color(darker(oak, 0.12)))
        ctx.fill(oval(c.x - 64, c.y - 11, 128, 19), with: .linearGradient(Gradient(colors: [lighter(oak, 0.25), oak]), startPoint: P(0, c.y - 11), endPoint: P(0, c.y + 8)))
        // Bücher, Vase mit Zweig, Schale
        shadow(&ctx, CGRect(x: c.x - 44, y: c.y - 6, width: 40, height: 6), 0.2)
        ctx.fill(rounded(c.x - 42, c.y - 9, 34, 5, 1), with: .color(rgb(0xE9E2D6)))
        ctx.fill(rounded(c.x - 39, c.y - 13.5, 29, 4.5, 1), with: .color(rgb(0x8193AA)))
        var twig = Path(); twig.move(to: P(c.x + 2, c.y - 16)); twig.addQuadCurve(to: P(c.x + 9, c.y - 34), control: P(c.x + 2, c.y - 28))
        ctx.stroke(twig, with: .color(rgb(0x6B5A48)), lineWidth: 1)
        for (dx, dy) in [(4.0, -23.0), (8, -28), (6, -32), (10, -34)] as [(CGFloat, CGFloat)] {
            ctx.fill(oval(c.x + dx - 2, c.y + dy - 3, 5, 6), with: .color(rgb(0x7FA36E)))
        }
        ctx.fill(rounded(c.x - 3, c.y - 18, 10, 13, 4), with: .linearGradient(Gradient(colors: [rgb(0xEDEFF2, 0.95), rgb(0xBFC8D0, 0.9)]), startPoint: P(c.x - 3, 0), endPoint: P(c.x + 7, 0)))
        ctx.fill(oval(c.x + 16, c.y - 12, 30, 9), with: .color(dark ? rgb(0xDADADF) : .white))
        for (dx, col) in [(22.0, 0xE8B04A), (30.0, 0xD9674F), (37.0, 0x9CBF5A)] as [(CGFloat, Int)] {
            ctx.fill(circle(P(c.x + dx, c.y - 13), 3.8), with: .color(rgb(col)))
        }
    }

    /// Geigenfeige im weißen Keramiktopf.
    private func drawFig(_ ctx: inout GraphicsContext, at b: CGPoint, scale s: CGFloat) {
        shadow(&ctx, CGRect(x: b.x - 34 * s, y: b.y - 7 * s, width: 68 * s, height: 14 * s), dark ? 0.3 : 0.18)
        let pot = CGRect(x: b.x - 22 * s, y: b.y - 42 * s, width: 44 * s, height: 42 * s)
        potBack(&ctx, pot, s, rim: 8 * s)
        var stem = Path(); stem.move(to: P(b.x, b.y - 42 * s)); stem.addQuadCurve(to: P(b.x - 4 * s, b.y - 150 * s), control: P(b.x + 6 * s, b.y - 100 * s))
        ctx.stroke(stem, with: .color(rgb(0x6B5238)), lineWidth: 2.6 * s)
        let sway = sin(time * 0.8 + Double(b.x)) * 0.035
        let leaves: [(CGFloat, CGFloat, CGFloat, Double)] = [(-16, -64, 1.0, -1.1), (14, -76, 1.05, 1.0), (-14, -96, 1.0, -0.8), (16, -108, 0.95, 0.9),
                                                              (-10, -126, 0.9, -0.5), (10, -138, 0.85, 0.5), (-2, -154, 0.8, 0.05), (4, -88, 0.8, 0.2)]
        for (i, l) in leaves.enumerated() {
            let ls = s * l.2
            var leaf = Path()
            leaf.move(to: P(0, 0))
            leaf.addCurve(to: P(0, -34 * ls), control1: P(-17 * ls, -6 * ls), control2: P(-15 * ls, -30 * ls))
            leaf.addCurve(to: P(0, 0), control1: P(15 * ls, -30 * ls), control2: P(17 * ls, -6 * ls))
            let t = CGAffineTransform(translationX: b.x + l.0 * s * 0.2, y: b.y + l.1 * s + 20 * s).rotated(by: CGFloat(l.3 + sway * Double(i % 3 + 1)))
            let shade: Color = i % 2 == 0 ? rgb(0x3E7F48) : rgb(0x4F9456)
            ctx.fill(leaf.applying(t), with: .linearGradient(Gradient(colors: [lighter(shade, 0.18), darker(shade, 0.12)]),
                                                             startPoint: P(0, 0).applying(t), endPoint: P(0, -34 * ls).applying(t)))
            var vein = Path(); vein.move(to: P(0, -2 * ls)); vein.addLine(to: P(0, -30 * ls))
            ctx.stroke(vein.applying(t), with: .color(.white.opacity(0.18)), lineWidth: 0.7 * s)
        }
        potFront(&ctx, pot, s, rim: 8 * s, corner: 10 * s)
    }

    /// Bogenhanf im Topf – wenige, große, aufrechte Blätter (ruhige Silhouette).
    private func drawSnakePlant(_ ctx: inout GraphicsContext, at b: CGPoint, scale s: CGFloat) {
        shadow(&ctx, CGRect(x: b.x - 34 * s, y: b.y - 7 * s, width: 68 * s, height: 14 * s), dark ? 0.3 : 0.18)
        let sway = sin(time * 0.7 + Double(b.x)) * 0.012
        let pot = CGRect(x: b.x - 22 * s, y: b.y - 42 * s, width: 44 * s, height: 42 * s)
        potBack(&ctx, pot, s, rim: 8 * s)
        // (Versatz am Fuß – innerhalb der Topföffnung, Höhe, Breite, Neigung); äußere Blätter zuerst, damit die mittleren davor stehen
        let blades: [(CGFloat, CGFloat, CGFloat, Double)] = [(-12, 92, 11, -0.34), (12, 100, 11, 0.32), (-8, 118, 12, -0.2), (8, 126, 12, 0.18),
                                                             (-3, 150, 13, -0.06), (4, 138, 12, 0.07), (0, 110, 12, 0.0)]
        for (i, l) in blades.enumerated() {
            var leaf = Path()
            let w = l.2 * s, h = l.1 * s
            leaf.move(to: P(-w / 2, 0))
            leaf.addCurve(to: P(0, -h), control1: P(-w * 0.75, -h * 0.45), control2: P(-w * 0.35, -h * 0.85))
            leaf.addCurve(to: P(w / 2, 0), control1: P(w * 0.35, -h * 0.85), control2: P(w * 0.75, -h * 0.45))
            leaf.closeSubpath()
            let t = CGAffineTransform(translationX: b.x + l.0 * s, y: b.y - 40 * s).rotated(by: CGFloat(l.3 + sway * Double(i % 3 + 1)))
            let base: Color = i % 2 == 0 ? rgb(0x3F7A4C) : rgb(0x4E8A58)
            ctx.fill(leaf.applying(t), with: .linearGradient(Gradient(colors: [darker(base, 0.1), base, lighter(base, 0.2)]),
                                                             startPoint: P(-w / 2, 0).applying(t), endPoint: P(w / 2, 0).applying(t)))
            ctx.stroke(leaf.applying(t), with: .color(rgb(0xC9D38A, 0.55)), lineWidth: 0.8 * s)
        }
        potFront(&ctx, pot, s, rim: 8 * s, corner: 10 * s)
    }

    /// Hinterer Teil des Topfs: Innenwand und Erde – wird VOR den Blättern gezeichnet, damit sie aus der Erde wachsen.
    private func potBack(_ ctx: inout GraphicsContext, _ r: CGRect, _ s: CGFloat, rim: CGFloat) {
        let light = dark ? rgb(0xD9D9DE) : .white
        let top = oval(r.minX, r.minY - rim / 2, r.width, rim)
        ctx.fill(top, with: .color(darker(light, 0.18)))                                   // Innenwand hinten
        ctx.fill(oval(r.minX + 2.5 * s, r.minY - rim / 2 + 1.2 * s, r.width - 5 * s, rim - 1.6 * s),
                 with: .linearGradient(Gradient(colors: [rgb(0x4A3A2C), rgb(0x6A5340)]), startPoint: P(0, r.minY - rim / 2), endPoint: P(0, r.minY + rim / 2)))
    }

    /// Vorderer Teil: Topfkörper ab der Randmitte plus helle Vorderkante – verdeckt die Blattansätze.
    private func potFront(_ ctx: inout GraphicsContext, _ r: CGRect, _ s: CGFloat, rim: CGFloat, corner: CGFloat) {
        let light = dark ? rgb(0xD9D9DE) : .white
        var body = Path()
        body.move(to: P(r.minX, r.minY))
        body.addArc(center: P(r.midX, r.minY), radius: r.width / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true,
                    transform: CGAffineTransform(translationX: r.midX, y: r.minY).scaledBy(x: 1, y: rim / r.width).translatedBy(x: -r.midX, y: -r.minY))
        body.addLine(to: P(r.maxX, r.maxY - corner))
        body.addQuadCurve(to: P(r.maxX - corner, r.maxY), control: P(r.maxX, r.maxY))
        body.addLine(to: P(r.minX + corner, r.maxY))
        body.addQuadCurve(to: P(r.minX, r.maxY - corner), control: P(r.minX, r.maxY))
        body.closeSubpath()
        ctx.fill(body, with: .linearGradient(Gradient(colors: [light, darker(light, 0.12)]), startPoint: P(r.minX, 0), endPoint: P(r.maxX, 0)))
        // Vorderkante des Rands
        var lip = Path()
        lip.addArc(center: P(r.midX, r.minY), radius: r.width / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true,
                   transform: CGAffineTransform(translationX: r.midX, y: r.minY).scaledBy(x: 1, y: rim / r.width).translatedBy(x: -r.midX, y: -r.minY))
        ctx.stroke(lip, with: .color(lighter(light, 0.3)), lineWidth: 1.6 * s)
    }

    /// Saugroboter: fährt über das Parkett, je höher die CPU-Last, desto schneller.
    private func drawVacuum(_ ctx: inout GraphicsContext) {
        let speed = 0.05 + cpu * 0.35
        // Phase aus Zeit×Geschwindigkeit – leichtes Springen bei Laständerung ist unauffällig
        let phase = (time * speed).truncatingRemainder(dividingBy: 2 * .pi)
        let x = 480 + CGFloat(cos(phase)) * 400
        let y: CGFloat = 589 + CGFloat(sin(phase)) * 4
        shadow(&ctx, CGRect(x: x - 25, y: y - 3, width: 50, height: 10), 0.28)
        ctx.fill(oval(x - 20, y - 9, 40, 12), with: .color(rgb(0x1F1F21)))
        ctx.fill(oval(x - 20, y - 13, 40, 13), with: .linearGradient(Gradient(colors: [rgb(0xF4F4F6), rgb(0xCFD1D5)]), startPoint: P(0, y - 13), endPoint: P(0, y)))
        ctx.fill(oval(x - 6.5, y - 13, 13, 6), with: .color(rgb(0xB9BCC1)))
        ctx.fill(oval(x - 5.5, y - 14.2, 11, 4.6), with: .color(rgb(0xE8E9EC)))
        let led = cpu > 0.6 ? rgb(0xFF9F0A) : rgb(0x30D158)
        ctx.fill(circle(P(x + 11, y - 7.5), 1.3), with: .color(led.opacity(0.6 + 0.4 * sin(time * 4))))
    }

    // MARK: Figuren

    private struct Tones {
        let skin, skinShade, skinLight, hair, hairLight, hairShade, shirt, shirtShade, shirtLight: Color
    }

    private func tones(_ L: Look) -> Tones {
        Tones(skin: L.skin, skinShade: darker(L.skin, 0.14), skinLight: lighter(L.skin, 0.22),
              hair: L.hair, hairLight: lighter(L.hair, 0.28), hairShade: darker(L.hair, 0.2),
              shirt: L.shirt, shirtShade: darker(L.shirt, 0.14), shirtLight: lighter(L.shirt, 0.16))
    }

    /// Sitzende Figur: a.point = Tischkante bzw. Sofasitz unter dem Oberkörper.
    private func drawSeated(_ ctx: inout GraphicsContext, _ a: Actor) {
        let s = a.scale, x = a.point.x, base = a.point.y
        let T = tones(a.look)
        let breathe = CGFloat(sin(time * 1.6 + Double(x))) * 0.7 * s
        var shoulderY = base - 62 * s + breathe
        var head = P(x, shoulderY - 25 * s)
        var tilt: Double = 0
        switch a.pose {
        case .typing:
            head.y += CGFloat(sin(time * 6 + Double(x))) * 0.6 * s + 1.5 * s
            tilt = sin(time * 0.7 + Double(x)) * 0.03
        case .napping:
            shoulderY = base - 40 * s
            head = P(x + 6 * s, base - 30 * s)
            tilt = 0.42
        case .sofa(let sleep):
            if sleep { head.x += 4 * s; head.y += 3 * s; tilt = 0.22 }
        case .relaxed:
            tilt = sin(time * 0.5 + Double(x)) * 0.05 - 0.04
        case .upset:
            tilt = -0.08
        default: break
        }

        // Arme hinter dem Kopf (entspannt zurückgelehnt)
        if a.pose == .relaxed {
            for side in [-1.0, 1.0] as [CGFloat] {
                var arm = Path()
                arm.move(to: P(x + side * 19 * s, shoulderY + 9 * s))
                arm.addLine(to: P(x + side * 31 * s, head.y - 2 * s))
                arm.addLine(to: P(x + side * 13 * s, head.y - 15 * s))
                ctx.stroke(arm, with: .color(T.shirtShade), style: StrokeStyle(lineWidth: 8.5 * s, lineCap: .round, lineJoin: .round))
            }
        }
        // Helfer-Kugeln hinter dem Kopf
        let helpers = min(a.session.workingHelpers, 4)
        let orbitC = P(head.x, head.y - 27 * s)
        if helpers > 0 { orbs(&ctx, orbitC, s, helpers, front: false) }

        // Oberkörper
        let torso = CGRect(x: x - 25 * s, y: shoulderY, width: 50 * s, height: base - shoulderY + 4 * s)
        ctx.fill(Path(roundedRect: torso, cornerRadius: 19 * s, style: .continuous), with: vgrad([T.shirtLight, T.shirt, T.shirtShade], torso.minY, torso.maxY))
        // Hals + Kragen
        ctx.fill(rounded(x - 6.5 * s, shoulderY - 9 * s, 13 * s, 14 * s, 5 * s), with: .color(T.skinShade))
        var collar = Path()
        collar.addArc(center: P(x, shoulderY + 1 * s), radius: 8 * s, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        ctx.stroke(collar, with: .color(T.shirtShade), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))

        // Kopf
        drawHead(&ctx, center: head, s: s, tones: T, look: a.look, pose: a.pose, tilt: tilt)

        // Arme vorn
        switch a.pose {
        case .typing:
            for side in [-1.0, 1.0] as [CGFloat] {
                let bob = CGFloat(sin(time * 13 + (side > 0 ? 0 : 1.9))) * 2.2 * s
                var arm = Path(); arm.move(to: P(x + side * 19 * s, shoulderY + 10 * s))
                arm.addLine(to: P(x + side * 15 * s, base - 9 * s + bob))
                ctx.stroke(arm, with: .color(T.shirt), style: StrokeStyle(lineWidth: 10.5 * s, lineCap: .round))
            }
        case .raiseHand:
            let wave = CGFloat(sin(time * 6)) * 0.18
            var arm = Path()
            let sh = P(x + 19 * s, shoulderY + 9 * s)
            let hand = P(x + 36 * s + wave * 20 * s, shoulderY - 44 * s)
            arm.move(to: sh); arm.addQuadCurve(to: hand, control: P(x + 38 * s, shoulderY - 4 * s))
            ctx.stroke(arm, with: .color(T.shirt), style: StrokeStyle(lineWidth: 10.5 * s, lineCap: .round))
            palm(&ctx, hand, s, T, angle: Double(wave))
            var other = Path(); other.move(to: P(x - 19 * s, shoulderY + 10 * s)); other.addLine(to: P(x - 18 * s, base - 4 * s))
            ctx.stroke(other, with: .color(T.shirt), style: StrokeStyle(lineWidth: 10.5 * s, lineCap: .round))
        case .upset:
            // Hand an die Stirn
            var arm = Path()
            arm.move(to: P(x - 19 * s, shoulderY + 10 * s))
            arm.addQuadCurve(to: P(head.x - 12 * s, head.y - 12 * s), control: P(x - 38 * s, shoulderY - 6 * s))
            ctx.stroke(arm, with: .color(T.shirt), style: StrokeStyle(lineWidth: 10.5 * s, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 20 * s, y: head.y - 19 * s, width: 17 * s, height: 11 * s)).applying(rot(-0.3, P(head.x - 11 * s, head.y - 13 * s))), with: .color(T.skin))
            var other = Path(); other.move(to: P(x + 19 * s, shoulderY + 10 * s)); other.addLine(to: P(x + 18 * s, base - 4 * s))
            ctx.stroke(other, with: .color(T.shirt), style: StrokeStyle(lineWidth: 10.5 * s, lineCap: .round))
        case .sofa(let sleep):
            // Tasse in beiden Händen
            let cupY = shoulderY + (sleep ? 32 : 22) * s
            for side in [-1.0, 1.0] as [CGFloat] {
                var arm = Path(); arm.move(to: P(x + side * 19 * s, shoulderY + 10 * s))
                arm.addQuadCurve(to: P(x + side * 8 * s, cupY + 6 * s), control: P(x + side * 24 * s, cupY))
                ctx.stroke(arm, with: .color(T.shirt), style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
            }
            let cup = CGRect(x: x - 7 * s, y: cupY - 2 * s, width: 14 * s, height: 14 * s)
            ctx.fill(Path(roundedRect: cup, cornerRadius: 3.5 * s, style: .continuous), with: .linearGradient(Gradient(colors: [.white, rgb(0xD8D8DC)]), startPoint: P(cup.minX, 0), endPoint: P(cup.maxX, 0)))
            for side in [-1.0, 1.0] as [CGFloat] {
                ctx.fill(circle(P(x + side * 7 * s, cupY + 7 * s), 3.6 * s), with: .color(T.skin))
            }
            if !sleep {
                for i in 0..<2 {
                    let t = (time * 0.55 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    let sy = cupY - 4 * s - CGFloat(t) * 16 * s
                    ctx.fill(oval(x - 2.5 * s + CGFloat(sin(t * 6 + Double(i))) * 2.5 * s, sy, 4 * s, 6 * s), with: .color(.white.opacity(0.45 * (1 - t))))
                }
            }
        case .napping:
            // Verschränkte Arme auf dem Tisch, Kopf darauf
            let armsR = CGRect(x: x - 30 * s, y: base - 22 * s, width: 60 * s, height: 16 * s)
            ctx.fill(Path(roundedRect: armsR, cornerRadius: 8 * s, style: .continuous), with: vgrad([T.shirtLight, T.shirt], armsR.minY, armsR.maxY))
            drawHead(&ctx, center: head, s: s, tones: T, look: a.look, pose: a.pose, tilt: tilt)
        default:
            for side in [-1.0, 1.0] as [CGFloat] where a.pose != .relaxed {
                var arm = Path(); arm.move(to: P(x + side * 19 * s, shoulderY + 10 * s))
                arm.addLine(to: P(x + side * 20 * s, base - 4 * s))
                ctx.stroke(arm, with: .color(T.shirt), style: StrokeStyle(lineWidth: 10.5 * s, lineCap: .round))
            }
        }
        if helpers > 0 { orbs(&ctx, orbitC, s, helpers, front: true) }
        if case .napping = a.pose { zzz(&ctx, P(head.x + 22 * s, head.y - 26 * s), s) }
        if case .sofa(true) = a.pose { zzz(&ctx, P(head.x + 20 * s, head.y - 30 * s), s) }
    }

    private func palm(_ ctx: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat, _ T: Tones, angle: Double) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(angle))
        for (i, dx) in [-4.2, -1.4, 1.4, 4.2].enumerated() {
            let h: CGFloat = [7, 8.5, 8, 6.5][i]
            g.fill(rounded(CGFloat(dx) * s - 1.3 * s, -6 * s - h * s + 3 * s, 2.6 * s, h * s, 1.3 * s), with: .color(T.skin))
        }
        g.fill(Path(roundedRect: CGRect(x: -6 * s, y: -6 * s, width: 12 * s, height: 11 * s), cornerRadius: 4.5 * s, style: .continuous), with: .color(T.skin))
        g.fill(Path(ellipseIn: CGRect(x: -9.5 * s, y: -3 * s, width: 5 * s, height: 3.2 * s)).applying(CGAffineTransform(rotationAngle: -0.6)), with: .color(T.skin))
    }

    /// Siri-artige Kugeln kreisen wie ein Heiligenschein über dem Kopf (vorne/hinten getrennt gezeichnet).
    private func orbs(_ ctx: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat, _ n: Int, front: Bool) {
        let palette: [[Color]] = [[rgb(0x5AC8FA), rgb(0xAF52DE)], [rgb(0xFF6482), rgb(0xFF9F0A)], [rgb(0x34C759), rgb(0x5AC8FA)], [rgb(0xBF5AF2), rgb(0xFF375F)]]
        for i in 0..<n {
            let ang = time * 1.5 + Double(i) * (2 * .pi / Double(n))
            let depth = sin(ang)
            guard (depth > 0) == front else { continue }
            let p = P(c.x + CGFloat(cos(ang)) * 31 * s, c.y + CGFloat(depth) * 6 * s)
            let r = (5.2 + CGFloat(depth) * 0.8) * s
            let col = palette[i % palette.count]
            ctx.fill(circle(p, r * 2.8), with: glow(p, r * 2.8, col[0], 0.45))
            ctx.fill(circle(p, r), with: .radialGradient(Gradient(colors: [lighter(col[0], 0.35), col[0], col[1]]),
                                                        center: P(p.x - r * 0.35, p.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
            ctx.fill(oval(p.x - r * 0.55, p.y - r * 0.65, r * 0.6, r * 0.42), with: .color(.white.opacity(0.75)))
        }
    }

    /// Stehende/laufende Figur: a.point = Füße.
    private func drawStanding(_ ctx: inout GraphicsContext, _ a: Actor, walk t: Double) {
        let s = a.scale, x = a.point.x, feet = a.point.y
        let T = tones(a.look)
        let idle = a.pose == .standing
        let swing = idle ? 0 : CGFloat(sin(t * 8.5)) * 7 * s
        let bob = idle ? CGFloat(sin(time * 1.4 + Double(x))) * 0.6 * s : abs(CGFloat(sin(t * 8.5))) * 2 * s
        shadow(&ctx, CGRect(x: x - 24 * s, y: feet - 5 * s, width: 48 * s, height: 10 * s), 0.2)
        let hip = feet - 38 * s - bob
        for (side, d) in [(-1.0, swing), (1.0, -swing)] as [(CGFloat, CGFloat)] {
            var leg = Path(); leg.move(to: P(x + side * 8 * s, hip)); leg.addLine(to: P(x + side * 8 * s + d, feet - 6 * s))
            ctx.stroke(leg, with: .color(a.look.pants), style: StrokeStyle(lineWidth: 11.5 * s, lineCap: .round))
            ctx.fill(rounded(x + side * 8 * s + d - 7 * s, feet - 8 * s, 14 * s, 8 * s, 4 * s), with: .color(rgb(0xF4F4F6)))
            ctx.fill(rounded(x + side * 8 * s + d - 7 * s, feet - 1.8 * s, 14 * s, 1.8 * s, 0.9 * s), with: .color(rgb(0xC9CBD0)))
        }
        let shoulderY = hip - 46 * s
        // hinterer Arm
        var back = Path(); back.move(to: P(x - 19 * s, shoulderY + 10 * s)); back.addLine(to: P(x - 22 * s - swing * 0.6, shoulderY + 40 * s))
        ctx.stroke(back, with: .color(T.shirtShade), style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
        ctx.fill(circle(P(x - 22 * s - swing * 0.6, shoulderY + 43 * s), 4.8 * s), with: .color(T.skinShade))
        let torso = CGRect(x: x - 23 * s, y: shoulderY, width: 46 * s, height: 52 * s)
        ctx.fill(Path(roundedRect: torso, cornerRadius: 17 * s, style: .continuous), with: vgrad([T.shirtLight, T.shirt, T.shirtShade], torso.minY, torso.maxY))
        if idle {
            // Tasse vor der Brust, leichter Dampf
            let cup = P(x + 9 * s, shoulderY + 22 * s)
            var front = Path(); front.move(to: P(x + 19 * s, shoulderY + 10 * s))
            front.addQuadCurve(to: P(cup.x + 4 * s, cup.y + 8 * s), control: P(x + 26 * s, shoulderY + 34 * s))
            ctx.stroke(front, with: .color(T.shirt), style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
            let r = CGRect(x: cup.x - 7 * s, y: cup.y - 4 * s, width: 14 * s, height: 14 * s)
            ctx.fill(Path(roundedRect: r, cornerRadius: 3.5 * s, style: .continuous), with: .linearGradient(Gradient(colors: [.white, rgb(0xD8D8DC)]), startPoint: P(r.minX, 0), endPoint: P(r.maxX, 0)))
            ctx.fill(circle(P(cup.x + 5 * s, cup.y + 6 * s), 4.4 * s), with: .color(T.skin))
            for i in 0..<2 {
                let k = (time * 0.6 + Double(i) * 0.5 + Double(x) * 0.01).truncatingRemainder(dividingBy: 1)
                ctx.fill(circle(P(cup.x + CGFloat(sin(k * 6)) * 2 * s, cup.y - 6 * s - CGFloat(k) * 16 * s), 2.2 * s), with: .color(.white.opacity(0.45 * (1 - k))))
            }
        } else {
            var front = Path(); front.move(to: P(x + 19 * s, shoulderY + 10 * s)); front.addLine(to: P(x + 22 * s + swing * 0.6, shoulderY + 40 * s))
            ctx.stroke(front, with: .color(T.shirt), style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
            ctx.fill(circle(P(x + 22 * s + swing * 0.6, shoulderY + 43 * s), 4.8 * s), with: .color(T.skin))
        }
        ctx.fill(rounded(x - 6.5 * s, shoulderY - 9 * s, 13 * s, 14 * s, 5 * s), with: .color(T.skinShade))
        drawHead(&ctx, center: P(x, shoulderY - 25 * s), s: s, tones: T, look: a.look, pose: a.pose, tilt: Double(swing) * 0.004)
    }

    /// Memoji-artiger Kopf: großer runder Schädel, weiche Schattierung, ausdrucksstarke Augen/Brauen.
    private func drawHead(_ outer: inout GraphicsContext, center c: CGPoint, s: CGFloat, tones T: Tones, look L: Look, pose: Pose, tilt: Double) {
        var ctx = outer
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: .radians(tilt))
        let r = 24 * s
        let hairFill = GraphicsContext.Shading.linearGradient(Gradient(colors: [T.hairLight, T.hair, T.hairShade]), startPoint: P(-r * 0.5, -r * 1.1), endPoint: P(r * 0.3, r * 0.2))

        // Haare hinten
        if L.hairStyle == 2 {
            ctx.fill(Path(roundedRect: CGRect(x: -r - 4 * s, y: -r - 2 * s, width: 2 * r + 8 * s, height: 2 * r + 20 * s), cornerRadius: r, style: .continuous), with: hairFill)
        }
        if L.hairStyle == 3 {
            ctx.fill(circle(P(0, -r - 5 * s), 10 * s), with: hairFill)
        }
        // Ohren
        for side in [-1.0, 1.0] as [CGFloat] {
            ctx.fill(oval(side * r * 0.96 - 4.5 * s, -3 * s, 9 * s, 12 * s), with: .color(T.skin))
            ctx.fill(oval(side * r * 0.96 - 2 * s + side * 0.5 * s, -0.5 * s, 4 * s, 7 * s), with: .color(T.skinShade.opacity(0.7)))
        }
        // Gesicht
        let face = Path(ellipseIn: CGRect(x: -r, y: -r * 1.0, width: 2 * r, height: 2 * r * 1.03))
        ctx.fill(face, with: .radialGradient(Gradient(colors: [T.skinLight, T.skin, T.skinShade]), center: P(-r * 0.25, -r * 0.3), startRadius: 0, endRadius: r * 1.35))

        // Haare oben
        switch L.hairStyle {
        case 0:
            // Seitenscheitel mit Schwung
            var p = Path()
            p.addArc(center: .zero, radius: r + 1.8 * s, startAngle: .degrees(192), endAngle: .degrees(350), clockwise: false)
            p.addQuadCurve(to: P(r * 0.1, -r * 0.5), control: P(r * 0.75, -r * 0.62))
            p.addQuadCurve(to: P(-r - 1.4 * s, -2 * s), control: P(-r * 0.62, -r * 0.62))
            ctx.fill(p, with: hairFill)
        case 1:
            // Tolle
            var p = Path()
            p.addArc(center: .zero, radius: r + 2 * s, startAngle: .degrees(186), endAngle: .degrees(354), clockwise: false)
            p.addQuadCurve(to: P(-2 * s, -r * 0.52), control: P(r * 0.55, -r * 0.4))
            p.addQuadCurve(to: P(-r - 2 * s, -1 * s), control: P(-r * 0.7, -r * 0.45))
            ctx.fill(p, with: hairFill)
            ctx.fill(oval(-r * 0.75, -r - 7 * s, r * 1.4, 14 * s), with: hairFill)
        case 2:
            // Lange Haare, Mittelscheitel
            var p = Path()
            p.addArc(center: .zero, radius: r + 2 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: P(r + 2 * s, 8 * s))
            p.addQuadCurve(to: P(0, -r * 0.62), control: P(r * 0.55, -r * 0.55))
            p.addQuadCurve(to: P(-r - 2 * s, 8 * s), control: P(-r * 0.55, -r * 0.55))
            p.closeSubpath()
            ctx.fill(p, with: hairFill)
        case 3:
            // Zurückgebunden mit Dutt
            var p = Path()
            p.addArc(center: .zero, radius: r + 1.2 * s, startAngle: .degrees(194), endAngle: .degrees(346), clockwise: false)
            p.addQuadCurve(to: P(-r - 0.6 * s, -5 * s), control: P(0, -r * 0.62))
            ctx.fill(p, with: hairFill)
        case 4:
            // Locken
            for i in 0..<11 {
                let ang = Double.pi * 0.92 + Double(i) / 10 * Double.pi * 1.16
                let px = CGFloat(cos(ang)) * r * 0.92, py = CGFloat(sin(ang)) * r * 0.86 - 1 * s
                ctx.fill(circle(P(px, py), 8.5 * s), with: hairFill)
            }
            ctx.fill(oval(-r * 0.8, -r * 1.02, r * 1.6, r * 0.7), with: hairFill)
        default:
            // Kurz geschoren
            var p = Path()
            p.addArc(center: .zero, radius: r + 0.8 * s, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            p.addQuadCurve(to: P(-r * 0.94, -r * 0.34), control: P(0, -r * 0.72))
            ctx.fill(p, with: .color(T.hair.opacity(0.85)))
        }
        // Glanzlicht im Haar
        if L.hairStyle != 5 {
            var shine = Path()
            shine.addArc(center: .zero, radius: r - 1 * s, startAngle: .degrees(222), endAngle: .degrees(252), clockwise: false)
            ctx.stroke(shine, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
        }

        // Brauen
        let sleeping: Bool = { if case .sofa(true) = pose { return true }; return pose == .napping }()
        let browY: CGFloat = pose == .raiseHand ? -11 * s : -8.5 * s
        for side in [-1.0, 1.0] as [CGFloat] {
            var b = Path()
            let inner: CGFloat, outer: CGFloat
            switch pose {
            case .upset: inner = 2.2 * s; outer = -1.2 * s
            case .typing: inner = 0.8 * s; outer = 0
            default: inner = 0; outer = 0.6 * s
            }
            b.move(to: P(side * 4.6 * s, browY + inner))
            b.addQuadCurve(to: P(side * 12 * s, browY + outer), control: P(side * 8.4 * s, browY - 1.6 * s + (inner + outer) / 2))
            ctx.stroke(b, with: .color(darker(T.hair, 0.2).opacity(0.85)), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
        }
        // Augen
        let blink = (time + Double(c.x) * 0.37).truncatingRemainder(dividingBy: 4.4) < 0.12
        let eyeY: CGFloat = 1 * s
        for side in [-1.0, 1.0] as [CGFloat] {
            let ex = side * 8.2 * s
            if sleeping || blink {
                var l = Path(); l.move(to: P(ex - 3.4 * s, eyeY)); l.addQuadCurve(to: P(ex + 3.4 * s, eyeY), control: P(ex, eyeY + 2.8 * s))
                ctx.stroke(l, with: .color(rgb(0x2B2118)), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
            } else {
                let look: CGPoint
                switch pose {
                case .typing: look = P(0, 1.3 * s)
                case .relaxed: look = P(side * 0.2 * s + 0.8 * s, -0.9 * s)
                case .upset: look = P(0, 0.8 * s)
                default: look = .zero
                }
                ctx.fill(oval(ex - 3.6 * s, eyeY - 4.2 * s, 7.2 * s, 8.4 * s), with: .color(.white))
                ctx.fill(circle(P(ex + look.x, eyeY + look.y + 0.3 * s), 2.9 * s), with: .radialGradient(Gradient(colors: [rgb(0x6B4A33), rgb(0x2A1C14)]), center: P(ex + look.x, eyeY + look.y + 1.2 * s), startRadius: 0, endRadius: 3 * s))
                ctx.fill(circle(P(ex + look.x, eyeY + look.y + 0.3 * s), 1.3 * s), with: .color(rgb(0x120C08)))
                ctx.fill(circle(P(ex + look.x - 1 * s, eyeY + look.y - 1 * s), 0.95 * s), with: .color(.white))
                // Oberlid
                var lid = Path(); lid.addArc(center: P(ex, eyeY + 0.2 * s), radius: 4 * s, startAngle: .degrees(205), endAngle: .degrees(335), clockwise: false)
                ctx.stroke(lid, with: .color(rgb(0x2B2118, 0.8)), style: StrokeStyle(lineWidth: 1.1 * s, lineCap: .round))
            }
        }
        if L.glasses {
            let gc = rgb(0x2A2A2C, 0.9)
            for side in [-1.0, 1.0] as [CGFloat] {
                ctx.stroke(Path(roundedRect: CGRect(x: side * 8.2 * s - 6.4 * s, y: eyeY - 5.6 * s, width: 12.8 * s, height: 11 * s), cornerRadius: 5 * s, style: .continuous), with: .color(gc), lineWidth: 1.3 * s)
                ctx.fill(Path(roundedRect: CGRect(x: side * 8.2 * s - 5 * s, y: eyeY - 4.6 * s, width: 5 * s, height: 2 * s), cornerRadius: 1 * s), with: .color(.white.opacity(0.35)))
            }
            var bridge = Path(); bridge.move(to: P(-1.8 * s, eyeY - 1.4 * s)); bridge.addQuadCurve(to: P(1.8 * s, eyeY - 1.4 * s), control: P(0, eyeY - 3 * s))
            ctx.stroke(bridge, with: .color(gc), lineWidth: 1.3 * s)
        }
        // Nase
        ctx.fill(oval(-2.6 * s, 6 * s, 5.2 * s, 3.6 * s), with: .color(T.skinShade.opacity(0.55)))
        ctx.fill(oval(-1.6 * s, 5.8 * s, 2.4 * s, 1.4 * s), with: .color(.white.opacity(0.35)))
        // Wangen
        for side in [-1.0, 1.0] as [CGFloat] {
            ctx.fill(circle(P(side * 13 * s, 8 * s), 4.5 * s), with: glow(P(side * 13 * s, 8 * s), 4.5 * s, rgb(0xFF6F61), 0.3))
        }
        // Mund
        let my = 13 * s
        let lip = rgb(0x6B2B2B)
        switch pose {
        case .raiseHand:
            ctx.fill(oval(-3 * s, my - 2 * s, 6 * s, 6.4 * s), with: .color(lip))
        case .upset:
            var m = Path(); m.move(to: P(-5 * s, my + 2.6 * s)); m.addQuadCurve(to: P(5 * s, my + 2.6 * s), control: P(0, my - 2 * s))
            ctx.stroke(m, with: .color(lip), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
        case .typing, .napping, .walking:
            var m = Path(); m.move(to: P(-3.4 * s, my)); m.addQuadCurve(to: P(3.4 * s, my), control: P(0, my + 2 * s))
            ctx.stroke(m, with: .color(lip), style: StrokeStyle(lineWidth: 1.7 * s, lineCap: .round))
        case .sofa(true):
            ctx.fill(oval(-2 * s, my - 0.5 * s, 4 * s, 3.4 * s), with: .color(lip.opacity(0.85)))
        default:
            // offenes Lächeln mit Zähnen
            var m = Path()
            m.move(to: P(-6 * s, my - 1 * s)); m.addQuadCurve(to: P(6 * s, my - 1 * s), control: P(0, my - 0.2 * s))
            m.addQuadCurve(to: P(-6 * s, my - 1 * s), control: P(0, my + 9 * s))
            ctx.fill(m, with: .color(lip))
            var teeth = Path()
            teeth.move(to: P(-4.6 * s, my - 0.6 * s)); teeth.addQuadCurve(to: P(4.6 * s, my - 0.6 * s), control: P(0, my))
            teeth.addQuadCurve(to: P(-4.6 * s, my - 0.6 * s), control: P(0, my + 3 * s))
            ctx.fill(teeth, with: .color(.white))
        }
    }

    private func zzz(_ ctx: inout GraphicsContext, _ p: CGPoint, _ s: CGFloat) {
        for i in 0..<3 {
            let t = (time * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let a = sin(t * .pi)
            ctx.draw(Text("z").font(.system(size: (8 + CGFloat(i) * 2.5) * s, weight: .bold, design: .rounded))
                .foregroundColor(dark ? rgb(0xC9D4FF, 0.9 * a) : rgb(0x7C7AD6, 0.9 * a)),
                     at: P(p.x + CGFloat(t) * 14 * s, p.y - CGFloat(t) * 22 * s))
        }
    }

    // MARK: Beschriftung

    private func headTop(_ a: Actor) -> CGFloat {
        let s = a.scale
        switch a.pose {
        case .walking, .standing: return a.point.y - 138 * s
        case .napping: return a.point.y - 58 * s
        default: return a.point.y - 116 * s
        }
    }

    private func drawLabels(_ ctx: inout GraphicsContext, _ a: Actor) {
        let s = a.scale
        let st = a.session.status
        var walking = false
        if case .walking = a.pose { walking = true }
        let nameY: CGFloat
        switch a.pose {
        case .walking: nameY = headTop(a) - 12 * s        // über dem Kopf – unten wäre es am Bildrand abgeschnitten
        case .standing: nameY = a.point.y + 12 * s
        case .sofa: nameY = 516
        default: nameY = a.point.y + 22 * s
        }
        let icon: String, tint: Color
        switch st {
        case .working: icon = Self.symbol(for: a.session.tool); tint = rgb(0x0A84FF)
        case .waiting: icon = "hand.raised.fill"; tint = .white
        case .error: icon = "exclamationmark.triangle.fill"; tint = rgb(0xFF453A)
        case .done: icon = "checkmark.circle.fill"; tint = rgb(0x30C759)
        case .idle: icon = a.pose == .napping || a.pose == .sofa(sleep: true) ? "moon.zzz.fill" : "cup.and.saucer.fill"; tint = rgb(0x8E8E93)
        }
        let hover = hovered == a.id
        let fill: Color = hover ? .accentColor : st == .waiting ? rgb(0xFF9500) : (dark ? rgb(0x2C2C2E, 0.92) : rgb(0xFFFFFF, 0.94))
        let text: Color = hover || st == .waiting ? .white : ink
        tag(&ctx, String(a.session.project.prefix(16)), icon: icon, tint: hover ? .white : tint,
            at: P(a.point.x, nameY), size: s < 0.9 ? 9 : 10.5, fill: fill, text: text)

        guard !walking, !hover else { return }
        // Status-Bläschen über dem Kopf
        let top = P(a.point.x + (a.pose == .napping ? 6 * s : 0), headTop(a) - 13 * s)
        switch st {
        case .waiting:
            let t = (time * 0.8).truncatingRemainder(dividingBy: 1)
            ctx.stroke(circle(top, (12 + CGFloat(t) * 12) * max(s, 0.9)), with: .color(rgb(0xFF9500, 0.5 * (1 - t))), lineWidth: 1.5)
            bubble(&ctx, "hand.raised.fill", at: top, s: s * CGFloat(1 + 0.05 * sin(time * 5)), fill: rgb(0xFF9500), fg: .white)
        case .error:
            bubble(&ctx, "exclamationmark", at: top, s: s, fill: rgb(0xFF453A), fg: .white)
        case .done where a.statusAge < 90:
            bubble(&ctx, "checkmark", at: top, s: s, fill: rgb(0x30C759), fg: .white)
        default: break
        }
    }

    /// Details beim Überfahren: Sprechblase über dem Kopf (zuoberst gezeichnet).
    private func drawHover(_ ctx: inout GraphicsContext, _ a: Actor) {
        let st = a.session.status
        var text = a.session.displayName
        if !a.session.activity.isEmpty { text += " · " + a.session.activity } else { text += " · " + st.label }
        if text.count > 52 { text = String(text.prefix(51)) + "…" }
        speech(&ctx, text, at: P(a.point.x, headTop(a) - 8), size: 11.5,
               fill: st == .waiting ? rgb(0xFF9500) : st == .error ? rgb(0xFF453A) : (dark ? rgb(0x2C2C2E, 0.97) : rgb(0xFFFFFF, 0.98)),
               text: st == .waiting || st == .error ? .white : ink)
    }

    static func symbol(for tool: String) -> String {
        switch tool {
        case "Bash": return "apple.terminal"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "pencil"
        case "Read": return "doc.text.fill"
        case "Grep", "Glob", "ToolSearch": return "magnifyingglass"
        case "WebFetch", "WebSearch": return "globe"
        case "Agent", "Task": return "person.2.fill"
        case "TodoWrite": return "checklist"
        case "thinking", "": return "brain.head.profile"
        case "Skill": return "book.fill"
        default: return tool.hasPrefix("mcp__") ? "puzzlepiece.extension.fill" : "gearshape.fill"
        }
    }

    /// Weicher, gefälschter Schlagschatten unter Plaketten (billiger als ein Filter)
    private func softShadow(_ ctx: inout GraphicsContext, _ path: Path, _ o: Double) {
        ctx.fill(path.offsetBy(dx: 0, dy: 1.5), with: .color(.black.opacity(o)))
        ctx.stroke(path.offsetBy(dx: 0, dy: 2), with: .color(.black.opacity(o * 0.4)), lineWidth: 3)
    }

    /// Runde Plakette mit SF-Symbol über dem Kopf.
    private func bubble(_ ctx: inout GraphicsContext, _ symbol: String, at p: CGPoint, s: CGFloat, fill: Color, fg: Color) {
        let d = 22 * max(s, 0.85)
        let path = circle(p, d / 2)
        softShadow(&ctx, path, 0.12)
        ctx.fill(path, with: .linearGradient(Gradient(colors: [lighter(fill, 0.12), fill]), startPoint: P(0, p.y - d / 2), endPoint: P(0, p.y + d / 2)))
        ctx.draw(Text(Image(systemName: symbol)).font(.system(size: d * 0.48, weight: .bold)).foregroundColor(fg), at: p)
    }

    /// Namensschild: helles Milchglas-Pill mit Status-Symbol.
    private func tag(_ ctx: inout GraphicsContext, _ str: String, icon: String, tint: Color, at p: CGPoint, size: CGFloat, fill: Color, text: Color) {
        let t = ctx.resolve(Text(str).font(.system(size: size, weight: .semibold, design: .rounded)).foregroundColor(text))
        let ic = ctx.resolve(Text(Image(systemName: icon)).font(.system(size: size * 0.92, weight: .semibold)).foregroundColor(tint))
        let m = t.measure(in: CGSize(width: 400, height: 40))
        let im = ic.measure(in: CGSize(width: 40, height: 40))
        let w = m.width + im.width + 20, h = size + 10
        let r = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
        let path = Path(roundedRect: r, cornerRadius: h / 2)
        softShadow(&ctx, path, dark ? 0.3 : 0.08)
        ctx.fill(path, with: .color(fill))
        ctx.stroke(path, with: .color(dark ? .white.opacity(0.08) : .black.opacity(0.06)), lineWidth: 0.5)
        ctx.draw(ic, at: P(r.minX + 8 + im.width / 2, p.y))
        ctx.draw(t, at: P(r.minX + 12 + im.width + m.width / 2, p.y))
    }

    private func speech(_ ctx: inout GraphicsContext, _ str: String, at p: CGPoint, size: CGFloat, fill: Color, text: Color) {
        let t = ctx.resolve(Text(str).font(.system(size: size, weight: .medium, design: .rounded)).foregroundColor(text))
        let m = t.measure(in: CGSize(width: 320, height: 40))
        let w = m.width + 20, h = m.height + 10
        var x = p.x - w / 2
        x = max(6, min(Self.size.width - w - 6, x))
        let r = CGRect(x: x, y: p.y - h, width: w, height: h)
        var path = Path(roundedRect: r, cornerRadius: h / 2)
        var tail = Path()
        tail.move(to: P(p.x - 6, r.maxY - 1)); tail.addQuadCurve(to: P(p.x, r.maxY + 7), control: P(p.x - 1, r.maxY + 2))
        tail.addQuadCurve(to: P(p.x + 6, r.maxY - 1), control: P(p.x + 1, r.maxY + 2))
        path.addPath(tail)
        ctx.drawLayer { c in
            c.addFilter(.shadow(color: .black.opacity(0.18), radius: 8, y: 3))
            c.fill(path, with: .color(fill))
        }
        ctx.draw(t, at: P(r.midX, r.midY))
    }
}

/// Kleiner deterministischer Zufall (für Sterne, Dielen, Blätter).
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(state >> 11) / Double(1 << 53))
    }
}
