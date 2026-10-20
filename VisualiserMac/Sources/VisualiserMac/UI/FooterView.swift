import SwiftUI

struct FooterView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        // Subscribe to the throttled display tick (see AudioEngine).
        let _ = app.audio.displayTick
        let snap = app.audio.snapshot
        HStack(spacing: 0) {
            // While auto-scanning, report the vibscape actually on screen
            // rather than the "AUTO SCAN" that was selected.
            FooterCell(key: "VIBSCAPE", value: app.activeVibscape.isAutoScan
                       ? app.displayName(for: app.scanTarget)
                       : app.displayName(for: app.activeVibscape))
            // The vibscape is the one value someone watching actually wants.
            // The other five are diagnostics — ours, not theirs — so they're
            // the first thing to go when the window narrows.
            if app.layout.showsFooterNumbers {
                FooterCell(key: "RMS",   value: String(format: "%.2f", snap.rms))
                FooterCell(key: "BASS",  value: String(format: "%.2f", snap.bass))
                FooterCell(key: "MID",   value: String(format: "%.2f", snap.mid))
                FooterCell(key: "TREB",  value: String(format: "%.2f", snap.treble))
                FooterCell(key: "BEAT",  value: snap.beatStrength > 0.05
                    ? String(format: "%.2f", snap.beatStrength)
                    : "—",
                           flash: snap.beatStrength > 0.4)
            }
        }
    }
}

struct FooterCell: View {
    let key: String
    let value: String
    var flash: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color(white: 0.45))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(flash ? Color(red: 1, green: 0.17, blue: 0.84) : Color.white)
                .shadow(color: flash ? Color(red: 1, green: 0.17, blue: 0.84).opacity(0.7) : .clear, radius: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}