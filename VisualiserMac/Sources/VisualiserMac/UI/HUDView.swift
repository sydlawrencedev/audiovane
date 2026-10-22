import SwiftUI
import VibresiaBrand

struct HUDView: View {
    @EnvironmentObject var app: AppState

    /// From the bundle, so it can't drift from the released build. Falls back
    /// to "dev" for a bare `swift build`, where there is no Info.plist.
    private static let version: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }()

    var body: some View {
        HStack(alignment: .center) {
            // Brand only. The share pill used to sit under the wordmark here,
            // riding the chrome and sliding away with it — which meant the one
            // control for passing a vibescape on was only there when you were
            // already moving the mouse. It lives in the footer strip now,
            // beside the name and credit, and never hides.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    BrandMark()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("VIBRESIA")
                            .font(.system(size: 17, weight: .bold, design: .default))
                            .tracking(3.5)
                            .foregroundStyle(Color.white)
                        // The real version, not a standing "v1": someone reporting
                        // a crash or a vibescape that looks wrong needs to be able to
                        // read it off the screen. Uppercased by .textCase, like
                        // the rest of the header.
                        Text("v\(Self.version)")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(Color(white: 0.45))
                            .textCase(.uppercase)
                    }
                }
            }

            Spacer()

            // Below the narrowest tier the pills go entirely: at that size the
            // scene is the point, and the same choices are still one keystroke
            // away (1–0, -, [, ], ; and =) or in the Visualizer menu.
            if app.layout.showsPills {
                // First in the row, and deliberately not part of the picker
                // below: making a vibescape isn't switching to one.
                VibeYourOwnButton()

                // vibescape picker (header drop-down)
                VibescapePicker()

                // genre picker (band vibescape only)
                GenrePicker()

                // colour palette picker
                PalettePicker()

                // source picker
                SourcePicker()
            }

            // The tempo is not shown. It used to be the last thing to
            // survive in the header, in a pill of its own, and it was
            // saying something the picture was already saying better: the
            // beat clock, the sprite rate, the flashes. It is still measured
            // — the beat clock needs it, and so do the genre, the exports
            // and the readings an agent asks for — but a number on the
            // screen is not what anybody was looking for.
        }
    }
}

/// The audio source, as a header picker.
///
/// This used to be a status display — you could see "system audio" but the only
/// way to change it was the intro screen or the Visualizer menu, which meant
/// quitting what you were doing to switch inputs. Same list, same click-away,
/// same visual language as the vibescape and palette pickers; the dot still says
/// whether anything is actually flowing.
struct SourcePicker: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        DropdownMenu(
            id: .source,
            entries: AudioSource.allCases.map { source in
                DropdownEntry(value: source,
                              title: source.menuTitle,
                              subtitle: source.subtitle)
            },
            selection: Binding(get: { app.audio.savedSource },
                               set: { app.selectSource($0, via: "pill") }),
            tint: tint,
            pillLeading: AnyView(
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .shadow(color: tint, radius: 6)
            ),
            pillTitle: app.activeSource?.title ?? app.sourceLabel.uppercased(),
            showsPillText: app.layout.showsPillText
        )
        .animation(.easeInOut(duration: 0.2), value: app.sourceState)
        .help("Change what Vibresia listens to")
    }

    /// Live is magenta, demo is amber, idle is grey and anything that failed is
    /// red — the same four meanings the pill always had.
    private var tint: Color {
        switch app.sourceState {
        case .live: return Color(red: 1.0, green: 0.17, blue: 0.84)
        case .demo: return Color(red: 1.0, green: 0.71, blue: 0.28)
        case .idle: return Color(white: 0.55)
        case .error: return Color(red: 1.0, green: 0.35, blue: 0.35)
        }
    }
}

/// The Vibresia mark: the wave, in the app's header.
///
/// The shape comes from `BrandWave`, which is also what the share pictures
/// are stamped with and what the website's logo is drawn from. One shape,
/// three places — otherwise the app and its own share pictures stop looking
/// like the same product.
struct BrandMark: View {
    var body: some View {
        Canvas { ctx, size in
            let path = Path { p in
                for (index, point) in BrandWave.points.enumerated() {
                    let q = CGPoint(x: point.x * size.width, y: point.y * size.height)
                    index == 0 ? p.move(to: q) : p.addLine(to: q)
                }
            }
            ctx.stroke(
                path,
                with: .color(Color(red: 1, green: 0.17, blue: 0.84)),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 28, height: 28)
        .shadow(color: Color(red: 1, green: 0.17, blue: 0.84).opacity(0.7), radius: 8)
    }
}