import Foundation
import ImageIO
import CoreGraphics

/// Animated sprites loaded from a user folder (GIF / APNG / PNG), packed into
/// RGBA layers of a GL texture array. Layers are sized to the largest image so
/// GIFs keep their native pixels (they're tiled as wallpaper); smaller images
/// are centered. Each image keeps its own frame timing. Used by Hamster Dance.
struct SpriteAtlas {
    static let maxCell = 512       // largest layer edge, in pixels
    static let maxBytes = 64 << 20 // cap on total texture memory
    static let maxSprites = 16     // matches the shader's uniform arrays

    struct Sprite {
        let firstLayer: Int
        let frameCount: Int
        let frameDelay: Double     // average seconds per frame
    }

    var sprites: [Sprite] = []
    /// Premultiplied RGBA, top row first, `cell * cell * 4` bytes per layer.
    var pixels: [UInt8] = []
    var cellWidth = 0
    var cellHeight = 0
    var layerCount: Int { cellWidth == 0 ? 0 : pixels.count / (cellWidth * cellHeight * 4) }

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AUDIVANE/Hamsters", isDirectory: true)
    }

    static func ensureFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static func imageURLs() -> [URL] {
        let exts: Set<String> = ["gif", "png", "apng"]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Cheap fingerprint of the folder (names + modification dates) to detect changes.
    static func folderStamp() -> String {
        imageURLs().map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970 ?? 0
            return "\(url.lastPathComponent):\(date)"
        }.joined(separator: "|")
    }

    static func load() -> SpriteAtlas {
        var atlas = SpriteAtlas()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let sources = imageURLs().prefix(maxSprites).compactMap { url -> (URL, CGImageSource)? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(src) > 0 else { return nil }
            return (url, src)
        }
        // Layer size = largest image, so the biggest GIF keeps its native pixels.
        for (_, src) in sources {
            if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                atlas.cellWidth = max(atlas.cellWidth, props[kCGImagePropertyPixelWidth] as? Int ?? 0)
                atlas.cellHeight = max(atlas.cellHeight, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
            }
        }
        atlas.cellWidth = min(max(atlas.cellWidth, 1), maxCell)
        atlas.cellHeight = min(max(atlas.cellHeight, 1), maxCell)
        let cw = atlas.cellWidth, ch = atlas.cellHeight
        let layerBytes = cw * ch * 4
        let maxLayers = maxBytes / layerBytes

        for (url, src) in sources {
            let frames = min(CGImageSourceGetCount(src), maxLayers - atlas.layerCount)
            guard frames > 0 else { continue }

            let first = atlas.layerCount
            atlas.pixels.append(contentsOf: repeatElement(0, count: frames * layerBytes))
            var totalDelay = 0.0
            for i in 0..<frames {
                totalDelay += frameDelay(src, i)
                guard let image = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
                let w = CGFloat(image.width), h = CGFloat(image.height)
                let scale = min(1, CGFloat(cw) / w, CGFloat(ch) / h)
                let rect = CGRect(x: ((CGFloat(cw) - w * scale) / 2).rounded(), y: ((CGFloat(ch) - h * scale) / 2).rounded(),
                                  width: w * scale, height: h * scale)
                atlas.pixels.withUnsafeMutableBytes { buf in
                    guard let ctx = CGContext(
                        data: buf.baseAddress!.advanced(by: (first + i) * layerBytes),
                        width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    else { return }
                    ctx.interpolationQuality = .none   // keep small pixel-art GIFs crisp
                    ctx.draw(image, in: rect)
                }
            }
            atlas.sprites.append(Sprite(firstLayer: first, frameCount: frames,
                                        frameDelay: totalDelay / Double(frames)))
            NSLog("[SPRITES] \(url.lastPathComponent): \(frames) frames, \(String(format: "%.3f", totalDelay / Double(frames)))s/frame")
        }
        return atlas
    }

    /// Per-frame delay, treating near-zero delays as 0.1s like browsers do.
    private static func frameDelay(_ src: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any] else { return 0.1 }
        var delay: Double?
        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
        } else if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            delay = (png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double) ?? (png[kCGImagePropertyAPNGDelayTime] as? Double)
        }
        guard let d = delay, d >= 0.02 else { return 0.1 }
        return d
    }
}
