import SwiftUI

/// Genre picker — the header drop-down that chooses the band vibescape's genre.
///
/// AUTO is the default: a `GenreDetector` watches the audio and picks the
/// genre itself. Clicking a genre locks that choice for the rest of the
/// current song; the next song re-arms auto. The confidence bar shows how
/// sure the detector is — cyan when it has committed, amber while it's still
/// deciding (below the auto-swap threshold it won't change the stage on its
/// own yet).
struct GenrePicker: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        // Only meaningful when the band is on screen — the genre drives the
        // stage, the lineup and the palette there. During auto-scan that
        // includes the moments the scanner is sitting on the band vibescape.
        let bandOnScreen = app.activeVibescape.isBand
            || (app.activeVibescape.isAutoScan && app.scanTarget.isBand)
        if bandOnScreen {
            DropdownMenu(
                id: .genre,
                entries: entries,
                // A pick goes through userPickedGenre so it turns auto-detect
                // off for this song; writing app.genre directly left auto on,
                // and the detector put its own genre straight back.
                selection: Binding(
                    get: { app.genre },
                    set: { app.userPickedGenre($0) }
                ),
                tint: app.genreIsAuto ? .bandTint : .modeTint,
                pillExtra: AnyView(confidenceBar)
            )
            .help("The band's genre — \(genreSource)")
        }
    }

    private var entries: [DropdownEntry<Genre>] {
        var out: [DropdownEntry<Genre>] = []
        out.append(DropdownEntry(
            value: app.genre,
            title: "Auto-detect",
            subtitle: autoSubtitle,
            glyph: "✦",
            action: { app.userToggledAuto(!app.genreIsAuto) }
        ))
        out.append(contentsOf: Genre.allCases.map { g in
            DropdownEntry(
                value: g,
                title: g.name,
                subtitle: (g == app.genre && !app.genreIsAuto) ? "locked for this song" : nil,
                glyph: g.glyph
            )
        })
        return out
    }

    private var autoSubtitle: String {
        if app.genreIsAuto {
            if app.genreIsDecided { return "on · \(app.genre.name)" } else { return "on · detecting…" }
        }
        return "off · click to re-enable"
    }

    /// Where the genre came from, for the tooltip.
    ///
    /// A catalogue knows the genre of a song; the detector is reading the
    /// waveform and guessing. Both are called "auto" from here, and it is
    /// worth saying which one is answering.
    private var genreSource: String {
        if app.nowPlaying?.genre != nil {
            return "from the song's genre in the catalogue"
        }
        return "from the sound"
    }

    /// Confidence bar in the pill. Cyan when the detector has committed,
    /// amber while it's still deciding. Hollow rather than solid while
    /// undecided so it reads as "measuring" instead of "empty".
    private var confidenceBar: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.10))
                .frame(width: 22, height: 3)
            RoundedRectangle(cornerRadius: 1)
                .fill(app.genreIsDecided ? Color.bandTint : .clear)
                .frame(width: 22 * CGFloat(app.genreConfidence), height: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color(red: 1, green: 0.71, blue: 0.28).opacity(0.6), lineWidth: 0.5)
                        .frame(width: 22 * CGFloat(app.genreConfidence), height: 3)
                )
        }
        .opacity(app.genreIsAuto ? 1 : 0.25)
    }
}
