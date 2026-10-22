import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// "Share this vibescape" pill, in the bottom-left strip beside the name and
/// the credit.
///
/// It used to sit under the VIBRESIA wordmark in the header, where it rode the
/// chrome and slid away with it. That made it useless for the one job it has:
/// someone watching a vibescape someone else wrote, who wants to send it on.
/// If it isn't there, it isn't there, and the only other route is a keyboard
/// shortcut nobody knows about. So it lives with the name now, and stays.
///
/// Two visuals to keep parity with the rest of the chrome:
///   - same rounded-rectangle fill/stroke as `SourcePicker` / `BPM`
///   - uses `app.layout.showsPillText` so the label drops at the narrow tier
///
/// The button itself is never hidden, at any width — it's the affordance the
/// name and credit sit next to, and dropping it would leave the strip reading
/// as a caption with no action attached.
struct ShareVibescapeButton: View {
    @EnvironmentObject var app: AppState
    @State private var hovering = false
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
            Task { await Analytics.shared.track("share_pill_clicked", [
                "kind": kindFor(app.activeVibescape)
            ]) }
        } label: {
            HStack(spacing: 6) {
                // The word comes first, so that the first thing inside the
                // pill is the first thing in the column below it. An icon in
                // front would push the word a whole icon's width to the
                // right of the name, and no amount of moving the pill left
                // would fix that without pushing the pill off the window.
                if app.layout.showsPillText {
                    Text("Share")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                }
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(hovering
                             ? Color.white
                             : Color(red: 0.65, green: 0.95, blue: 1.0))
            .padding(.horizontal, padding)
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
        .fixedSize()
        // The pill's own padding puts its contents a padding's width in from
        // its edge, so it moves left by that much: what is written in it
        // then starts in the same column as the name and the credit under
        // it, and the pill itself hangs a little into the margin to the
        // left. Up a touch as well, which opens the gap underneath.
        .offset(x: -padding, y: -2)
        .onHover { hovering = $0 }
        .help("Share this vibescape with someone")
        .sheet(isPresented: $showingSheet) {
            ShareVibescapeView(vibescape: app.activeVibescape)
                .environmentObject(app)
        }
    }

    /// How much the pill pads itself, which is also how far its contents sit
    /// from its edge.
    private var padding: CGFloat { app.layout.showsPillText ? 12 : 9 }

    private func kindFor(_ id: VibescapeID) -> String {
        id.isCustom ? "custom" : (id.builtin.flatMap { $0 == .autoScan ? nil : $0.rawValue } ?? "auto_scan")
    }
}
