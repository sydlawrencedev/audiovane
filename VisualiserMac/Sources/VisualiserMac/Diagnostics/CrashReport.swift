import Foundation

/// One crash, as written to disk at the moment the process died.
///
/// Written by the signal / exception handler, so it has to stay small and
/// dependency-free: no network, no MainActor, nothing that can allocate its
/// way into a second fault. Read back on the next launch, when there is a
/// whole process available to decide whether to upload it.
///
/// The point of this file is the part the system's own `.ips` can't have.
/// "SIGSEGV" on its own is a shrug; SIGSEGV *with the genre on stage, four
/// musicians up, a cross-fade half finished and the last dozen actions
/// leading up to it* is a bug report. Everything here is app state — vibscape,
/// genre, lineup, our own backtrace. Nothing derived from what the user is
/// watching or listening to goes in: no track names, no audio, no screen
/// content. Same line the analytics client draws.
struct CrashReport: Codable {
    static let currentSchema = 1

    struct Frame: Codable {
        /// Hex address, so a frame can be symbolicated later by someone who has
        /// the matching binary.
        let address: String
        /// `dladdr`'s nearest symbol. Swift symbols are mangled, but
        /// `$s11AudioVane12OpenGLRenderer...` is still a starting point.
        let symbol: String?
        /// Binary the frame belongs to, so a Foundation frame can be told apart
        /// from ours at a glance.
        let module: String?

        var display: String {
            guard let symbol else { return address }
            guard let module else { return symbol }
            return "\(symbol) (\(module))"
        }
    }

    let schema: Int
    /// Stable id, so a report that fails to upload isn't uploaded twice.
    let id: String
    /// The app's display name. A report is worthless if you can't tell which
    /// app it came from — a bare signal number reads the same coming out of
    /// anything on the machine — so this is field zero.
    let appName: String
    let date: Date
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let arch: String
    /// Stays out of anything uploaded — see `postHogProperties`.
    let hostName: String
    let uptimeSeconds: Double
    /// `signal` or `exception`.
    let kind: String
    /// "SIGSEGV", "EXC_BAD_ACCESS", or the NSException's name.
    let reason: String
    let signal: Int32?
    /// NSException reason string, when there is one.
    let exceptionReason: String?
    let frames: [Frame]
    /// What was on screen: vibscape, genre, palette, band lineup, audio source.
    let state: [String: String]
    let breadcrumbs: [String]

    /// Frames as PostHog sees them — one property, oldest frame last, so the
    /// interesting end reads first.
    var frameChain: String {
        frames.prefix(12).map(\.display).joined(separator: " <- ")
    }

    /// The upload payload. Deliberately a summary: PostHog is for spotting
    /// patterns across installs, and the full JSON stays on the user's disk
    /// where they can attach it to a bug report.
    ///
    /// The machine name is the one thing cut from the report on the way out.
    /// The analytics rule here is "identifies an install, not a person", and a
    /// hostname is closer to a name than to an install.
    var postHogProperties: [String: Any] {
        var props: [String: Any] = [
            "report_id": id,
            "app_name": appName,
            "kind": kind,
            "reason": reason,
            "uptime_seconds": Int(uptimeSeconds),
        ]
        if let exceptionReason, !exceptionReason.isEmpty {
            props["exception_reason"] = exceptionReason
        }
        for key in ["mode", "drawing", "genre", "source", "band_on_stage", "band_singers"] {
            if let value = state[key], !value.isEmpty { props[key] = value }
        }
        let frames = frameChain
        if !frames.isEmpty { props["frames"] = frames }
        let crumbs = breadcrumbs.suffix(12).joined(separator: " | ")
        if !crumbs.isEmpty { props["breadcrumbs"] = crumbs }
        return props
    }

    /// Human-readable body for the email the user sends us. Written to be
    /// pasted into an issue tracker without editing.
    var summary: String {
        var out = """
        \(appName) \(appVersion) (\(appBuild)) crashed
        when: \(Self.timestamp.string(from: date))
        reason: \(reason)\(exceptionReason.map { " — \($0)" } ?? "")
        after: \(Int(uptimeSeconds))s of running
        os: \(osVersion) (\(arch))

        """
        if !state.isEmpty {
            out += "on screen:\n"
            for (key, value) in state.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
                out += "  \(key): \(value)\n"
            }
            out += "\n"
        }
        if !frames.isEmpty {
            out += "last frames:\n"
            for (i, frame) in frames.prefix(12).enumerated() {
                out += "  \(i): \(frame.display)\n"
            }
            out += "\n"
        }
        if !breadcrumbs.isEmpty {
            out += "last actions:\n"
            for crumb in breadcrumbs.suffix(20) { out += "  \(crumb)\n" }
            out += "\n"
        }
        out += """
        Full report: crash report \(id)
        """
        return out
    }

    /// Body for "Report a Problem…" when nothing has crashed — the same
    /// state, without the wreckage. Built from a live snapshot, so this takes
    /// the pieces rather than being read off a report that doesn't exist yet.
    static func stateOnlySummary(appVersion: String, osVersion: String,
                                 state: [String: String], breadcrumbs: [String]) -> String {
        var out = """
        Vibresia \(appVersion)
        os: \(osVersion) (\(CrashReport.arch))

        """
        for (key, value) in state.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
            out += "  \(key): \(value)\n"
        }
        out += "\nLast actions:\n"
        for crumb in breadcrumbs.suffix(20) { out += "  \(crumb)\n" }
        return out
    }

    static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Filename stamp: sorts chronologically and survives a trip through an
    /// email client.
    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}