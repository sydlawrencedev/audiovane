import SwiftUI
import AppKit

/// The bottom-left strip: what is playing, who made it, the way to send it to
/// someone, and — when the window is wide enough and the pointer is inside —
/// the audio numbers.
///
/// Two halves with different rules. The name, the credit and the share button
/// always stay: someone watching a vibescape they didn't write wants to know
/// whose it is and wants to be able to pass it on, and both were only available
/// while they happened to be moving the mouse. The audio numbers are ours, not
/// the viewer's — diagnostics for the app, not for the person watching — so
/// they ride the chrome out with everything else.
struct FooterView: View {
    @EnvironmentObject var app: AppState

    /// Whether the pointer is over the window. Drives the audio numbers only.
    var chromeVisible: Bool

    var body: some View {
        // Subscribe to the throttled display tick (see AudioEngine).
        let _ = app.audio.displayTick
        let snap = app.audio.snapshot
        // While auto-scanning, report the vibescape actually on screen rather
        // than the "AUTO SCAN" that was selected — including its author, which
        // is how you know whose vibescape Auto Scan just handed you.
        let current = app.activeVibescape.isAutoScan ? app.scanTarget : app.activeVibescape

        HStack(alignment: .bottom, spacing: 16) {
            NowPlayingCell(id: current)

            Spacer(minLength: 0)

            if app.layout.showsFooterNumbers {
                HStack(spacing: 0) {
                    FooterCell(key: "RMS",  value: String(format: "%.2f", snap.rms))
                    FooterCell(key: "BASS", value: String(format: "%.2f", snap.bass))
                    FooterCell(key: "MID",  value: String(format: "%.2f", snap.mid))
                    FooterCell(key: "TREB", value: String(format: "%.2f", snap.treble))
                    FooterCell(key: "BEAT", value: snap.beatStrength > 0.05
                        ? String(format: "%.2f", snap.beatStrength)
                        : "—",
                               flash: snap.beatStrength > 0.4)
                }
                // Hidden outright as well as faded, so the numbers aren't left
                // in the layout as dead space while they're gone.
                .offset(y: chromeVisible ? 0 : 80)
                .opacity(chromeVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: chromeVisible)
            }
        }
    }
}

/// What is on screen right now, who made it, and the way to pass it on.
///
/// The share button sits on the title's line rather than beside the block. It
/// is about *this* vibescape, so it belongs next to the name of this vibescape,
/// and putting it after the credit put it on a row that only sometimes exists —
/// so its position moved every time the credit appeared or didn't.
struct NowPlayingCell: View {
    @EnvironmentObject var app: AppState
    let id: VibescapeID

    var body: some View {
        // nil whenever there's nobody worth naming — a custom vibescape with no
        // author filled in, or one by Minith Labs, whose name is already in the
        // bottom-right corner. See AppState.credit(for:).
        let credit = app.credit(for: id)

        return VStack(alignment: .leading, spacing: 4) {
            Text("VIBESCAPE")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color(white: 0.45))

            HStack(alignment: .center, spacing: 12) {
                Text(app.displayName(for: id))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Capped on the line, not on the container. A maxWidth on
                    // the container reads as permission to grow, and it grew —
                    // competing for leftover space with the audio cells and
                    // ending up a third of the screen wide.
                    .frame(maxWidth: 260, alignment: .leading)

                ShareVibescapeButton()
            }

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
        // fixedSize so the block hugs its text rather than competing with the
        // audio cells for leftover space. Both caps above still truncate.
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 4)
        .help(app.displayName(for: id))
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