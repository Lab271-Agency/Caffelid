import AppKit

guard CommandLine.arguments.count == 2 else { exit(64) }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
            pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let inset = CGFloat(pixels) * 0.055
        let tile = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                                xRadius: CGFloat(pixels) * 0.22, yRadius: CGFloat(pixels) * 0.22)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.39, green: 0.25, blue: 0.19, alpha: 1),
                                  ending: NSColor(srgbRed: 0.18, green: 0.11, blue: 0.09, alpha: 1))!
        gradient.draw(in: tile, angle: -90)
        // Original mug artwork. System symbols are reserved for in-app UI,
        // rather than being incorporated into the app icon or brand.
        let unit = CGFloat(pixels)
        let cream = NSColor(srgbRed: 1, green: 0.93, blue: 0.79, alpha: 1)
        cream.setStroke()
        let handle = NSBezierPath(ovalIn: NSRect(x: unit * 0.215, y: unit * 0.315,
                                                width: unit * 0.24, height: unit * 0.25))
        handle.lineWidth = unit * 0.057
        handle.stroke()
        cream.setFill()
        let body = NSBezierPath()
        body.move(to: NSPoint(x: unit * 0.345, y: unit * 0.59))
        body.line(to: NSPoint(x: unit * 0.38, y: unit * 0.30))
        body.curve(to: NSPoint(x: unit * 0.73, y: unit * 0.30),
                   controlPoint1: NSPoint(x: unit * 0.40, y: unit * 0.20),
                   controlPoint2: NSPoint(x: unit * 0.70, y: unit * 0.20))
        body.line(to: NSPoint(x: unit * 0.765, y: unit * 0.59))
        body.close()
        body.fill()
        NSBezierPath(ovalIn: NSRect(x: unit * 0.345, y: unit * 0.52,
                                    width: unit * 0.42, height: unit * 0.145)).fill()
        NSColor(srgbRed: 0.24, green: 0.13, blue: 0.085, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: unit * 0.382, y: unit * 0.545,
                                    width: unit * 0.346, height: unit * 0.087)).fill()
        cream.setStroke()
        let steam = NSBezierPath()
        steam.move(to: NSPoint(x: unit * 0.55, y: unit * 0.715))
        steam.curve(to: NSPoint(x: unit * 0.57, y: unit * 0.835),
                    controlPoint1: NSPoint(x: unit * 0.64, y: unit * 0.765),
                    controlPoint2: NSPoint(x: unit * 0.49, y: unit * 0.79))
        steam.lineWidth = unit * 0.029
        steam.lineCapStyle = .round
        steam.stroke()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
