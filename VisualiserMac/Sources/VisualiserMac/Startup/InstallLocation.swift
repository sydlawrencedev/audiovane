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
        /// Running from the Downloads folder — the app somebody downloaded.
        /// `source` is the copy in Downloads, which is not always the one
        /// running: macOS runs a quarantined app from a temporary copy of
        /// itself.
        case inDownloads(source: URL)
        /// Somewhere else. Not worth interrupting anybody about: a build
        /// directory, a disk image, a folder on the desktop.
        case elsewhere
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

    /// The bundle identifier, used to check that a file in Downloads is
    /// really this app and not something else that happens to share its
    /// name.
    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "" }

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

    /// Where downloads land.
    static var downloadsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    /// Whether the app is where it should be, or in the Downloads folder
    /// where a download lands.
    ///
    /// Only Downloads counts. The app is not worth interrupting somebody
    /// about because it is in a build directory or on a disk image — and
    /// offering to move an app out of a disk image is not something it can
    /// do anyway.
    static var status: Status {
        let bundle = bundleURL
        let parent = bundle.deletingLastPathComponent().standardizedFileURL
        for directory in applicationDirectories
        where parent == directory.standardizedFileURL {
            return .installed
        }

        // The obvious case: the bundle really is in Downloads.
        if parent == downloadsDirectory.standardizedFileURL {
            return .inDownloads(source: bundle)
        }

        // The common case: macOS runs a quarantined app from a temporary
        // copy of itself, so the path is a temporary folder even when the
        // app the user downloaded is sitting in Downloads. The copy is the
        // signal that this came from a download at all, and Downloads is
        // where a download lands.
        //
        // There is no way to ask macOS where the original was — the
        // temporary copy is a real copy on a read-only mount, not a link
        // back — so the copy in Downloads is looked for instead.
        guard isTranslocated(bundle) else { return .elsewhere }
        guard let source = copyInDownloads() else { return .elsewhere }
        return .inDownloads(source: source)
    }

    /// A copy of this app in the Downloads folder, if there is one.
    static func copyInDownloads() -> URL? {
        let candidate = downloadsDirectory
            .appendingPathComponent(bundleURL.lastPathComponent)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        // Same name is not enough — check it really is this app, so a
        // different bundle that happens to be called Vibresia.app is not
        // mistaken for it.
        let bundle = Bundle(url: candidate)
        guard bundle?.bundleIdentifier == bundleIdentifier else { return nil }
        return candidate
    }

    /// A quarantined app is run from a copy macOS makes in a temporary
    /// folder, not from where it actually sits.
    static func isTranslocated(_ url: URL) -> Bool {
        url.path.contains("/AppTranslocation/")
    }

    /// Where the app is now, in words a person can read.
    static func describeCurrentLocation() -> String {
        switch status {
        case .installed:
            return "Applications"
        case .inDownloads:
            return "Downloads"
        case .elsewhere:
            return bundleURL.deletingLastPathComponent().path
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

    /// Removes the copy in Downloads, now that there is one in Applications.
    ///
    /// Only ever the copy in Downloads, and only if it really is this app —
    /// the same bundle identifier — so nothing else that happens to be
    /// called Vibresia.app is touched.
    ///
    /// This is done by the instance running from Applications rather than by
    /// the one that is moving: the instance that is moving is, in the case
    /// that matters, running from that very copy, and deleting the files
    /// under a running application is asking for trouble.
    static func removeDownloadedCopy() {
        // Looked for directly rather than through `status`, which is about
        // where the *running* app is — and by now that is Applications, which
        // is the whole point.
        guard let source = copyInDownloads() else { return }
        guard source != bundleURL else { return }
        try? FileManager.default.removeItem(at: source)
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
