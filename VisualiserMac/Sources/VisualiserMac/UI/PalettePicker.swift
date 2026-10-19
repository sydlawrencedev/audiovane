import SwiftUI
import simd

/// A small two-stop gradient chip showing a palette's shadow → highlight ramp.
struct PaletteSwatch: View {
    let shadow: SIMD3<Float>
    let highlight: SIMD3<Float>

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [Color(shadow), Color(highlight)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 16, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            )
    }
}

extension Color {
    init(_ c: SIMD3<Float>) {
        self.init(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: 1)
    }
}

/// Colour palette picker — a drop-down in the header.
///
/// The palette is applied as a post-process over the finished frame, so it
/// themes every mode at once rather than being one more thing each shader
/// has to know about.
struct PalettePicker: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        DropdownMenu(
            id: .palette,
            entries: Palette.all.enumerated().map { index, palette in
                DropdownEntry(
                    value: index,
                    title: palette.name,
                    swatch: (palette.shadow, palette.highlight)
                )
            },
            selection: Binding(
                get: { app.paletteIndex },
                set: { app.paletteIndex = $0 }
            ),
            tint: .bandTint
        )
    }
}
