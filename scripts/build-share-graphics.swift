#!/usr/bin/env swift
// Renders per-vibscape share graphics for the OG image metadata on
// `site/share/<slug>.html`. Takes the existing `site/media/modes/<slug>.jpg`
// and lays it down on a 1200x630 canvas with the Vibresia mark top-left and
// "Made with ❤ by Minith Labs" bottom-right.
//
// Run from the repo root:
//   swift scripts/build-share-graphics.swift
//
// Idempotent: existing files are overwritten. Re-run any time a vibscape
// image changes, or after adding a new vibscape to the lookup table below.
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let modesDir = root.appendingPathComponent("site/media/modes")
let outDir = root.appendingPathComponent("site/share")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// One entry per built-in vibscape. Slug is what `VibscapeEntry.id.slug`
// produces on the app side, so the share URL `vibresia.com/share/<slug>`
// round-trips cleanly.
struct Spec {
    let slug: String
    let title: String
    let author: String
    let modeJPG: String   // site/media/modes/<modeJPG>
    let shotJPG: String   // site/share/<shotJPG> - the output
}

let specs: [Spec] = [
    Spec(slug: "ribbons",     title: "Ribbons",        author: "Minith Labs", modeJPG: "ribbons.jpg",    shotJPG: "ribbons.jpg"),
    Spec(slug: "vortex",      title: "Vortex",         author: "Minith Labs", modeJPG: "vortex.jpg",     shotJPG: "vortex.jpg"),
    Spec(slug: "silk",        title: "Silk Flight",    author: "Minith Labs", modeJPG: "silk.jpg",       shotJPG: "silk.jpg"),
    Spec(slug: "flux",        title: "Flux",           author: "Minith Labs", modeJPG: "flux.jpg",       shotJPG: "flux.jpg"),
    Spec(slug: "spectrum",    title: "Spectrum",       author: "Minith Labs", modeJPG: "spectrum.jpg",   shotJPG: "spectrum.jpg"),
    Spec(slug: "tunnel",      title: "Tunnel",         author: "Minith Labs", modeJPG: "tunnel.jpg",     shotJPG: "tunnel.jpg"),
    Spec(slug: "liquid",      title: "Liquid",         author: "Minith Labs", modeJPG: "liquid.jpg",     shotJPG: "liquid.jpg"),
    Spec(slug: "kaleidoscope", title: "Kaleidoscope", author: "Minith Labs", modeJPG: "kaleidoscope.jpg", shotJPG: "kaleidoscope.jpg"),
    Spec(slug: "waveform",    title: "Neon Wave",      author: "Minith Labs", modeJPG: "waveform.jpg",   shotJPG: "waveform.jpg"),
    Spec(slug: "machine",     title: "Machine",        author: "Minith Labs", modeJPG: "machine.jpg",    shotJPG: "machine.jpg"),
    Spec(slug: "warp",        title: "Warp",           author: "Minith Labs", modeJPG: "warp.jpg",       shotJPG: "warp.jpg"),
    Spec(slug: "particles",   title: "Constellation",  author: "Minith Labs", modeJPG: "particles.jpg",  shotJPG: "particles.jpg"),
    Spec(slug: "nyan",        title: "Nyan Cat",       author: "Minith Labs", modeJPG: "nyan.jpg",       shotJPG: "nyan.jpg"),
    Spec(slug: "hamster",     title: "Hamster Dance",  author: "Minith Labs", modeJPG: "hamster.jpg",    shotJPG: "hamster.jpg"),
    Spec(slug: "badger",      title: "Badger Badger",  author: "Minith Labs", modeJPG: "badger.jpg",     shotJPG: "badger.jpg"),
    Spec(slug: "llama",       title: "Whooping Llama", author: "Minith Labs", modeJPG: "llama.jpg",      shotJPG: "llama.jpg"),
    Spec(slug: "danceFloor",  title: "Dance Floor",    author: "Minith Labs", modeJPG: "danceFloor.jpg", shotJPG: "danceFloor.jpg"),
    Spec(slug: "band",        title: "The Band",       author: "Minith Labs", modeJPG: "band.jpg",       shotJPG: "band.jpg"),
]

// 1200x630 is the canvas Twitter/Slack/iMessage pick up from `og:image`.
// The mode JPGs are 640x360 — same 16:9, centred on the larger canvas at
// native pixels and the rest of the space goes to the chrome (logo, title,
// credit).
let canvasW = 1200
let canvasH = 630

// Path that mirrors the inline SVG on the landing page (32-unit viewBox).
let wave: [CGPoint] = [(3, 16), (7, 16), (9, 8), (13, 24), (17, 12), (21, 20), (25, 16), (29, 16)]
    .map { CGPoint(x: $0.0, y: $0.1) }

// Background gradient — same deep purple as the landing page: a dark navy at
// the top rolling into near-black so the mark glows against it.
let bgTop = NSColor(red: 0.024, green: 0.004, blue: 0.05, alpha: 1)
let bgBottom = NSColor(red: 0.06, green: 0.03, blue: 0.11, alpha: 1)

// Same magenta as the app's accent (`#ff2bd6`).
let magenta = NSColor(red: 1, green: 0.17, blue: 0.84, alpha: 1)
let magentaSoft = NSColor(red: 1, green: 0.78, blue: 0.96, alpha: 1)
let gold = NSColor(red: 1, green: 0.76, blue: 0.35, alpha: 1)
let text = NSColor.white
let muted = NSColor(white: 0.75, alpha: 1)

func render(_ spec: Spec) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasW, pixelsHigh: canvasH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        return Data()
    }
    let w = CGFloat(canvasW), h = CGFloat(canvasH)

    // The bitmap is bottom-up: y=0 is the canvas bottom, y=canvasH the
    // canvas top. Names like "topY" make the direction explicit.

    // 1. Background gradient — deep navy at the top, near-black at the
    //    bottom, so the magenta mark glows against it.
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        bg, start: .zero, end: CGPoint(x: 0, y: h),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // 2. Vibscape frame in the middle of the canvas, 16:9. Vertical
    //    extents in flipped coords: image "bottom" is `imgBase`,
    //    image "top" is `imgBase + imgH`. A dark frame on either side
    //    keeps the eye on the picture.
    let modeURL = modesDir.appendingPathComponent(spec.modeJPG)
    guard let modeImage = NSImage(contentsOf: modeURL) else {
        NSGraphicsContext.current = nil
        return Data()
    }
    let imgW: CGFloat = 720, imgH: CGFloat = 360
    let imgX = (w - imgW) / 2
    let imgBase: CGFloat = 105             // image's bottom edge, flipped-y
    let imgRect = CGRect(x: imgX, y: imgBase, width: imgW, height: imgH)
    ctx.setStrokeColor(NSColor(white: 0.15, alpha: 1).cgColor)
    ctx.setLineWidth(1)
    ctx.stroke(imgRect)
    modeImage.draw(in: imgRect)

    // 3. Subtitle — small uppercase "A vibscape by…" between the title
    //    and the image, in flipped coords that's just above `imgBase + imgH`.
    let subtitleText = "A VIBSCAPE BY \(spec.author.uppercased())"
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold),
        .foregroundColor: muted,
        .kern: 3.0,
    ]
    let subSize = (subtitleText as NSString).size(withAttributes: subAttrs)
    (subtitleText as NSString).draw(
        at: CGPoint(x: (w - subSize.width) / 2,
                    y: imgBase + imgH + 18),
        withAttributes: subAttrs
    )

    // 4. Title — large, centred, just above the subtitle. The bit that
    //    has to survive lossy compression in a chat preview.
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 64, weight: .bold),
        .foregroundColor: text,
    ]
    let titleSize = (spec.title as NSString).size(withAttributes: titleAttrs)
    let titleBaselineY = imgBase + imgH + 18 + subSize.height + 18
    (spec.title as NSString).draw(
        at: CGPoint(x: (w - titleSize.width) / 2, y: titleBaselineY),
        withAttributes: titleAttrs
    )

    // 5. Wave logo top-left of the canvas (high y in flipped coords) with
    //    a magenta glow.
    ctx.saveGState()
    let waveUnit: CGFloat = 1.5
    let waveOriginY: CGFloat = h - 50       // baseline near the canvas top
    let waveOriginX: CGFloat = 36
    let wavePath = CGMutablePath()
    for (i, p) in wave.enumerated() {
        let q = CGPoint(x: waveOriginX + p.x * waveUnit,
                        y: waveOriginY + (16 - p.y) * waveUnit)
        i == 0 ? wavePath.move(to: q) : wavePath.addLine(to: q)
    }
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setShadow(offset: .zero, blur: 16,
                  color: magenta.withAlphaComponent(0.7).cgColor)
    ctx.setLineWidth(2.6)
    ctx.setStrokeColor(magenta.cgColor)
    ctx.addPath(wavePath); ctx.strokePath()
    ctx.restoreGState()
    // Hot core so the wave reads as neon, not just a magenta line.
    ctx.setLineWidth(0.9)
    ctx.setStrokeColor(magentaSoft.cgColor)
    ctx.addPath(wavePath); ctx.strokePath()

    // 6. Brand wordmark next to the wave. The wave is centred vertically on
    //    `waveOriginY`, so the wordmark sits on the same baseline.
    let brand = "VIBRESIA"
    let brandAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18, weight: .bold),
        .foregroundColor: text,
        .kern: 3.5,
    ]
    let brandSize = (brand as NSString).size(withAttributes: brandAttrs)
    (brand as NSString).draw(
        at: CGPoint(x: 80,
                    y: waveOriginY + brandSize.height / 2 - 12),
        withAttributes: brandAttrs
    )

    // 7. "Made with ❤ by <author>" — bottom-right of the canvas. Same
    //    wording as the app's credits button (`AboutButton.swift`).
    //    Low y in flipped coords = near the canvas bottom.
    let creditText = "Made with ❤ by \(spec.author)"
    let creditAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
        .foregroundColor: gold,
    ]
    let creditSize = (creditText as NSString).size(withAttributes: creditAttrs)
    (creditText as NSString).draw(
        at: CGPoint(x: w - creditSize.width - 30,
                    y: 32),
        withAttributes: creditAttrs
    )

    NSGraphicsContext.current = nil
    return rep.representation(using: .jpeg, properties: [
        NSBitmapImageRep.PropertyKey.compressionFactor: 0.86
    ])!
}

var wrote = 0
var missing: [String] = []
for spec in specs {
    let modeURL = modesDir.appendingPathComponent(spec.modeJPG)
    if !FileManager.default.fileExists(atPath: modeURL.path) {
        missing.append(spec.modeJPG)
    }
    let data = render(spec)
    let url = outDir.appendingPathComponent(spec.shotJPG)
    do {
        try data.write(to: url, options: .atomic)
        wrote += 1
    } catch {
        print("[share-graphics] failed to write \(url.lastPathComponent): \(error)")
        exit(1)
    }
    print("[share-graphics] wrote \(url.lastPathComponent) (\(data.count) bytes)")
}
if !missing.isEmpty {
    print("[share-graphics] FAILED: missing source images: \(missing.joined(separator: ", "))")
    exit(1)
}
print("[share-graphics] \(wrote) share graphics written to \(outDir.path)")
