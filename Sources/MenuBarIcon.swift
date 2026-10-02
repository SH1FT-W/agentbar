import AppKit

/// Menüleisten-Symbol (Vorlagenbild, färbt sich mit der Menüleiste): Kopf hinter einem Laptop wie im App-Icon.
/// Ruhe = Funkeln auf dem Bildschirm, arbeitet = zusätzlich Punkt oben rechts, braucht dich = „!“ statt Funkeln.
enum MenuBarIcon {
    static func make(waiting: Bool, working: Bool) -> NSImage {
        let badge = working && !waiting
        let size = NSSize(width: badge ? 21 : 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill(); NSColor.black.setStroke()
            NSBezierPath(ovalIn: NSRect(x: 5.9, y: 10.8, width: 6.2, height: 6.2)).fill()             // Kopf
            clear(NSBezierPath(roundedRect: NSRect(x: 1.2, y: 1.8, width: 15.6, height: 10.4), xRadius: 2.6, yRadius: 2.6))
            let lid = NSBezierPath(roundedRect: NSRect(x: 2.7, y: 3.3, width: 12.6, height: 7.6), xRadius: 1.6, yRadius: 1.6)
            lid.lineWidth = 1.5; lid.stroke()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0.4, width: 18, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()   // Unterteil
            if waiting {
                NSBezierPath(roundedRect: NSRect(x: 8.25, y: 6.2, width: 1.5, height: 3.4), xRadius: 0.75, yRadius: 0.75).fill()
                NSBezierPath(ovalIn: NSRect(x: 8.25, y: 4.4, width: 1.5, height: 1.5)).fill()
            } else {
                sparkle(CGPoint(x: 9, y: 7.1), 2.5).fill()
            }
            if badge {
                let dot = NSRect(x: size.width - 6.5, y: size.height - 6.5, width: 6.5, height: 6.5)
                clear(NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)))
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "AgentBar"
        return img
    }

    private static func clear(_ path: NSBezierPath) {
        NSGraphicsContext.current?.compositingOperation = .clear
        path.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    /// Vierzackiger Stern mit nach innen gewölbten Kanten (wie im App-Icon).
    private static func sparkle(_ c: CGPoint, _ r: CGFloat) -> NSBezierPath {
        let p = NSBezierPath(), k = r * 0.28
        p.move(to: CGPoint(x: c.x, y: c.y + r))
        p.curve(to: CGPoint(x: c.x + r, y: c.y), controlPoint1: CGPoint(x: c.x + k * 0.3, y: c.y + k), controlPoint2: CGPoint(x: c.x + k, y: c.y + k * 0.3))
        p.curve(to: CGPoint(x: c.x, y: c.y - r), controlPoint1: CGPoint(x: c.x + k, y: c.y - k * 0.3), controlPoint2: CGPoint(x: c.x + k * 0.3, y: c.y - k))
        p.curve(to: CGPoint(x: c.x - r, y: c.y), controlPoint1: CGPoint(x: c.x - k * 0.3, y: c.y - k), controlPoint2: CGPoint(x: c.x - k, y: c.y - k * 0.3))
        p.curve(to: CGPoint(x: c.x, y: c.y + r), controlPoint1: CGPoint(x: c.x - k, y: c.y + k * 0.3), controlPoint2: CGPoint(x: c.x - k * 0.3, y: c.y + k))
        p.close()
        return p
    }
}
