import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, size) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let rect = NSRect(x: 60, y: 60, width: 904, height: 904)
    let path = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(red: 0.12, green: 0.19, blue: 0.20, alpha: 1), ending: NSColor(red: 0.035, green: 0.055, blue: 0.075, alpha: 1))!.draw(in: path, angle: -70)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    path.lineWidth = 3
    path.stroke()
    let heights: [CGFloat] = [120, 240, 390, 540, 340, 200, 110]
    for (i, height) in heights.enumerated() {
        let bar = NSBezierPath(roundedRect: NSRect(x: 234 + CGFloat(i) * 82, y: 512 - height / 2, width: 44, height: height), xRadius: 22, yRadius: 22)
        (i == 5 ? NSColor(red: 1, green: 0.50, blue: 0.42, alpha: 1) : NSColor(red: 0.41, green: 0.94, blue: 0.76, alpha: 1)).setFill()
        bar.fill()
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
}
