import SwiftUI

/// Mode picker — a drop-down anchored in the top HUD rather than the old
/// 11-row vertical rail down the left edge. With eleven modes the rail ate a
/// fixed 200pt column and about 60% of the window height, which was real
/// estate the visualisation should have had.
///
/// The number-row shortcuts still work exactly as before, and each row in the
/// list shows its shortcut so the keyboard route stays discoverable now that
/// the list isn't permanently on screen.
struct ModePicker: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        DropdownMenu(
            id: .mode,
            // Auto Scan always sits at the bottom of the list.
            entries: (VisualizerMode.allCases.filter { $0 != .autoScan } + [.autoScan]).map { mode in
                DropdownEntry(
                    value: mode,
                    title: mode.displayName,
                    subtitle: mode == .autoScan ? "key = · 20s each" : "key \(String(mode.shortcutKey))",
                    glyph: mode.glyph
                )
            },
            selection: Binding(
                get: { app.activeMode },
                set: {
                    // Flags the change as deliberate so the mode_changed event
                    // can tell a click apart from auto-scan cycling.
                    app.viaPicker = true
                    app.activeMode = $0
                }
            ),
            tint: app.activeMode == .band || app.activeMode == .autoScan ? .bandTint : .modeTint,
            pillExtra: app.activeMode == .autoScan ? AnyView(scanIndicator) : nil
        )
    }

    /// While auto-scanning, the pill says what's on screen right now and
    /// how long is left on it.
    private var scanIndicator: some View {
        HStack(spacing: 5) {
            Text("▸")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.bandTint)
            Text(app.scanTarget.displayName)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.bandTint.opacity(0.9))
        }
    }
}

extension VisualizerMode {
    /// SF Symbol used in the drop-down menu.
    var symbolName: String {
        switch self {
        case .tunnel: return "tunnel"
        case .particles: return "sparkles"
        case .liquid: return "water.waves"
        case .badger: return "hare"
        case .llama: return "loud.speaker"
        case .hamster: return "hare.fill"
        case .nyan: return "rainbow"
        case .spectrum: return "chart.bar"
        case .kaleidoscope: return "square.grid.3x3"
        case .warp: return "arrow.left.and.right"
        case .band: return "music.mic"
        case .autoScan: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .machine: return "gearshape.2"
        case .waveform: return "waveform.path"
        }
    }
}

extension Color {
    /// The app's primary magenta accent.
    static let modeTint = Color(red: 1, green: 0.17, blue: 0.84)
    /// Cyan, used for the band mode and anything auto-detected.
    static let bandTint = Color(red: 0.17, green: 0.95, blue: 1.0)
}
