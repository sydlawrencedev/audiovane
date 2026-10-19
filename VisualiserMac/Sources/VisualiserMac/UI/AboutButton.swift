import SwiftUI
import AppKit

/// The small "Made with ❤️" button in the bottom-right corner.
///
/// Clicking it opens a popover with the credits and a "Buy us a coffee"
/// button (Stripe's hosted checkout).
struct AboutButton: View {
    @EnvironmentObject var app: AppState

    private static let site = URL(string: "https://minithlabs.com")!

    var body: some View {
        Button {
            app.showAbout.toggle()
        } label: {
            HStack(spacing: 6) {
                Text("Made with ❤️ by Minith Labs")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color(white: 0.62))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 100)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 100))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $app.showAbout, arrowEdge: .bottom) {
            popoverContent
        }
        .help("Credits and ways to support the project")
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AUDIOVANE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.white)
                Link(destination: Self.site) {
                    Text("minithlabs.com")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(red: 0.17, green: 0.95, blue: 1.0))
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 6) {
                Text("Thank you.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Someone who has used what we've made took the time to say so, and this is how. Every coffee helps us keep building, and it means a lot that you noticed.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            StripeBuyButton()

            Text("Opens Stripe's secure checkout in your browser.")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.45))

            Divider().overlay(Color.white.opacity(0.1))

            AnalyticsToggle()
        }
        .padding(18)
        .frame(width: 320)
        .background(Color(red: 0.06, green: 0.03, blue: 0.11))
    }
}

/// Anonymous usage toggle.
///
/// This app watches audio and draws the screen, so the line between "harmless"
/// and "creepy" telemetry is drawn on purpose: the client only ever sends
/// feature usage (which mode, which palette, did you click the coffee button).
/// Nothing about *what is playing or on screen* is ever included. The toggle is
/// here so that's a decision the user makes rather than one we make for them.
private struct AnalyticsToggle: View {
    @State private var enabled = false
    @State private var configured = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $enabled) {
                Text("Share anonymous usage")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .onChange(of: enabled) { _, newValue in
                Task { await Analytics.shared.setEnabled(newValue) }
            }
            .disabled(!configured)

            Text(configured
                 ? "Counts which modes and palettes you use, and whether the support button got clicked. Never screen content, audio, window titles or track names."
                 : "Not configured in this build.")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            configured = await Analytics.shared.isConfigured
            enabled = await Analytics.shared.isEnabled
        }
    }
}
