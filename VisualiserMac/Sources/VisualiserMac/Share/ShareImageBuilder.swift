import AppKit
import Foundation
import VibresiaBrand

/// The picture a share shows: the vibescape, with Vibresia's mark and the
/// credit on it.
///
/// Two pictures come out of this, and they are the same picture: the JPEG
/// that gets uploaded and becomes the link's preview in a chat, and the PNG
/// somebody saves to attach to a service that doesn't show link previews.
///
/// The brand goes on after the render and before the encoding, because a
/// picture of a vibescape with nothing on it doesn't say where it came from.
///
/// The render is a GPU job and happens off the main thread. The brand is
/// drawn with AppKit, which is main-thread-only, so that part hops back —
/// drawing text from a background queue is not supported and can go wrong
/// in ways that only show up on somebody else's Mac.
enum ShareImageBuilder {
    /// The name and the author for a shared picture.
    ///
    /// The app's own rule about who is worth naming: a vibescape by Minith
    /// Labs is not credited to anybody, and neither is one whose author field
    /// was left blank. The corner of the app's own window follows the same
    /// rule, so the picture and the window agree.
    static func title(name: String, author: String?) -> ShareImageBrand.Title {
        let trimmed = (author ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ShareImageBrand.Title(name: name) }
        guard trimmed.caseInsensitiveCompare(VibescapeMetadata.author) != .orderedSame else {
            return ShareImageBrand.Title(name: name)
        }
        return ShareImageBrand.Title(name: name, author: trimmed)
    }

    /// The share picture, as JPEG data.
    static func jpeg(renderer: OpenGLRenderer, mode: VibescapeID,
                      width: Int, height: Int, time: Double,
                      title: ShareImageBrand.Title,
                      maxBytes: Int = ShareLinkStore.maxImageBytes) async -> Data? {
        guard let image = await stillImage(renderer: renderer, mode: mode,
                                           width: width, height: height, time: time) else {
            return nil
        }
        guard let branded = await brand(image, title: title) else { return nil }
        return encodeJPEG(branded, quality: 0.82, maxBytes: maxBytes)
    }

    /// The same picture as PNG data.
    ///
    /// A run of frames rather than a single one, so a shader that moves has
    /// reached its stride by the last frame — the same reason the preview
    /// runs rather than drawing one instant.
    static func png(renderer: OpenGLRenderer, mode: VibescapeID,
                    width: Int, height: Int, frames: Int,
                    title: ShareImageBrand.Title) async -> Data? {
        guard let image = await lastFrameImage(renderer: renderer, mode: mode,
                                               width: width, height: height, frames: frames) else {
            return nil
        }
        guard let branded = await brand(image, title: title) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, branded, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// One frame of the vibescape, at a chosen moment, off the main thread.
    private static func stillImage(renderer: OpenGLRenderer, mode: VibescapeID,
                                   width: Int, height: Int, time: Double) async -> CGImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: renderer.renderStillImage(
                    width: width, height: height, mode: mode, time: time))
            }
        }
    }

    /// The last frame of a run of them, off the main thread.
    private static func lastFrameImage(renderer: OpenGLRenderer, mode: VibescapeID,
                                       width: Int, height: Int, frames: Int) async -> CGImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: renderer.renderLastFrameImage(
                    width: width, height: height, mode: mode, frames: frames))
            }
        }
    }

    /// The brand, on the main thread.
    @MainActor
    private static func brand(_ image: CGImage, title: ShareImageBrand.Title) -> CGImage? {
        ShareImageBrand.branded(image, title: title)
    }

    /// Encodes an image as JPEG data.
    ///
    /// JPEG rather than PNG because it is 1200x630 of smooth gradients, which
    /// is what JPEG is good at, and it is a third of the size — and the
    /// picture is stored, one per share, against a quota.
    private static func encodeJPEG(_ image: CGImage, quality: CGFloat) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Encodes a picture small enough for the site to take.
    ///
    /// A detailed vibescape produces a picture twice the size the site will
    /// store: a screen full of fine detail does not compress. So the quality
    /// comes down until the picture fits, and if it will not fit at any
    /// sensible quality the picture is left out — a share with a generic
    /// preview is much better than a share that does not exist.
    private static func encodeJPEG(_ image: CGImage, quality: CGFloat, maxBytes: Int) -> Data? {
        for quality in [quality, 0.65, 0.5, 0.4] {
            guard let data = encodeJPEG(image, quality: quality) else { continue }
            if data.count <= maxBytes { return data }
        }
        // Nothing fitted. The share is still worth having.
        return nil
    }
}
