import SwiftUI

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

            // BPM — the last thing to survive, and only when there's a beat to
            // show.
            if app.bpm > 30 && app.layout.showsPills {
                HStack(spacing: 6) {
                    Text("\(Int(app.bpm.rounded()))")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.17, green: 0.95, blue: 1.0))
                        .shadow(color: Color(red: 0.17, green: 0.95, blue: 1.0).opacity(0.5), radius: 8)
                    Text("BPM")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.45))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 100)
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 100)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
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

struct BrandMark: View {
    var body: some View {
        Canvas { ctx, size in
            let path = Path { p in
                let w = size.width
                let h = size.height
                p.move(to: CGPoint(x: 0, y: h * 0.5))
                p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.5))
                p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.2))
                p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.8))
                p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.3))
                p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.65))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.5))
                p.addLine(to: CGPoint(x: w, y: h * 0.5))
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