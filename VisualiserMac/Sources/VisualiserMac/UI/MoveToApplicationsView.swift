import SwiftUI
import AppKit

/// The prompt shown when the app is running from somewhere it should not be.
///
/// It is a sheet rather than an alert because the app's own windows are
/// full-bleed visuals, and an alert in the middle of one looks like a
/// system dialog pasted over a picture. A sheet is also dismissible in the
/// way the rest of the app is.
struct MoveToApplicationsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var working = false
    @State private var failure: String?

    private var location: String {
        InstallLocation.describeCurrentLocation()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            body_
            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(width: 520)
        .background(Color(red: 0.05, green: 0.02, blue: 0.09))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MOVE TO APPLICATIONS?")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(.white)
            Text("Where Vibresia should live")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color(white: 0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vibresia is running from \(location).")
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.85))
                .fixedSize(horizontal: false, vertical: true)

            Text("Applications is where it belongs: it stays put, it can update itself, and it can open with your music. It also stops being run from a temporary copy macOS makes for downloaded apps, which is where a lot of the odd behaviour comes from.")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.6))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            if let failure {
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                // "Not now" means not now, for good. A prompt that comes back
                // on every launch is a nag, and this is a shareware app that
                // should not nag anybody about anything.
                app.declineMoveToApplications()
                dismiss()
            } label: {
                Text("Not now")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 100)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 100)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                            )
                    )
                    .foregroundStyle(Color(white: 0.75))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            Button {
                moveIt()
            } label: {
                HStack(spacing: 6) {
                    if working {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    }
                    Text(working ? "Moving…" : "Move to Applications")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 100)
                                .fill(Color(red: 1, green: 0.17, blue: 0.84))
                                .shadow(color: Color(red: 1, green: 0.17, blue: 0.84).opacity(0.4),
                                        radius: 10)
                        )
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    /// Copies the app across and restarts it from there.
    ///
    /// The order matters. The new instance is launched from the way out, so
    /// the two never run at once: the app restores whatever audio source it
    /// had last, and two of them fighting over the capture session would
    /// leave the new one with no sound.
    private func moveIt() {
        working = true
        failure = nil
        let result = InstallLocation.install()
        switch result {
        case .success(let url):
            NSLog("[move] installed at \(url.path) — relaunching")
            InstallLocation.pendingRelaunch = url
            app.movedToApplications()
            NSApp.terminate(nil)
        case .failure(let error):
            NSLog("[move] failed: \(error.localizedDescription)")
            working = false
            failure = error.localizedDescription
        }
    }
}
