import SwiftUI
import AppKit

/// The prompt shown when the app is running from the Downloads folder.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            body_
            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(width: 460)
        .background(Color(red: 0.05, green: 0.02, blue: 0.09))
    }

    private var header: some View {
        Text("MOVE TO APPLICATIONS?")
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .tracking(2.2)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vibresia is in your Downloads folder.")
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.85))
                .fixedSize(horizontal: false, vertical: true)

            Text("Applications is where it belongs — it stays put, and it can update itself.")
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
                // "Not now" means not now, not never. It is remembered for a
                // while, so it is not a nag, and asked again later for
                // somebody who changes their mind.
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
            // The copy in Downloads has served its purpose — it is what
            // the user downloaded, and it is the thing that would otherwise
            // still be sitting there being run from a temporary copy next
            // time. It is removed by the instance that relaunches in
            // Applications, because that one is not running from it.
            app.markDownloadsCopyForRemoval()
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
