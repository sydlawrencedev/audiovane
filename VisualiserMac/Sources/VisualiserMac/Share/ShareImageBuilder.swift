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
    /// The share picture, as JPEG data.
    static func jpeg(renderer: OpenGLRenderer, mode: VibescapeID,
                      width: Int, height: Int, time: Double, author: String) async -> Data? {
        guard let image = await stillImage(renderer: renderer, mode: mode,
                                           width: width, height: height, time: time) else {
            return nil
        }
        guard let branded = await brand(image, author: author) else { return nil }
        return encodeJPEG(branded, quality: 0.82)
    }

    /// The same picture as PNG data.
    ///
    /// A run of frames rather than a single one, so a shader that moves has
    /// reached its stride by the last frame — the same reason the preview
    /// runs rather than drawing one instant.
    static func png(renderer: OpenGLRenderer, mode: VibescapeID,
                    width: Int, height: Int, frames: Int, author: String) async -> Data? {
        guard let image = await lastFrameImage(renderer: renderer, mode: mode,
                                               width: width, height: height, frames: frames) else {
            return nil
        }
        guard let branded = await brand(image, author: author) else { return nil }
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
    private static func brand(_ image: CGImage, author: String) -> CGImage? {
        ShareImageBrand.branded(image, author: author)
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
}
