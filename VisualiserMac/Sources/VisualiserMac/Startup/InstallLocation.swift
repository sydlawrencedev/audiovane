import Foundation
import AppKit

/// Where the app is running from, and what to do about it.
///
/// An app that lives in a folder somewhere — unzipped from a download, or
/// opened off a disk image — is a guest in a directory that might be tidied
/// away, and it cannot update itself in place. Applications is where it
/// belongs, and the installer puts it there anyway, so the app offering to
/// do the same is doing the obvious thing rather than anything clever.
///
/// There is a wrinkle that makes this more than a file move. A downloaded
/// app is quarantined, and macOS runs a quarantined app from a temporary
/// read-only copy of itself rather than from where it sits — so the app is
/// usually not even running from the folder the user unzipped it into. That
/// copy cannot be moved (the volume is read-only) and macOS deletes it
/// anyway. So the app is copied to Applications, the quarantine flag is
/// taken off the copy, and the new copy is what gets launched.
enum InstallLocation {

    enum Status: Equatable {
        /// In /Applications or ~/Applications: where it belongs.
        case installed
        /// Running from somewhere else, and it can be put right.
        case elsewhere(current: URL, translocated: Bool)
    }

    enum Failure: LocalizedError {
        case destinationUnavailable
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .destinationUnavailable:
                return "Applications isn't writable and ~/Applications couldn't be created."
            case .copyFailed(let why):
                return "Couldn't copy the app: \(why)"
            }
        }
    }

    /// Where the app would be launched from after being moved.
    static var pendingRelaunch: URL?

    static var bundleURL: URL { Bundle.main.bundleURL }

    /// The directories an app is expected to live in. The user's own
    /// ~/Applications is here because that is where the installer puts it
    /// when /Applications isn't writable.
    static var applicationDirectories: [URL] {
        var directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
        if let override = ProcessInfo.processInfo.environment["VIBRESIA_APPLICATIONS_DIR"] {
            directories.append(URL(fileURLWithPath: override, isDirectory: true))
        }
        return directories
    }

    /// Whether the app is where it should be.
    static var status: Status {
        let bundle = bundleURL
        let parent = bundle.deletingLastPathComponent().standardizedFileURL
        for directory in applicationDirectories
        where parent == directory.standardizedFileURL {
            return .installed
        }
        return .elsewhere(current: bundle, translocated: isTranslocated(bundle))
    }

    /// A quarantined app is run from a copy macOS makes in a temporary
    /// folder, not from where it actually sits.
    static func isTranslocated(_ url: URL) -> Bool {
        url.path.contains("/AppTranslocation/")
    }

    /// Where the app is now, in words a person can read. The temporary
    /// folder macOS makes is called out as such rather than printed as a
    /// path nobody recognises.
    static func describeCurrentLocation() -> String {
        switch status {
        case .installed:
            return "Applications"
        case .elsewhere(let current, let translocated):
            if translocated { return "a temporary folder" }
            let folder = current.deletingLastPathComponent()
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if folder.path.hasPrefix(home) {
                return "~" + folder.path.dropFirst(home.count)
            }
            return folder.path
        }
    }

    /// Where the app should go. /Applications if it can be written to, and
    /// the user's own otherwise — which is what the installer does too.
    ///
    /// `VIBRESIA_APPLICATIONS_DIR` points it somewhere else, so the move can
    /// be rehearsed without installing anything real.
    static var destinationDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["VIBRESIA_APPLICATIONS_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: system.path) { return system }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    }

    /// Copies the app to Applications and returns where it ended up.
    ///
    /// A copy rather than a move, because the app is usually running from a
    /// read-only temporary copy that macOS is going to delete anyway, and
    /// because copying leaves the running app working right up until the new
    /// one takes over.
    static func install() -> Result<URL, Failure> {
        let bundle = bundleURL
        let directory = destinationDirectory

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(.destinationUnavailable)
        }

        let target = directory.appendingPathComponent(bundle.lastPathComponent)

        // Put an existing copy aside rather than deleting it before the new
        // one is in place: a copy that fails halfway should not leave the
        // user with no app at all.
        var displaced: URL?
        if FileManager.default.fileExists(atPath: target.path) {
            displaced = directory.appendingPathComponent(".Vibresia-replaced-\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: target, to: displaced!)
            } catch {
                return .failure(.copyFailed(error.localizedDescription))
            }
        }

        do {
            try FileManager.default.copyItem(at: bundle, to: target)
        } catch {
            if let displaced { try? FileManager.default.moveItem(at: displaced, to: target) }
            return .failure(.copyFailed(error.localizedDescription))
        }

        // The quarantine flag has to come off. It is what made macOS run the
        // app from a temporary copy in the first place, and a quarantined
        // app in Applications gets translocated too — the move would put it
        // straight back where it started.
        //
        // Only that one attribute: com.apple.macl is what ties the app to
        // the privacy permissions it has already been given, and stripping
        // it would mean asking for screen recording all over again.
        clearQuarantine(at: target)

        if let displaced { try? FileManager.default.removeItem(at: displaced) }
        return .success(target)
    }

    /// Removes the quarantine flag from a bundle and everything in it.
    static func clearQuarantine(at bundle: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-dr", "com.apple.quarantine", bundle.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    /// Opens the app at a path, as a new instance.
    ///
    /// `open -n` rather than `open`, because the running app has the same
    /// bundle identifier and plain `open` would just bring that one to the
    /// front instead of starting the one we want.
    static func launch(at url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
