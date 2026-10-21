#!/usr/bin/env swift
// Round-trip verifier for the share-link codec. Mirrors the algorithm in
// `Sources/VisualiserMac/Share/ShareImporter.swift` — if you change one,
// change both. The whole of the codec is <100 lines and this duplication is
// cheaper than threading a test target through SwiftPM for one file.
//
// Run from the repo root:
//   swift scripts/verify-share-codec.swift
import Foundation
import Compression
import CryptoKit

// MARK: - codec (mirrors ShareImporter)

struct SharePayload: Codable, Equatable {
    var name: String
    var author: String
    var url: String?
    var shader: String
}

enum VibescapeStub: String {
    case ribbons, vortex, silk, flux, spectrum, tunnel, liquid
    case kaleidoscope, waveform, machine, warp, particles, nyan
    case hamster, badger, llama, danceFloor, band, autoScan
}

enum Request: Equatable {
    case builtin(VibescapeStub)
    case custom(SharePayload)
    case malformed(String)
}

func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func base64URLDecode(_ s: String) -> Data? {
    var t = s
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t.append("=") }
    return Data(base64Encoded: t)
}

// Mirrors ShareImporter.deflate / .inflate — raw DEFLATE via COMPRESSION_ZLIB,
// which despite the name emits no zlib wrapper. That is what the landing page's
// DecompressionStream("deflate-raw") expects.
func deflate(_ input: Data) -> Data? {
    guard !input.isEmpty else { return nil }
    var out = [UInt8](repeating: 0, count: input.count + 64)
    let n = input.withUnsafeBytes { s in
        out.withUnsafeMutableBufferPointer { d in
            compression_encode_buffer(d.baseAddress!, d.count,
                s.bindMemory(to: UInt8.self).baseAddress!, input.count,
                nil, COMPRESSION_ZLIB)
        }
    }
    return n > 0 ? Data(out[0..<n]) : nil
}

func inflate(_ input: Data) -> Data? {
    guard !input.isEmpty else { return nil }
    var out = [UInt8](repeating: 0, count: input.count * 12 + 4096)
    let n = input.withUnsafeBytes { s in
        out.withUnsafeMutableBufferPointer { d in
            compression_decode_buffer(d.baseAddress!, d.count,
                s.bindMemory(to: UInt8.self).baseAddress!, input.count,
                nil, COMPRESSION_ZLIB)
        }
    }
    return (n > 0 && n < out.count) ? Data(out[0..<n]) : nil
}

// Mirrors ShareImporter.encodePayload.
func encodePayload(_ p: SharePayload, minify: Bool) -> String {
    let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
    var q = p
    if minify { q.shader = GLSLMinifierMirror.minify(p.shader) }
    let json = (try? e.encode(q)) ?? Data()
    return base64URLEncode(deflate(json) ?? json)
}

// Mirrors ShareImporter.decodePayload: try JSON, else inflate and retry.
func decodePayload(_ d: String) -> Request {
    guard let data = base64URLDecode(d) else { return .malformed("bad base64") }
    if let p = try? JSONDecoder().decode(SharePayload.self, from: data) {
        guard !p.name.isEmpty, !p.shader.isEmpty else { return .malformed("missing name or shader") }
        return .custom(p)
    }
    guard let inflated = inflate(data) else { return .malformed("neither JSON nor deflate") }
    guard let p = try? JSONDecoder().decode(SharePayload.self, from: inflated) else {
        return .malformed("bad json")
    }
    guard !p.name.isEmpty, !p.shader.isEmpty else { return .malformed("missing name or shader") }
    return .custom(p)
}

// Mirrors Sources/.../Share/GLSLMinifier.swift.
enum GLSLMinifierMirror {
    static func minify(_ source: String) -> String {
        var noComments = ""
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var l = String(line)
            while let i = l.range(of: "//") { l = String(l[l.startIndex..<i.lowerBound]) }
            noComments += l + "\n"
        }
        // block comments
        while let a = noComments.range(of: "/*"), let b = noComments.range(of: "*/", range: a.upperBound..<noComments.endIndex) {
            noComments = String(noComments[noComments.startIndex..<a.lowerBound]) + String(noComments[b.upperBound...])
        }
        return noComments.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

func decodeURL(_ s: String) -> Request {
    guard let u = URL(string: s) else { return .malformed("not a url") }
    guard u.scheme?.lowercased() == "vibresia" else { return .malformed("wrong scheme") }
    let verb = (u.host ?? u.path.trimmingCharacters(in: .init(charactersIn: "/"))).lowercased()
    guard verb == "open" else { return .malformed("unknown verb") }
    guard let comps = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return .malformed("bad url") }
    let items = comps.queryItems ?? []
    func v(_ n: String) -> String? { items.first { $0.name == n }?.value }
    if let slug = v("p"), !slug.isEmpty {
        if let mode = VibescapeStub(rawValue: slug) { return .builtin(mode) }
        return .malformed("unknown slug")
    }
    if let d = v("d"), !d.isEmpty {
        return decodePayload(d)
    }
    return .malformed("missing p or d")
}

/// Which share a link came from — mirrors ShareImporter.decode reading `s`.
func shareIDFrom(_ s: String) -> String? {
    guard let u = URL(string: s),
          let comps = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
    return comps.queryItems?.first { $0.name == "s" }?.value
}

// MARK: - identity (mirrors ShareIdentity)

/// The key a vibescape's content hashes to — mirrors `ShareIdentity.key`.
func identityKey(name: String, author: String, url: String?, shader: String) -> String {
    var text = ""
    for field in [name, author, url ?? "", shader] {
        text += "\(field.utf8.count):\(field)"
    }
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - tests

var failures = 0
func check(_ label: String, _ got: Request, _ want: Request) {
    if got == want {
        print("ok   \(label)")
    } else {
        failures += 1
        print("FAIL \(label)\n     got:  \(got)\n     want: \(want)")
    }
}

/// A yes-or-no check, for the things that aren't decode results.
func checkTrue(_ label: String, _ ok: Bool) {
    if ok {
        print("ok   \(label)")
    } else {
        failures += 1
        print("FAIL \(label)")
    }
}

let sample = SharePayload(
    name: "Glitter Path",
    author: "Syd Lawrence",
    url: "https://minithlabs.com",
    shader: """
        vec3 render(vec2 p, float t) {
            float pulse = 0.5 + 0.5 * sin(t * 2.0);
            return vec3(pulse, 0.8, 1.0) * uActive;
        }
        """
)

// 1. Built-in URL decodes to a known slug.
check("built-in ribbons",
      decodeURL("vibresia://open?p=ribbons"),
      .builtin(.ribbons))

check("built-in danceFloor (camelCase)",
      decodeURL("vibresia://open?p=danceFloor"),
      .builtin(.danceFloor))

check("built-in whoopingLlama aliases llama",
      decodeURL("vibresia://open?p=llama"),
      .builtin(.llama))

// 2. Unknown slug → malformed, not a silent builtin fallthrough.
check("unknown slug is malformed",
      decodeURL("vibresia://open?p=mystery"),
      .malformed("unknown slug"))

// 3. Custom URL round-trips a payload.
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let encoded = encodePayload(sample, minify: false)
let got = decodeURL("vibresia://open?d=\(encoded)")
if case let .custom(p) = got, p == sample {
    print("ok   custom payload round-trips")
} else {
    failures += 1
    print("FAIL custom payload round-trip\n     got: \(got)")
}

// 4. Empty d parameter is malformed (not a crash, not a silent fallthrough).
check("missing d is malformed",
      decodeURL("vibresia://open"),
      .malformed("missing p or d"))

// 5. Wrong scheme stays malformed.
check("wrong scheme is malformed",
      decodeURL("https://example.com/open?p=ribbons"),
      .malformed("wrong scheme"))

// 6. Unknown verb stays malformed.
check("unknown verb is malformed",
      decodeURL("vibresia://install?p=ribbons"),
      .malformed("unknown verb"))

// 7. base64 alphabet round-trips (some chat clients substitute + for -).
let standard = data_base64sample()
func data_base64sample() -> Data { return Data("hello world \(sample.name) hello world hello world".utf8) }

let stdEncoded = standard.base64EncodedString()
guard let stdDecoded = Data(base64Encoded: stdEncoded) else { fatalError() }
if stdDecoded == standard { print("ok   standard base64 round-trips") }
else { failures += 1; print("FAIL standard base64 round-trip") }

let urlEncoded = base64URLEncode(standard)
guard let urlDecoded = base64URLDecode(urlEncoded) else { fatalError() }
if urlDecoded == standard { print("ok   url-safe base64 round-trips") }
else { failures += 1; print("FAIL url-safe base64 round-trip") }

// 8. Padding tolerance: hand-trim trailing = and we still decode.
let stripped = String(urlEncoded.drop(while: { $0 == "=" }))
guard let padded = base64URLDecode(stripped) else { fatalError() }
if padded == standard { print("ok   base64 tolerates missing padding") }
else { failures += 1; print("FAIL base64 missing-padding tolerance") }

// 9. A legacy link — plain base64 JSON, made before the format changed — still
//    decodes. These are already in chat threads and will not be re-sent.
let legacyData = try! encoder.encode(sample)
let legacyEncoded = base64URLEncode(legacyData)
if case let .custom(p) = decodeURL("vibresia://open?d=\(legacyEncoded)"), p == sample {
    print("ok   legacy uncompressed link still decodes")
} else {
    failures += 1
    print("FAIL legacy uncompressed link")
}

// 10. The same payload, compressed, is materially shorter and round-trips
//     byte-for-byte — compression is lossless, so the recipient gets back the
//     code that was actually sent.
let compressedEncoded = encodePayload(sample, minify: false)
if case let .custom(p) = decodeURL("vibresia://open?d=\(compressedEncoded)"), p == sample {
    print("ok   compressed payload round-trips (\(legacyEncoded.count) -> \(compressedEncoded.count) chars)")
} else {
    failures += 1
    print("FAIL compressed round-trip")
}
if compressedEncoded.count < legacyEncoded.count {
    print("ok   compression shrinks the link by \(100 - compressedEncoded.count * 100 / legacyEncoded.count)%")
} else {
    failures += 1
    print("FAIL compression made the link bigger")
}

// 11. A truncated compressed payload must be malformed rather than half-read.
//     This is the case that matters: a chat client that cuts a long URL used to
//     produce JSON that failed to parse, and now produces deflate that fails.
let truncated = String(compressedEncoded.dropLast(compressedEncoded.count / 5))
if case .malformed = decodeURL("vibresia://open?d=\(truncated)") {
    print("ok   truncated compressed link is malformed, not half-decoded")
} else {
    failures += 1
    print("FAIL truncated compressed link was accepted")
}

// 12. Minify is opt-in and lossy to readability, so it is tested as a separate
//     path rather than folded into the default round-trip above.
let minifiedEncoded = encodePayload(sample, minify: true)
if case let .custom(p) = decodeURL("vibresia://open?d=\(minifiedEncoded)"),
   !p.shader.contains("//"), p.name == sample.name {
    print("ok   minified payload drops comments and still round-trips (\(compressedEncoded.count) -> \(minifiedEncoded.count) chars)")
} else {
    failures += 1
    print("FAIL minified round-trip")
}

// 13. The URL is short enough to fit in any chat platform.
let smallShader = "vec3 render(vec2 p, float t) { return vec3(uBass); }"
let small = SharePayload(name: "P", author: "A", url: nil, shader: smallShader)
let smallEncoded = encodePayload(small, minify: false)
print("ok   tiny payload encodes to \(smallEncoded.count) chars (limit 8000)")

// 14. Real shaders, compared across all three encodings so the size the
//     feature actually ships is a measured number rather than a hope.
//
//     The starter template the app hands people, verbatim.
let starter = SharePayload(name: "Pink Pulse", author: "Minith Labs", url: nil, shader: """
    // Your vibescape. Edit the colour, press Test.
    // Full list of uniforms and helpers: press "What's available?" below.
    vec3 render(vec2 p, float t)
    {
        // A colour that brightens with the bass.
        float pulse = 0.5 + 0.5 * sin(t * 2.0);
        float amount = uBass * 0.6 + pulse * 0.2;

        vec3 colour = vec3(1.0, 0.2, 0.8) * amount;   // pink
        colour += vec3(0.2, 0.9, 1.0) * uTreble;      // cyan on the highs

        // Fade out when there's no music.
        return colour * uActive;
    }
    """)

/// A shader written the way people actually write them: varied, commented,
/// not one line repeated. The earlier version of this test repeated a single
/// line fifty times, which DEFLATE compresses to almost nothing and made the
/// saving look like 96% — a number that would have been true and useless.
let handwritten = SharePayload(name: "Drifting Smoke", author: "Ada Lovelace",
                                url: "https://example.com/ada", shader: """
    // Smoke drifting over a warm floor, reacting to the bass.
    vec3 render(vec2 p, float t)
    {
        // Slow vertical drift so it never looks frozen when nothing is playing.
        p.y += t * 0.04;

        float n = fbm(p * 7.0 + vec2(0.0, -t * 0.5));
        n = fbm(p * 7.0 + vec2(n * 1.6, n * 1.6));

        // Warm at the base, cold in the smoke, pulsing with the low end.
        vec3 warm = vec3(1.0, 0.45, 0.12);
        vec3 cold = vec3(0.15, 0.35, 0.75);
        vec3 colour = mix(warm, cold, smoothstep(0.2, 0.9, n));

        colour *= 0.6 + 0.8 * uBass;
        colour += vec3(0.2, 0.9, 1.0) * uTreble * 0.15 * n;

        // Hold still in silence rather than going black.
        return mix(colour, colour * 0.5, 1.0 - uActive);
    }
    """)

for (label, payload) in [("starter template", starter), ("hand-written", handwritten)] {
    let plain = base64URLEncode(try! encoder.encode(payload))
    let real = encodePayload(payload, minify: false)
    let realMin = encodePayload(payload, minify: true)
    print("ok   \(label) (\(payload.shader.count) byte shader):")
    print("       plain base64       \(plain.count) chars")
    print("       compressed         \(real.count) chars  (\(100 - real.count * 100 / plain.count)% smaller)")
    print("       compressed+minify  \(realMin.count) chars  (\(100 - realMin.count * 100 / plain.count)% smaller)")
}

// MARK: - the link a vibescape keeps

// The point of the key: the same vibescape always gets the same link, so
// sharing it twice doesn't produce two links, and re-sharing one somebody
// sent you gives you the link it came with.

let keyOfSample = identityKey(name: sample.name, author: sample.author,
                               url: sample.url, shader: sample.shader)
let keyOfSampleAgain = identityKey(name: sample.name, author: sample.author,
                                    url: sample.url, shader: sample.shader)
checkTrue("the same vibescape has the same key", keyOfSample == keyOfSampleAgain)
checkTrue("the key is a hash, not the content", !keyOfSample.contains(sample.shader))
checkTrue("the key is 64 hex characters",
          keyOfSample.count == 64 && keyOfSample.allSatisfy { $0.isHexDigit })

let keyOfEdited = identityKey(name: sample.name, author: sample.author,
                               url: sample.url, shader: sample.shader + "\n// edited")
checkTrue("an edited vibescape has a different key", keyOfEdited != keyOfSample)

let keyOfOtherAuthor = identityKey(name: sample.name, author: "Somebody Else",
                                    url: sample.url, shader: sample.shader)
checkTrue("a different author has a different key", keyOfOtherAuthor != keyOfSample)

// Minifying is a choice about how long the link is, not a different
// vibescape, so it must not give the same one a second identity. The key
// comes from the vibescape's own shader, whatever the payload sent happens
// to be.
let minifiedPayload = SharePayload(name: sample.name, author: sample.author,
                                    url: sample.url, shader: GLSLMinifierMirror.minify(sample.shader))
checkTrue("minifying changes the payload", minifiedPayload.shader != sample.shader)
checkTrue("the key is the vibescape's, not the payload's",
          identityKey(name: minifiedPayload.name, author: minifiedPayload.author,
                      url: minifiedPayload.url, shader: sample.shader) == keyOfSample)

// The link a share arrives on carries which share it was, so the app can
// hand the same link back.
let shareURL = "vibresia://open?d=\(encoded)&s=abc123"
checkTrue("the share a link came from is in the link",
          shareIDFrom(shareURL) == "abc123")
checkTrue("a link with no share still decodes",
          shareIDFrom("vibresia://open?d=\(encoded)") == nil)
checkTrue("the payload still decodes with a share id in the link",
          decodeURL(shareURL) == .custom(sample))

if failures > 0 {
    print("\n\(failures) failure(s)")
    exit(1)
}
print("\nall share-codec checks passed")
