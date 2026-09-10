import AppKit

// Draw both resolutions so Finder keeps the background sharp on Retina displays.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 640, height: 400)
var representations: [NSBitmapImageRep] = []

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let bounds = NSRect(origin: .zero, size: size)
    NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.98, blue: 1, alpha: 1),
        ending: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1))!
        .draw(in: bounds, angle: 270)

    func text(_ string: String, top: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (string as NSString).draw(in: NSRect(x: 24, y: size.height - top - 38,
            width: size.width - 48, height: 38), withAttributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ])
    }
    let navy = NSColor(srgbRed: 0.10, green: 0.16, blue: 0.25, alpha: 1)
    let grey = NSColor(srgbRed: 0.37, green: 0.41, blue: 0.48, alpha: 1)
    text("MacOS Ultrabright", top: 38, font: .systemFont(ofSize: 29, weight: .semibold), color: navy)
    text("Drag the app to Applications.", top: 85, font: .systemFont(ofSize: 16), color: grey)

    // Icon centres are (164, 220) and (476, 220) in Finder's top-down coordinates.
    let arrow = NSBezierPath()
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 282, y: 180))
    arrow.line(to: NSPoint(x: 357, y: 180))
    arrow.move(to: NSPoint(x: 345, y: 193))
    arrow.line(to: NSPoint(x: 358, y: 180))
    arrow.line(to: NSPoint(x: 345, y: 167))
    NSColor(srgbRed: 0.90, green: 0.59, blue: 0.08, alpha: 1).setStroke()
    arrow.stroke()

    text("Then open MacOS Ultrabright from Applications.", top: 340,
        font: .systemFont(ofSize: 12), color: grey)
    NSGraphicsContext.restoreGraphicsState()
    representations.append(bitmap)
}

let data = NSBitmapImageRep.representationOfImageReps(in: representations, using: .tiff,
    properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue])!
try data.write(to: destination)
