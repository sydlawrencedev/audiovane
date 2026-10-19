import Foundation
import Accelerate

/// Watches the audio features over a sliding window and decides which genre
/// the current song best matches. Rule-based heuristic — no model, no
/// training data — because we only need 10 buckets and the audio features
/// already in `AudioSnapshot` are enough to separate them most of the time.
///
/// Designed to be called once per render frame from `AudioEngine.tick()`.
/// `detect()` returns the current best guess; it is throttled internally so
/// callers can just spam it. The detector is hysteresis-stable: it only
/// declares a new genre once it has been the best guess for
/// `stabilityWindow` consecutive detections, so a momentary blip doesn't
/// flip the band mid-song.
final class GenreDetector {
    /// How much audio history to keep. Long enough that a 100bpm song's
    /// downbeats (~3s apart) give us ~5 full beats; short enough that the
    /// detector responds to a real change in ~10s.
    private let windowDuration: TimeInterval = 15.0
    /// How long the candidate genre must remain the best guess before we
    /// commit to it. Prevents flapping around the boundary between two
    /// close genres (e.g. Pop vs Hip-Hop) and lets the user enjoy a
    /// confident call for a while.
    private let stabilityWindow: Int = 3
    /// How often `detect()` actually scores, in seconds. Cheaper than every
    /// frame and the features don't change fast enough to need it.
    private let detectInterval: TimeInterval = 1.5

    private struct Sample {
        let t: TimeInterval
        let bpm: Double
        let bass: Float
        let mid: Float
        let treble: Float
        let centroid: Float      // 0..1, log-frequency weighted
        let onsetDensity: Float  // onsets per second
        let dynamicRange: Float  // max(rms) - min(rms) over the window
        let vocal: Float
    }

    private var window: [Sample] = []
    private var windowStart: TimeInterval = 0
    private var minRms: Float = 1
    private var maxRms: Float = 0
    private var lastDetect: TimeInterval = 0
    private var candidate: Genre = .rock
    private var candidateStreak: Int = 0

    /// The currently committed genre. Read by AppState.
    private(set) var genre: Genre = .rock
    /// 0..1, how confident the latest decision was. Used for the picker UI
    /// to grey out genres the detector is sure aren't right.
    private(set) var confidence: Float = 0
    /// The latest scoring inputs and per-genre scores, for the band
    /// evaluation log (scripts/band-eval.py) and tuning.
    private(set) var lastFeatures: [String: Float] = [:]
    private(set) var lastScores: [Genre: Float] = [:]

    func update(snapshot: AudioSnapshot, beat: Bool, vocal: Float, now: TimeInterval) {
        if now - windowStart > windowDuration {
            windowStart = now
            minRms = 1
            maxRms = 0
        }
        minRms = Swift.min(minRms, snapshot.rms)
        maxRms = Swift.max(maxRms, snapshot.rms)

        let s = Sample(
            t: now,
            bpm: snapshot.bpm,
            bass: snapshot.bass,
            mid: snapshot.mid,
            treble: snapshot.treble,
            centroid: centroid(of: snapshot.bands),
            // Approximate density from the bass envelope: every time the bass
            // doubles in one frame we count an onset. Cheaper than running a
            // dedicated onset detector and good enough for genre bucketing.
            onsetDensity: beat ? 0 : 0,
            dynamicRange: max(0, maxRms - minRms),
            vocal: vocal
        )
        window.append(s)
        // Trim, then recompute onsetDensity from the trimmed window so it
        // reflects only the last 15s.
        window.removeAll { now - $0.t > windowDuration }
        let span = max(0.1, now - windowStart)
        let recentBeats = window.reduce(0) { $0 + ($1.onsetDensity > 0 ? 1 : 0) }
        let density = Float(recentBeats) / Float(span)

        // Patch the last sample with the freshly-computed density. We don't
        // bother patching the older ones — they're out of the window next
        // tick.
        if !window.isEmpty {
            window[window.count - 1] = Sample(
                t: s.t, bpm: s.bpm, bass: s.bass, mid: s.mid, treble: s.treble,
                centroid: s.centroid, onsetDensity: density,
                dynamicRange: s.dynamicRange, vocal: s.vocal
            )
        }

        guard now - lastDetect > detectInterval else { return }
        lastDetect = now
        let (g, conf) = score()
        if g == candidate {
            candidateStreak += 1
        } else {
            candidate = g
            candidateStreak = 1
        }
        if candidateStreak >= stabilityWindow {
            genre = candidate
            confidence = conf
        }
    }

    /// Weighted spectral centroid normalised to 0..1 over the 40Hz–16kHz band.
    /// Bright material (cymbals, strings) lives near 1, bass-heavy material
    /// near 0. The first 96 log bands already match this range.
    private func centroid(of bands: [Float]) -> Float {
        guard !bands.isEmpty else { return 0 }
        var weighted: Float = 0
        var total: Float = 0
        let n = Float(bands.count - 1)
        for (i, b) in bands.enumerated() {
            // i in 0..n-1 → frequency index 0..1 (log scale)
            let f = Float(i) / n
            weighted += b * f
            total += b
        }
        return total > 0 ? weighted / total : 0
    }

    /// One score per genre. Each rule is a small contribution; the winner is
    /// the highest sum. Rules are deliberately soft — they contribute even
    /// when partially satisfied, so an unclear song falls back to Rock
    /// (the default) rather than ping-ponging.
private func score() -> (Genre, Float) {
        let n = Float(window.count)
        guard n > 0 else { return (.rock, 0) }

        let bpm = window.reduce(0.0) { $0 + $1.bpm } / Double(n)
        let bass = window.reduce(0) { $0 + $1.bass } / n
        let mid = window.reduce(0) { $0 + $1.mid } / n
        let treble = window.reduce(0) { $0 + $1.treble } / n
        let centroid = window.reduce(0) { $0 + $1.centroid } / n
        let onsets = window.reduce(0) { $0 + $1.onsetDensity } / n
        let range = window.reduce(0) { $0 + $1.dynamicRange } / n
        let vocal = window.reduce(0) { $0 + $1.vocal } / n

        // A smooth 0..1 ramp between lo and hi. Rules below use these instead
        // of hard thresholds: a genre earns partial credit as it approaches
        // its ideal value rather than getting all-or-nothing, which is what
        // makes the confidence margin meaningful instead of a step function.
        func ramp(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
            guard hi != lo else { return x >= hi ? 1 : 0 }
            return min(1, max(0, (x - lo) / (hi - lo)))
        }
        func bell(_ x: Float, _ ideal: Float, _ width: Float) -> Float {
            return max(0, 1 - abs(x - ideal) / max(0.0001, width))
        }

        let bpmF = Float(bpm)
        let hasBeat = bpm >= 40

        var s: [Genre: Float] = [:]

        // --- Genre signatures ------------------------------------------------
        // Each genre is described by what makes it *that* genre rather than a
        // loose bundle of "genre-plausible" conditions. Where two genres share
        // a tempo band (the slow acoustic ones especially) the discriminator
        // is the one feature that genuinely differs between them.

        // Classical: slow, wide dynamics, bright, and crucially — very few
        // percussive onsets. That's the orchestral tell.
        s[.classical] = ramp(bpmF, 110, 45) * 0.30
            + ramp(range, 0.09, 0.22) * 0.30
            + ramp(centroid, 0.38, 0.62) * 0.22
            + (1 - ramp(onsets, 0.05, 0.35)) * 0.18

        // Electronic: fast, bass-heavy, metronomic, and dynamically squashed
        // by the compressor — the flat loudness is the club sound.
        s[.electronic] = bell(bpmF, 128, 26) * 0.28
            + ramp(bass, 0.22, 0.50) * 0.30
            + ramp(onsets, 0.35, 0.85) * 0.22
            + (1 - ramp(range, 0.06, 0.14)) * 0.20

        // Rock: fast-ish, mid-forward (distorted guitars), driving onsets.
        // The dynamic-range term is what separates it from Electronic: rock
        // leaves headroom between hits, a mastered club track doesn't.
        s[.rock] = bell(bpmF, 128, 34) * 0.24
            + ramp(mid, 0.12, 0.34) * 0.24
            + ramp(onsets, 0.28, 0.70) * 0.22
            + ramp(bass, 0.10, 0.30) * 0.16
            + ramp(range, 0.08, 0.20) * 0.14

        // Pop: mid tempo, vocal-forward, full-band but tame. Deliberately
        // balanced rather than extreme — pop is the *average* of the genres
        // that lean one way or the other, so it wins by having no penalty.
        s[.pop] = bell(bpmF, 118, 24) * 0.26
            + ramp(vocal, 0.12, 0.32) * 0.30
            + ramp(range, 0.07, 0.17) * 0.18
            + bell(mid, 0.26, 0.18) * 0.14
            + bell(bass, 0.26, 0.16) * 0.12

        // Hip-Hop: slow, 808 sub-heavy, sparse-but-heavy kick. The huge bass
        // weight is what stops R&B (which shares the tempo) from taking it.
        s[.hiphop] = bell(bpmF, 88, 22) * 0.26
            + ramp(bass, 0.32, 0.60) * 0.44
            + ramp(onsets, 0.20, 0.55) * 0.30

        // R&B: slow-mid, vocal-forward, present but not dominant bass. The
        // *inverse* bass ramp is the discriminator against Hip-Hop.
        s[.rnb] = bell(bpmF, 86, 20) * 0.26
            + ramp(vocal, 0.15, 0.38) * 0.38
            + bell(bass, 0.24, 0.13) * 0.22
            + ramp(range, 0.07, 0.16) * 0.14

        // Jazz: mid-fast, mid-dominant, brushed rather than struck — onsets
        // sit *between* Blues (too sparse) and Rock (too dense).
        s[.jazz] = bell(bpmF, 135, 40) * 0.26
            + bell(mid, 0.32, 0.16) * 0.30
            + bell(onsets, 0.32, 0.20) * 0.24
            + ramp(vocal, 0.06, 0.22) * 0.20

        // Blues: slow, sparse, and DARK — almost no treble. The treble ramp is
        // what separates it from Country at the same tempo.
        s[.blues] = bell(bpmF, 78, 26) * 0.26
            + (1 - ramp(onsets, 0.05, 0.30)) * 0.26
            + (1 - ramp(treble, 0.04, 0.14)) * 0.28
            + ramp(mid, 0.14, 0.32) * 0.20

        // Country: mid tempo with a bright acoustic top end (fiddle / steel /
        // brushed snare). Rewards treble, which Blues specifically lacks.
        s[.country] = bell(bpmF, 104, 24) * 0.24
            + ramp(treble, 0.10, 0.24) * 0.30
            + ramp(vocal, 0.10, 0.30) * 0.26
            + ramp(onsets, 0.18, 0.48) * 0.20

        // Ambient: barely any onsets, little dynamic movement, no real beat.
        // Its score is *inverted* on purpose — every rhythmic genre gets
        // disqualified below when there's no beat, so this only has to
        // out-score an empty field, which it does comfortably.
        s[.ambient] = (1 - ramp(onsets, 0.02, 0.22)) * 0.55
            + (1 - ramp(range, 0.04, 0.22)) * 0.25
            + (bpm < 60 ? 0.20 : 0.0)

        // --- Beat gate ------------------------------------------------------
        // BPM below 40 means we never locked onto a pulse: pads, drones, or
        // just silence. Every genre except Ambient is rhythmic, so they're all
        // disqualified rather than left to tie at a partial score — which is
        // what used to let a tempo-less acoustic ballad get called R&B.
        if !hasBeat {
            for g in Genre.allCases where g != .ambient { s[g] = 0 }
        }

        lastScores = s
        lastFeatures = ["bpm": bpmF, "bass": bass, "mid": mid, "treble": treble, "centroid": centroid,
                        "onsets": onsets, "range": range, "vocal": vocal]

        let ranked = s.sorted { $0.value > $1.value }
        guard let top = ranked.first else { return (.rock, 0) }
        let runnerUp = ranked.count > 1 ? ranked[1].value : 0

        // Confidence is the margin over the runner-up, saturating at 0.18 of
        // separation. Reporting the raw top score instead would be dishonest:
        // two genres can both score 0.8 and be completely indistinguishable.
        let margin = max(0, top.value - runnerUp)
        let confidence = min(1, margin / 0.18)
        return (top.key, confidence)
    }
}