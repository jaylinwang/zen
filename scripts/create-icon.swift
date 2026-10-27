import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let background = NSBezierPath(roundedRect: rect.insetBy(dx: Double(pixels)*0.035, dy: Double(pixels)*0.035), xRadius: Double(pixels)*0.22, yRadius: Double(pixels)*0.22)
        NSColor(red: 0.965, green: 0.953, blue: 0.923, alpha: 1).setFill(); background.fill()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: Double(pixels)*0.5, y: Double(pixels)*0.52), radius: Double(pixels)*0.28, startAngle: 98, endAngle: 442)
        arc.lineWidth = Double(pixels)*0.025; arc.lineCapStyle = .round
        NSColor(red: 0.36, green: 0.43, blue: 0.33, alpha: 0.8).setStroke(); arc.stroke()
        let text = "禅" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Songti SC", size: Double(pixels)*0.34) ?? NSFont.systemFont(ofSize: Double(pixels)*0.34), .foregroundColor: NSColor(red: 0.2, green: 0.24, blue: 0.22, alpha: 1)]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (Double(pixels)-textSize.width)/2, y: (Double(pixels)-textSize.height)/2), withAttributes: attributes)
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
