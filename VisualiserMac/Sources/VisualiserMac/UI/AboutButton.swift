import SwiftUI
import AppKit

/// The small "🩷 from Minith Labs" button in the bottom-right corner.
///
/// Clicking it opens a popover with the credits and a "Buy us a coffee"
/// button (Stripe's hosted checkout).
struct AboutButton: View {
    @EnvironmentObject var app: AppState
    @StateObject private var startup = StartupManager.shared
    @State private var titleHovering = false

    private static let site = URL(string: "https://minithlabs.com")!
    /// The app's own site, which is what the name in the credits should go to
    /// — minithlabs.com is the maker's, and stays below it as its own link.
    private static let product = URL(string: "https://vibresia.com")!

    var body: some View {
        Button {
            app.showAbout.toggle()
        } label: {
            HStack(spacing: 6) {
                // A different heart from the one under the vibescape, on purpose: this is
                // the maker signing their own work, the other one is the maker
                // crediting whoever wrote the vibescape you're watching. Saying
                // the same words in both places made the app credit itself.
                Text("🩷 from Minith Labs")
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
                Link(destination: Self.product) {
                    Text("VIBRESSIA")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(.white)
                        .underline(titleHovering)
                }
                .buttonStyle(.plain)
                .onHover { titleHovering = $0 }
                .help("vibresia.com")

                Link(destination: Self.site) {
                    Text("minithlabs.com")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(red: 0.17, green: 0.95, blue: 1.0))
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 6) {
                Text("Proudly Shareware")
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

            WindowToggles()

            Divider().overlay(Color.white.opacity(0.1))

            AnalyticsToggle()

            Divider().overlay(Color.white.opacity(0.1))

            LegalLinks()
        }
        .padding(18)
        .frame(width: 320)
        .background(Color(red: 0.06, green: 0.03, blue: 0.11))
    }
}

/// The privacy policy and the terms.
///
/// Both are on the website, in plain English, and linked from every page of
/// it — but somebody asking "what does this thing collect?" should not have
/// to go looking for the answer.
private struct LegalLinks: View {
    private static let privacy = URL(string: "https://vibresia.com/privacy")!
    private static let terms = URL(string: "https://vibresia.com/terms")!

    var body: some View {
        HStack(spacing: 16) {
            Link(destination: Self.privacy) {
                Text("Privacy")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.62))
            }
            Link(destination: Self.terms) {
                Text("Terms")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.62))
            }
        }
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
                   help: "Vibresia opens by itself when you log in.") {
                manager.setLaunchAtLogin($0)
            }

            toggle("Open with Music or Spotify",
                   detail: manager.watchMusicAppsDetail,
                   isOn: manager.watchMusicApps,
                   help: "A small background watcher opens Vibresia when Apple Music or Spotify starts. No audio, no window titles — it just watches which apps launch.") {
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

/// "Float above other apps" — its own section because it isn't a start-up
/// choice, it's how the window behaves while you're watching it.
private struct WindowToggles: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WINDOW")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color(white: 0.45))

            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: Binding(get: { app.alwaysOnTop }, set: { app.setAlwaysOnTop($0) })) {
                    Text("Float above other apps")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Keeps Vibresia above other apps' windows. Full screen apps and the menu bar still cover it.")

                Text(app.alwaysOnTop
                     ? "Vibresia stays above other windows"
                     : "Vibresia goes behind other apps")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Anonymous usage toggle.
///
/// This app watches audio and draws the screen, so the line between "harmless"
/// and "creepy" telemetry is drawn on purpose: the client only ever sends
/// feature usage (which vibescape, which palette, did you click the coffee button)
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
                 ? "Counts which vibescapes and palettes you use, and whether the support button got clicked. Also sends crash reports: what was on screen (vibescape, genre, stage) and a stack trace. Never screen content, audio, window titles or track names."
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

/// "Proudly Shareware" — the one place in the app that asks to be passed on,
/// so it opens the same share sheet Finder and Mail use (AirDrop, Messages,
/// Slack, a mail draft, whatever they actually use) rather than sending them to
/// the website. The URL travels with the message, so a share that lands in a
/// message is already a link.
struct SharewareLink: View {
    private static let site = URL(string: "https://vibresia.com")!
    private static let pitch = "I think you'll love Vibresia, it's free and proudly shareware"
    @State private var hovering = false
    @State private var isSharing = false

    var body: some View {
        Button {
            isSharing = true
            // Fires when the sheet opens, not when something is actually
            // shared — NSSharingServicePicker doesn't report the outcome, and
            // claiming a share that never happened would be worse than a
            // slightly generous count.
            Task { await Analytics.shared.track("share_opened", ["source": "shareware_link"]) }
        } label: {
            Text("Proudly Shareware")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.35).opacity(hovering ? 1 : 0.8))
                .underline(hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .background(SharePickerAnchor(isPresented: $isSharing, items: Self.shareItems))
        .help("Share Vibresia with someone")
        .task {
            // `--about --share` opens the share sheet without a click, for
            // checking it still behaves on this version of macOS (Apple moves
            // these menus around between releases).
            if CommandLine.arguments.contains("--share") {
                try? await Task.sleep(nanoseconds: 600_000_000)
                isSharing = true
            }
        }
    }

    /// The message first, the link second: services that compose a post use the
    /// first item for the body and still render the URL as a link, and the ones
    /// that only understand a single string still get both.
    static var shareItems: [Any] { [pitch, site] }
}

/// SwiftUI has no share sheet, so this is the AppKit one in a 1×1 view parked
/// behind the label: `NSSharingServicePicker` positions its menu relative to a
/// view, and this is the only way to say *which* one without asking the user to
/// click it.
private struct SharePickerAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Not hidden: a zero-alpha view still gets a frame, and the picker needs
        // one to point at.
        view.alphaValue = 0
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented, !context.coordinator.isShowing else { return }
        context.coordinator.isShowing = true
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .maxY)
        // Re-arming after the menu closes, so a second share works without a
        // relaunch. Done on the next runloop turn: `isShowing` is only ever read
        // from `updateNSView`.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            context.coordinator.isShowing = false
            if self.isPresented { self.isPresented = false }
        }
    }

    final class Coordinator {
        var isShowing = false
    }
}
