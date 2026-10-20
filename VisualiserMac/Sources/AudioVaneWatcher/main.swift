import AppKit
import Foundation

/// Watches for Apple Music and Spotify starting, and opens Vibresia when they
/// do. Runs as a launchd agent installed by `WatcherControl` (or by hand — see
/// the README); the app itself can't do this job, because an app that isn't
/// running has no way to hear about anything.
///
/// It is a separate, tiny, invisible process rather than a second mode of the
/// main app for two reasons: the main app is a windowed OpenGL surface that
/// would be expensive to keep resident, and a watcher that lives in the app
/// can't catch the launch that would start the app.
///
/// Usage:
///     VibresiaWatcher [--check] [path/to/Vibresia.app]
///
/// `--check` prints what it would do and exits, which is how you tell a
/// working agent from one whose binary path has gone stale.

let targetBundleID = "com.minithlabs.visualiser"

/// The apps worth opening a visualiser for. Spotify's identifier has changed
/// once already, so this also matches on the process name when the bundle id
/// isn't what we expect.
let watched: [String: [String]] = [
    "com.apple.Music": ["Music"],
    "com.spotify.client": ["Spotify"],
]

func log(_ message: String) {
    NSLog("[watcher] %@", message)
}

/// Where Vibresia lives. Ask Launch Services first — it survives the app being
/// moved or installed somewhere unusual — and fall back to the path the
/// installer recorded in the plist.
func locateVibresia(fallback: String?) -> URL? {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleID) {
        return url
    }
    if let fallback, FileManager.default.fileExists(atPath: fallback) {
        return URL(fileURLWithPath: fallback)
    }
    return nil
}

func openVibresia(fallback: String?) {
    if NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).isEmpty {
        guard let app = locateVibresia(fallback: fallback) else {
            log("can't find Vibresia to open (bundle id \(targetBundleID))")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: config) { _, error in
            if let error { log("open failed: \(error.localizedDescription)") }
            else { log("opened Vibresia") }
        }
    }
}

// --- Modes -----------------------------------------------------------------

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--check") {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID)
    let app = locateVibresia(fallback: arguments.first)
    print("Vibresia at: \(app?.path ?? "not found")")
    print("Vibresia running: \(running.isEmpty ? "no" : "yes")")
    print("watching: \(watched.keys.sorted().joined(separator: ", "))")
    exit(0)
}

// --- Watching --------------------------------------------------------------

let center = NSWorkspace.shared.notificationCenter

center.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil,
    queue: .main
) { note in
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
    guard let bundleID = app.bundleIdentifier else { return }

    // Spotify ships under more than one id across versions; treat any of them
    // as a match, and fall back to the process name for the times it ships
    // without an id at all.
    let isWatched = watched[bundleID] != nil
        || watched.values.contains { $0.contains(app.localizedName ?? "") }
    guard isWatched else { return }

    let name = app.localizedName ?? bundleID
    log("\(name) launched — opening Vibresia")
    openVibresia(fallback: arguments.first)
}

log("watching for Apple Music and Spotify (pid \(ProcessInfo.processInfo.processIdentifier))")
NSApplication.shared.setActivationPolicy(.accessory)
NSApp.run()