import Foundation
import simd

/// A colour grade applied to the finished frame of every visualizer.
///
/// The grade is a duotone-plus-saturation pass: the scene's luminance ramp is
/// mapped between a shadow colour and a highlight colour, then the result is
/// pushed back toward (or away from) greyscale. Applying it as a post-process
/// means it themes *every* mode at once — the tunnel, the band, the machine —
/// without each shader needing to know about palettes.
struct Palette {
    let name: String
    /// Colour the darkest parts of the image tend toward.
    let shadow: SIMD3<Float>
    /// Colour the brightest parts tend toward.
    let highlight: SIMD3<Float>
    /// 0 = greyscale, 1 = as rendered, >1 = more saturated.
    let saturation: Float
    /// How strongly the duotone ramp is applied (0 = none, 1 = full).
    let duotone: Float
    /// How much the shadow colour lifts the blacks.
    let lift: Float

    static func rgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> {
        SIMD3<Float>(r, g, b)
    }

    /// The five palettes, in picker order. The first is the app's original
    /// magenta-and-cyan look, so it comes across as "unchanged".
    static let all: [Palette] = [
        Palette(
            name: "NEON",
            shadow:    rgb(0.07, 0.00, 0.11),
            highlight: rgb(1.00, 0.36, 0.95),
            saturation: 1.15,
            duotone: 0.25,
            lift: 0.22
        ),
        Palette(
            name: "EMBER",
            shadow:    rgb(0.09, 0.02, 0.00),
            highlight: rgb(1.00, 0.62, 0.24),
            saturation: 1.10,
            duotone: 0.72,
            lift: 0.28
        ),
        Palette(
            name: "TOXIC",
            shadow:    rgb(0.00, 0.07, 0.01),
            highlight: rgb(0.56, 1.00, 0.34),
            saturation: 1.25,
            duotone: 0.72,
            lift: 0.24
        ),
        Palette(
            name: "ABYSS",
            shadow:    rgb(0.00, 0.02, 0.11),
            highlight: rgb(0.56, 0.86, 1.00),
            saturation: 1.05,
            duotone: 0.78,
            lift: 0.32
        ),
        Palette(
            name: "MONO",
            shadow:    rgb(0.02, 0.02, 0.03),
            highlight: rgb(1.00, 1.00, 1.00),
            saturation: 0.00,
            duotone: 0.00,
            lift: 0.08
        ),
    ]

    static func palette(at index: Int) -> Palette {
        guard index >= 0, index < all.count else { return all[0] }
        return all[index]
    }
}
