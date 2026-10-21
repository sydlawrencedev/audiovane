import SwiftUI

/// "Vibe your own" — the way in to writing a vibescape, in the chrome.
///
/// It used to be the last entry in the vibescape drop-down, under a divider.
/// That was the wrong shape twice over. It isn't a vibescape, so it can't be
/// selected, and everything else in that list is something you *switch to* —
/// and what this one does is make something new. It also sat after every
/// vibescape on screen, which is exactly where the least likely thing to be
/// clicked belongs if the point is that people write their own.
///
/// The neon is the same treatment the Share… button gets, because it is the
/// other primary action here: both of them are about doing rather than
/// watching, and neither is something anyone arrives by accident.
struct VibeYourOwnButton: View {
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        Button {
            app.customVibescapeSheet = .new
            Task { await Analytics.shared.track("custom_vibescape_opened", [
                "via": "pill"
            ]) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
                // Same rule as every other pill: the label drops before the
                // brand mark gets cramped.
                if app.layout.showsPillText {
                    Text("Vibe your own")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, app.layout.showsPillText ? 12 : 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 100)
                    .fill(Color(red: 1, green: 0.17, blue: 0.84))
                    .shadow(color: Color(red: 1, green: 0.17, blue: 0.84).opacity(hovering ? 0.75 : 0.4),
                            radius: hovering ? 16 : 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(Color.white.opacity(hovering ? 0.5 : 0.25), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 100))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Write your own vibescape")
    }
}