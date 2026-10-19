import Foundation

/// Minimal PostHog capture client.
///
/// Deliberately not the official SDK: that pulls in feature flags, session
/// replay and surveys, and session replay in particular has no business inside
/// an app whose entire job is capturing the screen. This speaks the same
/// `/batch` endpoint with nothing attached.
///
/// Privacy: this app watches audio and draws the screen, so the rule is that
/// nothing derived from *what the user is watching or listening to* ever
/// leaves the machine. No window titles, no track names, no audio-derived
/// detail beyond a coarse genre bucket, no file paths, no hardware IDs.
/// `distinct_id` is a random UUID held in UserDefaults — it identifies an
/// install, not a person, and the user can reset it from the credits popover.
actor Analytics {
    static let shared = Analytics()

    static let enabledKey = "analytics.enabled"
    static let distinctIdKey = "analytics.distinctId"
    private static let seenBeforeKey = "analytics.seenBefore"

    /// Build-time kill switch — set POSTHOG_DISABLE=1 to compile telemetry out
    /// entirely, so a build can be shipped with no capture code path at all.
    private static let disabledAtBuild: Bool = {
        if let v = ProcessInfo.processInfo.environment["POSTHOG_DISABLE"] {
            return v == "1" || v.lowercased() == "true"
        }
        return false
    }()

    private var apiKey: String?
    private var host: String
    private var distinctId: String
    private var queue: [[String: Any]] = []
    private var flushTask: Task<Void, Never>?

    /// Rolled up per session so a mode-flicker doesn't cost 40 API calls.
    private var session: [String: Int] = [:]
    private var sessionStarted = Date()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let info = Bundle.main.infoDictionary ?? [:]
        apiKey = (info["PostHogKey"] as? String)?.nilIfBlank
        host = ((info["PostHogHost"] as? String)?.nilIfBlank) ?? "https://us.i.posthog.com"
        if let key = apiKey, !key.hasPrefix("phc_") {
            NSLog("[analytics] ignoring malformed PostHog key")
            apiKey = nil
        }

        if let existing = defaults.string(forKey: Self.distinctIdKey) {
            distinctId = existing
        } else {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: Self.distinctIdKey)
            distinctId = fresh
        }
    }

    var isEnabled: Bool {
        get async { Self.disabledAtBuild ? false : defaults.bool(forKey: Self.enabledKey) }
    }

    /// False when the bundle has no project key — the toggle then shows as
    /// unavailable rather than pretending to collect.
    var isConfigured: Bool {
        Self.disabledAtBuild ? false : apiKey != nil
    }

    /// Opting in is a one-time write, so a returning user doesn't have to
    /// re-toggle it every launch. Seeded from Info.plist at first run.
    func bootstrapOptIn() {
        guard !Self.disabledAtBuild else { return }
        guard apiKey != nil else { return }
        let marker = "analytics.optInPrompted"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)
        defaults.set(true, forKey: Self.enabledKey)
    }

    var currentDistinctId: String { distinctId }

    func setEnabled(_ on: Bool) async {
        guard !Self.disabledAtBuild else { return }
        defaults.set(on, forKey: Self.enabledKey)
        if !on {
            queue.removeAll()
            flushTask?.cancel()
            flushTask = nil
            NSLog("[analytics] disabled by user")
        } else {
            NSLog("[analytics] enabled")
        }
    }

    /// Wipes the local identity and drops anything unsent. Next event starts a
    /// brand new anonymous install record.
    func resetIdentity() async {
        defaults.removeObject(forKey: Self.distinctIdKey)
        distinctId = UUID().uuidString
        defaults.set(distinctId, forKey: Self.distinctIdKey)
        queue.removeAll()
        NSLog("[analytics] identity reset")
    }

    func track(_ event: String, _ properties: [String: Any] = [:]) {
        guard !Self.disabledAtBuild, apiKey != nil else { return }
        guard defaults.bool(forKey: Self.enabledKey) else { return }

        var payload: [String: Any] = [
            "api_key": apiKey ?? "",
            "event": event,
            "distinct_id": distinctId,
            "properties": properties,
            "$lib": "audiovane",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        payload["properties"] = properties.merging(defaultProperties()) { a, _ in a }

        queue.append(payload)
        scheduleFlush()
    }

    /// Counts an occurrence in a per-session tally instead of sending a row.
    /// Detail screens send the exact sequence; PostHog gets the histogram.
    func countInSession(_ key: String, by amount: Int = 1) {
        guard !Self.disabledAtBuild, apiKey != nil else { return }
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        session[key, default: 0] += amount
    }

    func sessionLengthSeconds() -> Int {
        Int(Date().timeIntervalSince(sessionStarted))
    }

    private func defaultProperties() -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        var props: [String: Any] = [
            // The website reports into the same PostHog project (`site/analytics.js`),
            // so this is what keeps an install apart from a page view.
            "surface": "mac_app",
            "app_version": info["CFBundleShortVersionString"] ?? "0",
            "build": info["CFBundleVersion"] ?? "0",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "arch": currentArch,
            "session_seconds": sessionLengthSeconds(),
        ]
        props["locale"] = Locale.current.identifier
        return props
    }

    private var currentArch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self else { return }
            await self.flush()
        }
    }

    /// Sends everything queued, then any per-session tallies. Returns whether
    /// PostHog took it — crash reports only get deleted from disk on a `true`.
    @discardableResult
    func flush() async -> Bool {
        flushTask = nil
        guard !Self.disabledAtBuild, let apiKey, defaults.bool(forKey: Self.enabledKey) else { return false }

        var batch = queue
        queue.removeAll()

        if !session.isEmpty {
            var tallies = session
            session = [:]
            sessionStarted = Date()
            var props = defaultProperties()
            for (k, v) in tallies { props[k] = v }
            batch.append([
                "api_key": apiKey,
                "event": "session_summary",
                "distinct_id": distinctId,
                "properties": props,
                "$lib": "audiovane",
            ])
        }

        guard !batch.isEmpty else { return true }

        // `/batch/`, not `/capture/`: the capture endpoint takes one event per
        // request, and this queue is a batch. Posting to the bare host root (as
        // this used to) gets a 404 back, which reads exactly like "no events
        // ever arrived".
        var request = URLRequest(url: URL(string: host)!.appendingPathComponent("batch"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["api_key": apiKey, "batch": batch])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) {
                NSLog("[analytics] sent \(batch.count) event(s)")
                return true
            }
            NSLog("[analytics] HTTP \(code)")
            return false
        } catch {
            // Fire and forget. Failed sends are dropped rather than retried:
            // an offline visualiser shouldn't accumulate a backlog, and the
            // next session re-reports the same aggregate anyway. Crash reports
            // are the exception — they're on disk and re-read next launch.
            NSLog("[analytics] send failed: \(error.localizedDescription)")
            return false
        }
    }

    func flushNow() async -> Bool {
        await flush()
    }

    func setSeenBefore() {
        defaults.set(true, forKey: Self.seenBeforeKey)
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
