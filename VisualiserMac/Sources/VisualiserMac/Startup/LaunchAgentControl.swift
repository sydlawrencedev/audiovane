import Foundation

/// A user LaunchAgent: a plist in `~/Library/LaunchAgents` that launchd runs at
/// login.
///
/// Written by hand rather than through `SMAppService`, for two reasons. The
/// agent has to point at a binary *inside* the app bundle, and a plist inside
/// the bundle can't say "next to me" — the app lands in `/Applications` or
/// `~/Applications` depending on permissions, so the path is only knowable at
/// runtime. And `SMAppService` refuses to register an ad-hoc-signed app at all
/// ("Operation not permitted"), which is what AudioVane ships as today.
///
/// That second reason means `StartupManager` tries `SMAppService` first and
/// falls back to this — the supported API is preferred in case the app ever
/// gets notarised, and the plist is what actually works until then.
struct LaunchAgentControl {
    let label: String
    let enabledKey: String
    /// Path of the executable to run, or nil when this build can't (a bare
    /// `swift build`, say) — a reason to say so rather than install an agent
    /// that can't start.
    let executable: () -> String?
    /// Anything after the executable. Absolute paths here are deliberate: the
    /// agent survives the app being moved because it is rewritten on next
    /// launch.
    let arguments: [String]

    enum Failure: LocalizedError {
        case missingExecutable
        case loadFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingExecutable:
                return "This build doesn't include the helper this option needs."
            case .loadFailed:
                return "macOS refused to start it. It may be blocked in Login Items."
            case .writeFailed(let why):
                return "Couldn't write the LaunchAgent: \(why)"
            }
        }
    }

    // MARK: - Paths

    private static var library: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
    }

    var plistURL: URL {
        Self.library.appendingPathComponent("LaunchAgents/\(label).plist")
    }

    var logURL: URL {
        let dir = Self.library.appendingPathComponent("Logs/AudioVane", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(label).log")
    }

    // MARK: - State

    /// The user's choice, as opposed to what's installed. Reading them
    /// separately is what lets the UI say "on, but the agent isn't there"
    /// instead of silently snapping back to off.
    var isWanted: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }
    var isLoaded: Bool { (try? run(["print", "gui/\(getuid())/\(label)"])) == 0 }

    /// What the user sees as the switch position.
    var isOn: Bool { isWanted && isInstalled }

    // MARK: - Actions

    /// Writes the plist and loads it. Safe to call repeatedly: an unchanged,
    /// loaded agent is left alone rather than bounced, so turning the app off
    /// and on doesn't leave a stale process behind.
    @discardableResult
    func install() -> Result<Void, Failure> {
        guard let executable = executable() else { return .failure(.missingExecutable) }

        if (try? String(contentsOf: plistURL, encoding: .utf8)) == plistContents(executable: executable),
           isLoaded {
            NSLog("[\(label)] already installed")
            return .success(())
        }

        // Remove first: launchd holds the old job until it's booted out, and
        // rewriting the file under a loaded agent leaves the old process
        // running against a plist it has already read.
        unload()

        do {
            try plistContents(executable: executable).write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[\(label)] could not write plist: \(error.localizedDescription)")
            return .failure(.writeFailed(error.localizedDescription))
        }

        guard load() else { return .failure(.loadFailed) }
        NSLog("[\(label)] installed at \(plistURL.path)")
        return .success(())
    }

    @discardableResult
    func uninstall() -> Result<Void, Failure> {
        unload()
        do {
            try FileManager.default.removeItem(at: plistURL)
        } catch {
            // Already gone is the state we were aiming for.
            if (error as NSError).code != NSFileNoSuchFileError {
                NSLog("[\(label)] could not remove plist: \(error.localizedDescription)")
                return .failure(.writeFailed(error.localizedDescription))
            }
        }
        NSLog("[\(label)] removed")
        return .success(())
    }

    /// Re-installs when the user wants it but the agent has gone missing or
    /// points at a path that no longer exists — after the in-app updater swaps
    /// the bundle, after the app is dragged to another folder, after a manual
    /// delete, or after the user disables it in Login Items.
    @discardableResult
    func reconcile() -> Result<Void, Failure> {
        guard isWanted else { return .success(()) }
        guard let executable = executable() else { return .failure(.missingExecutable) }
        if (try? String(contentsOf: plistURL, encoding: .utf8)) == plistContents(executable: executable),
           isLoaded {
            return .success(())
        }
        NSLog("[\(label)] repairing — agent missing, stale or not loaded")
        return install()
    }

    // MARK: - launchd

    private func load() -> Bool {
        // `bootstrap` is the modern form; `load` is the older spelling that
        // prints a deprecation warning on newer macOS.
        (try? run(["bootstrap", "gui/\(getuid())", plistURL.path])) == 0
    }

    private func unload() {
        _ = try? run(["bootout", "gui/\(getuid())/\(label)"])
    }

    @discardableResult
    private func run(_ args: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: - plist

    private func plistContents(executable: String) -> String {
        let arguments = ([executable] + arguments)
            .map { "                <string>\($0)</string>" }
            .joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
        \(arguments)
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
            <key>StandardOutPath</key>
            <string>/dev/null</string>
            <key>StandardErrorPath</key>
            <string>\(logURL.path)</string>
        </dict>
        </plist>
        """
    }
}

/// The agent that opens AudioVane when Apple Music or Spotify starts.
enum WatcherControl {
    static let agent = LaunchAgentControl(
        label: "com.minithlabs.visualiser.music-watch",
        enabledKey: "audiovane.musicWatch.enabled",
        executable: { helperPath },
        arguments: [Bundle.main.bundleURL.path]
    )

    static let label = agent.label
    static let defaultsKey = agent.enabledKey

    /// Path of the bundled helper, or nil in a build that doesn't have it.
    static var helperPath: String? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AudioVaneWatcher")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url.path : nil
    }
}

/// The login item: the app itself, relaunched at login.
enum LoginItem {
    static let agent = LaunchAgentControl(
        label: "com.minithlabs.visualiser.login",
        enabledKey: "audiovane.launchAtLogin.enabled",
        executable: { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/AudioVane").path },
        arguments: []
    )
}