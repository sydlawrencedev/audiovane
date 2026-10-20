import SwiftUI

/// Mode picker — a drop-down anchored in the top HUD rather than the old
/// 11-row vertical rail down the left edge. With eleven modes the rail ate a
/// fixed 200pt column and about 60% of the window height, which was real
/// estate the visualisation should have had.
///
/// One line per mode (no shortcut subtitles) so the open list stays short
/// enough for small windows. The keyboard shortcuts still work and are
/// listed in the Visualizer menu.
struct ModePicker: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        DropdownMenu(
            id: .mode,
            // Auto Scan always sits at the bottom of the list, after the two
            // buttons that open the panels.
            entries: entries,
            selection: Binding(
                get: { app.activeMode },
                set: {
                    // Flags the change as deliberate so the mode_changed event
                    // can tell a click apart from auto-scan cycling.
                    app.viaPicker = true
                    app.activeMode = $0
                }
            ),
            tint: app.activeMode.isBand || app.activeMode.isAutoScan ? .bandTint : .modeTint,
            pillExtra: app.activeMode.isAutoScan ? AnyView(scanIndicator) : nil,
            showsPillText: app.layout.showsPillText
        )
    }

    /// The list: every mode the user has switched on, then Auto Scan, then
    /// the two buttons that open the Custom Mode and View All panels.
    private var entries: [DropdownEntry<ModeID>] {
        var items: [DropdownEntry<ModeID>] = app.enabledModes.map { entry in
            DropdownEntry(
                value: entry.id,
                title: entry.title,
                // A user's own mode gets a pencil to edit it, and nothing
                // else — how many lines it is isn't the business of a list
                // of modes.
                subtitle: entry.isCustom ? nil : entry.subtitle,
                glyph: entry.glyph,
                editAction: entry.isCustom ? { app.editCustomMode(id: entry.id.slug) } : nil
            )
        }
        items.append(DropdownEntry(
            value: .builtin(.autoScan),
            title: VisualizerMode.autoScan.displayName,
            // The key that picks Auto Scan, like every other row.
            glyph: "="
        ))
        // A divider, so the buttons don't read as more modes.
        items.append(DropdownEntry(
            value: .builtin(.autoScan),
            title: "",
            isDivider: true
        ))
        items.append(DropdownEntry(
            value: .builtin(.autoScan),
            title: "+ CUSTOM MODE",
            glyph: "+",
            action: {
                app.openDropdown = nil
                app.customModeSheet = .new
            }
        ))
        items.append(DropdownEntry(
            value: .builtin(.autoScan),
            title: "VIEW ALL",
            glyph: "≡",
            action: {
                app.openDropdown = nil
                app.showAllModesSheet = true
            }
        ))
        return items
    }

    /// While auto-scanning, the pill says what's on screen right now and
    /// how long is left on it.
    private var scanIndicator: some View {
        HStack(spacing: 5) {
            Text("▸")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.bandTint)
            Text(app.displayName(for: app.scanTarget))
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
        case .ribbons: return "scribble.variable"
        case .silk: return "wind"
        case .flux: return "rays"
        case .spectrum: return "chart.bar"
        case .tunnel: return "tunnel"
        case .particles: return "sparkles"
        case .liquid: return "water.waves"
        case .kaleidoscope: return "square.grid.3x3"
        case .warp: return "arrow.left.and.right"
        case .waveform: return "waveform.path"
        case .nyan: return "rainbow"
        case .hamster: return "hare.fill"
        case .badger: return "hare"
        case .llama: return "loud.speaker"
        case .danceFloor: return "square.grid.3x3.fill"
        case .band: return "music.mic"
        case .machine: return "gearshape.2"
        case .autoScan: return "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }
}

extension Color {
    /// The app's primary magenta accent.
    static let modeTint = Color(red: 1, green: 0.17, blue: 0.84)
    /// Cyan, used for the band mode and anything auto-detected.
    static let bandTint = Color(red: 0.17, green: 0.95, blue: 1.0)
}
