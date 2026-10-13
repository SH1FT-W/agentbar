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

    /// Floor-Kürbis neben der Feige (Halloween), versteckte Ostereier – als tiefensortierte Einträge.
    func holidayItems() -> [(CGFloat, (inout GraphicsContext) -> Void)] {
        var items: [(CGFloat, (inout GraphicsContext) -> Void)] = []
        if festive.halloween > 0 {
            items.append((458, { c in drawPumpkin(&c, at: P(668, 458), r: 13) }))
            if festive.halloween >= 2 { items.append((560, { c in drawPumpkin(&c, at: P(30, 560), r: 15, face: 1) })) }
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
        var spots = [P(668, 444)]
        if festive.halloween >= 2 { spots += [P(30, 544), Self.tablePumpkin] }
        for (i, p) in spots.enumerated() {
            let flick = 0.85 + 0.15 * sin(time * 6 + Double(i) * 2)
            ctx.fill(circle(p, 46), with: glow(p, 46, rgb(0xFFB347), 0.38 * k * flick))
        }
    }

    static let tablePumpkin = CGPoint(x: 872 + 30, y: 556 - 16)

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
        default: break
        }
    }
}
