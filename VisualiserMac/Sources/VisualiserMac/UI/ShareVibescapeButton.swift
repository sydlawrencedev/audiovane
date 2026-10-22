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
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                if app.layout.showsPillText {
                    Text("Share")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                }
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
        // The words in the pill sit a padding's width in from its edge, which
        // is a padding's width right of the name underneath — so the two
        // read as two things that do not quite line up. The pill moves left
        // by that much, which puts its words in the same column as the name
        // and the credit, and up a touch, which opens the gap under it.
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
