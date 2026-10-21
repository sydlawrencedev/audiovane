import AppKit
import Foundation
import VibresiaBrand

// Draws the website's share picture for every built-in vibescape.
//
// The app's own share images are drawn by the app, and this is the other
// half: the static pictures the website serves for the built-ins. Both use
// the same brand code, so the mark in the corner of a built-in's picture is
// the same mark the app draws in its header.
//
// Run from the repo root:
//
//   swift run --package-path VisualiserMac ShareGraphics
//
// or, if you prefer, scripts/build-share-graphics.sh, which does that for you.
//
// Idempotent: existing files are overwritten. Re-run any time a vibescape's
// picture changes.

// MARK: - Where things are

// The repo root, so the tool can be run from anywhere as long as it is told
// where the site is. The default is the working directory, which is the repo
// root when the tool is run the way the script runs it.
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
                ? CommandLine.arguments[1]
                : FileManager.default.currentDirectoryPath)
let modesDir = root.appendingPathComponent("site/media/modes")
let shareDir = root.appendingPathComponent("site/share")
let manifestPath = shareDir.appendingPathComponent("manifest.json")

guard FileManager.default.fileExists(atPath: manifestPath.path) else {
    FileHandle.standardError.write(Data("""
    No \(manifestPath.path). Run this from the repo root, or pass the path to \
    it as the first argument.

    """.utf8))
    exit(1)
}

// MARK: - Which vibescapes

/// The list comes from the manifest the share pages are generated from, so
/// there is one list of built-ins rather than two — the old script carried
/// its own table, which had to be edited by hand whenever a vibescape was
/// added.
struct Manifest: Decodable {
    struct BuiltIn: Decodable {
        let slug: String
        let title: String
    }
    let builtIns: [BuiltIn]

    enum CodingKeys: String, CodingKey {
        case builtIns = "built_ins"
    }
}

let manifest: Manifest
do {
    let data = try Data(contentsOf: manifestPath)
    manifest = try JSONDecoder().decode(Manifest.self, from: data)
} catch {
    FileHandle.standardError.write(Data("Couldn't read \(manifestPath.path): \(error)\n".utf8))
    exit(1)
}

/// Who made the built-ins. They all ship with the app, so this is one name.
let author = "Minith Labs"

// MARK: - The canvas

// 1200x630 is the canvas Twitter/Slack/iMessage pick up from `og:image`.
// The mode JPGs are 640x360 — same 16:9, centred on the larger canvas at
// native pixels and the rest of the space goes to the chrome (title, credit).
let canvasW = 1200
let canvasH = 630

// Background gradient — the same deep purple as the landing page: a dark
// navy at the top rolling into near-black so the mark glows against it.
let bgTop = NSColor(red: 0.024, green: 0.004, blue: 0.05, alpha: 1)
let bgBottom = NSColor(red: 0.06, green: 0.03, blue: 0.11, alpha: 1)

func render(slug: String, title: String) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasW, pixelsHigh: canvasH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
    let w = CGFloat(canvasW), h = CGFloat(canvasH)

    // The bitmap is bottom-up: y=0 is the canvas bottom, y=canvasH the
    // canvas top. Names like "topY" make the direction explicit.

    // 1. Background gradient — deep navy at the top, near-black at the
    //    bottom, so the magenta mark glows against it.
    guard let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray,
                               locations: [0, 1]) else { return nil }
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: h),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // 2. Vibescape frame in the middle of the canvas, 16:9. Vertical
    //    extents in flipped coords: image "bottom" is `imgBase`,
    //    image "top" is `imgBase + imgH`. A dark frame on either side
    //    keeps the eye on the picture.
    let modeURL = modesDir.appendingPathComponent("\(slug).jpg")
    guard let modeImage = NSImage(contentsOf: modeURL),
          let cgImage = modeImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        NSGraphicsContext.current = nil
        return nil
    }
    let imgW: CGFloat = 720, imgH: CGFloat = 360
    let imgX = (w - imgW) / 2
    let imgBase: CGFloat = 105             // image's bottom edge, flipped-y
    let imgRect = CGRect(x: imgX, y: imgBase, width: imgW, height: imgH)
    ctx.setStrokeColor(NSColor(white: 0.15, alpha: 1).cgColor)
    ctx.setLineWidth(1)
    ctx.stroke(imgRect)
    ctx.draw(cgImage, in: imgRect)

    // How much wash the corners need, measured from the picture as it stands
    // now — the gradient and the vibescape, before the title and the credit
    // are on it. The corners of this canvas are a dark gradient whatever the
    // vibescape is, so the wash here is nearly always unnecessary, and the
    // app's own share image measures the same way.
    let wash = ctx.makeImage().map { ShareImageBrand.scrimStrengths(in: $0) }
        ?? (brand: 0.58, credit: 0.72)

    // 3. Subtitle — small uppercase "A vibescape by…" between the title
    //    and the image, in flipped coords that's just above `imgBase + imgH`.
    let subtitleText = "A VIBESCAPE BY \(author.uppercased())"
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold),
        .foregroundColor: NSColor(white: 0.75, alpha: 1),
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
        .foregroundColor: NSColor.white,
    ]
    let titleSize = (title as NSString).size(withAttributes: titleAttrs)
    let titleBaselineY = imgBase + imgH + 18 + subSize.height + 18
    (title as NSString).draw(
        at: CGPoint(x: (w - titleSize.width) / 2, y: titleBaselineY),
        withAttributes: titleAttrs
    )

    // 5. The brand and the credit — the same drawing the app puts on the
    //    share image it uploads, so the two don't look like different
    //    products.
    ShareImageBrand.draw(in: ctx, size: CGSize(width: w, height: h), author: author,
                         brandWash: wash.brand, creditWash: wash.credit)

    NSGraphicsContext.current = nil
    return rep.representation(using: .jpeg, properties: [
        NSBitmapImageRep.PropertyKey.compressionFactor: 0.86
    ])
}

// MARK: - Go

// The drawing uses AppKit for the lettering, which is main-thread-only.
// Top-level code runs on the main thread, so this is the right place for it.
func drawAll() {
    var wrote = 0
    var missing: [String] = []
    for builtIn in manifest.builtIns {
        let modeURL = modesDir.appendingPathComponent("\(builtIn.slug).jpg")
        if !FileManager.default.fileExists(atPath: modeURL.path) {
            missing.append(builtIn.slug)
            continue
        }
        guard let data = render(slug: builtIn.slug, title: builtIn.title) else {
            print("[share-graphics] failed to draw \(builtIn.slug)")
            exit(1)
        }
        let url = shareDir.appendingPathComponent("\(builtIn.slug).jpg")
        do {
            try data.write(to: url, options: .atomic)
            wrote += 1
        } catch {
            print("[share-graphics] failed to write \(url.lastPathComponent): \(error)")
            exit(1)
        }
        print("[share-graphics] wrote \(builtIn.slug).jpg (\(data.count) bytes)")
    }
    if !missing.isEmpty {
        print("[share-graphics] FAILED: missing source images: \(missing.joined(separator: ", "))")
        exit(1)
    }
    print("[share-graphics] \(wrote) share graphics written to \(shareDir.path)")
}

drawAll()
