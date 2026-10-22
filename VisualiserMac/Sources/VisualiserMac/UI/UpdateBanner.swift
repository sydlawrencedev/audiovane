import SwiftUI

/// A banner at the top of the window saying that an update is waiting.
///
/// The check finds an update on its own, and the menu saying so is easy to
/// miss: a visualiser is full screen with the lights off, and nobody is
/// looking at the menu bar. So the update is offered here too — but as a
/// banner and not a modal, because a modal in the middle of a full-screen
/// visualiser is worse than the problem it solves, and the check must not
/// interrupt what is on screen.
///
/// Installing still takes two clicks: this button asks, and the alert that
/// follows asks again. "Later" puts the banner away, and the version is
/// remembered, so the hourly check does not put it back up.
struct UpdateBanner: View {
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        if let version = updater.availableVersion, updater.isUpdateBannerVisible {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.17, green: 0.95, blue: 1.0))

                Text("Vibresia \(version) is available")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Button("Install & Relaunch") { updater.installAvailableUpdate() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.17, green: 0.95, blue: 1.0))
                    .help("Install the update and start Vibresia again")

                Button("What's New") { updater.openReleaseNotes() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.65))
                    .help("Open the notes for this release")

                Button("Later") { updater.dismissUpdateBanner() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.45))
                    .help("Not now — the menu still has the update in it")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 100)
                    .fill(Color.black.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
