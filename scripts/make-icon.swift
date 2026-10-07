import AppKit
import Foundation

/// ShotPanel's icon: an original blue folder with a captured window on the
/// front. The window (bezel, title bar, page) stands in for a screenshot.
/// This is not Apple's Pictures folder artwork.

let size = 1024
let canvas = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let scale = CGFloat(size) / 1024
    func r(_ value: CGFloat) -> CGFloat { value * scale }
    func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: r(x), y: r(y), width: r(width), height: r(height))
    }
    func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    let back = NSBezierPath(roundedRect: box(156, 196, 712, 548), xRadius: r(72), yRadius: r(72))
    let tab = NSBezierPath(roundedRect: box(156, 692, 308, 156), xRadius: r(46), yRadius: r(46))
    let front = NSBezierPath(roundedRect: box(128, 156, 768, 528), xRadius: r(68), yRadius: r(68))

    let backColor = color(0.13, 0.38, 0.78)
    let tabColor = color(0.20, 0.48, 0.88)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.04, 0.10, 0.24, 0.38)
    shadow.shadowOffset = NSSize(width: 0, height: r(-26))
    shadow.shadowBlurRadius = r(32)
    shadow.set()
    backColor.setFill()
    back.fill()
    tabColor.setFill()
    tab.fill()
    color(0.22, 0.52, 0.92).setFill()
    front.fill()
    NSGraphicsContext.restoreGraphicsState()

    backColor.setFill()
    back.fill()
    tabColor.setFill()
    tab.fill()

    NSGraphicsContext.saveGraphicsState()
    tab.addClip()
    NSGradient(colors: [color(0.47, 0.74, 0.98), color(0.20, 0.48, 0.88)])?
        .draw(in: box(156, 748, 308, 100), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        color(0.16, 0.44, 0.86),
        color(0.30, 0.62, 0.96),
        color(0.50, 0.78, 1.00),
    ])?.draw(in: front, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    front.addClip()
    color(1, 1, 1, 0.22).setStroke()
    let rim = NSBezierPath(roundedRect: box(140, 168, 744, 504), xRadius: r(58), yRadius: r(58))
    rim.lineWidth = r(8)
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let bezel = NSBezierPath(roundedRect: box(236, 228, 552, 376), xRadius: r(36), yRadius: r(36))
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = color(0.05, 0.16, 0.36, 0.40)
    cardShadow.shadowOffset = NSSize(width: 0, height: r(-12))
    cardShadow.shadowBlurRadius = r(18)
    cardShadow.set()
    color(0.10, 0.13, 0.18).setFill()
    bezel.fill()
    NSGraphicsContext.restoreGraphicsState()

    color(0.11, 0.13, 0.17).setFill()
    bezel.fill()

    NSGraphicsContext.saveGraphicsState()
    bezel.addClip()
    color(0.96, 0.97, 0.98).setFill()
    NSBezierPath(rect: box(256, 246, 512, 340)).fill()

    color(0.90, 0.92, 0.94).setFill()
    NSBezierPath(rect: box(256, 516, 512, 70)).fill()

    let dot = r(18)
    let dotY = r(551)
    for (index, dotColor) in [
        color(0.96, 0.36, 0.33),
        color(0.98, 0.74, 0.22),
        color(0.34, 0.78, 0.38),
    ].enumerated() {
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: r(286) + CGFloat(index) * r(36),
            y: dotY,
            width: dot,
            height: dot
        )).fill()
    }

    color(0.24, 0.52, 0.92).setFill()
    NSBezierPath(roundedRect: box(280, 392, 464, 96), xRadius: r(16), yRadius: r(16)).fill()
    color(1, 1, 1, 0.92).setFill()
    NSBezierPath(roundedRect: box(302, 432, 210, 16), xRadius: r(8), yRadius: r(8)).fill()
    NSBezierPath(roundedRect: box(302, 406, 140, 14), xRadius: r(7), yRadius: r(7)).fill()

    color(0.80, 0.84, 0.88).setFill()
    NSBezierPath(roundedRect: box(280, 332, 300, 18), xRadius: r(9), yRadius: r(9)).fill()
    NSBezierPath(roundedRect: box(280, 292, 200, 18), xRadius: r(9), yRadius: r(9)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Capture corners on the folder, around the window, so it reads as a screenshot.
    let marks = NSBezierPath()
    marks.lineWidth = r(20)
    marks.lineCapStyle = .butt
    marks.lineJoinStyle = .miter
    let arm = r(52)
    let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (212, 628, 1, -1),
        (812, 628, -1, -1),
        (212, 204, 1, 1),
        (812, 204, -1, 1),
    ]
    for (x, y, dx, dy) in corners {
        marks.move(to: NSPoint(x: r(x) + dx * arm, y: r(y)))
        marks.line(to: NSPoint(x: r(x), y: r(y)))
        marks.line(to: NSPoint(x: r(x), y: r(y) + dy * arm))
    }
    color(0.97, 0.98, 1, 0.96).setStroke()
    marks.stroke()

    return true
}

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not draw the icon\n", stderr)
    exit(1)
}

let destination = CommandLine.arguments.dropFirst().first ?? "icon.png"
do {
    try png.write(to: URL(fileURLWithPath: destination))
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
