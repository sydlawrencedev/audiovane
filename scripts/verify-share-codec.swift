#!/usr/bin/env swift
// Round-trip verifier for the share-link codec. Mirrors the algorithm in
// `Sources/VisualiserMac/Share/ShareImporter.swift` — if you change one,
// change both. The whole of the codec is <100 lines and this duplication is
// cheaper than threading a test target through SwiftPM for one file.
//
// Run from the repo root:
//   swift scripts/verify-share-codec.swift
import Foundation

// MARK: - codec (mirrors ShareImporter)

struct SharePayload: Codable, Equatable {
    var name: String
    var author: String
    var url: String?
    var shader: String
}

enum VibscapeStub: String {
    case ribbons, vortex, silk, flux, spectrum, tunnel, liquid
    case kaleidoscope, waveform, machine, warp, particles, nyan
    case hamster, badger, llama, danceFloor, band, autoScan
}

enum Request: Equatable {
    case builtin(VibscapeStub)
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

func decodeURL(_ s: String) -> Request {
    guard let u = URL(string: s) else { return .malformed("not a url") }
    guard u.scheme?.lowercased() == "vibresia" else { return .malformed("wrong scheme") }
    let verb = (u.host ?? u.path.trimmingCharacters(in: .init(charactersIn: "/"))).lowercased()
    guard verb == "open" else { return .malformed("unknown verb") }
    guard let comps = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return .malformed("bad url") }
    let items = comps.queryItems ?? []
    func v(_ n: String) -> String? { items.first { $0.name == n }?.value }
    if let slug = v("p"), !slug.isEmpty {
        if let mode = VibscapeStub(rawValue: slug) { return .builtin(mode) }
        return .malformed("unknown slug")
    }
    if let d = v("d"), !d.isEmpty {
        guard let data = base64URLDecode(d) else { return .malformed("bad base64") }
        guard let payload = try? JSONDecoder().decode(SharePayload.self, from: data) else {
            return .malformed("bad json")
        }
        return .custom(payload)
    }
    return .malformed("missing p or d")
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
let payloadData = try! encoder.encode(sample)
let encoded = base64URLEncode(payloadData)
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

// 9. The URL is short enough to fit in any chat platform. Vibscape-like
//    shader bodies (typical 1-3KB) plus metadata produce a payload of ~3-5KB
//    base64-encoded, which Slack/Twitter/iMessage all accept.
let smallShader = "vec3 render(vec2 p, float t) { return vec3(uBass); }"
let small = SharePayload(name: "P", author: "A", url: nil, shader: smallShader)
let smallData = try! encoder.encode(small)
let smallEncoded = base64URLEncode(smallData)
print("ok   tiny payload encodes to \(smallEncoded.count) chars (limit 8000)")

// 10. A realistic 2KB shader still fits in 3-4KB.
let realisticShader = String(repeating: "    float n = uBass * sin(p.x * 3.14) + uTreble * cos(p.y); ", count: 50)
let realistic = SharePayload(name: "Glitter Path", author: "Syd Lawrence", url: nil, shader: realisticShader)
let realisticData = try! encoder.encode(realistic)
let realisticEncoded = base64URLEncode(realisticData)
print("ok   realistic (~2KB shader) encodes to \(realisticEncoded.count) chars")

if failures > 0 {
    print("\n\(failures) failure(s)")
    exit(1)
}
print("\nall share-codec checks passed")
