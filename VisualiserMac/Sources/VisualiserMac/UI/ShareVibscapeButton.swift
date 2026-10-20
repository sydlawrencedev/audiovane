import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// "Share this vibescape" pill, under the VIBRESIA wordmark in the chrome.
///
/// A small button that opens `ShareVibscapeView`. Built into the HUD so it
/// rides the existing chrome (slides out with the rest of the bar when the
/// pointer leaves the window). At the tiny layout tier it drops entirely —
/// the keyboard shortcut on the existing `Visualizer` menu still works, and
/// the URL scheme `vibresia://open?p=…` covers deep links.
///
/// Two visuals to keep parity with the rest of the chrome:
///   - same rounded-rectangle fill/stroke as `SourcePicker` / `BPM`
///   - uses `app.layout.showsPillText` so the label drops at the narrow tier,
///     same as the other pills, instead of cramping the brand mark.
struct ShareVibscapeButton: View {
    @EnvironmentObject var app: AppState
    @State private var hovering = false
    @State private var showingSheet = false

    var body: some View {
        if app.layout.showsPills {
            Button {
                showingSheet = true
                Task { await Analytics.shared.track("share_pill_clicked", [
                    "kind": kindFor(app.activeVibscape)
                ]) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                    if app.layout.showsPillText {
                        Text("Share this vibescape")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.4)
                    }
                }
                .foregroundStyle(hovering
                                 ? Color.white
                                 : Color(red: 0.65, green: 0.95, blue: 1.0))
                .padding(.horizontal, app.layout.showsPillText ? 12 : 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 100)
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 100)
                                .stroke(
                                    (hovering ? Color.white.opacity(0.25)
                                              : Color.white.opacity(0.08)),
                                    lineWidth: 1
                                )
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 100))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Share this vibescape with someone")
            .sheet(isPresented: $showingSheet) {
                ShareVibscapeView(vibscape: app.activeVibscape)
                    .environmentObject(app)
            }
        }
    }

    private func kindFor(_ id: VibscapeID) -> String {
        id.isCustom ? "custom" : (id.builtin.flatMap { $0 == .autoScan ? nil : $0.rawValue } ?? "auto_scan")
    }
}
