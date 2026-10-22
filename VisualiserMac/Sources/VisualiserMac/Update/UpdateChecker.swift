import AppKit
import Foundation

/// Checks GitHub for a newer release every launch (and from the menu), and
/// installs it in place: download the release zip, unpack it, swap it for the
/// running app once we've quit, and relaunch.
///
/// Releases are published by `release.sh` as `Vibresia.zip` on
/// github.com/sydlawrencedev/vibresia. Builds are signed with a Developer ID
/// certificate and notarized, so the downloaded copy opens on its own; the
/// quarantine flag is still cleared before relaunching, which costs nothing
/// and is a fallback for a Mac that cannot validate the ticket.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let repo = "sydlawrencedev/vibresia"
    private static let assetName = "Vibresia.zip"

    /// How often the automatic check runs.
    private static let hourlyInterval: TimeInterval = 3600

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]
        struct Asset: Decodable { let name: String; let browser_download_url: String }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The version waiting to be installed, when one has been found.
    ///
    /// Set by the hourly check, which must not interrupt whatever is on
    /// screen — a visualiser that is full screen with the lights off does
    /// not want a modal in the middle of it. So it is offered in a banner
    /// that sits at the top of the window, and the menu says so too, and
    /// the install happens when somebody asks for it.
    @Published private(set) var availableVersion: String?

    /// Whether the banner is on screen.
    ///
    /// The banner is the visible part of the prompt. It is not a modal, so
    /// it can be up while the app is being used, and it can be put away
    /// without installing anything.
    @Published private(set) var isUpdateBannerVisible = false

    /// The release behind it, so the install can be started from the menu
    /// without asking GitHub again.
    private var availableRelease: Release?

    /// The version somebody said "Later" to. Not offered again on its own.
    ///
    /// It is remembered across restarts as well: a prompt that comes back
    /// every time the app is opened is a prompt nobody reads, and the
    /// version is still in the menu for whoever wants it.
    private var declinedVersion: String? {
        get { UserDefaults.standard.string(forKey: Self.declinedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.declinedKey) }
    }

    /// Where the declined version is remembered.
    private static let declinedKey = "vibresia.declinedUpdateVersion"

    /// Puts the banner away without installing anything.
    ///
    /// The version is remembered, so the hourly check does not put the
    /// banner back up for the same release. A newer one will.
    func dismissUpdateBanner() {
        if let version = availableVersion { declinedVersion = version }
        isUpdateBannerVisible = false
    }

    /// Opens the release notes for the update that is waiting.
    func openReleaseNotes() {
        guard let url = availableRelease?.html_url, let link = URL(string: url) else { return }
        NSWorkspace.shared.open(link)
    }

    /// A check that is already running. Two at once is two requests for one
    /// answer, and the second one to arrive is the one that wins.
    private var isChecking = false

    /// The timer behind the hourly check.
    private var hourlyTimer: Timer?

    /// Starts the hourly check, once, for the life of the app.
    ///
    /// A timer on the main run loop does not wake a sleeping Mac, and a
    /// run loop that was asleep for three hours fires it once rather than
    /// three times — which is what "do not wake a sleeping Mac, and after
    /// waking perform at most one overdue check" comes down to.
    func startHourlyChecks() {
        guard hourlyTimer == nil else { return }
        let timer = Timer(timeInterval: Self.hourlyInterval, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        // Two minutes of slack: a check that is a few minutes late is still
        // on time, and the system can move it to a moment when the Mac is
        // awake and busy with something else.
        timer.tolerance = 120
        // Common mode, so the timer keeps running while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        hourlyTimer = timer
        NSLog("[UPDATE] checking every hour as well as at launch")
    }

    /// Pretends there is a newer release, for checking the update flow
    /// without publishing one.
    ///
    /// The app is usually up to date, so the state the hourly check leaves
    /// behind is the part that never gets seen. `--update-spike` puts it
    /// there on purpose.
    private var isSpiking: Bool {
        CommandLine.arguments.contains("--update-spike")
    }

    /// `userInitiated`: from the menu — also report "you're up to date" and errors.
    func check(userInitiated: Bool) {
        if !userInitiated && ProcessInfo.processInfo.environment["VIBRESIA_NO_UPDATE_CHECK"] != nil { return }
        // One at a time. The manual check and the hourly one can land on
        // each other, and the answer should not be fetched twice.
        guard !isChecking else { return }
        isChecking = true
        if userInitiated {
            Task {
                await Analytics.shared.track("update_check_requested")
                await Analytics.shared.logToPostHog("manual update check requested")
            }
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, error in
            let release = data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
            DispatchQueue.main.async {
                // The check is over, one way or another — so the next one
                // can start.
                self.isChecking = false
                guard let release else {
                    if userInitiated {
                        Task {
                            await Analytics.shared.logToPostHog(
                                "manual update check failed",
                                attributes: ["reason": "release_metadata_unavailable"])
                        }
                        self.alert("Couldn't check for updates", error?.localizedDescription ?? "No release information found.")
                    }
                    return
                }
                var latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if self.isSpiking {
                    // A version that is definitely newer than this build, in
                    // the same date scheme — an odd one would be read as an
                    // old-style version and compared the other way round.
                    latest = "1.0.101"
                }
                guard Self.isNewer(latest, than: self.currentVersion) else {
                    if userInitiated {
                        Task {
                            await Analytics.shared.logToPostHog(
                                "manual update check completed",
                                attributes: ["update_available": false])
                        }
                        self.alert("You're up to date", "Vibresia \(self.currentVersion) is the latest version.")
                    }
                    return
                }
                if userInitiated {
                    Task {
                        await Analytics.shared.logToPostHog(
                            "manual update check completed",
                            attributes: ["update_available": true, "latest_version": latest])
                    }
                    self.offer(latest, release: release)
                    return
                }
                // The hourly check does not ask with a modal. A visualiser
                // that is full screen in a dark room should not have one
                // appear in the middle of it, so the update is offered in a
                // banner at the top of the window and in the menu, and the
                // install happens when somebody asks for it.
                //
                // A version somebody has already said "Later" to is not
                // offered again on its own — but it stays in the menu, so
                // the update is one click away for whoever wants it.
                let declined = self.declinedVersion == latest
                self.availableVersion = latest
                self.availableRelease = release
                if !declined {
                    self.isUpdateBannerVisible = true
                }
                NSLog("[UPDATE] found \(latest) — offering it in the banner and the menu")
                Task {
                    await Analytics.shared.logToPostHog(
                        "update found by the hourly check",
                        attributes: ["latest_version": latest])
                }
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        // Versions are dates, and the patch packs the day and the build
        // number together — so they're compared as a day and a build rather
        // than as one number. See AppVersion.
        if let va = AppVersion(a), let vb = AppVersion(b) {
            return va.isNewer(than: vb)
        }
        // Anything unparseable falls back to a plain numeric comparison.
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Installs the update that was found, if there is one.
    ///
    /// This is the explicit action the hourly check waits for: the menu says
    /// an update is there, and clicking it is somebody asking for it.
    func installAvailableUpdate() {
        guard let version = availableVersion, let release = availableRelease else {
            check(userInitiated: true)
            return
        }
        offer(version, release: release)
    }

    private func offer(_ version: String, release: Release) {
        let a = NSAlert()
        a.messageText = "Vibresia \(version) is available"
        a.informativeText = "You have \(currentVersion). Install the update now? Vibresia will restart."
        a.addButton(withTitle: "Install & Relaunch")
        a.addButton(withTitle: "Later")
        a.addButton(withTitle: "What's New")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            guard let asset = release.assets.first(where: { $0.name == Self.assetName }),
                  let url = URL(string: asset.browser_download_url) else {
                alert("Update not available", "This release has no \(Self.assetName) download.")
                return
            }
            Task {
                await Analytics.shared.track("update_install_started", [
                    "from_version": currentVersion,
                    "to_version": version,
                ])
            }
            install(from: url)
        case .alertThirdButtonReturn:
            Task { await Analytics.shared.track("update_release_notes_opened", ["version": version]) }
            if let url = URL(string: release.html_url) { NSWorkspace.shared.open(url) }
        default:
            // "Later" means later: the same release is not offered again
            // on its own, so the hourly check stops mentioning it.
            declinedVersion = version
            availableVersion = nil
            availableRelease = nil
            break
        }
    }

    private func install(from url: URL) {
        URLSession.shared.downloadTask(with: url) { file, _, error in
            do {
                guard let file else { throw error ?? URLError(.badServerResponse) }
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("vibresia-update-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent(Self.assetName)
                try FileManager.default.moveItem(at: file, to: zip)
                try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
                guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                        .first(where: { $0.pathExtension == "app" }) else { throw URLError(.cannotDecodeContentData) }
                DispatchQueue.main.async { self.swapAndRelaunch(newApp: newApp, scratch: work) }
            } catch {
                DispatchQueue.main.async { self.alert("Update failed", error.localizedDescription) }
            }
        }.resume()
    }

    /// Hands over to a tiny script that waits for us to quit, replaces the
    /// app bundle, clears quarantine and opens the new one.
    private func swapAndRelaunch(newApp: URL, scratch: URL) {
        let dest = Bundle.main.bundleURL.path
        let script = scratch.appendingPathComponent("swap.sh")
        let body = """
        #!/bin/bash
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(dest).old"
        mv "\(dest)" "\(dest).old" && mv "\(newApp.path)" "\(dest)" && rm -rf "\(dest).old"
        xattr -dr com.apple.quarantine "\(dest)" 2>/dev/null
        open "\(dest)"
        """
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script.path]
            try p.run()
            NSApp.terminate(nil)
        } catch {
            alert("Update failed", error.localizedDescription)
        }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
