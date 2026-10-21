import SwiftUI

/// The bottom-left strip: what is playing, who made it, the way to send it to
/// someone, and — when the window is wide enough — the audio numbers.
///
/// Always on screen. Everything else in the chrome slides away when the
/// pointer leaves the window, on the reasoning that the visuals are the point
/// and a bar of diagnostics over them is noise. That reasoning does not extend
/// to this: someone watching a vibescape they didn't write wants to know whose
/// it is and to be able to pass it on without hunting for the control. Hiding
/// that is hiding the one part of the interface that belongs to the person
/// watching rather than to the app.
struct FooterView: View {
    @EnvironmentObject var app: AppState

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
            ShareVibescapeButton()

            Spacer(minLength: 0)

            // The audio numbers are ours, not the viewer's — the vibescape name
            // above is theirs — so they're the first thing to go when the
            // window narrows.
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
            }
        }
    }
}

/// What is on screen right now, and who made it.
struct NowPlayingCell: View {
    @EnvironmentObject var app: AppState
    let id: VibescapeID

    var body: some View {
        let author = app.authorName(for: id)
        VStack(alignment: .leading, spacing: 4) {
            Text("VIBESCAPE")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color(white: 0.45))
            Text(app.displayName(for: id))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
                // Capped per line rather than on the VStack, and the VStack is
                // fixedSize so the whole block hugs its text. Both matter: a
                // maxWidth on the container reads as permission to grow, and it
                // grew — competing for leftover space with the audio cells
                // below and ending up a third of the screen wide, which put the
                // share button nowhere near the name it belongs to.
                .frame(maxWidth: 260, alignment: .leading)
            // Left out entirely rather than shown as a blank line: a custom
            // vibescape with no author filled in has nobody to credit, and an
            // empty line where a name should be reads as a bug.
            if !author.isEmpty {
                Text(author)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 4)
        .help(author.isEmpty ? app.displayName(for: id)
                             : "\(app.displayName(for: id)) by \(author)")
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