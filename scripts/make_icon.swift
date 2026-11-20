// Generates AppIcon.iconset for AI FileRenamer.
//
// Usage:
//   swift scripts/make_icon.swift /tmp/iconbuild
//   iconutil -c icns /tmp/iconbuild/AppIcon.iconset -o Assets/AppIcon.icns
//
// Design: dark slate rounded square, white paperclip (same glyph as the
// menu bar item). Change the two colors below to re-skin; everything
// else (sizes, corner radius, glyph scale) is standard macOS icon geometry.

import AppKit
import Foundation

let bgTop = NSColor(calibratedRed: 0.24, green: 0.31, blue: 0.44, alpha: 1)
let bgBottom = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background rounded square (~standard macOS icon mask geometry).
    let inset = size * 0.06
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = rect.width * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [bgTop, bgBottom])!.draw(in: path, angle: -90)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    path.lineWidth = max(1, size / 128)
    path.stroke()

    // White paperclip glyph, centered, ~52% of the square.
    if let sym = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil),
       let cfg = sym.withSymbolConfiguration(
            .init(pointSize: rect.height * 0.52, weight: .regular)) {
        let img = cfg
        let tinted = NSImage(size: img.size)
        tinted.lockFocus()
        NSColor.white.set()
        img.draw(in: NSRect(origin: .zero, size: img.size))
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: rect.midX - tinted.size.width / 2,
                               y: rect.midY - tinted.size.height / 2,
                               width: tinted.size.width,
                               height: tinted.size.height))
    }

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

do {
    let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/iconbuild"
    let iconset = outDir + "/AppIcon.iconset"
    if FileManager.default.fileExists(atPath: outDir) {
        try FileManager.default.removeItem(atPath: outDir)
    }
    try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

    let specs: [(String, CGFloat)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    for (name, px) in specs {
        guard let data = drawIcon(size: px).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "make_icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "render failed for \(name)"])
        }
        try data.write(to: URL(fileURLWithPath: iconset + "/" + name))
    }
    print("iconset written to \(iconset)")
} catch {
    FileHandle.standardError.write("make_icon failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
