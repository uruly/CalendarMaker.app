import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

func rounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func line(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    color.setStroke()
    path.stroke()
}

let navy = NSColor(srgbRed: 0.10, green: 0.16, blue: 0.22, alpha: 1)
let coral = NSColor(srgbRed: 0.94, green: 0.42, blue: 0.34, alpha: 1)
let cream = NSColor(srgbRed: 1, green: 0.987, blue: 0.954, alpha: 1)
let muted = NSColor(srgbRed: 0.77, green: 0.81, blue: 0.82, alpha: 1)

rounded(NSRect(x: 28, y: 28, width: 968, height: 968), radius: 220, color: navy)
rounded(NSRect(x: 189, y: 151, width: 646, height: 722), radius: 55, color: cream)
rounded(NSRect(x: 189, y: 694, width: 646, height: 179), radius: 55, color: coral)
coral.setFill()
NSBezierPath(rect: NSRect(x: 189, y: 694, width: 646, height: 94)).fill()

for x in [341.0, 683.0] {
    rounded(NSRect(x: x - 24, y: 799, width: 48, height: 112), radius: 24, color: navy)
}

for x in [403.0, 622.0] {
    line(from: NSPoint(x: x, y: 231), to: NSPoint(x: x, y: 617), color: muted, width: 7)
}
for y in [348.0, 493.0] {
    line(from: NSPoint(x: 255, y: y), to: NSPoint(x: 768, y: y), color: muted, width: 7)
}

rounded(NSRect(x: 426, y: 375, width: 173, height: 95), radius: 27, color: coral)
let number = NSAttributedString(string: "15", attributes: [
    .font: NSFont.systemFont(ofSize: 72, weight: .bold),
    .foregroundColor: cream
])
let numberSize = number.size()
number.draw(at: NSPoint(x: 512 - numberSize.width / 2,
                        y: 422 - numberSize.height / 2))

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("CalendarMaker-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
let master = iconset.appendingPathComponent("master.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: master)

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let destination = iconset.appendingPathComponent(filename)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        task.arguments = ["-z", "\(points * scale)", "\(points * scale)", master.path,
                          "--out", destination.path]
        task.standardOutput = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { fatalError("sips failed: \(filename)") }
    }
}
try FileManager.default.removeItem(at: master)

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
