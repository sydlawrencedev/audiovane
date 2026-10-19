import SwiftUI
import AppKit

/// The small "Made with ❤️" button in the bottom-right corner.
///
/// Clicking it opens a popover with the credits and a "Buy us a coffee"
/// button (Stripe's hosted checkout).
struct AboutButton: View {
    @EnvironmentObject var app: AppState
    @StateObject private var startup = StartupManager.shared

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

            StartupToggles(manager: startup)

            Divider().overlay(Color.white.opacity(0.1))

            AnalyticsToggle()
        }
        .padding(18)
        .frame(width: 320)
        .background(Color(red: 0.06, green: 0.03, blue: 0.11))
    }
}

/// "Start at login" and "Open when Music or Spotify starts".
///
/// Both belong here rather than in the header: they're settings you set once,
/// and putting them behind a visible control is the difference between a
/// feature and something that startles someone.
private struct StartupToggles: View {
    @ObservedObject var manager: StartupManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STARTUP")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color(white: 0.45))

            toggle("Start at login",
                   detail: manager.launchAtLoginDetail,
                   isOn: manager.launchAtLogin,
                   help: "AudioVane opens by itself when you log in.") {
                manager.setLaunchAtLogin($0)
            }

            toggle("Open with Music or Spotify",
                   detail: manager.watchMusicAppsDetail,
                   isOn: manager.watchMusicApps,
                   help: "A small background watcher opens AudioVane when Apple Music or Spotify starts. No audio, no window titles — it just watches which apps launch.") {
                manager.setWatchMusicApps($0)
            }

            if let message = manager.errorMessage {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { manager.refresh() }
    }

    private func toggle(_ title: String, detail: String, isOn: Bool,
                        help: String, action: @escaping (Bool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { isOn }, set: action)) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(help)

            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Anonymous usage toggle.
///
/// This app watches audio and draws the screen, so the line between "harmless"
/// and "creepy" telemetry is drawn on purpose: the client only ever sends
/// feature usage (which mode, which palette, did you click the coffee button)
/// and crash reports (what was on screen when it died, plus a stack trace).
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
                 ? "Counts which modes and palettes you use, and whether the support button got clicked. Also sends crash reports: what was on screen (mode, genre, stage) and a stack trace. Never screen content, audio, window titles or track names."
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

/// "Proudly Shareware", linking to the AudioVane website. Sits just above
/// the credits button.
struct SharewareLink: View {
    private static let site = URL(string: "https://audiovane.minithlabs.com")!
    @State private var hovering = false

    var body: some View {
        Link(destination: Self.site) {
            Text("Proudly Shareware")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.35).opacity(hovering ? 1 : 0.8))
                .underline(hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("audiovane.minithlabs.com")
    }
}
