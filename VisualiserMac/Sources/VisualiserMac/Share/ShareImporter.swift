import Foundation
import AppKit
import Compression

/// Decodes a `vibresia://open?...` URL handed in by macOS and acts on it.
///
/// Two payload shapes:
///
/// - `vibresia://open?p=<slug>` — built-in vibescape, looked up by slug.
/// - `vibresia://open?d=<base64>` — custom vibescape; the base64 payload is a
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
        case builtin(Vibescape)
        case custom(CustomVibescape)
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
            // Built-in: slug is one of `Vibescape.allCases`. The
            // `Vibescape(rawValue:)` initialiser gives a `nil` for any
            // unknown slug, which we surface as `.malformed` rather
            // than crashing the app.
            if let mode = Vibescape(rawValue: slug) {
                return .builtin(mode)
            }
            return .malformed("unknown built-in slug '\(slug)'")
        }
        if let d = value("d"), !d.isEmpty {
            // `s` is which share this arrived from, when the link knows it:
            // the page puts it in the deep link so the vibescape can remember
            // the link it arrived on and hand the same one back.
            return decodePayload(d, shareID: shareID(from: value("s")))
        }
        return .malformed("URL has no p or d parameter")
    }

    /// The share a link came from, if it is one.
    ///
    /// A deep link is not something to trust: `s` can be empty, or anything
    /// at all, and it ends up in a link other people click. The Worker makes
    /// ids out of six characters from an alphabet with no l, 1 or 0 in it —
    /// the same alphabet is in `worker/index.js` — so anything else is not a
    /// share id and is treated as if there wasn't one.
    private static func shareID(from value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.range(of: shareIDPattern, options: .regularExpression) != nil
            ? value
            : nil
    }

    /// The shape of a share id.
    private static let shareIDPattern = "^[abcdefghijkmnopqrstuvwxyz23456789]{6}$"

    /// Decode the base64 payload in `d=...` into a `Request`. Mirror of
    /// `encodePayload` below; the round-trip is exercised by
    /// `scripts/verify-share-codec.swift`.
    ///
    /// Handles both payload formats, because links made before the format
    /// changed are already in chat threads and will not be re-sent. Unchanged
    /// links are plain base64 JSON, so JSON is tried first and deflate is the
    /// fallback: sniffing rather than a version marker, because it costs
    /// nothing and needs no coordination with the links already out there.
    static func decodePayload(_ base64url: String, shareID: String? = nil) -> Request {
        guard let data = base64URLDecode(base64url) else {
            return .malformed("payload is not valid base64url")
        }
        if let payload = try? JSONDecoder().decode(SharePayload.self, from: data) {
            return vibescape(from: payload, shareID: shareID)
        }
        guard let inflated = inflate(data) else {
            return .malformed("payload is neither JSON nor deflate")
        }
        do {
            return vibescape(from: try JSONDecoder().decode(SharePayload.self, from: inflated),
                             shareID: shareID)
        } catch {
            return .malformed("payload JSON failed to decode: \(error.localizedDescription)")
        }
    }

    /// The payload as a vibescape the app can actually use. The slug is
    /// generated from the display name the same way the store does, so the file
    /// lands where the app expects it and `activeVibescape` can address it.
    ///
    /// `shareID` is the share this arrived from, if it came from one. It is
    /// kept on the vibescape so that sharing it on hands back the link it
    /// arrived on rather than making a new one.
    private static func vibescape(from payload: SharePayload, shareID: String? = nil) -> Request {
        guard !payload.name.isEmpty, !payload.shader.isEmpty else {
            return .malformed("payload missing name or shader")
        }
        return .custom(CustomVibescape(
            id: CustomVibescapeStore.uniqueSlug(from: payload.name),
            name: payload.name,
            author: payload.author,
            url: payload.url,
            shader: payload.shader,
            enabled: true,
            modified: Date(),
            shareID: shareID,
            // The key of what arrived, so the app can tell whether the
            // vibescape has been edited since. Edited means a new share;
            // unedited means the same link.
            shareKey: ShareIdentity.key(name: payload.name, author: payload.author,
                                        url: payload.url, shader: payload.shader)
        ))
    }

    /// Encode a custom vibescape into a URL-safe base64 fragment.
    ///
    /// The JSON is compressed with raw DEFLATE before it is base64'd, which
    /// takes a typical vibescape from around 1.1K characters to 640 — enough
    /// headroom that a real shader stops being the thing that breaks a share
    /// link. Compression is lossless, so whoever opens the link gets back the
    /// exact code that was sent, which minifying would not.
    ///
    /// Raw DEFLATE specifically, because it is the one algorithm in Apple's
    /// Compression framework a browser can read on its own, through
    /// `DecompressionStream('deflate-raw')`. COMPRESSION_ZLIB sounds like the
    /// match and is not: it emits raw DEFLATE despite the name, and its LZFSE,
    /// LZ4 and LZMA siblings are all Apple-proprietary framing with no
    /// JavaScript decoder at all.
    ///
    /// `minify` strips comments and redundant whitespace, which roughly halves
    /// it again — and hands the recipient unreadable code, saved verbatim to
    /// their disk. So it is off unless the person sharing asks for it.
    static func encodePayload(_ mode: CustomVibescape, minify: Bool = false) -> String {
        let payload = SharePayload(
            name: mode.name,
            author: mode.author,
            url: mode.url,
            shader: minify ? GLSLMinifier.minify(mode.shader) : mode.shader
        )
        let encoder = JSONEncoder()
        // Keys sorted and whitespace-free so the round-trip is byte-stable.
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(payload)) ?? Data()
        // Compression is an optimisation, never a requirement: if it somehow
        // fails, an uncompressed payload is still a perfectly good link.
        let data = deflate(json) ?? json
        return base64URLEncode(data)
    }

    // MARK: - Compression

    /// Raw DEFLATE, via the one algorithm in the Compression framework that a
    /// browser can read back without a library.
    ///
    /// `COMPRESSION_ZLIB` is named misleadingly — it emits raw DEFLATE, with no
    /// zlib wrapper — which is exactly what `DecompressionStream('deflate-raw')`
    /// and `zlib.inflateRawSync` expect. Verified by round-tripping between the
    /// two, not by reading the name. LZFSE, LZ4 and LZMA are all Apple-only
    /// framing (`bvx-`, `bv4-`, XZ) and would make the landing page unable to
    /// read a shared vibescape at all.
    static func deflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        // DEFLATE's worst case is a few bytes over the input. The buffer has to
        // be that big or the call fails rather than growing.
        var output = [UInt8](repeating: 0, count: input.count + 64)
        let written = input.withUnsafeBytes { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(
                    dst.baseAddress!, dst.count,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return Data(output[0..<written])
    }

    static func inflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        // Inflate needs room for the result. Twelve times the input covers
        // anything a vibescape could compress to well past its original size;
        // encoding strips comments and the JSON escaping shrinks, so a payload
        // that inflates to more than this is malformed rather than large.
        var output = [UInt8](repeating: 0, count: input.count * 12 + 4096)
        let written = input.withUnsafeBytes { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(
                    dst.baseAddress!, dst.count,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        // 0 means the buffer was too small; anything less than the full buffer
        // means it stopped early, which is a truncated or corrupt payload.
        guard written > 0, written < output.count else { return nil }
        return Data(output[0..<written])
    }

    // MARK: - Apply (main-actor)

    /// Run the request against the live app state. Called from
    /// `AppDelegate`'s Apple Event handler; the optional completion fires
    /// once the active vibescape is showing and the window is up, so a
    /// caller can toas or log from there.
    @MainActor
    static func apply(_ request: Request, completion: ((Request) -> Void)? = nil) {
        guard let app = AppState.shared else { return }
        switch request {
        case .builtin(let mode):
            app.setVibescape(.builtin(mode))
            bringAppToFront()
            Task { await Analytics.shared.track("share_opened", ["kind": "builtin", "slug": mode.rawValue]) }
            completion?(request)
        case .custom(let mode):
            // The share it came from goes with it, so sharing it on hands
            // back the same link rather than making a new one.
            switch app.addCustomVibescape(name: mode.name, author: mode.author, url: mode.url,
                                           shader: mode.shader,
                                           shareID: mode.shareID, shareKey: mode.shareKey) {
            case .success(let saved):
                app.setVibescape(saved.modeID)
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

    /// Make sure the user can actually see the vibescape we just loaded.
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
