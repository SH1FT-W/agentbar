import AppKit

/// Menüleisten-Symbol (Vorlagenbild, färbt sich mit der Menüleiste): Clawd als Silhouette.
/// Ruhe = Augen zu, arbeitet = Augen offen, braucht dich = winkt mit dem rechten Arm.
enum MenuBarIcon {
    static func make(waiting: Bool, working: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let t = NSAffineTransform(); t.translateX(by: 0, yBy: 0.5); t.concat()   // optische Mitte wie die Nachbarsymbole
            rr(2.9, 4.6, 12.2, 9.4, 1.3).fill()                                          // Körper
            for x: CGFloat in [3.7, 5.8, 11.0, 13.1] { rr(x, 2.2, 1.2, 3.0, 0.45).fill() } // Beine
            rr(0.8, 8.0, 2.8, 2.6, 0.8).fill()                                           // linker Arm
            if waiting { rr(14.6, 9.0, 2.6, 7.4, 0.9).fill() }                           // winkt
            else { rr(14.4, 8.0, 2.8, 2.6, 0.8).fill() }
            if working || waiting {
                clear(rr(5.7, 8.6, 1.5, 3.6, 0.6)); clear(rr(10.8, 8.6, 1.5, 3.6, 0.6))  // Augen offen
            } else {
                clear(rr(5.0, 9.8, 2.8, 1.25, 0.6)); clear(rr(10.2, 9.8, 2.8, 1.25, 0.6)) // Augen zu
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "AgentBar"
        return img
    }

    private static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }

    private static func clear(_ path: NSBezierPath) {
        NSGraphicsContext.current?.compositingOperation = .clear
        path.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
