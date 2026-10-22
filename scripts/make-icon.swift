#!/usr/bin/env swift
// Renders the landing-page logo (the neon pink waveform) as the macOS app
// icon: VisualiserMac/Resources/AppIcon.icns. Run from the repo root:
//   swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
let output = root.appendingPathComponent("VisualiserMac/Resources/AppIcon.icns")

// The logo path from site/index.html, in its 32×32 viewBox.
let wave: [CGPoint] = [(3, 16), (7, 16), (9, 8), (13, 24), (17, 12), (21, 20), (25, 16), (29, 16)]
    .map { CGPoint(x: $0.0, y: $0.1) }

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024

    // Apple's icon grid: an 824pt rounded square centred on a 1024 canvas.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

    // No shadow of our own. macOS draws one around every app icon, and a
    // shadow baked into the artwork is a second one: the tile ends up with
    // a grey halo around it that reads as a pale rim, and the artwork's
    // bounds grow past the tile, so macOS shrinks the whole thing to fit
    // them. Apple's own icons leave it to the system.
    ctx.saveGState()
    ctx.addPath(shape); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.13, green: 0.03, blue: 0.22, alpha: 1).cgColor,
        NSColor(red: 0.024, green: 0.004, blue: 0.05, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: 512 * s, y: 560 * s), startRadius: 0,
                           endCenter: CGPoint(x: 512 * s, y: 512 * s), endRadius: 620 * s, options: .drawsAfterEndLocation)

    // Wave: 32-unit viewBox mapped onto the tile, y flipped (SVG is y-down).
    let unit = 824 * s / 32 * 0.92
    let origin = CGPoint(x: 512 * s - 16 * unit, y: 512 * s + 16 * unit)
    let path = CGMutablePath()
    for (i, p) in wave.enumerated() {
        let q = CGPoint(x: origin.x + p.x * unit, y: origin.y - p.y * unit)
        i == 0 ? path.move(to: q) : path.addLine(to: q)
    }
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let pink = NSColor(red: 1, green: 0.17, blue: 0.84, alpha: 1)
    for (width, blur, alpha) in [(2.4, 60.0, 0.9), (2.4, 22.0, 1.0)] {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: blur * s, color: pink.withAlphaComponent(alpha).cgColor)
        ctx.addPath(path); ctx.setLineWidth(width * unit); ctx.setStrokeColor(pink.cgColor); ctx.strokePath()
        ctx.restoreGState()
    }
    // Hot core so it reads as neon.
    ctx.addPath(path); ctx.setLineWidth(0.8 * unit)
    ctx.setStrokeColor(NSColor(red: 1, green: 0.78, blue: 0.96, alpha: 1).cgColor); ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
