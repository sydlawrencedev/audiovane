import Foundation
import SwiftUI

/// The two things that decide when AudioVane is running: whether it opens at
/// login, and whether it opens when a music app does.
///
/// Both are off until asked for. A visualiser that appears uninvited — at
/// login, or every time a track starts — is the kind of thing people
/// uninstall, so this is opt-in and visibly so.
///
/// Both are ordinary login items in `~/Library/LaunchAgents`, and both are
/// switched off from here and nowhere else. macOS's own `SMAppService` is the
/// tidier API, but it refuses to register an app that isn't properly signed —
/// which AudioVane isn't — so using it would mean two code paths and, worse,
/// the possibility of the same thing being registered twice. One mechanism,
/// one switch, one place to look.
@MainActor
final class StartupManager: ObservableObject {
    static let shared = StartupManager()

    @Published private(set) var launchAtLogin = false
    @Published private(set) var watchMusicApps = false
    /// Shown under the toggles when something didn't work. Empty is the good
    /// case; a failure the user can't see is worse than no feature.
    @Published private(set) var errorMessage: String?

    /// Captions under each toggle.
    private(set) var launchAtLoginDetail = "Open AudioVane when you log in"
    private(set) var watchMusicAppsDetail = "Open AudioVane when Music or Spotify starts"

    private init() {}

    // MARK: - Reading current state

    /// Reads both switches back from launchd rather than from our own defaults,
    /// so the switch shows what's true — including after the user deleted an
    /// agent by hand or disabled it in Login Items.
    func refresh() {
        launchAtLogin = LoginItem.agent.isOn
        watchMusicApps = WatcherControl.agent.isOn
        launchAtLoginDetail = Self.detail(for: LoginItem.agent,
                                          describing: "Open AudioVane when you log in")
        watchMusicAppsDetail = Self.detail(for: WatcherControl.agent,
                                          describing: "Open AudioVane when Music or Spotify starts")
    }

    /// The caption is the same sentence either way — the switch says on or off.
    /// The third case is the one worth saying out loud: the user asked for it,
    /// and it isn't there.
    private static func detail(for agent: LaunchAgentControl, describing what: String) -> String {
        if agent.isOn { return what }
        return agent.isWanted ? "Couldn't be installed — turn this off and on again" : what
    }

    /// Called on every launch: the in-app updater replaces the bundle, which
    /// moves the watcher helper and rewrites the login item's own path, so both
    /// agents have to be put back where they point.
    func reconcile() {
        var problems: [String] = []
        if case .failure(let error) = LoginItem.agent.reconcile() {
            problems.append(error.localizedDescription)
            NSLog("[startup] login item reconcile failed: \(error.localizedDescription)")
        }
        if case .failure(let error) = WatcherControl.agent.reconcile() {
            problems.append(error.localizedDescription)
            NSLog("[startup] watcher reconcile failed: \(error.localizedDescription)")
        }
        errorMessage = problems.isEmpty ? nil : problems.joined(separator: " ")
        refresh()
    }

    // MARK: - Turning them on and off

    func setLaunchAtLogin(_ on: Bool) {
        apply(on, to: LoginItem.agent)
        refresh()
    }

    func setWatchMusicApps(_ on: Bool) {
        apply(on, to: WatcherControl.agent)
        refresh()
    }

    /// Records the choice first, then makes it true, and undoes the choice if
    /// it couldn't be: the switch and the stored preference have to agree, or
    /// the next launch repairs something the user never asked for.
    private func apply(_ on: Bool, to agent: LaunchAgentControl) {
        UserDefaults.standard.set(on, forKey: agent.enabledKey)
        let result = on ? agent.install() : agent.uninstall()
        switch result {
        case .success:
            errorMessage = nil
        case .failure(let error):
            UserDefaults.standard.set(false, forKey: agent.enabledKey)
            errorMessage = error.localizedDescription
            NSLog("[startup] \(agent.label) failed: \(error.localizedDescription)")
        }
    }

    static let watchedApps = ["Apple Music", "Spotify"]
}