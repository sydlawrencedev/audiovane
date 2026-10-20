import SwiftUI

struct IntroView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            // dim the background
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Text("FEED IT SOME SOUND.")
                        .font(.system(size: 48, weight: .bold, design: .default))
                        .tracking(1.0)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(white: 0.72)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(red: 1, green: 0.17, blue: 0.84).opacity(0.3), radius: 30)

                    Text("Pick any audio source. Vibresia reacts to bass, mids, treble, and beats in real time.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color(white: 0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 540)
                        .lineSpacing(4)
                }

                VStack(spacing: 10) {
                    SourceButton(
                        label: "Share System Audio",
                        sub: "Spotify, YouTube, Logic, anything playing on your Mac.",
                        primary: true,
                        action: { app.selectSource(.system, via: "intro") }
                    )
                    SourceButton(
                        label: "Use Microphone",
                        sub: "Plays whatever the mic hears. Good for ambient testing.",
                        primary: false,
                        action: { app.selectSource(.microphone, via: "intro") }
                    )
                    SourceButton(
                        label: "Use Demo Tone",
                        sub: "Generated kick + pad sweep. No permissions needed.",
                        primary: false,
                        action: { app.selectSource(.demo, via: "intro") }
                    )
                }
                .frame(maxWidth: 580)

                Text("macOS will ask for system audio recording permission the first time you share system audio. Allow it, then pick the same source again.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(white: 0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 40)
        }
    }
}

struct SourceButton: View {
    let label: String
    let sub: String
    let primary: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .tracking(1.0)
                        .foregroundStyle(Color.white)
                    Text(sub)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(primary
                          ? LinearGradient(
                                colors: [
                                    Color(red: 1, green: 0.17, blue: 0.84).opacity(0.20),
                                    Color(red: 0.54, green: 0.30, blue: 1.0).opacity(0.10),
                                    Color(red: 0.17, green: 0.95, blue: 1.0).opacity(0.05)
                              ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing)
                          : LinearGradient(colors: [.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(primary
                                    ? Color(red: 1, green: 0.17, blue: 0.84).opacity(0.4)
                                    : Color.white.opacity(0.08),
                                    lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .scaleEffect(hovering ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}