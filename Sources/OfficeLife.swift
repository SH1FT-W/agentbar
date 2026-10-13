import SwiftUI

// MARK: - Kaffeebar (Sideboard mit Siebträgermaschine hinter dem Sofa)

extension OfficeScene {
    /// Läuft die Maschine gerade? Jemand steht an Platz 0 ohne Tasse.
    func brewing(_ coffee: [Actor]) -> Bool {
        coffee.contains { $0.place == .coffee(0) && !$0.cup && $0.pose == .standing }
    }

    /// Sideboard an der Rückwand: Eiche, weiße Front; darauf Tassenstapel, Kaffeedose und die Maschine.
    func drawCoffeeBar(_ ctx: inout GraphicsContext, brewing: Bool) {
        let x0: CGFloat = 752, x1: CGFloat = 866, base: CGFloat = 374, top: CGFloat = 343
        shadow(&ctx, CGRect(x: x0 - 6, y: base - 5, width: x1 - x0 + 12, height: 10), dark ? 0.3 : 0.15)
        // Korpus
        let front = dark ? rgb(0xD8D8DC) : rgb(0xF7F7F8)
        ctx.fill(rounded(x0, top + 3, x1 - x0, base - top - 5, 2), with: vgrad([front, darker(front, 0.07)], top, base))
        ctx.fill(Path(CGRect(x: (x0 + x1) / 2 - 0.4, y: top + 6, width: 0.8, height: base - top - 11)), with: .color(.black.opacity(0.08)))
        for gx in [x0 + 26, x1 - 26] {
            ctx.fill(rounded(gx - 7, top + 10, 14, 1.6, 0.8), with: .color(aluDark))
        }
        // Platte (Eiche) und Sockel
        ctx.fill(rounded(x0 - 3, top - 1, x1 - x0 + 6, 5, 1.5), with: vgrad([lighter(oak, 0.2), oak], top - 1, top + 4))
        ctx.fill(rounded(x0 + 3, base - 3, x1 - x0 - 6, 3, 1), with: .color(darker(oak, 0.25)))

        // Tassenstapel und Dose links
        for i in 0..<3 {
            let cy = top - 1 - CGFloat(i) * 5.5
            ctx.fill(rounded(x0 + 10 - CGFloat(i % 2), cy - 5.5, 12, 5.5, 1.5), with: .linearGradient(Gradient(colors: [.white, rgb(0xD9D9DE)]), startPoint: P(x0 + 10, 0), endPoint: P(x0 + 22, 0)))
        }
        ctx.fill(rounded(x0 + 30, top - 15, 11, 15, 3), with: .linearGradient(Gradient(colors: [rgb(0x3B3E44), rgb(0x24262A)]), startPoint: P(x0 + 30, 0), endPoint: P(x0 + 41, 0)))
        ctx.fill(rounded(x0 + 30, top - 16.5, 11, 3, 1.2), with: .color(alu))
        // kleine Pflanze
        let pot = CGRect(x: x0 + 50, y: top - 9, width: 10, height: 9)
        potBack(&ctx, pot, 0.7, rim: 2.4)
        for (dx, dy, r) in [(-3.0, -14.0, 3.4), (3, -15, 3.6), (0, -19, 3.6), (5, -10, 2.8), (-5, -10, 2.8)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.fill(circle(P(pot.midX + dx, top + dy), r), with: .color(dx == 0 ? rgb(0x6DB566) : rgb(0x4F9A55)))
        }
        potFront(&ctx, pot, 0.7, rim: 2.4, corner: 2)

        drawEspressoMachine(&ctx, at: OfficeModel.coffeeMachine, brewing: brewing)
    }

    /// Siebträgermaschine in Edelstahl: Gehäuse, Tassenablage oben, Brühgruppe mit Siebträger, Tropfschale.
    private func drawEspressoMachine(_ ctx: inout GraphicsContext, at c: CGPoint, brewing: Bool) {
        let w: CGFloat = 34, h: CGFloat = 38
        let x = c.x - w / 2, base = c.y
        shadow(&ctx, CGRect(x: x - 3, y: base - 3, width: w + 6, height: 6), 0.2)
        let steel = Gradient(colors: [rgb(0xE9EBEE), rgb(0xBFC4CA), rgb(0xDADDE1), rgb(0xA9AEB5)])
        ctx.fill(rounded(x, base - h, w, h, 4), with: .linearGradient(steel, startPoint: P(x, 0), endPoint: P(x + w, 0)))
        // dunkle Front zwischen Brühgruppe und Tropfschale
        ctx.fill(rounded(x + 4, base - 22, w - 8, 18, 2), with: vgrad([rgb(0x2C2E32), rgb(0x1E1F22)], base - 22, base - 4))
        // Tassen oben drauf
        for dx in [7.0, 14, 21] as [CGFloat] {
            ctx.fill(rounded(x + dx - 3, base - h - 4, 6, 4, 1.2), with: .color(.white))
        }
        // Brühgruppe + Siebträger mit Griff nach rechts
        ctx.fill(rounded(c.x - 5, base - 24, 10, 4, 1.5), with: .color(rgb(0xC9CDD2)))
        ctx.fill(rounded(c.x - 6, base - 20.5, 12, 3, 1.5), with: .color(rgb(0x9EA3AA)))
        var handle = Path(); handle.move(to: P(c.x + 5, base - 19)); handle.addLine(to: P(c.x + 15, base - 17))
        ctx.stroke(handle, with: .color(rgb(0x1C1C1E)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        // Tropfgitter
        ctx.fill(rounded(x + 3, base - 5, w - 6, 3, 1), with: .color(rgb(0xB5BAC0)))
        // Anzeige: grün bereit, bernstein beim Brühen
        let led = brewing ? rgb(0xFFB340).opacity(0.75 + 0.25 * sin(time * 6)) : rgb(0x30D158).opacity(0.75)
        ctx.fill(circle(P(x + w - 6, base - h + 7), 1.5), with: .color(led))
        ctx.fill(rounded(x + 5, base - h + 5.5, 12, 3, 1.2), with: .color(rgb(0x1E1F22)))
        if brewing {
            ctx.fill(rounded(x + 5.5, base - h + 6, 11 * CGFloat(0.5 + 0.5 * sin(time * 1.7)), 2, 1), with: .color(rgb(0xFFB340, 0.8)))
            // Tasse unterm Auslauf, dünner Kaffeestrahl
            let cup = CGRect(x: c.x - 4.5, y: base - 12, width: 9, height: 8)
            ctx.fill(Path(roundedRect: cup, cornerRadius: 2, style: .continuous), with: .color(.white))
            let flick = CGFloat(sin(time * 23)) * 0.15
            ctx.fill(Path(CGRect(x: c.x - 0.6 + flick, y: base - 17.5, width: 1.2, height: 5.5)), with: .color(rgb(0x6B4226)))
            coffeeSteam(&ctx, at: P(c.x - 10, base - 22), s: 0.9, seed: 3)
        }
    }

    /// Zwei kleine Dampfwölkchen über einer Tasse.
    func coffeeSteam(_ ctx: inout GraphicsContext, at p: CGPoint, s: CGFloat, seed: Double) {
        for i in 0..<2 {
            let k = (time * 0.5 + Double(i) * 0.5 + seed * 0.37).truncatingRemainder(dividingBy: 1)
            ctx.fill(circle(P(p.x + CGFloat(sin(k * 6 + seed)) * 2 * s, p.y - CGFloat(k) * 14 * s), 2 * s),
                     with: .color(.white.opacity(0.4 * (1 - k))))
        }
    }

    /// Plausch an der Maschine: stehen zwei da, schwebt über den gestaffelten Schildern eine Sprechblase mit Pünktchen,
    /// deren Spitze abwechselnd zum Sprechenden zeigt.
    func drawCoffeeChat(_ ctx: inout GraphicsContext, _ coffee: [Actor]) {
        let settled = coffee.filter { $0.pose == .standing }.sorted { $0.point.x < $1.point.x }
        guard settled.count == 2, hovered == nil || !settled.contains(where: { $0.id == hovered }) else { return }
        let speaker = settled[Int(time / 2.6) % 2]
        let left = settled[0], right = settled[1]
        let s = left.scale
        let p = P((left.point.x + right.point.x) / 2, left.point.y - 138 * s - 56)
        let w: CGFloat = 28, h: CGFloat = 16
        var bubble = Path(roundedRect: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), cornerRadius: h / 2, style: .continuous)
        let tipX = speaker.point.x < p.x ? p.x - 8 : p.x + 4
        bubble.addEllipse(in: CGRect(x: tipX, y: p.y + h / 2 - 1.5, width: 4.5, height: 4.5))
        ctx.fill(bubble, with: .color(dark ? rgb(0x3A3A3C, 0.95) : .white.opacity(0.96)))
        for i in 0..<3 {
            let lift = CGFloat(max(0, sin(time * 5 - Double(i) * 0.8))) * 1.5
            ctx.fill(circle(P(p.x - 7 + CGFloat(i) * 7, p.y - lift), 1.7), with: .color(ink.opacity(0.55)))
        }
    }
}
