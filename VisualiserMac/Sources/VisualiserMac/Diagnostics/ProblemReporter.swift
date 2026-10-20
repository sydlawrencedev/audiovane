import Foundation

/// Reports problems to the site's `/api/notify`, which forwards them to
/// Discord.
///
/// Why the site and not Discord directly: the webhook URL would have to ship
/// inside the app, where anyone can read it out of the bundle. The site already
/// holds it as a Worker secret, so the app posts to our own domain instead and
/// the secret stays where it belongs.
///
/// This is deliberately independent of the analytics switch. Analytics is
/// usage data the user opts into; a crash report or a capture failure is
/// something the user told us to do by choosing that source, and a visualiser
/// that silently falls back to a dead input is a bug we can't see. What's sent
/// is app state — mode, genre, error text — never audio, never track names.
enum ProblemReporter {
    /// The site. Overridable so a fork can point at its own instance.
    private static var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ReportEndpoint") as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private static var token: String {
        (Bundle.main.object(forInfoDictionaryKey: "ReportToken") as? String) ?? ""
    }

    /// A build without a token simply doesn't report, rather than posting and
    /// being ignored — and this is how `--report-test` and the build output say
    /// so out loud.
    static var isConfigured: Bool { !token.isEmpty && endpoint != nil }

    /// What the user would see if the report arrived. Used to tell a startup
    /// failure from a later one: at launch the visualiser opens dead, and a
    /// useful thing to do is open it a second time.
    static func report(_ problem: Problem) {
        guard isConfigured, let endpoint else { return }
        var fields: [[String: Any]] = [
            ["name": "App version", "value": problem.appVersion],
            ["name": "OS", "value": problem.osVersion],
            ["name": "Running", "value": "\(Int(problem.uptime))s"],
        ]
        for (key, value) in problem.state.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
            fields.append(["name": key, "value": value])
        }
        if let frames = problem.frames, !frames.isEmpty {
            fields.append(["name": "Top frames", "value": frames.joined(separator: " <- "), "inline": false])
        }

        let payload: [String: Any] = [
            "kind": problem.kind,
            "title": problem.title,
            "message": problem.message,
            "priority": problem.priority,
            "fields": fields,
            // Honeypot, in case this endpoint is ever opened up.
            "website": "",
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-av-token")
        request.timeoutInterval = 8
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        // Deliberately not awaited by callers and deliberately not retried: the
        // user is waiting on the app, not on us. Discord has its own record.
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                NSLog("[report] %@ failed: %@", problem.kind, error.localizedDescription)
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) {
                    NSLog("[report] %@ delivered (HTTP %d)", problem.kind, code)
                } else {
                    NSLog("[report] %@ rejected: HTTP %d", problem.kind, code)
                }
            }
        }.resume()
    }

    struct Problem {
        var kind: String
        var title: String
        var message: String
        /// `urgent` / `high` / `default`, matching the worker's colour table.
        var priority = "high"
        var appVersion = ""
        var osVersion = ""
        var uptime: TimeInterval = 0
        var state: [String: String] = [:]
        var frames: [String]?

        /// The crash's own values, not the current run's — a report read on the
        /// next launch would otherwise claim the crash happened just now, with
        /// this launch's version and uptime.
        static func from(_ report: CrashReport) -> Problem {
            Problem(
                kind: "app_crash",
                title: "Vibresia crashed: \(report.reason)",
                message: report.summary,
                priority: "urgent",
                appVersion: "\(report.appVersion) (\(report.appBuild))",
                osVersion: report.osVersion,
                uptime: report.uptimeSeconds,
                state: report.state,
                frames: report.frames.prefix(8).map(\.display)
            )
        }

        static func current(kind: String, title: String, message: String,
                            priority: String = "high", state: [String: String] = [:],
                            frames: [String]? = nil) -> Problem {
            let info = Bundle.main.infoDictionary ?? [:]
            return Problem(
                kind: kind,
                title: title,
                message: message,
                priority: priority,
                appVersion: "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                uptime: Date().timeIntervalSince(CrashReporter.shared.sessionStartedAt),
                state: state,
                frames: frames
            )
        }
    }
}