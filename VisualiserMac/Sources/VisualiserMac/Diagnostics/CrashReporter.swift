import AppKit
import Darwin
import Foundation

/// Catches crashes, keeps them on disk, and sends them to PostHog on the next
/// launch.
///
/// Two halves, because a process in the middle of a memory fault can't be
/// trusted to finish a network request:
///
///   1. `install()` puts a handler on the fatal signals (and on
///      `NSSetUncaughtExceptionHandler`). When one fires it writes a report to
///      `~/Library/Application Support/AudioVane/Crashes/` and then re-raises
///      with the default disposition, so macOS still writes its own `.ips` into
///      `~/Library/Logs/DiagnosticReports` exactly as it would have. Ours has
///      the app state and breadcrumbs; the system's has registers and images.
///   2. On the next launch `uploadPendingReports()` sends each report to
///      PostHog as an `app_crashed` event and deletes it — but only if the user
///      has anonymous usage switched on. Reports stay on disk either way, so
///      "Report a Problem…" can attach one by hand.
///
/// Band mode is where this earns its keep: it is a stage full of state
/// machines (genre cross-fade, per-musician hold timers, a sound classifier
/// feeding it) and a crash there is unreadable without knowing what that
/// state was at the time.
final class CrashReporter {
    static let shared = CrashReporter()

    /// Signals worth catching. SIGILL and SIGABRT are what a Swift runtime trap
    /// (`fatalError`, force-unwrapped nil, array out of range) turns into, and
    /// SIGTRAP is what it becomes on some architectures — either way it's a
    /// crash the user experienced, not a clean shutdown.
    private static let caughtSignals: [Int32] = [
        SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGTRAP,
    ]

    /// Where reports land. Also the folder "Reveal Crash Reports" opens, so it
    /// has to be somewhere a user can find without this file.
    static var reportsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("AudioVane/Crashes", isDirectory: true)
    }

    private static let maxBreadcrumbs = 200
    private static let maxFrameDepth = 64
    /// How many reports to keep on disk. Enough to cover a bug someone hits
    /// over a few weeks; not enough to grow forever on a visualiser that runs
    /// all day.
    private static let keptReports = 20
    /// Uploads per launch. A machine that crashes in a loop shouldn't spend a
    /// minute talking to PostHog about it.
    private static let uploadsPerLaunch = 3

    private static let uploadedKey = "audiovane.crashes.uploaded"

    /// Guards `breadcrumbs` and `state`. Also reached from a signal handler, so
    /// the handler uses `try()` and loses information rather than deadlocking
    /// against a main thread that was updating state when it crashed.
    private let lock = NSLock()
    private var breadcrumbs: [String] = []
    private var state: [String: String] = [:]
    private var installed = false
    private let startedAt = Date()

    private init() {}

    // MARK: - Setup

    func install() {
        lock.lock()
        let already = installed
        installed = true
        lock.unlock()
        guard !already else { return }

        let dir = Self.reportsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pruneOldReports()

        for sig in Self.caughtSignals {
            signal(sig, avCrashSignalHandler)
        }
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }
        log("session start on \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    // MARK: - Context

    /// Deliberate crash, so the whole report-and-upload path can be exercised
    /// from the command line (`--simulate-crash`) instead of waiting for a real
    /// band-mode fault to happen to somebody.
    func simulateCrash() {
        NSLog("[crash] simulating a crash on purpose")
        raise(SIGSEGV)
    }

    /// One line in the report's "last actions" list. Also goes to the unified
    /// log so the two can be read together.
    func log(_ message: String) {
        let line = "\(CrashReport.timestamp.string(from: Date())) \(message)"
        lock.lock()
        breadcrumbs.append(line)
        if breadcrumbs.count > Self.maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - Self.maxBreadcrumbs)
        }
        lock.unlock()
        NSLog("[crash] %@", message)
    }

    /// Replaces the app-state half of the next report. Called a couple of times
    /// a second at most — this is a snapshot, not a trace.
    func setState(_ newState: [String: String]) {
        lock.lock()
        state = newState
        lock.unlock()
    }

    /// What's known right now, for the "Report a Problem…" path when nothing
    /// has crashed.
    func currentSnapshot() -> (state: [String: String], breadcrumbs: [String]) {
        lock.lock()
        defer { lock.unlock() }
        return (state, breadcrumbs)
    }

    // MARK: - Crash handling

    fileprivate func handleSignal(_ sig: Int32) {
        // A fault inside the reporter must not recurse into another report: if
        // we're already writing one, hand straight back to the system.
        if avHandlingCrash {
            avReraise(sig)
            return
        }
        avHandlingCrash = true
        // Skip this handler, the C trampoline, its thunk and _sigtramp — what's
        // left is the code that actually faulted, which is the frame anyone
        // will want to look at.
        write(makeReport(kind: "signal", reason: avSignalName(sig), signal: sig,
                         exceptionReason: nil, skipFrames: 4))
        avReraise(sig)
    }

    fileprivate func handleException(_ exception: NSException) {
        if avHandlingCrash {
            avReraise(SIGABRT)
            return
        }
        avHandlingCrash = true
        let report = makeReport(
            kind: "exception",
            reason: exception.name.rawValue,
            signal: nil,
            exceptionReason: exception.reason,
            skipFrames: 0,
            extraFrames: Self.frames(from: exception.callStackSymbols, skipFirst: 3)
        )
        write(report)
        // No signal to re-raise: an NSException unwinds by returning here, and
        // AppKit turns it back into a crash on its own.
    }

    /// Back to the default disposition so the system writes its own report too.
    private func avReraise(_ sig: Int32) {
        signal(sig, SIG_DFL)
        raise(sig)
    }

    private func makeReport(kind: String, reason: String, signal sig: Int32?,
                            exceptionReason: String?, skipFrames: Int,
                            extraFrames: [CrashReport.Frame] = []) -> CrashReport {
        var snapshot: [String: String] = [:]
        var crumbs: [String] = []
        if lock.try() {
            snapshot = state
            crumbs = breadcrumbs
            lock.unlock()
        }

        var frames = Self.captureFrames(skip: skipFrames)
        if !extraFrames.isEmpty { frames.append(contentsOf: extraFrames) }

        let info = Bundle.main.infoDictionary ?? [:]
        return CrashReport(
            schema: CrashReport.currentSchema,
            id: UUID().uuidString,
            appName: (info["CFBundleName"] as? String) ?? "AudioVane",
            date: Date(),
            appVersion: info["CFBundleShortVersionString"] as? String ?? "0",
            appBuild: info["CFBundleVersion"] as? String ?? "0",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: CrashReport.arch,
            hostName: ProcessInfo.processInfo.hostName,
            uptimeSeconds: Date().timeIntervalSince(startedAt),
            kind: kind,
            reason: reason,
            signal: sig,
            exceptionReason: exceptionReason,
            frames: frames,
            state: snapshot,
            breadcrumbs: Array(crumbs.suffix(40))
        )
    }

    /// The stack we're standing on, right now, on whatever thread faulted.
    ///
    /// `backtrace()` and `dladdr()` aren't async-signal-safe — they allocate.
    /// Every alternative (a pre-allocated buffer walked by hand) needs a
    /// symbolizer we'd have to ship, and an unreadable report is worse than a
    /// report written from a slightly-risky call. In practice this runs once,
    /// on the way down, and the work it does is bounded.
    private static func captureFrames(skip: Int) -> [CrashReport.Frame] {
        var buffer = [UnsafeMutableRawPointer?](repeating: nil, count: maxFrameDepth)
        let captured = Int(backtrace(&buffer, Int32(maxFrameDepth)))
        guard captured > skip else { return [] }

        var frames: [CrashReport.Frame] = []
        frames.reserveCapacity(captured - skip)
        for i in skip..<captured {
            guard let addr = buffer[i] else { continue }
            var info = Dl_info()
            var symbol: String?
            var module: String?
            if dladdr(addr, &info) != 0 {
                if let name = info.dli_sname { symbol = String(cString: name) }
                if let image = info.dli_fname {
                    module = String(cString: image).split(separator: "/").last.map(String.init)
                }
            }
            frames.append(.init(address: "0x" + String(UInt(bitPattern: addr), radix: 16),
                                symbol: symbol,
                                module: module))
        }
        return frames
    }

    /// NSException hands us strings rather than addresses, so they go in as-is.
    private static func frames(from symbols: [String], skipFirst: Int) -> [CrashReport.Frame] {
        symbols.dropFirst(skipFirst).prefix(maxFrameDepth).map {
            CrashReport.Frame(address: $0, symbol: $0, module: nil)
        }
    }

    // MARK: - Storage

    @discardableResult
    private func write(_ report: CrashReport) -> URL? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(report) else { return nil }

        let dir = Self.reportsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(
            "AudioVane-\(CrashReport.stamp(report.date))-\(report.id.prefix(8)).crash.json")
        try? data.write(to: url, options: .atomic)
        NSLog("[crash] report written to %@", url.path)
        pruneOldReports()
        return url
    }

    private func pruneOldReports() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: Self.reportsDirectory,
                                                        includingPropertiesForKeys: [.contentModificationDateKey],
                                                        options: [.skipsHiddenFiles]) else { return }
        let dated = entries
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                guard let values, let date = values.contentModificationDate else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
        for (url, _) in dated.dropFirst(Self.keptReports) {
            try? fm.removeItem(at: url)
        }
    }

    /// Reports on disk, oldest first. Anything malformed is left alone and
    /// skipped — losing one unreadable file isn't worth deleting evidence.
    func pendingReports() -> [(url: URL, report: CrashReport)] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: Self.reportsDirectory,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles]) else { return [] }
        return entries
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                let decoder = JSONDecoder()
                // Must match the encoder below: reports are written with ISO
                // dates because they're read by humans and by email clients as
                // often as by this code.
                decoder.dateDecodingStrategy = .iso8601
                guard let data = try? Data(contentsOf: url),
                      let report = try? decoder.decode(CrashReport.self, from: data) else {
                    // Left on disk rather than deleted: losing one unreadable
                    // file isn't worth losing the evidence, and `pruneOldReports`
                    // will eventually take it with the rest.
                    NSLog("[crash] can't read %@ — left in place", url.lastPathComponent)
                    return nil
                }
                return (url, report)
            }
    }

    func latestReport() -> (url: URL, report: CrashReport)? {
        pendingReports().last
    }

    // MARK: - Upload

    /// Sends whatever the last run left behind. Deliberately gated on the same
    /// "Share anonymous usage" switch as everything else: a crash report is
    /// usage data by another name, and the switch is the user's decision.
    func uploadPendingReports() async {
        let reports = pendingReports()
        guard !reports.isEmpty else { return }
        guard await Analytics.shared.isConfigured else {
            NSLog("[crash] %d report(s) kept — no analytics in this build", reports.count)
            return
        }
        await Analytics.shared.bootstrapOptIn()
        guard await Analytics.shared.isEnabled else {
            NSLog("[crash] %d report(s) kept — anonymous usage is off", reports.count)
            return
        }

        var uploaded = Set(UserDefaults.standard.stringArray(forKey: Self.uploadedKey) ?? [])
        for (url, report) in reports.prefix(Self.uploadsPerLaunch) {
            if uploaded.contains(report.id) {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            await Analytics.shared.track("app_crashed", report.postHogProperties)
            // Only destroy the evidence once PostHog has confirmed it. A failed
            // send leaves the report on disk and it goes out next launch.
            guard await Analytics.shared.flushNow() else {
                NSLog("[crash] upload failed — %@ kept for next launch", report.id)
                break
            }
            uploaded.insert(report.id)
            try? FileManager.default.removeItem(at: url)
            NSLog("[crash] uploaded %@ (%@)", report.id, report.reason)
        }
        // Trim the memory of what we've sent so this stays a short list rather
        // than growing into a second backlog.
        if uploaded.count > 50 {
            uploaded = Set(uploaded.suffix(50))
        }
        UserDefaults.standard.set(Array(uploaded), forKey: Self.uploadedKey)
    }

    // MARK: - User-facing

    /// "Report a Problem…" — attach the most recent crash to a new email so the
    /// user can read it before it leaves their machine. With nothing on disk,
    /// send the current state instead, which is what a "it only happens when I
    /// …" report needs.
    @MainActor
    func composeProblemReport() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        let ask = "\n\n---\nWhat were you doing when it happened? What did you expect, and what happened instead?\n"

        if let (url, report) = latestReport() {
            let subject = "AudioVane crash — \(report.reason)"
            let body = report.summary + ask
            // The compose service attaches the file and pastes the body, so the
            // user can see exactly what's being sent before sending it.
            if let service = NSSharingService(named: .composeEmail) {
                service.subject = subject
                service.perform(withItems: [body, url])
                return
            }
            openMail(subject: subject, body: body + "\n\nThe full report is at:\n\(url.path)")
            return
        }

        let snap = currentSnapshot()
        openMail(subject: "AudioVane \(version) problem report",
                 body: CrashReport.stateOnlySummary(
                        appVersion: version,
                        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                        state: snap.state,
                        breadcrumbs: Array(snap.breadcrumbs.suffix(20))) + ask)
    }

    /// "Reveal Crash Reports…" — for someone who'd rather read the JSON (or
    /// attach it themselves) than write an email.
    @MainActor
    func revealReports() {
        let dir = Self.reportsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }

    /// Last resort when Mail isn't set up: a `mailto:` URL carries the summary
    /// in the body, no attachment.
    private func openMail(subject: String, body: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@minithlabs.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - C entry points

/// Signal handlers have to be plain C functions, so these can't touch `self`.
/// Globals rather than static properties: a handler that has to resolve a
/// `let` through the Swift runtime is one more thing to go wrong on the way
/// down.
nonisolated(unsafe) private var avHandlingCrash = false

private func avCrashSignalHandler(_ sig: Int32) {
    CrashReporter.shared.handleSignal(sig)
}

private func avSignalName(_ sig: Int32) -> String {
    switch sig {
    case SIGSEGV: return "SIGSEGV (bad memory access — the usual null / out-of-bounds crash)"
    case SIGBUS: return "SIGBUS (misaligned or unmapped memory access)"
    case SIGILL: return "SIGILL (illegal instruction — usually a Swift runtime trap: force-unwrapped nil, array out of range, integer overflow)"
    case SIGABRT: return "SIGABRT (abort — usually a failed precondition or an uncaught Objective-C exception)"
    case SIGFPE: return "SIGFPE (arithmetic fault — division by zero)"
    case SIGTRAP: return "SIGTRAP (runtime trap or debugger break)"
    default: return "signal \(sig)"
    }
}