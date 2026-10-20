import Foundation
import AppKit

/// Decodes a `vibresia://open?...` URL handed in by macOS and acts on it.
///
/// Two payload shapes:
///
/// - `vibresia://open?p=<slug>` — built-in vibscape, looked up by slug.
/// - `vibresia://open?d=<base64>` — custom vibscape; the base64 payload is a
///   compact JSON `{name, author, url?, shader}`.
///
/// The decoder is a pure `static` so a Swift verifier script can round-trip
/// golden vectors without launching the app. The action side touches
/// `AppState`, the renderer and the window — main-actor, async.
enum ShareImporter {

    /// What the URL asked for, expressed in a shape that doesn't yet care
    /// whether the runtime can satisfy it. A `Malformed` result doesn't
    /// crash or alert; it's returned up the chain so we can PostHog the
    /// failure mode and move on.
    enum Request: Equatable {
        case builtin(Vibscape)
        case custom(CustomVibscape)
        case malformed(String)
    }

    /// The flat payload that gets base64-encoded into a share URL.
    /// Matched against the receiver's decoder, so renaming a field is a
    /// coordinating change on both sides.
    struct SharePayload: Codable, Equatable {
        var name: String
        var author: String
        var url: String?
        var shader: String
    }

    // MARK: - Decode (pure)

    /// Parse a `vibresia://open?...` URL into a request. Returns
    /// `.malformed(...)` for anything we don't recognise, including the
    /// wrong scheme, an empty verb or an undecodable payload.
    static func decode(_ url: URL) -> Request {
        guard url.scheme?.lowercased() == "vibresia" else {
            return .malformed("unexpected scheme: \(url.scheme ?? "nil")")
        }
        let verb = (url.host ?? url.path.trimmingCharacters(in: .init(charactersIn: "/"))).lowercased()
        guard verb == "open" else {
            return .malformed("unknown verb: \(verb)")
        }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .malformed("URL failed to parse")
        }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        if let slug = value("p"), !slug.isEmpty {
            // Built-in: slug is one of `Vibscape.allCases`. The
            // `Vibscape(rawValue:)` initialiser gives a `nil` for any
            // unknown slug, which we surface as `.malformed` rather
            // than crashing the app.
            if let mode = Vibscape(rawValue: slug) {
                return .builtin(mode)
            }
            return .malformed("unknown built-in slug '\(slug)'")
        }
        if let d = value("d"), !d.isEmpty {
            return decodePayload(d)
        }
        return .malformed("URL has no p or d parameter")
    }

    /// Decode the base64 payload in `d=...` into a `Request`. Mirror of
    /// `encodePayload` below; the round-trip is exercised by
    /// `scripts/verify-share-codec.swift`.
    static func decodePayload(_ base64url: String) -> Request {
        guard let data = base64URLDecode(base64url) else {
            return .malformed("payload is not valid base64url")
        }
        let decoder = JSONDecoder()
        do {
            let payload = try decoder.decode(SharePayload.self, from: data)
            guard !payload.name.isEmpty, !payload.shader.isEmpty else {
                return .malformed("payload missing name or shader")
            }
            // The slug is generated from the display name the same way the
            // store does, so the file lands where the app expects it and
            // the activeVibscape can address it.
            let id = CustomVibscapeStore.uniqueSlug(from: payload.name)
            let mode = CustomVibscape(
                id: id,
                name: payload.name,
                author: payload.author,
                url: payload.url,
                shader: payload.shader,
                enabled: true,
                modified: Date()
            )
            return .custom(mode)
        } catch {
            return .malformed("payload JSON failed to decode: \(error.localizedDescription)")
        }
    }

    /// Encode a custom vibscape into a URL-safe base64 fragment. Output
    /// stays around 2-4KB for typical shader sizes, which fits any chat
    /// platform without complaint.
    static func encodePayload(_ mode: CustomVibscape) -> String {
        let payload = SharePayload(
            name: mode.name,
            author: mode.author,
            url: mode.url,
            shader: mode.shader
        )
        let encoder = JSONEncoder()
        // Keys sorted and whitespace-free so the round-trip is byte-stable.
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data()
        return base64URLEncode(data)
    }

    // MARK: - Apply (main-actor)

    /// Run the request against the live app state. Called from
    /// `AppDelegate`'s Apple Event handler; the optional completion fires
    /// once the active vibscape is showing and the window is up, so a
    /// caller can toas or log from there.
    @MainActor
    static func apply(_ request: Request, completion: ((Request) -> Void)? = nil) {
        guard let app = AppState.shared else { return }
        switch request {
        case .builtin(let mode):
            app.setVibscape(.builtin(mode))
            bringAppToFront()
            Task { await Analytics.shared.track("share_opened", ["kind": "builtin", "slug": mode.rawValue]) }
            completion?(request)
        case .custom(let mode):
            switch app.addCustomVibscape(name: mode.name, author: mode.author, url: mode.url, shader: mode.shader) {
            case .success(let saved):
                app.setVibscape(saved.modeID)
                bringAppToFront()
                Task { await Analytics.shared.track("share_opened", ["kind": "custom", "name": saved.name]) }
                completion?(request)
            case .failure(let problem):
                Task { await Analytics.shared.track("share_import_failed", ["reason": problem.message]) }
                completion?(request)
            }
        case .malformed(let reason):
            Task { await Analytics.shared.track("share_import_failed", ["reason": reason]) }
            completion?(request)
        }
    }

    /// Make sure the user can actually see the vibscape we just loaded.
    /// The URL handler can fire while the app is in the background, or
    /// for a cold launch while the window is still settling, so we ask
    /// both AppKit and the window itself.
    @MainActor
    private static func bringAppToFront() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            if !window.isVisible { window.orderFrontRegardless() }
        }
    }

    // MARK: - base64url

    /// URL-safe base64 decode. Accepts both standard and URL-safe alphabets
    /// (some chat clients re-encode) and tolerates missing padding.
    static func base64URLDecode(_ s: String) -> Data? {
        var t = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to a multiple of 4.
        while t.count % 4 != 0 { t.append("=") }
        return Data(base64Encoded: t)
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
