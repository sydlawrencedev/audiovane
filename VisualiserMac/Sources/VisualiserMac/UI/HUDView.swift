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
            // brand
            HStack(spacing: 12) {
                BrandMark()
                VStack(alignment: .leading, spacing: 3) {
                    Text("AUDIOVANE")
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .tracking(3.5)
                        .foregroundStyle(Color.white)
                    // The real version, not a standing "v1": someone reporting
                    // a crash or a mode that looks wrong needs to be able to
                    // read it off the screen. Uppercased by .textCase, like
                    // the rest of the header.
                    Text("audio visualiser · v\(Self.version)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Color(white: 0.45))
                        .textCase(.uppercase)
                }
            }

            Spacer()

            // mode picker (header drop-down)
            ModePicker()

            // genre picker (band mode only)
            GenrePicker()

            // colour palette picker
            PalettePicker()

            // source pill
            SourcePill(state: app.sourceState, label: app.sourceLabel)

            // BPM
            if app.bpm > 30 {
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

struct SourcePill: View {
    let state: SourceState
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color, radius: 6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 100)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .stroke(color.opacity(0.4), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    var color: Color {
        switch state {
        case .live:  return Color(red: 1.0, green: 0.17, blue: 0.84)
        case .demo:  return Color(red: 1.0, green: 0.71, blue: 0.28)
        case .idle:  return Color(white: 0.55)
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