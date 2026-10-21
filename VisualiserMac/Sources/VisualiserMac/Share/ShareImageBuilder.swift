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
enum ShareImageBuilder {
    /// The share picture, as JPEG data.
    ///
    /// JPEG rather than PNG because it is 1200x630 of smooth gradients, which
    /// is what JPEG is good at, and it is a third of the size — and the
    /// picture is stored, one per share, against a quota.
    static func jpeg(renderer: OpenGLRenderer, mode: VibescapeID,
                      width: Int, height: Int, time: Double, author: String) -> Data? {
        guard let image = renderer.renderStillImage(width: width, height: height,
                                                    mode: mode, time: time),
              let branded = ShareImageBrand.branded(image, author: author) else {
            return nil
        }
        return renderer.encodeJPEG(branded, quality: 0.82)
    }

    /// The same picture as PNG data.
    ///
    /// A run of frames rather than a single one, so a shader that moves has
    /// reached its stride by the last frame — the same reason the preview
    /// runs rather than drawing one instant.
    static func png(renderer: OpenGLRenderer, mode: VibescapeID,
                    width: Int, height: Int, frames: Int, author: String) -> Data? {
        guard let image = renderer.renderLastFrameImage(width: width, height: height,
                                                       mode: mode, frames: frames),
              let branded = ShareImageBrand.branded(image, author: author) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, branded, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
