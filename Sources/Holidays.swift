import SwiftUI

// MARK: - Halloween, Valentinstag, Ostern (Deko und Kostüme)

extension OfficeScene {
    private var nightK: Double { 1 - dayness }

    /// Herzform um c (Breite ≈ 2·r).
    func heartPath(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: P(c.x, c.y + r * 0.95))
        p.addCurve(to: P(c.x - r, c.y - r * 0.2), control1: P(c.x - r * 0.55, c.y + r * 0.55), control2: P(c.x - r, c.y + r * 0.2))
        p.addArc(center: P(c.x - r * 0.5, c.y - r * 0.3), radius: r * 0.52, startAngle: .degrees(170), endAngle: .degrees(355), clockwise: false)
        p.addArc(center: P(c.x + r * 0.5, c.y - r * 0.3), radius: r * 0.52, startAngle: .degrees(185), endAngle: .degrees(10), clockwise: false)
        p.addCurve(to: P(c.x, c.y + r * 0.95), control1: P(c.x + r, c.y + r * 0.2), control2: P(c.x + r * 0.55, c.y + r * 0.55))
        p.closeSubpath()
        return p
    }

    // MARK: Glasfront

    /// Fledermäuse aus Papier (Halloween), Spinnennetz in der Ecke, Herzgirlande (Valentinstag) – vor dem Glas, an Fäden.
    func drawHolidayWindow(_ ctx: inout GraphicsContext) {
        let g = Self.glass
        let pw = g.width / CGFloat(Self.panes)
        let thread = dark ? Color.white.opacity(0.3) : rgb(0x6A6F78, 0.5)
        if festive.halloween > 0 {
            for (pane, drop, size) in [(0, 70.0, 15.0), (1, 52, 11), (2, 96, 13), (4, 62, 16), (5, 88, 12)] as [(Int, CGFloat, CGFloat)] {
                let cx = g.minX + pw * (CGFloat(pane) + 0.5) + (pane % 2 == 0 ? 14 : -10)
                let tilt = sin(time * 0.6 + Double(pane) * 1.7) * 0.06
                let c = P(cx + CGFloat(tilt) * 12, g.minY + drop)
                var t = Path(); t.move(to: P(cx, g.minY)); t.addLine(to: P(c.x, c.y - size * 0.3))
                ctx.stroke(t, with: .color(thread), lineWidth: 0.6)
                paperBat(&ctx, c, size, tilt: tilt)
            }
        }
        if festive.halloween >= 2 { spiderWeb(&ctx, corner: P(g.minX + 3, g.minY + 1), r: 58) }
        if festive.valentine {
            // Girlande: Herzen an einer durchhängenden Schnur je zweiter Scheibe, dazwischen einzelne Herzen an Fäden
            for i in stride(from: 0, to: Self.panes, by: 2) {
                let x0 = g.minX + CGFloat(i) * pw + 10, x1 = x0 + pw * 2 - 20
                let y0 = g.minY + 4, sag: CGFloat = 26
                var cord = Path(); cord.move(to: P(x0, y0)); cord.addQuadCurve(to: P(x1, y0), control: P((x0 + x1) / 2, y0 + sag * 2))
                ctx.stroke(cord, with: .color(thread), lineWidth: 0.7)
                for k in 1...6 {
                    let t = CGFloat(k) / 7
                    let p = P(x0 + (x1 - x0) * t, y0 + sag * 4 * t * (1 - t) + 6)
                    let col = [rgb(0xE5546E), rgb(0xF29BB0), rgb(0xD63A57)][(k + i) % 3]
                    ctx.fill(heartPath(p, 5.5), with: .linearGradient(Gradient(colors: [lighter(col, 0.2), col]), startPoint: P(p.x - 5, p.y - 5), endPoint: P(p.x + 5, p.y + 5)))
                }
            }
            for (pane, drop) in [(1, 78.0), (3, 64), (5, 90)] as [(Int, CGFloat)] {
                let cx = g.minX + pw * (CGFloat(pane) + 0.5) + 12
                let c = P(cx + CGFloat(sin(time * 0.5 + Double(pane))) * 0.8, g.minY + drop)
                var t = Path(); t.move(to: P(cx, g.minY)); t.addLine(to: P(c.x, c.y - 10))
                ctx.stroke(t, with: .color(thread), lineWidth: 0.6)
                ctx.fill(heartPath(c, 11), with: .linearGradient(Gradient(colors: [rgb(0xF0718A), rgb(0xC92F4E)]), startPoint: P(c.x - 10, c.y - 10), endPoint: P(c.x + 10, c.y + 10)))
                ctx.fill(heartPath(P(c.x - 3, c.y - 3), 3.2), with: .color(.white.opacity(0.25)))
            }
        }
    }

    /// Fledermaus aus schwarzem Papier: Körper mit Ohren, Flügel mit gezackter Unterkante.
    private func paperBat(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, tilt: Double) {
        var bat = Path()
        bat.move(to: P(c.x, c.y - r * 0.15))
        // linker Flügel
        bat.addQuadCurve(to: P(c.x - r * 1.25, c.y - r * 0.45), control: P(c.x - r * 0.6, c.y - r * 0.75))
        bat.addQuadCurve(to: P(c.x - r * 0.85, c.y + r * 0.15), control: P(c.x - r * 1.05, c.y - r * 0.05))
        bat.addQuadCurve(to: P(c.x - r * 0.5, c.y + r * 0.08), control: P(c.x - r * 0.7, c.y - r * 0.1))
        bat.addQuadCurve(to: P(c.x - r * 0.15, c.y + r * 0.3), control: P(c.x - r * 0.35, c.y + r * 0.0))
        // rechter Flügel
        bat.addLine(to: P(c.x + r * 0.15, c.y + r * 0.3))
        bat.addQuadCurve(to: P(c.x + r * 0.5, c.y + r * 0.08), control: P(c.x + r * 0.35, c.y + r * 0.0))
        bat.addQuadCurve(to: P(c.x + r * 0.85, c.y + r * 0.15), control: P(c.x + r * 0.7, c.y - r * 0.1))
        bat.addQuadCurve(to: P(c.x + r * 1.25, c.y - r * 0.45), control: P(c.x + r * 1.05, c.y - r * 0.05))
        bat.addQuadCurve(to: P(c.x, c.y - r * 0.15), control: P(c.x + r * 0.6, c.y - r * 0.75))
        bat.closeSubpath()
        // Kopf mit Ohren
        bat.addEllipse(in: CGRect(x: c.x - r * 0.2, y: c.y - r * 0.38, width: r * 0.4, height: r * 0.45))
        var ears = Path()
        ears.move(to: P(c.x - r * 0.18, c.y - r * 0.28)); ears.addLine(to: P(c.x - r * 0.14, c.y - r * 0.55)); ears.addLine(to: P(c.x - r * 0.04, c.y - r * 0.34))
        ears.move(to: P(c.x + r * 0.18, c.y - r * 0.28)); ears.addLine(to: P(c.x + r * 0.14, c.y - r * 0.55)); ears.addLine(to: P(c.x + r * 0.04, c.y - r * 0.34))
        bat.addPath(ears)
        let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(tilt)).translatedBy(x: -c.x, y: -c.y)
        ctx.fill(bat.applying(t), with: .color(dark ? rgb(0x1A1A1E) : rgb(0x2A2830)))
        // Augen
        for side in [-1.0, 1.0] as [CGFloat] {
            ctx.fill(circle(P(c.x + side * r * 0.08, c.y - r * 0.18).applying(t), max(0.8, r * 0.05)), with: .color(rgb(0xF2C14E)))
        }
    }

    /// Spinnennetz in der oberen linken Glas-Ecke, mit kleiner Spinne am Faden.
    private func spiderWeb(_ ctx: inout GraphicsContext, corner c: CGPoint, r: CGFloat) {
        let col = Color.white.opacity(dark || dayness < 0.5 ? 0.35 : 0.6)
        var web = Path()
        let angles: [Double] = [0, 18, 36, 54, 72, 90]
        for a in angles {
            web.move(to: c)
            web.addLine(to: P(c.x + CGFloat(cos(a * .pi / 180)) * r, c.y + CGFloat(sin(a * .pi / 180)) * r))
        }
        for ring in [0.3, 0.52, 0.74, 0.95] as [CGFloat] {
            for (i, a) in angles.enumerated() where i > 0 {
                let a0 = angles[i - 1] * .pi / 180, a1 = a * .pi / 180
                let p0 = P(c.x + CGFloat(cos(a0)) * r * ring, c.y + CGFloat(sin(a0)) * r * ring)
                let p1 = P(c.x + CGFloat(cos(a1)) * r * ring, c.y + CGFloat(sin(a1)) * r * ring)
                let mid = (a0 + a1) / 2
                if i == 1 { web.move(to: p0) }
                web.addQuadCurve(to: p1, control: P(c.x + CGFloat(cos(mid)) * r * ring * 0.86, c.y + CGFloat(sin(mid)) * r * ring * 0.86))
            }
        }
        ctx.stroke(web, with: .color(col), lineWidth: 0.6)
        // Spinne seilt sich langsam ab und wieder hoch
        let drop = 20 + 10 * CGFloat(sin(time * 0.4))
        let sp = P(c.x + r * 0.62, c.y + r * 0.45 + drop)
        var line = Path(); line.move(to: P(sp.x, c.y + r * 0.45)); line.addLine(to: sp)
        ctx.stroke(line, with: .color(col), lineWidth: 0.5)
        var legs = Path()
        for side in [-1.0, 1.0] as [CGFloat] {
            for k in 0..<3 {
                let y = sp.y - 1 + CGFloat(k) * 1.6
                legs.move(to: P(sp.x, y)); legs.addQuadCurve(to: P(sp.x + side * 5, y + 2), control: P(sp.x + side * 3.5, y - 2.5))
            }
        }
        ctx.stroke(legs, with: .color(rgb(0x1E1E22)), lineWidth: 0.7)
        ctx.fill(oval(sp.x - 2.6, sp.y - 2, 5.2, 5.6), with: .color(rgb(0x1E1E22)))
    }

    // MARK: Raum

    /// Kürbis mit geschnitztem Gesicht; nachts leuchtet er von innen.
    func drawPumpkin(_ ctx: inout GraphicsContext, at b: CGPoint, r: CGFloat, face: Int = 0) {
        shadow(&ctx, CGRect(x: b.x - r * 1.3, y: b.y - r * 0.25, width: r * 2.6, height: r * 0.5), dark ? 0.3 : 0.18)
        let h = r * 1.55
        let top = b.y - h
        // Rippen: drei überlappende Ovale, das mittlere vorn
        let orange = rgb(0xEE8A2C), deep = rgb(0xC9631C)
        for (dx, w) in [(-0.42, 1.15), (0.42, 1.15), (0.0, 1.2)] as [(CGFloat, CGFloat)] {
            let e = CGRect(x: b.x + dx * r - w * r / 2, y: top, width: w * r, height: h)
            ctx.fill(Path(ellipseIn: e), with: .linearGradient(Gradient(colors: [lighter(orange, 0.18), orange, deep]), startPoint: P(e.minX, e.minY), endPoint: P(e.maxX, e.maxY)))
        }
        // Stiel
        var stem = Path()
        stem.move(to: P(b.x - r * 0.1, top + r * 0.12)); stem.addQuadCurve(to: P(b.x + r * 0.2, top - r * 0.28), control: P(b.x - r * 0.08, top - r * 0.2))
        ctx.stroke(stem, with: .color(rgb(0x6B7A3A)), style: StrokeStyle(lineWidth: r * 0.18, lineCap: .round))
        // Gesicht
        let glow = nightK > 0.3
        let inside = glow ? rgb(0xFFD36B).opacity(0.75 + 0.25 * sin(time * 7 + Double(b.x))) : rgb(0x5A2D10)
        var f = Path()
        let ey = top + h * 0.38
        for side in [-1.0, 1.0] as [CGFloat] {
            f.move(to: P(b.x + side * r * 0.22, ey - r * 0.18)); f.addLine(to: P(b.x + side * r * 0.42, ey + r * 0.12)); f.addLine(to: P(b.x + side * r * 0.08, ey + r * 0.12)); f.closeSubpath()
        }
        let my = top + h * 0.66
        f.move(to: P(b.x - r * 0.52, my - r * 0.06))
        let teeth: [(CGFloat, CGFloat)] = face == 0 ? [(-0.3, 0.1), (-0.15, -0.04), (0, 0.12), (0.15, -0.04), (0.3, 0.1)] : [(-0.25, 0.14), (0, 0.04), (0.25, 0.14)]
        for (tx, ty) in teeth { f.addLine(to: P(b.x + tx * r, my + ty * r)) }
        f.addLine(to: P(b.x + r * 0.52, my - r * 0.06))
        f.addQuadCurve(to: P(b.x - r * 0.52, my - r * 0.06), control: P(b.x, my + r * 0.5))
        f.closeSubpath()
        ctx.fill(f, with: .color(inside))
    }

    /// Floor pumpkins (Halloween), versteckte Ostereier – als tiefensortierte Einträge.
    func holidayItems() -> [(CGFloat, (inout GraphicsContext) -> Void)] {
        var items: [(CGFloat, (inout GraphicsContext) -> Void)] = []
        if festive.halloween > 0 {
            // Free floor only: by the snake plant at the window (left of the first rear desk) and on the lounge rug
            // left of the coffee table – off the aisles, the vacuum loop and the seats
            items.append((Self.floorPumpkins[0].y, { c in drawPumpkin(&c, at: Self.floorPumpkins[0], r: 10) }))
            if festive.halloween >= 2 { items.append((Self.floorPumpkins[1].y, { c in drawPumpkin(&c, at: Self.floorPumpkins[1], r: 13, face: 1) })) }
        }
        if festive.easter >= 2 {
            // Gut versteckt: hinter dem Bogenhanf, an der Feige, unter dem Sofa, am Tischbein, unterm Couchtisch, an der Kaffeebar
            let eggs: [(CGFloat, CGFloat, Int, Double)] = [(76, 477, 0, -0.3), (692, 458, 1, 0.2), (794, 501, 2, 0.1), (248, 470, 3, -0.15),
                                                           (836, 586, 4, 0.35), (868, 377, 5, 0), (604, 598, 1, -0.2)]
            for (x, y, k, rot) in eggs { items.append((y, { c in easterEgg(&c, at: P(x, y), r: 5.5, style: k, tilt: rot) })) }
        }
        return items
    }

    /// Bemaltes Osterei (Pastell mit Streifen oder Punkten).
    func easterEgg(_ ctx: inout GraphicsContext, at b: CGPoint, r: CGFloat, style k: Int, tilt: Double, shadowed: Bool = true) {
        let cols: [(Int, Int)] = [(0xF5A3B5, 0xFFFFFF), (0x8FC9F0, 0xFFF1B8), (0xF7D46B, 0xE97A84), (0xA5D99A, 0xFFFFFF), (0xC3A6EE, 0xF7D46B), (0xF6B26B, 0x8FC9F0)]
        let (base, deco) = cols[k % cols.count]
        if shadowed { shadow(&ctx, CGRect(x: b.x - r * 1.2, y: b.y - r * 0.3, width: r * 2.4, height: r * 0.6), 0.2) }
        let t = CGAffineTransform(translationX: b.x, y: b.y - r * 1.25).rotated(by: CGFloat(tilt))
        var egg = Path()
        egg.move(to: P(0, -r * 1.3))
        egg.addCurve(to: P(0, r * 1.2), control1: P(r * 1.15, -r * 1.2), control2: P(r * 1.1, r * 1.2))
        egg.addCurve(to: P(0, -r * 1.3), control1: P(-r * 1.1, r * 1.2), control2: P(-r * 1.15, -r * 1.2))
        let shape = egg.applying(t)
        ctx.fill(shape, with: .linearGradient(Gradient(colors: [lighter(rgb(base), 0.25), rgb(base), darker(rgb(base), 0.1)]),
                                              startPoint: P(b.x - r, b.y - 2.5 * r), endPoint: P(b.x + r, b.y)))
        var c = ctx
        c.clip(to: shape)
        if k % 2 == 0 {
            var band = Path(); band.addRect(CGRect(x: -r * 1.2, y: -r * 0.25, width: r * 2.4, height: r * 0.45))
            c.fill(band.applying(t), with: .color(rgb(deco, 0.9)))
        } else {
            var dots = Path()
            for (dx, dy) in [(-0.4, -0.5), (0.35, -0.2), (-0.2, 0.35), (0.45, 0.6), (0.05, -0.9)] as [(CGFloat, CGFloat)] {
                dots.addEllipse(in: CGRect(x: dx * r - r * 0.17, y: dy * r - r * 0.17, width: r * 0.34, height: r * 0.34))
            }
            c.fill(dots.applying(t), with: .color(rgb(deco, 0.95)))
        }
    }

    /// Osterstrauch: Zweige in der Vase mit bunten Eiern an Fäden (ersetzt den einzelnen Zweig).
    func easterShrub(_ ctx: inout GraphicsContext, vase c: CGPoint) {
        var twigs = Path()
        let tips: [CGPoint] = [P(c.x - 16, c.y - 52), P(c.x + 4, c.y - 60), P(c.x + 22, c.y - 48), P(c.x - 6, c.y - 44), P(c.x + 14, c.y - 36)]
        for t in tips {
            twigs.move(to: P(c.x + 2, c.y - 16))
            twigs.addQuadCurve(to: t, control: P((c.x + t.x) / 2, c.y - 30))
        }
        ctx.stroke(twigs, with: .color(rgb(0x6B5A48)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        for (i, t) in tips.enumerated() {
            ctx.fill(oval(t.x - 2.5, t.y - 3, 5, 6), with: .color(rgb(0x8DBB6E)))
            let hang = P(t.x + (i % 2 == 0 ? 3 : -4), t.y + 12 + CGFloat(i % 3) * 3)
            var thread = Path(); thread.move(to: P(hang.x, t.y + 3)); thread.addLine(to: P(hang.x, hang.y - 7))
            ctx.stroke(thread, with: .color(rgb(0x8E8E93, 0.6)), lineWidth: 0.5)
            easterEgg(&ctx, at: hang, r: 3.2, style: i, tilt: 0, shadowed: false)
        }
    }

    /// Drei rote Rosen in der Vase (Valentinstag).
    func roses(_ ctx: inout GraphicsContext, vase c: CGPoint) {
        let heads: [CGPoint] = [P(c.x - 4, c.y - 40), P(c.x + 9, c.y - 44), P(c.x + 2, c.y - 33)]
        var stems = Path()
        for h in heads { stems.move(to: P(c.x + 2, c.y - 16)); stems.addQuadCurve(to: h, control: P((c.x + h.x) / 2 + 1, c.y - 26)) }
        ctx.stroke(stems, with: .color(rgb(0x4E7D46)), lineWidth: 1.1)
        ctx.fill(oval(c.x - 6, c.y - 30, 6, 3.4).applying(rot(-0.5, P(c.x - 3, c.y - 28))), with: .color(rgb(0x5E9C52)))
        ctx.fill(oval(c.x + 6, c.y - 27, 6, 3.4).applying(rot(0.5, P(c.x + 9, c.y - 25))), with: .color(rgb(0x5E9C52)))
        for h in heads {
            ctx.fill(circle(h, 4.6), with: .radialGradient(Gradient(colors: [rgb(0xE0405E), rgb(0xA5182F)]), center: P(h.x - 1, h.y - 1), startRadius: 0, endRadius: 5))
            var swirl = Path(); swirl.addArc(center: P(h.x + 0.4, h.y), radius: 2, startAngle: .degrees(200), endAngle: .degrees(80), clockwise: false)
            ctx.stroke(swirl, with: .color(rgb(0x7A0F22, 0.7)), lineWidth: 0.7)
        }
    }

    /// Saugroboter-Kostüme: Gespenst (Halloween) und Hasenohren (Ostern).
    func drawVacuumCostume(_ ctx: inout GraphicsContext, at p: CGPoint, front: CGFloat) {
        if festive.vacuumGhost {
            var sheet = Path()
            sheet.move(to: P(p.x - 22, p.y - 4))
            sheet.addCurve(to: P(p.x + 22, p.y - 4), control1: P(p.x - 22, p.y - 34), control2: P(p.x + 22, p.y - 34))
            for k in 0..<4 {   // Wellen-Saum
                let x0 = p.x + 22 - CGFloat(k) * 11
                sheet.addQuadCurve(to: P(x0 - 11, p.y - 4), control: P(x0 - 5.5, p.y + 1 + CGFloat(sin(time * 3 + Double(k))) * 1.2))
            }
            sheet.closeSubpath()
            ctx.fill(sheet, with: .linearGradient(Gradient(colors: [.white, rgb(0xDCDDE2)]), startPoint: P(p.x - 22, 0), endPoint: P(p.x + 22, 0)))
            for dx in [-5.0, 5.0] as [CGFloat] {
                ctx.fill(oval(p.x + front * 6 + dx - 2.2, p.y - 22, 4.4, 5.6), with: .color(rgb(0x1E1E22)))
            }
        }
        if festive.vacuumEars {
            for side in [-1.0, 1.0] as [CGFloat] {
                let base = P(p.x + side * 5, p.y - 12)
                let ear = Path(ellipseIn: CGRect(x: -3.6, y: -18, width: 7.2, height: 18)).applying(CGAffineTransform(translationX: base.x, y: base.y).rotated(by: side * 0.25))
                let inner = Path(ellipseIn: CGRect(x: -1.8, y: -15, width: 3.6, height: 12)).applying(CGAffineTransform(translationX: base.x, y: base.y).rotated(by: side * 0.25))
                ctx.fill(ear, with: .color(rgb(0xF4F4F6)))
                ctx.fill(inner, with: .color(rgb(0xF5B5C5)))
            }
        }
    }

    /// Nachtlicht der Kürbisse (nach dem Abdunkeln).
    func drawHolidayGlow(_ ctx: inout GraphicsContext) {
        guard festive.halloween > 0, nightK > 0.3 else { return }
        let k = nightK
        var spots = [P(Self.floorPumpkins[0].x, Self.floorPumpkins[0].y - 10)]
        if festive.halloween >= 2 { spots += [P(Self.floorPumpkins[1].x, Self.floorPumpkins[1].y - 14), Self.tablePumpkin] }
        for (i, p) in spots.enumerated() {
            let flick = 0.85 + 0.15 * sin(time * 6 + Double(i) * 2)
            ctx.fill(circle(p, 46), with: glow(p, 46, rgb(0xFFB347), 0.38 * k * flick))
        }
    }

    static let tablePumpkin = CGPoint(x: 872 + 30, y: 556 - 16)
    /// Floor pumpkins (base point): week before Halloween only the first, on the day both.
    static let floorPumpkins = [CGPoint(x: 96, y: 402), CGPoint(x: 762, y: 568)]

    // MARK: Kostüme (Kopf-Koordinaten wie drawHat)

    func drawCostumeHat(_ ctx: inout GraphicsContext, _ hat: Outfit.Hat, r: CGFloat, s: CGFloat) {
        switch hat {
        case .witch:
            let brimY = -r * 0.72
            var cone = Path()
            cone.move(to: P(-r * 0.62, brimY))
            cone.addQuadCurve(to: P(r * 0.42, -r * 2.25), control: P(-r * 0.25, -r * 1.7))
            cone.addQuadCurve(to: P(r * 0.62, brimY), control: P(r * 0.35, -r * 1.4))
            cone.closeSubpath()
            let felt = rgb(0x2E2838)
            ctx.fill(Path(ellipseIn: CGRect(x: -r * 1.4, y: brimY - r * 0.2, width: r * 2.8, height: r * 0.42)), with: .color(darker(felt, 0.15)))
            ctx.fill(cone, with: .linearGradient(Gradient(colors: [lighter(felt, 0.15), felt]), startPoint: P(-r * 0.6, 0), endPoint: P(r * 0.6, 0)))
            var band = ctx
            band.clip(to: cone)
            band.fill(Path(CGRect(x: -r, y: brimY - r * 0.32, width: 2 * r, height: r * 0.24)), with: .color(rgb(0xE8873A)))
            ctx.fill(rounded(-r * 0.12, brimY - r * 0.31, r * 0.24, r * 0.22, 1.5 * s), with: .color(rgb(0xF2C14E)))
        case .catEars:
            var band = Path()
            band.addArc(center: P(0, -r * 0.05), radius: r * 1.0, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(band, with: .color(rgb(0x1E1E22)), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
            for side in [-1.0, 1.0] as [CGFloat] {
                var ear = Path()
                ear.move(to: P(side * r * 0.3, -r * 0.92)); ear.addLine(to: P(side * r * 0.62, -r * 1.55)); ear.addLine(to: P(side * r * 0.82, -r * 0.62)); ear.closeSubpath()
                var inner = Path()
                inner.move(to: P(side * r * 0.42, -r * 0.92)); inner.addLine(to: P(side * r * 0.61, -r * 1.36)); inner.addLine(to: P(side * r * 0.72, -r * 0.78)); inner.closeSubpath()
                ctx.fill(ear, with: .color(rgb(0x1E1E22)))
                ctx.fill(inner, with: .color(rgb(0xE79AAE)))
            }
        case .horns:
            var band = Path()
            band.addArc(center: P(0, -r * 0.05), radius: r * 1.0, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(band, with: .color(rgb(0x8E1C24)), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
            for side in [-1.0, 1.0] as [CGFloat] {
                var horn = Path()
                horn.move(to: P(side * r * 0.32, -r * 0.88))
                horn.addQuadCurve(to: P(side * r * 0.72, -r * 1.55), control: P(side * r * 0.25, -r * 1.35))
                horn.addQuadCurve(to: P(side * r * 0.66, -r * 0.8), control: P(side * r * 0.7, -r * 1.1))
                horn.closeSubpath()
                ctx.fill(horn, with: .linearGradient(Gradient(colors: [rgb(0xE5404C), rgb(0xA4202B)]), startPoint: P(side * r * 0.3, -r * 1.5), endPoint: P(side * r * 0.7, -r * 0.8)))
            }
        case .bunnyEars:
            var band = Path()
            band.addArc(center: P(0, -r * 0.05), radius: r * 1.0, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(band, with: .color(rgb(0xF2F2F5)), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
            for side in [-1.0, 1.0] as [CGFloat] {
                // rechtes Ohr knickt ab
                let t = CGAffineTransform(translationX: side * r * 0.36, y: -r * 0.9).rotated(by: side * 0.16)
                let ear = Path(roundedRect: CGRect(x: -r * 0.2, y: -r * 1.15, width: r * 0.4, height: r * 1.2), cornerRadius: r * 0.2, style: .continuous)
                let inner = Path(roundedRect: CGRect(x: -r * 0.1, y: -r * 1.02, width: r * 0.2, height: r * 0.95), cornerRadius: r * 0.1, style: .continuous)
                if side > 0 {
                    let fold = CGAffineTransform(translationX: 0, y: -r * 0.55).rotated(by: 0.9).translatedBy(x: 0, y: r * 0.55)
                    let lower = Path(roundedRect: CGRect(x: -r * 0.2, y: -r * 0.6, width: r * 0.4, height: r * 0.65), cornerRadius: r * 0.2, style: .continuous)
                    let upper = Path(roundedRect: CGRect(x: -r * 0.2, y: -r * 1.15, width: r * 0.4, height: r * 0.62), cornerRadius: r * 0.2, style: .continuous)
                    ctx.fill(lower.applying(t), with: .color(.white))
                    ctx.fill(Path(roundedRect: CGRect(x: -r * 0.1, y: -r * 0.5, width: r * 0.2, height: r * 0.45), cornerRadius: r * 0.1).applying(t), with: .color(rgb(0xF5B5C5)))
                    ctx.fill(upper.applying(fold.concatenating(t)), with: .color(rgb(0xF0F0F3)))
                } else {
                    ctx.fill(ear.applying(t), with: .color(.white))
                    ctx.fill(inner.applying(t), with: .color(rgb(0xF5B5C5)))
                }
            }
        case .hearts:
            var band = Path()
            band.addArc(center: P(0, -r * 0.05), radius: r * 1.0, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(band, with: .color(rgb(0xC92F4E)), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
            for side in [-1.0, 1.0] as [CGFloat] {
                let wob = CGFloat(sin(time * 2.4 + Double(side))) * r * 0.06
                let tip = P(side * r * 0.55 + wob, -r * 1.68)
                var spring = Path(); spring.move(to: P(side * r * 0.4, -r * 0.9)); spring.addQuadCurve(to: tip, control: P(side * r * 0.62, -r * 1.25))
                ctx.stroke(spring, with: .color(rgb(0x3A3A3C)), lineWidth: 1 * s)
                ctx.fill(heartPath(tip, r * 0.24), with: .linearGradient(Gradient(colors: [rgb(0xF0718A), rgb(0xC92F4E)]), startPoint: P(tip.x - r * 0.2, tip.y - r * 0.2), endPoint: P(tip.x + r * 0.2, tip.y + r * 0.2)))
            }
        case .wizard:
            // Tall midnight-blue hat with a bent tip, wide brim and gold stars
            let brimY = -r * 0.7
            let blue = rgb(0x34407E)
            var cone = Path()
            cone.move(to: P(-r * 0.66, brimY))
            cone.addQuadCurve(to: P(-r * 0.05, -r * 2.15), control: P(-r * 0.4, -r * 1.6))
            cone.addQuadCurve(to: P(r * 0.62, -r * 2.05), control: P(r * 0.3, -r * 2.45))
            cone.addQuadCurve(to: P(r * 0.66, brimY), control: P(r * 0.3, -r * 1.5))
            cone.closeSubpath()
            ctx.fill(Path(ellipseIn: CGRect(x: -r * 1.45, y: brimY - r * 0.2, width: r * 2.9, height: r * 0.42)), with: .color(darker(blue, 0.2)))
            ctx.fill(cone, with: .linearGradient(Gradient(colors: [lighter(blue, 0.18), blue]), startPoint: P(-r * 0.6, 0), endPoint: P(r * 0.6, 0)))
            for (sx, sy, sr) in [(-0.2, -1.25, 0.2), (0.25, -1.65, 0.15), (0.18, -0.95, 0.13)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.fill(starPath(P(sx * r, sy * r), sr * r), with: .color(rgb(0xF2C94C)))
            }
        case .pumpkinCap:
            // Pumpkin hat: ribbed orange dome, green stem and a leaf
            let orange = rgb(0xEE8A2C)
            var dome = Path()
            dome.addArc(center: P(0, -r * 0.42), radius: r * 1.06, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            dome.addQuadCurve(to: P(-r * 1.06, -r * 0.42), control: P(0, -r * 0.2))
            ctx.fill(dome, with: .linearGradient(Gradient(colors: [lighter(orange, 0.15), orange, rgb(0xC9631C)]), startPoint: P(-r, -r * 1.4), endPoint: P(r, -r * 0.4)))
            var ribs = Path()
            for dx in [-0.5, 0, 0.5] as [CGFloat] {
                ribs.move(to: P(dx * r * 0.7, -r * 1.42)); ribs.addQuadCurve(to: P(dx * r * 1.3, -r * 0.36), control: P(dx * r * 1.25, -r * 1.05))
            }
            var c = ctx
            c.clip(to: dome)
            c.stroke(ribs, with: .color(rgb(0xB5561A, 0.55)), lineWidth: 1.4 * s)
            ctx.fill(rounded(-r * 0.09, -r * 1.75, r * 0.18, r * 0.36, 1.5 * s), with: .color(rgb(0x6B7A3A)))
            ctx.fill(Path(ellipseIn: CGRect(x: 0, y: -r * 0.13, width: r * 0.5, height: r * 0.26))
                        .applying(CGAffineTransform(translationX: r * 0.06, y: -r * 1.55).rotated(by: -0.4)), with: .color(rgb(0x5E9C52)))
        case .mummyWrap:
            // Bandages over the whole head, eyes and mouth stay free (they are drawn afterwards)
            let wrap = Path(ellipseIn: CGRect(x: -r - 1.5 * s, y: -r - 1.5 * s, width: 2 * r + 3 * s, height: 2 * r * 1.03 + 3 * s))
            ctx.fill(wrap, with: .radialGradient(Gradient(colors: [rgb(0xF6F1E4), rgb(0xE6DDC6), rgb(0xCFC3A6)]), center: P(-r * 0.25, -r * 0.3), startRadius: 0, endRadius: r * 1.35))
            var c = ctx
            c.clip(to: wrap)
            var seams = Path()
            for (k, y) in [-0.82, -0.52, -0.22, 0.42, 0.72].enumerated() {
                let tiltY = (k % 2 == 0 ? 1.0 : -1.0) * r * 0.12
                seams.move(to: P(-r * 1.1, y * r - tiltY)); seams.addLine(to: P(r * 1.1, y * r + tiltY))
            }
            c.stroke(seams, with: .color(rgb(0xA89A7A, 0.6)), lineWidth: 1.1 * s)
            // Dark gap around the eyes
            c.fill(Path(roundedRect: CGRect(x: -r * 0.78, y: -r * 0.2, width: r * 1.56, height: r * 0.5), cornerRadius: r * 0.2), with: .color(rgb(0x3A3128, 0.55)))
        case .skullPaint:
            // White face paint with dark eye sockets (eyes, nose and mouth are drawn on top)
            let face = Path(ellipseIn: CGRect(x: -r, y: -r * 1.0, width: 2 * r, height: 2 * r * 1.03))
            var c = ctx
            c.clip(to: face)
            c.fill(Path(ellipseIn: CGRect(x: -r * 0.92, y: -r * 0.5, width: r * 1.84, height: r * 1.6)), with: .color(rgb(0xF1EFE8)))
            for side in [-1.0, 1.0] as [CGFloat] {
                c.fill(Path(ellipseIn: CGRect(x: side * 8.2 * s - 6.4 * s, y: 1 * s - 6.8 * s, width: 12.8 * s, height: 12.6 * s)), with: .color(rgb(0x2A2A2E)))
            }
        default: break
        }
    }

    /// Small five-pointed star.
    func starPath(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            let rr = i % 2 == 0 ? r : r * 0.45
            let q = P(c.x + CGFloat(cos(a)) * rr, c.y + CGFloat(sin(a)) * rr)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }

    // MARK: Full costumes (Halloween day)

    /// Behind the body: vampire cape, devil tail. `bottom` = lower end of the cape (seat or near the feet).
    func drawCostumeBack(_ ctx: inout GraphicsContext, outfit o: Outfit, x: CGFloat, shoulderY: CGFloat, bottom: CGFloat, s: CGFloat, standing: Bool, sway: CGFloat = 0) {
        guard let c = o.costume else { return }
        switch c {
        case .vampire, .wizard:
            let outer = c == .vampire ? rgb(0x1C1A22) : rgb(0x2A3366)
            let lining = c == .vampire ? rgb(0xB0202E) : rgb(0x4A58A0)
            let flare: CGFloat = standing ? 36 : 33
            var cape = Path()
            cape.move(to: P(x - 18 * s, shoulderY + 2 * s))
            cape.addQuadCurve(to: P(x - flare * s - sway, bottom), control: P(x - 30 * s, shoulderY + 20 * s))
            cape.addQuadCurve(to: P(x + flare * s - sway, bottom), control: P(x, bottom + 6 * s))
            cape.addQuadCurve(to: P(x + 18 * s, shoulderY + 2 * s), control: P(x + 30 * s, shoulderY + 20 * s))
            cape.closeSubpath()
            ctx.fill(cape, with: .color(outer))
            var inner = Path()
            inner.move(to: P(x - 15 * s, shoulderY + 6 * s))
            inner.addQuadCurve(to: P(x - (flare - 4) * s - sway, bottom - 2 * s), control: P(x - 26 * s, shoulderY + 22 * s))
            inner.addQuadCurve(to: P(x + (flare - 4) * s - sway, bottom - 2 * s), control: P(x, bottom + 3 * s))
            inner.addQuadCurve(to: P(x + 15 * s, shoulderY + 6 * s), control: P(x + 26 * s, shoulderY + 22 * s))
            inner.closeSubpath()
            ctx.fill(inner, with: vgrad([darker(lining, 0.25), lining], shoulderY, bottom))
        case .devil where standing:
            // Tail with a spade tip, sticking out to the right (seated it would poke up behind the desk like an arrow)
            let root = P(x + 14 * s, shoulderY + 48 * s)
            let tip = P(x + 44 * s, root.y - 4 * s + CGFloat(sin(time * 2.2 + Double(x))) * 2 * s)
            var tail = Path(); tail.move(to: root)
            tail.addCurve(to: tip, control1: P(root.x + 26 * s, root.y + 14 * s), control2: P(tip.x - 14 * s, tip.y + 8 * s))
            ctx.stroke(tail, with: .color(rgb(0xA4202B)), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
            var spade = Path()
            spade.move(to: P(tip.x + 7 * s, tip.y - 6 * s))
            spade.addLine(to: P(tip.x - 4 * s, tip.y - 3 * s)); spade.addLine(to: P(tip.x + 2 * s, tip.y + 6 * s)); spade.closeSubpath()
            ctx.fill(spade, with: .color(rgb(0xC8303A)))
        default: break
        }
    }

    /// On the torso (clipped to it): ribs, pumpkin face, stars, bandages, shirt front.
    func drawCostumeTorso(_ ctx: inout GraphicsContext, outfit o: Outfit, torso: Path, x: CGFloat, shoulderY y: CGFloat, s: CGFloat) {
        guard let c = o.costume else { return }
        var g = ctx
        g.clip(to: torso)
        switch c {
        case .skeleton:
            let bone = rgb(0xF1EFE8)
            g.fill(rounded(x - 1.6 * s, y + 6 * s, 3.2 * s, 44 * s, 1.6 * s), with: .color(bone))
            var ribs = Path()
            for k in 0..<4 {
                let ry = y + (12 + CGFloat(k) * 7) * s, w = (15 - CGFloat(k) * 1.5) * s
                for side in [-1.0, 1.0] as [CGFloat] {
                    ribs.move(to: P(x + side * 2.5 * s, ry))
                    ribs.addQuadCurve(to: P(x + side * w, ry + 4 * s), control: P(x + side * w * 0.8, ry - 2.5 * s))
                }
            }
            g.stroke(ribs, with: .color(bone), style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
            // Collarbones
            var cb = Path(); cb.move(to: P(x - 16 * s, y + 5 * s)); cb.addQuadCurve(to: P(x + 16 * s, y + 5 * s), control: P(x, y + 9 * s))
            g.stroke(cb, with: .color(bone), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
        case .pumpkin:
            var ribs = Path()
            for dx in [-15.0, -6, 6, 15] as [CGFloat] {
                ribs.move(to: P(x + dx * s, y)); ribs.addQuadCurve(to: P(x + dx * 1.15 * s, y + 60 * s), control: P(x + dx * 1.35 * s, y + 30 * s))
            }
            g.stroke(ribs, with: .color(rgb(0xB5561A, 0.45)), lineWidth: 1.4 * s)
            let glowing = nightK > 0.3
            let inside = glowing ? rgb(0xFFD36B) : rgb(0x5A2D10)
            var f = Path()
            let ey = y + 15 * s
            for side in [-1.0, 1.0] as [CGFloat] {
                f.move(to: P(x + side * 5 * s, ey - 4 * s)); f.addLine(to: P(x + side * 10 * s, ey + 3 * s)); f.addLine(to: P(x + side * 1.5 * s, ey + 3 * s)); f.closeSubpath()
            }
            let my = y + 25 * s
            f.move(to: P(x - 12 * s, my))
            for (tx, ty) in [(-7.0, 3.0), (-3.5, 0.5), (0, 3.5), (3.5, 0.5), (7, 3)] as [(CGFloat, CGFloat)] { f.addLine(to: P(x + tx * s, my + ty * s)) }
            f.addLine(to: P(x + 12 * s, my))
            f.addQuadCurve(to: P(x - 12 * s, my), control: P(x, my + 13 * s))
            f.closeSubpath()
            g.fill(f, with: .color(inside))
        case .wizard:
            for (dx, dy, r) in [(-12.0, 14.0, 3.2), (9, 24, 2.6), (-4, 36, 2.4), (14, 42, 3), (-15, 46, 2.2)] as [(CGFloat, CGFloat, CGFloat)] {
                g.fill(starPath(P(x + dx * s, y + dy * s), r * s), with: .color(rgb(0xF2C94C)))
            }
            // Crescent moon
            var moon = Path(); moon.addEllipse(in: CGRect(x: x + 3 * s, y: y + 6 * s, width: 9 * s, height: 9 * s))
            g.fill(moon, with: .color(rgb(0xF2C94C)))
            g.fill(circle(P(x + 10 * s, y + 9 * s), 4.2 * s), with: .color(rgb(0x34407E)))
        case .mummy:
            var seams = Path()
            for k in 0..<9 {
                let yy = y + CGFloat(k) * 7 * s
                let d = (k % 2 == 0 ? 1.0 : -1.0) * 5 * s
                seams.move(to: P(x - 30 * s, yy - d)); seams.addLine(to: P(x + 30 * s, yy + d))
            }
            g.stroke(seams, with: .color(rgb(0xA89A7A, 0.65)), lineWidth: 1.1 * s)
            // A loose bandage end
            g.fill(Path(roundedRect: CGRect(x: x + 8 * s, y: y + 20 * s, width: 5 * s, height: 16 * s), cornerRadius: 1.5 * s).applying(rot(0.25, P(x + 10 * s, y + 20 * s))), with: .color(rgb(0xF6F1E4)))
        case .vampire:
            // White shirt front with a red vest and a brooch
            var front = Path()
            front.move(to: P(x - 10 * s, y)); front.addLine(to: P(x + 10 * s, y)); front.addLine(to: P(x + 4 * s, y + 34 * s)); front.addLine(to: P(x - 4 * s, y + 34 * s)); front.closeSubpath()
            g.fill(front, with: .color(rgb(0xF2F0EC)))
            for side in [-1.0, 1.0] as [CGFloat] {
                var vest = Path()
                vest.move(to: P(x + side * 10 * s, y)); vest.addLine(to: P(x + side * 4 * s, y + 34 * s)); vest.addLine(to: P(x + side * 14 * s, y + 40 * s)); vest.addLine(to: P(x + side * 18 * s, y)); vest.closeSubpath()
                g.fill(vest, with: .color(rgb(0x8E1C24)))
            }
            g.fill(circle(P(x, y + 9 * s), 3 * s), with: .radialGradient(Gradient(colors: [rgb(0xFF6B6B), rgb(0xA4202B)]), center: P(x - 1 * s, y + 8 * s), startRadius: 0, endRadius: 3.2 * s))
        case .witch:
            // Lacing across the bodice and an orange belt
            var lace = Path()
            for k in 0..<3 {
                let yy = y + (10 + CGFloat(k) * 7) * s
                lace.move(to: P(x - 5 * s, yy)); lace.addLine(to: P(x + 5 * s, yy + 6 * s))
                lace.move(to: P(x + 5 * s, yy)); lace.addLine(to: P(x - 5 * s, yy + 6 * s))
            }
            g.stroke(lace, with: .color(rgb(0x1E1E22)), style: StrokeStyle(lineWidth: 1.3 * s, lineCap: .round))
            g.fill(Path(CGRect(x: x - 30 * s, y: y + 34 * s, width: 60 * s, height: 5 * s)), with: .color(rgb(0xE8873A)))
            g.fill(rounded(x - 4 * s, y + 33 * s, 8 * s, 7 * s, 1.5 * s), with: .color(rgb(0xF2C14E)))
        case .cat:
            g.fill(Path(ellipseIn: CGRect(x: x - 11 * s, y: y + 8 * s, width: 22 * s, height: 34 * s)), with: .color(rgb(0x5A5A62)))
        case .devil:
            var v = Path(); v.move(to: P(x - 12 * s, y)); v.addLine(to: P(x, y + 14 * s)); v.addLine(to: P(x + 12 * s, y))
            g.stroke(v, with: .color(rgb(0x7A1018)), lineWidth: 2 * s)
        }
    }

    /// Standing vampire collar behind the head (drawn between neck and head).
    func drawCostumeCollar(_ ctx: inout GraphicsContext, outfit o: Outfit, x: CGFloat, shoulderY y: CGFloat, s: CGFloat) {
        guard o.costume == .vampire else { return }
        for side in [-1.0, 1.0] as [CGFloat] {
            var wing = Path()
            wing.move(to: P(x + side * 5 * s, y + 2 * s))
            wing.addLine(to: P(x + side * 36 * s, y - 32 * s))
            wing.addQuadCurve(to: P(x + side * 20 * s, y + 4 * s), control: P(x + side * 34 * s, y - 6 * s))
            wing.closeSubpath()
            ctx.fill(wing, with: .color(rgb(0x1C1A22)))
            var inner = Path()
            inner.move(to: P(x + side * 8 * s, y))
            inner.addLine(to: P(x + side * 32 * s, y - 27 * s))
            inner.addQuadCurve(to: P(x + side * 19 * s, y + 1 * s), control: P(x + side * 30 * s, y - 6 * s))
            inner.closeSubpath()
            ctx.fill(inner, with: .color(rgb(0xB0202E)))
        }
    }

    /// Face extras in head coordinates (after eyes and mouth): fangs, whiskers, skull teeth, wizard beard.
    func drawCostumeFace(_ ctx: inout GraphicsContext, outfit o: Outfit, r: CGFloat, s: CGFloat) {
        guard let c = o.costume else { return }
        let my = 13 * s
        switch c {
        case .vampire:
            for side in [-1.0, 1.0] as [CGFloat] {
                var fang = Path()
                fang.move(to: P(side * 1.4 * s, my)); fang.addLine(to: P(side * 4.2 * s, my)); fang.addLine(to: P(side * 2.9 * s, my + 4.2 * s)); fang.closeSubpath()
                ctx.fill(fang, with: .color(.white))
            }
        case .cat:
            ctx.fill(heartPath(P(0, 7.4 * s), 2.6 * s).applying(CGAffineTransform(translationX: 0, y: 0)), with: .color(rgb(0x1E1E22)))
            var w = Path()
            for side in [-1.0, 1.0] as [CGFloat] {
                for dy in [-2.0, 0.5, 3] as [CGFloat] {
                    w.move(to: P(side * 9 * s, (9 + dy * 0.4) * s)); w.addLine(to: P(side * 21 * s, (9 + dy * 1.4) * s))
                }
            }
            ctx.stroke(w, with: .color(rgb(0x1E1E22, 0.8)), style: StrokeStyle(lineWidth: 0.9 * s, lineCap: .round))
        case .skeleton:
            ctx.fill(heartPath(P(0, 7 * s), 2.8 * s).applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 14 * s)), with: .color(rgb(0x2A2A2E)))
            var teeth = Path()
            teeth.move(to: P(-7 * s, my + 1.5 * s)); teeth.addLine(to: P(7 * s, my + 1.5 * s))
            for k in -3...3 { teeth.move(to: P(CGFloat(k) * 2 * s, my - 1 * s)); teeth.addLine(to: P(CGFloat(k) * 2 * s, my + 4 * s)) }
            ctx.stroke(teeth, with: .color(rgb(0x2A2A2E)), style: StrokeStyle(lineWidth: 1 * s, lineCap: .round))
        case .devil:
            // Painted pointy goatee
            var goatee = Path()
            goatee.move(to: P(-3.2 * s, r * 0.86)); goatee.addQuadCurve(to: P(0, r * 1.22), control: P(-1.4 * s, r * 1.05))
            goatee.addQuadCurve(to: P(3.2 * s, r * 0.86), control: P(1.4 * s, r * 1.05)); goatee.closeSubpath()
            ctx.fill(goatee, with: .color(rgb(0x2A1A1C)))
        case .wizard:
            // White beard from the cheeks down past the chin, moustache over the mouth
            let white = rgb(0xF2F2F5), shade = rgb(0xD6D7DD)
            var beard = Path()
            beard.move(to: P(-r * 0.78, 4 * s))
            beard.addQuadCurve(to: P(-r * 0.35, r * 1.35), control: P(-r * 0.85, r * 0.95))
            beard.addLine(to: P(0, r * 1.65)); beard.addLine(to: P(r * 0.35, r * 1.35))
            beard.addQuadCurve(to: P(r * 0.78, 4 * s), control: P(r * 0.85, r * 0.95))
            beard.addQuadCurve(to: P(-r * 0.78, 4 * s), control: P(0, r * 0.95))
            beard.closeSubpath()
            ctx.fill(beard, with: .linearGradient(Gradient(colors: [white, shade]), startPoint: P(0, 4 * s), endPoint: P(0, r * 1.6)))
            for side in [-1.0, 1.0] as [CGFloat] {
                ctx.fill(Path(ellipseIn: CGRect(x: -5 * s, y: -2.4 * s, width: 10 * s, height: 4.8 * s))
                            .applying(CGAffineTransform(translationX: side * 4.4 * s, y: my - 1 * s).rotated(by: side * 0.25)), with: .color(white))
            }
        default: break
        }
    }
}

extension Outfit.Costume {
    var shirt: Color {
        switch self {
        case .witch: return rgb(0x5B3A7E)
        case .vampire: return rgb(0x2A2730)
        case .skeleton: return rgb(0x2A2A30)
        case .pumpkin: return rgb(0xEE8A2C)
        case .wizard: return rgb(0x34407E)
        case .mummy: return rgb(0xE9E2CF)
        case .devil: return rgb(0xC8303A)
        case .cat: return rgb(0x2E2E34)
        }
    }
    var pants: Color? {
        switch self {
        case .skeleton, .cat, .vampire: return rgb(0x1E1E22)
        case .mummy: return rgb(0xD8CFB8)
        default: return nil
        }
    }
    var headwear: Outfit.Hat {
        switch self {
        case .witch: return .witch
        case .wizard: return .wizard
        case .pumpkin: return .pumpkinCap
        case .mummy: return .mummyWrap
        case .skeleton: return .skullPaint
        case .devil: return .horns
        case .cat: return .catEars
        case .vampire: return .none
        }
    }
}
