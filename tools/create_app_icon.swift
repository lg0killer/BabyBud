// Original vector artwork rendered into Xcode's required app-icon sizes.
import AppKit
import Foundation
import ImageIO

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int, filename: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let teal = NSColor(srgbRed: 0.055, green: 0.39, blue: 0.40, alpha: 1)
    teal.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
    NSColor(srgbRed: 1, green: 0.80, blue: 0.46, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 632, y: 651, width: 190, height: 190)).fill()
    teal.setFill()
    NSBezierPath(ovalIn: NSRect(x: 685, y: 700, width: 170, height: 170)).fill()
    NSColor(srgbRed: 1, green: 0.97, blue: 0.90, alpha: 1).setFill()
    let heart = NSBezierPath()
    heart.move(to: NSPoint(x: 512, y: 210))
    heart.curve(to: NSPoint(x: 226, y: 520), controlPoint1: NSPoint(x: 420, y: 281), controlPoint2: NSPoint(x: 226, y: 388))
    heart.curve(to: NSPoint(x: 512, y: 616), controlPoint1: NSPoint(x: 226, y: 697), controlPoint2: NSPoint(x: 426, y: 724))
    heart.curve(to: NSPoint(x: 798, y: 520), controlPoint1: NSPoint(x: 598, y: 724), controlPoint2: NSPoint(x: 798, y: 697))
    heart.curve(to: NSPoint(x: 512, y: 210), controlPoint1: NSPoint(x: 798, y: 388), controlPoint2: NSPoint(x: 604, y: 281))
    heart.close()
    heart.fill()
    NSGraphicsContext.restoreGraphicsState()
    let opaque = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    opaque.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
    let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(filename) as CFURL,
        "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, opaque.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    // Keep generated icons free of EXIF and text metadata before committing them.
    let url = output.appendingPathComponent(filename)
    let bytes = [UInt8](try Data(contentsOf: url))
    var clean = Array(bytes.prefix(8))
    var offset = 8
    while offset + 12 <= bytes.count {
        let length = bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        let end = offset + 12 + length
        guard end <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
        let kind = String(bytes: bytes[offset + 4..<offset + 8], encoding: .ascii) ?? ""
        if !["eXIf", "tEXt", "iTXt", "zTXt"].contains(kind) {
            clean.append(contentsOf: bytes[offset..<end])
        }
        offset = end
    }
    try Data(clean).write(to: url)
}

var images: [[String: Any]] = [["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon-1024.png"]]
try render(size: 1024, filename: "AppIcon-1024.png")
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "AppIcon-mac-\(size)@\(scale)x.png"
        try render(size: size * scale, filename: filename)
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
