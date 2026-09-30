// Zeichnet das App-Icon von AgentBar im macOS-26/27-Stil (Liquid Glass) mit CoreGraphics:
// Squircle mit ruhigem Blau-Verlauf, davor eine freundliche Memoji-Figur hinter einem gläsernen
// Laptop mit Funkeln auf dem Deckel – ein Agent bei der Arbeit.
// Ohne Xcode/actool: jede Größe wird vektoriell neu gerendert, dann iconutil → Resources/AppIcon.icns.
// Aufruf (im Repo-Wurzelordner):
//   swift tools/make-icon.swift
// oder, falls der Skript-Interpreter mit SDK 27 streikt:
//   swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk tools/make-icon.swift -o build/make-icon && build/make-icon
import AppKit

// MARK: Farben

func c(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func white(_ a: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
}

let bgTop = c(0x7CC4FF), bgBottom = c(0x1E6CF0)         // Himmelblau → Systemblau
let skin = c(0xF6D5B8), skinShade = c(0xE9BD98)
let hair = c(0x5B3A22), hairLight = c(0x7A5233)
let shirt = c(0xFFB340), shirtShade = c(0xFF9500)
let ink = c(0x2B2118)
let sparkleA = c(0x5AB4FF), sparkleB = c(0x1560E8)

// MARK: Formen

/// Squircle nach Apples macOS-Icon-Maske: gerade Flanken, Ecken als Viertel-Superellipse
/// („continuous corners“, Radius ≈ 22,5 % der Kachel, Übergangsbereich 1,53 × Radius).
func squircle(_ r: CGRect, radius: CGFloat = 185, n: CGFloat = 3.6) -> CGPath {
    let p = CGMutablePath()
    let e = min(radius * 1.528, r.width / 2)
    let corners: [(CGPoint, CGFloat, CGFloat)] = [          // Mittelpunkt des Eckfeldes + Richtung
        (CGPoint(x: r.maxX - e, y: r.maxY - e), 1, 1), (CGPoint(x: r.minX + e, y: r.maxY - e), -1, 1),
        (CGPoint(x: r.minX + e, y: r.minY + e), -1, -1), (CGPoint(x: r.maxX - e, y: r.minY + e), 1, -1),
    ]
    let steps = 90
    for (k, (o, sx, sy)) in corners.enumerated() {
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * .pi / 2
            // k gerade: von der Seite zur Oberkante laufen, k ungerade: umgekehrt
            let (ct, st) = k % 2 == 0 ? (cos(t), sin(t)) : (sin(t), cos(t))
            let pt = CGPoint(x: o.x + sx * e * pow(ct, 2 / n), y: o.y + sy * e * pow(st, 2 / n))
            k == 0 && i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
    }
    p.closeSubpath()
    return p
}

func rounded(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

/// Vierzackiger Funkelstern mit eingezogenen Flanken.
func sparkle(center: CGPoint, radius: CGFloat, pinch: CGFloat = 0.18) -> CGPath {
    let p = CGMutablePath()
    let pts = (0..<4).map { i -> CGPoint in
        let a = CGFloat(i) * .pi / 2 + .pi / 2
        return CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
    }
    p.move(to: pts[0])
    for i in 0..<4 {
        let next = pts[(i + 1) % 4]
        let ctrl = CGPoint(x: center.x + (pts[i].x - center.x + next.x - center.x) * pinch,
                           y: center.y + (pts[i].y - center.y + next.y - center.y) * pinch)
        p.addQuadCurve(to: next, control: ctrl)
    }
    p.closeSubpath()
    return p
}

// MARK: Helfer

extension CGContext {
    func fill(_ path: CGPath, _ color: CGColor) { addPath(path); setFillColor(color); fillPath() }

    func fill(_ path: CGPath, gradient g: CGGradient, from: CGPoint, to: CGPoint) {
        saveGState(); addPath(path); clip()
        drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    func clipped(_ path: CGPath, _ body: () -> Void) {
        saveGState(); addPath(path); clip(); body(); restoreGState()
    }

    /// Glas-Randglanzlicht: feine Kontur, oben hell, zur Mitte hin auslaufend, unten ein Hauch.
    func rimLight(_ path: CGPath, bounds r: CGRect, width: CGFloat, top: CGFloat = 0.95, bottom: CGFloat = 0.35) {
        saveGState()
        addPath(path); setLineWidth(width * 2); replacePathWithStrokedPath(); clip()
        addPath(path); clip()                           // nur die innere Hälfte der Kontur
        drawLinearGradient(gradient([white(top), white(0.0), white(0.0), white(bottom)], [0, 0.45, 0.7, 1]),
                           start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX, y: r.minY), options: [])
        restoreGState()
    }
}

// MARK: Zeichnung (Koordinaten im 1024er-Raster, y nach oben)

func drawIcon(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)   // Apple-Raster: 824er Kachel, 100 Rand
    let shape = squircle(tile)

    // Schatten der Kachel
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0x000000, 0.28))
    ctx.fill(shape, bgBottom)
    ctx.restoreGState()

    // Hintergrund: ruhiger Verlauf + weicher Lichtschein oben links
    ctx.fill(shape, gradient: gradient([bgTop, bgBottom]), from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    ctx.clipped(shape) {
        ctx.drawRadialGradient(gradient([white(0.38), white(0)]), startCenter: CGPoint(x: 330, y: 860), startRadius: 0,
                               endCenter: CGPoint(x: 330, y: 860), endRadius: 560, options: [])
        // sanfter Bodenschatten unter dem Tisch
        ctx.drawRadialGradient(gradient([c(0x0A3A9A, 0.35), c(0x0A3A9A, 0)]), startCenter: CGPoint(x: 512, y: 250),
                               startRadius: 0, endCenter: CGPoint(x: 512, y: 250), endRadius: 380, options: [])
    }

    let desk = CGRect(x: 196, y: 238, width: 632, height: 60)
    let lid = CGRect(x: 290, y: 280, width: 444, height: 292)

    // Figur: Oberkörper hinter dem Laptop
    ctx.clipped(squircle(tile)) {
        let body = rounded(CGRect(x: 318, y: 360, width: 388, height: 300), 150)
        ctx.fill(body, gradient: gradient([shirt, shirtShade]), from: CGPoint(x: 512, y: 660), to: CGPoint(x: 512, y: 440))
        // Hals
        ctx.fill(rounded(CGRect(x: 474, y: 590, width: 76, height: 80), 30), skinShade)
    }

    // Kopf
    let headC = CGPoint(x: 512, y: 718), headR: CGFloat = 132
    let head = CGPath(ellipseIn: CGRect(x: headC.x - headR, y: headC.y - headR, width: headR * 2, height: headR * 2), transform: nil)
    // Ohren
    for dx in [-1.0, 1.0] as [CGFloat] {
        let ear = CGPath(ellipseIn: CGRect(x: headC.x + dx * (headR - 8) - 26, y: headC.y - 40, width: 52, height: 68), transform: nil)
        ctx.fill(ear, skinShade)
    }
    ctx.fill(head, gradient: gradient([skin, skinShade]), from: CGPoint(x: 470, y: headC.y + headR), to: CGPoint(x: 540, y: headC.y - headR))

    // Haare: Kappe mit weicher Stirnwelle, etwas voluminöser als der Kopf
    let hairVolume = CGPath(ellipseIn: CGRect(x: headC.x - headR - 12, y: headC.y - headR + 4,
                                             width: (headR + 12) * 2, height: (headR + 12) * 2), transform: nil)
    ctx.clipped(hairVolume) {
        let h = CGMutablePath()
        h.move(to: CGPoint(x: headC.x - headR - 30, y: headC.y + 10))
        h.addCurve(to: CGPoint(x: headC.x + 10, y: headC.y + 62),
                   control1: CGPoint(x: headC.x - 110, y: headC.y + 90), control2: CGPoint(x: headC.x - 50, y: headC.y + 40))
        h.addCurve(to: CGPoint(x: headC.x + headR + 30, y: headC.y + 20),
                   control1: CGPoint(x: headC.x + 60, y: headC.y + 80), control2: CGPoint(x: headC.x + 110, y: headC.y + 90))
        h.addLine(to: CGPoint(x: headC.x + headR + 30, y: headC.y + headR + 40))
        h.addLine(to: CGPoint(x: headC.x - headR - 30, y: headC.y + headR + 40))
        h.closeSubpath()
        ctx.fill(h, gradient: gradient([hairLight, hair]), from: CGPoint(x: 460, y: 850), to: CGPoint(x: 540, y: 760))
    }

    // Gesicht
    for dx in [-1.0, 1.0] as [CGFloat] {
        let eye = CGRect(x: headC.x + dx * 52 - 17, y: headC.y - 26, width: 34, height: 46)
        ctx.fill(CGPath(ellipseIn: eye, transform: nil), ink)
        ctx.fill(CGPath(ellipseIn: CGRect(x: eye.minX + 9, y: eye.maxY - 19, width: 12, height: 12), transform: nil), white(0.95))
        // Wangen
        ctx.fill(CGPath(ellipseIn: CGRect(x: headC.x + dx * 82 - 22, y: headC.y - 62, width: 44, height: 26), transform: nil),
                 c(0xFF8A7A, 0.35))
    }
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: headC.x - 34, y: headC.y - 58))
    smile.addQuadCurve(to: CGPoint(x: headC.x + 34, y: headC.y - 58), control: CGPoint(x: headC.x, y: headC.y - 92))
    ctx.saveGState()
    ctx.addPath(smile); ctx.setStrokeColor(ink); ctx.setLineWidth(12); ctx.setLineCap(.round); ctx.strokePath()
    ctx.restoreGState()

    // Tisch: weiße Platte mit Kante
    let deskPath = rounded(desk, 30)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: c(0x06307F, 0.35))
    ctx.fill(deskPath, white(1))
    ctx.restoreGState()
    ctx.fill(deskPath, gradient: gradient([white(1), c(0xE3EAF5)]), from: CGPoint(x: 512, y: desk.maxY), to: CGPoint(x: 512, y: desk.minY))

    // Laptop-Deckel: Milchglas-Scheibe mit Randglanzlicht
    let lidPath = rounded(lid, 44)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: c(0x06307F, 0.30))
    ctx.fill(lidPath, white(0.9))
    ctx.restoreGState()
    ctx.fill(lidPath, gradient: gradient([white(0.97), c(0xE6EEFA, 0.92)]), from: CGPoint(x: 512, y: lid.maxY), to: CGPoint(x: 512, y: lid.minY))
    ctx.clipped(lidPath) {                                   // diagonaler Glasreflex
        let sheen = CGMutablePath()
        sheen.move(to: CGPoint(x: lid.minX, y: lid.maxY))
        sheen.addLine(to: CGPoint(x: lid.minX + 230, y: lid.maxY))
        sheen.addLine(to: CGPoint(x: lid.minX + 60, y: lid.minY))
        sheen.addLine(to: CGPoint(x: lid.minX, y: lid.minY))
        sheen.closeSubpath()
        ctx.fill(sheen, white(0.35))
    }
    ctx.rimLight(lidPath, bounds: lid, width: 5, top: 1.0, bottom: 0.6)

    // Funkeln auf dem Deckel
    let sc = CGPoint(x: lid.midX, y: lid.midY + 4)
    let big = sparkle(center: sc, radius: 92)
    ctx.fill(big, gradient: gradient([sparkleA, sparkleB]), from: CGPoint(x: sc.x - 60, y: sc.y + 92), to: CGPoint(x: sc.x + 60, y: sc.y - 92))
    let small = sparkle(center: CGPoint(x: sc.x + 98, y: sc.y + 70), radius: 34)
    ctx.fill(small, gradient: gradient([sparkleA, sparkleB]), from: CGPoint(x: sc.x + 98, y: sc.y + 104), to: CGPoint(x: sc.x + 98, y: sc.y + 36))

    // Kachel: Glasrand-Glanzlicht
    ctx.rimLight(shape, bounds: tile, width: 6, top: 0.75, bottom: 0.25)
}

// MARK: Ausgabe

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = g.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    drawIcon(ctx)
    g.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try! fm.createDirectory(at: URL(fileURLWithPath: "Resources"), withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: "Resources/icon-1024.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { fatalError("iconutil fehlgeschlagen") }
print("Geschrieben: Resources/AppIcon.icns + Resources/icon-1024.png")
