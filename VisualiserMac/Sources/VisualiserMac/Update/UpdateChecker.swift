import AppKit
import Foundation

/// Checks GitHub for a newer release every launch (and from the menu), and
/// installs it in place: download the release zip, unpack it, swap it for the
/// running app once we've quit, and relaunch.
///
/// Releases are published by `release.sh` as `AudioVane.zip` on
/// github.com/sydlawrencedev/audiovane. Builds are ad-hoc signed, so the
/// downloaded copy has its quarantine flag cleared before relaunching.
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repo = "sydlawrencedev/audiovane"
    private static let assetName = "AudioVane.zip"

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]
        struct Asset: Decodable { let name: String; let browser_download_url: String }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// `userInitiated`: from the menu — also report "you're up to date" and errors.
    func check(userInitiated: Bool) {
        if !userInitiated && ProcessInfo.processInfo.environment["AUDIOVANE_NO_UPDATE_CHECK"] != nil { return }
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
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard Self.isNewer(latest, than: self.currentVersion) else {
                    if userInitiated {
                        Task {
                            await Analytics.shared.logToPostHog(
                                "manual update check completed",
                                attributes: ["update_available": false])
                        }
                        self.alert("You're up to date", "AudioVane \(self.currentVersion) is the latest version.")
                    }
                    return
                }
                if userInitiated {
                    Task {
                        await Analytics.shared.logToPostHog(
                            "manual update check completed",
                            attributes: ["update_available": true, "latest_version": latest])
                    }
                }
                self.offer(latest, release: release)
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

    private func offer(_ version: String, release: Release) {
        let a = NSAlert()
        a.messageText = "AudioVane \(version) is available"
        a.informativeText = "You have \(currentVersion). Install the update now? AudioVane will restart."
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
            break
        }
    }

    private func install(from url: URL) {
        URLSession.shared.downloadTask(with: url) { file, _, error in
            do {
                guard let file else { throw error ?? URLError(.badServerResponse) }
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("audiovane-update-\(UUID().uuidString)")
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
