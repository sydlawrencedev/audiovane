import Foundation
import simd

/// "MACHINE" mode — a port of the MIDEM Music Hack Day piece by @mrdoob and
/// @plamere (github.com/mrdoob/midemhackday), rebuilt from its source.
///
/// Two machines share the stage, as in the original:
///
///   * Machine 1 — twelve stations in a row, one per pitch class. Each has a
///     launch cannon, a catch cannon and three drums (one per loudness
///     bucket). A note fires a ball from the launch cannon, over to its drum
///     (which recoils and flashes white) and down into the catch cannon.
///   * Machine 2 — two cannons at the centre of a ring of 40 pads, each pad
///     with its own cannon behind it. Notes arc out to a pad and bounce on
///     into the outer cannon.
///
/// The camera flies the original's spline from the row of stations across
/// to the ring over the course of the track.
///
/// The original was driven by an Echo Nest score (per-segment pitch lists and
/// loudness buckets). Live, we derive the same thing from the spectrum: an
/// onset (spectral flux peak) fires a note for each pitch class that is
/// sounding strongly at that moment, and the flux sets the loudness bucket.
struct MachineMode {

    // MARK: - Layout (from the original source)

    static let stations = 12          // pitch classes
    static let volumes = 3            // loudness buckets → low / medium / high drum
    static let ringCount = 40         // pads around Machine 2
    static let machineColor = SIMD3<Float>(1.0, 0x80 / 255.0, 0x20 / 255.0)   // 0xff8020
    static let ballColor = SIMD3<Float>(1, 1, 1)

    /// Machine 1's container: x = -50 in Machine1.js, z = 120 set in Main.js.
    static let machine1Origin = SIMD3<Float>(-50, 0, 120)

    /// Drum centre (Machine-1 local, before the station's z) for each volume.
    static let drumPos: [SIMD2<Float>] = [SIMD2(95, 45), SIMD2(100, 50), SIMD2(105, 55)]
    static let drumScale: [Float] = [0.5, 0.6, 0.75]

    /// How long a corridor ball takes to reach its drum, and then the catch
    /// cannon. The original spends 0.5s each side of the hit (it knew the
    /// score in advance); live we can only launch on the onset, so the run-up
    /// is shortened to keep the hit close to the sound.
    static let corridorRunUp: CFTimeInterval = 0.32
    static let corridorRunOut: CFTimeInterval = 0.5
    static let ringRunUp: CFTimeInterval = 0.45
    static let ringRunOut: CFTimeInterval = 0.9
    /// A struck drum/pad springs back over this long (HitEffect: 0.5s).
    static let hitDuration: CFTimeInterval = 0.5

    // MARK: - State

    struct Note {
        var born: CFTimeInterval
        var pitch: Int        // 0..<12
        var volume: Int       // 0..<3
        var ringIndex: Int    // 0..<40
    }

    var notes: [Note] = []
    /// Time each drum / pad was last struck (for HitEffect).
    var drumHitAt = [CFTimeInterval](repeating: -10, count: stations * volumes)
    var padHitAt = [CFTimeInterval](repeating: -10, count: ringCount)

    private var prevBands: [Float] = []
    private var fluxAverage: Float = 0.05
    private var lastNoteAt: CFTimeInterval = 0
    private var bandPitchClass: [Int] = []

    static var lifetime: CFTimeInterval { max(corridorRunUp + corridorRunOut, ringRunUp + ringRunOut) }

    // MARK: - Notes from the live spectrum

    mutating func update(bands: [Float], rms: Float, now: CFTimeInterval) {
        if prevBands.count != bands.count {
            prevBands = [Float](repeating: 0, count: bands.count)
            // Pitch class of each log band (40Hz-16kHz across the bands).
            bandPitchClass = bands.indices.map { i in
                let f = 40 * pow(400, (Double(i) + 0.5) / Double(bands.count))
                let midi = Int((12 * log2(f / 440) + 69).rounded())
                return ((midi % 12) + 12) % 12
            }
        }

        // Positive spectral flux, overall and per pitch class (melodic range
        // only, roughly 100Hz-2kHz, where pitch is meaningful).
        var flux: Float = 0
        var chroma = [Float](repeating: 0, count: Self.stations)
        for i in bands.indices {
            let d = max(0, bands[i] - prevBands[i])
            flux += d
            let f = 40 * pow(400, (Float(i) + 0.5) / Float(bands.count))
            if f > 100 && f < 2000 { chroma[bandPitchClass[i]] += d }
        }
        prevBands = bands
        flux /= Float(max(1, bands.count))

        let onset = rms > 0.004 && flux > fluxAverage * 1.8 + 0.01 && now - lastNoteAt > 0.09
        fluxAverage += (flux - fluxAverage) * 0.05

        if onset {
            lastNoteAt = now
            let volume = min(Self.volumes - 1, Int(flux / max(fluxAverage, 1e-4) / 2.2))
            // Every pitch class sounding close to the strongest, up to three.
            let top = chroma.max() ?? 0
            let classes = chroma.indices
                .filter { top > 0 && chroma[$0] >= top * 0.6 }
                .sorted { chroma[$0] > chroma[$1] }
                .prefix(3)
            for pitch in (classes.isEmpty ? [Int.random(in: 0..<Self.stations)] : Array(classes)) {
                let ringIndex = (pitch + volume * Self.stations) % Self.ringCount
                notes.append(Note(born: now, pitch: pitch, volume: volume, ringIndex: ringIndex))
            }
        }

        // Strike the drum / pad as each ball arrives.
        for n in notes {
            let drum = n.pitch * Self.volumes + n.volume
            if now - n.born >= Self.corridorRunUp && drumHitAt[drum] < n.born { drumHitAt[drum] = n.born + Self.corridorRunUp }
            if now - n.born >= Self.ringRunUp && padHitAt[n.ringIndex] < n.born { padHitAt[n.ringIndex] = n.born + Self.ringRunUp }
        }
        notes.removeAll { now - $0.born > Self.lifetime }
        if notes.count > 120 { notes.removeFirst(notes.count - 120) }
    }

    /// Snapshot helper: a spread of notes caught at different points in flight.
    mutating func seedNotes(count: Int, now: CFTimeInterval) {
        for i in 0..<count {
            let pitch = (i * 5) % Self.stations
            let volume = i % Self.volumes
            let age = Double(i) / Double(count) * Self.lifetime
            notes.append(Note(born: now - age, pitch: pitch, volume: volume,
                              ringIndex: (pitch + volume * Self.stations) % Self.ringCount))
        }
    }

    /// HitEffect: 1 at the moment of the hit, easing back to 0 over 0.5s.
    static func hitAmount(since hitAt: CFTimeInterval, now: CFTimeInterval) -> Float {
        let t = (now - hitAt) / hitDuration
        return t < 0 || t > 1 ? 0 : Float(1 - t)
    }

    // MARK: - Ball paths (Bounce1Effect / Bounce2Effect)

    /// Two-leg bounce: p0 → p1 with an arc of `up1`, then p1 → p2 with a hop
    /// of `up2`. `progress` 0...1 with the hit at 0.5.
    private static func bounce(_ progress: Float, _ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>,
                               _ up1: Float, _ up2: Float) -> SIMD2<Float> {
        if progress < 0.5 {
            var p = p0 + (p1 - p0) * (progress * 2)
            p.y += sin(.pi * progress * 2) * up1
            return p
        }
        var p = p1 + (p2 - p1) * (progress * 2 - 1)
        p.y += abs(sin(.pi * (progress * 2 - 1))) * up2
        return p
    }

    /// Map age to the effect's 0...1 progress with the hit at 0.5, given
    /// separate run-up and run-out durations.
    private static func progress(age: CFTimeInterval, runUp: CFTimeInterval, runOut: CFTimeInterval) -> Float? {
        if age < 0 || age > runUp + runOut { return nil }
        return age < runUp ? Float(age / runUp) * 0.5 : 0.5 + Float((age - runUp) / runOut) * 0.5
    }

    /// Machine-1 ball, in Machine-1 local x/y (z is the station).
    static func corridorBall(age: CFTimeInterval, volume: Int) -> SIMD2<Float>? {
        guard let p = progress(age: age, runUp: corridorRunUp, runOut: corridorRunOut) else { return nil }
        return bounce(p, SIMD2(0, 50), drumPos[volume], SIMD2(18, 0), 25, 20)
    }

    /// Machine-2 ball, in its ring group's local x/y.
    static func ringBall(age: CFTimeInterval) -> SIMD2<Float>? {
        guard let p = progress(age: age, runUp: ringRunUp, runOut: ringRunOut) else { return nil }
        return bounce(p, SIMD2(0, 35), SIMD2(40, 25), SIMD2(78, 5), 40, 20)
    }

    // MARK: - Camera (Main.js)

    static let cameraPath: [SIMD3<Float>] = [
        SIMD3(0, 100, 100), SIMD3(50, 100, 0), SIMD3(100, 30, 0), SIMD3(0, 100, -200),
    ]
    static let cameraTargetPath: [SIMD3<Float>] = [
        SIMD3(0, 35, 200), SIMD3(0, 50, 0), SIMD3(0, 25, 0),
    ]

    /// THREE.Spline.getPoint: Catmull-Rom through the points, clamped ends.
    static func spline(_ pts: [SIMD3<Float>], _ k: Float) -> SIMD3<Float> {
        let point = Float(pts.count - 1) * min(max(k, 0), 1)
        let i = min(Int(point), pts.count - 1)
        let w = point - Float(i)
        let p0 = pts[i == 0 ? i : i - 1]
        let p1 = pts[i]
        let p2 = pts[min(i + 1, pts.count - 1)]
        let p3 = pts[min(i + 2, pts.count - 1)]
        let v0 = (p2 - p0) * 0.5, v1 = (p3 - p1) * 0.5
        let w2 = w * w, w3 = w2 * w
        let a: SIMD3<Float> = (2 * p1 - 2 * p2 + v0 + v1) * w3
        let b: SIMD3<Float> = (-3 * p1 + 3 * p2 - 2 * v0 - v1) * w2
        return a + b + v0 * w + p1
    }

    static func camera(progress k: Float) -> (pos: SIMD3<Float>, target: SIMD3<Float>) {
        (spline(cameraPath, k), spline(cameraTargetPath, k))
    }
}
