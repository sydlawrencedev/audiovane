import SwiftUI
import AppKit

/// The bottom-left strip: what is playing, who made it, and the way to send
/// it to someone.
///
/// The name, the credit and the share button always stay: someone watching a
/// vibescape they didn't write wants to know whose it is and wants to be able
/// to pass it on, and both were only available while they happened to be
/// moving the mouse.
struct FooterView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        // Subscribe to the throttled display tick (see AudioEngine).
        let _ = app.audio.displayTick
        // While auto-scanning, report the vibescape actually on screen rather
        // than the "AUTO SCAN" that was selected — including its author, which
        // is how you know whose vibescape Auto Scan just handed you.
        let current = app.activeVibescape.isAutoScan ? app.scanTarget : app.activeVibescape

        HStack(alignment: .bottom, spacing: 16) {
            NowPlayingCell(id: current)
            // The strip belongs in the corner rather than in the middle of
            // the window. It used to be nudged left of centre with a pair of
            // paddings, which is not the same thing: a block that is merely
            // off-centre reads as misplaced, and one that is in the corner
            // reads as designed.
            Spacer(minLength: 0)
        }
    }
}

/// What is on screen right now, who made it, and the way to pass it on.
///
/// The share button sits above the name rather than beside it. It is about
/// *this* vibescape, so it belongs with the name of this vibescape, and the
/// line it is on is the one that always exists.
struct NowPlayingCell: View {
    @EnvironmentObject var app: AppState
    let id: VibescapeID

    var body: some View {
        // nil whenever there's nobody worth naming — a custom vibescape with no
        // author filled in, or one by Minith Labs, whose name is already in the
        // bottom-right corner. See AppState.credit(for:).
        let credit = app.credit(for: id)

        return VStack(alignment: .leading, spacing: 4) {
            ShareVibescapeButton()

            Text(app.displayName(for: id))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
                // Capped on the line, not on the container. A maxWidth on the
                // container reads as permission to grow, and it grew —
                // competing for leftover space with the audio cells and
                // ending up a third of the screen wide.
                .frame(maxWidth: 260, alignment: .leading)

            if let credit {
                // One Group around both branches so the styling is written
                // once. Inside the if/else it doesn't compile: the two sides are
                // different types and neither is a View you can hang a .font()
                // on.
                Group {
                    if let link = credit.link {
                        Button { NSWorkspace.shared.open(link) } label: {
                            Text("Made with 💜 by \(credit.author)")
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .help("\(credit.author) — open their page")
                    } else {
                        Text("Made with 💜 by \(credit.author)")
                            .help(credit.author)
                    }
                }
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color(white: 0.55))
                .lineLimit(1)
                .frame(maxWidth: 260, alignment: .leading)
            }
        }
        // The whole block is lifted to sit on the same line as the "🩷 from
        // Minith Labs" in the bottom-right corner, which is eight points
        // higher: that label is inside a pill with six points of padding on
        // it, and the pill's bottom is two points lower than this strip's,
        // so without this the credit reads as sitting a little low.
        //
        // The name and the share button come up with it. The credit was
        // lifted on its own, which left the three of them looking like they
        // had been arranged by accident rather than as one thing.
        .offset(y: -8)
        // fixedSize so the block hugs its text rather than competing with the
        // audio cells for leftover space. Both caps above still truncate.
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 4)
        .help(app.displayName(for: id))
    }
}
