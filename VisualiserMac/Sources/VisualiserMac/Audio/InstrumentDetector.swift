import Foundation
import AVFoundation
import SoundAnalysis

/// Detects which band parts are playing using Apple's built-in on-device sound
/// classifier (SoundAnalysis, ~300 sound classes). It sees a sliding window of
/// audio, so presence updates a few times a second. That's fine for "who is
/// playing"; per-frame timing comes from the spectrum (see OpenGLRenderer).
final class InstrumentDetector: NSObject, SNResultsObserving {
    enum Part: Int, CaseIterable {
        case drums, bass, guitar, keys, vocals
    }

    /// Classifier labels that count towards each part (max confidence wins).
    private static let labels: [Part: [String]] = [
        .drums: ["drum", "drum_kit", "bass_drum", "snare_drum", "cymbal", "hi_hat"],
        .bass: ["bass_guitar", "double_bass"],
        .guitar: ["guitar", "electric_guitar", "acoustic_guitar", "guitar_strum",
                  "plucked_string_instrument", "steel_guitar_slide_guitar", "guitar_tapping"],
        .keys: ["piano", "electric_piano", "keyboard_musical", "synthesizer", "organ",
                "electronic_organ", "hammond_organ", "vibraphone"],
        .vocals: ["singing", "choir_singing", "rapping"],
    ]

    static let sampleRate: Double = 48000
    private static let chunkFrames = 4800   // hand audio to the analyzer every 0.1s

    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private let analyzer: SNAudioStreamAnalyzer
    private let queue = DispatchQueue(label: "viz.instruments", qos: .utility)
    private var framePosition: AVAudioFramePosition = 0

    // Audio-thread staging (single producer).
    private var staging = [Float](repeating: 0, count: chunkFrames)
    private var stagingCount = 0

    private var lastLog: CFAbsoluteTime = 0
    private let lock = NSLock()
    private var confidence = [Float](repeating: 0, count: Part.allCases.count)

    // Lead vocals. The classifier has no male/female singing classes, so while
    // it hears singing we track the voiced pitch (YIN). Over ~20s, a high
    // cluster reads as female, a low one as male, and both together as a duet;
    // the last ~0.6s says who is singing right now. A heuristic: ranges
    // overlap, and in a busy mix the tracker can lock onto an instrument.
    enum Lineup: String { case female, male, duet }
    private var pitchSamples: [(time: Double, hz: Float)] = []
    private static let lineupWindow = 20.0, currentWindow = 0.6
    private var lineup: Lineup?
    private var currentHigh: Bool?
    private var chunkTime: Double = 0      // audio time of the latest chunk (under lock)
    private var hpState: Float = 0, hpPrev: Float = 0

    /// Only analyse while the band vibscape is on screen. Set from the render
    /// thread, read from the audio thread; a stale read just costs one chunk.
    var isEnabled = false

    override init() {
        analyzer = SNAudioStreamAnalyzer(format: format)
        super.init()
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            // Shortest window the classifier allows, with heavy overlap, so
            // results arrive as often as possible.
            if case .enumeratedDurations(let durations) = request.windowDurationConstraint,
               let shortest = durations.min(by: { $0.seconds < $1.seconds }) {
                request.windowDuration = shortest
            }
            request.overlapFactor = 0.75
            try analyzer.add(request, withObserver: self)
            NSLog("[BAND] classifier window \(request.windowDuration.seconds)s")
        } catch {
            NSLog("[BAND] sound classifier unavailable: \(error.localizedDescription)")
        }
    }

    /// Per-part confidence, 0...1.
    func presence() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return confidence
    }

    /// Who sings lead (nil until enough sung pitch has been heard), and whether
    /// the voice singing right now is the high one (nil if nobody just sang).
    func vocals() -> (lineup: Lineup?, currentHigh: Bool?) {
        lock.lock(); defer { lock.unlock() }
        let fresh = pitchSamples.last.map { chunkTime - $0.time < 1.0 } ?? false
        return (lineup, fresh ? currentHigh : nil)
    }

    /// Forget the vocal estimate, e.g. at a song change, so the next song's
    /// singers are worked out afresh.
    func resetVocals() {
        lock.lock(); defer { lock.unlock() }
        pitchSamples.removeAll()
        lineup = nil
        currentHigh = nil
    }

    static let highHz: Float = 200, lowHz: Float = 185

    /// Decide the line-up from recent sung pitches. Hysteresis via `previous`.
    static func lineup(from hz: [Float], previous: Lineup?) -> Lineup? {
        guard hz.count >= 8 else { return previous }
        let high = hz.filter { $0 > highHz }.sorted()
        let low = hz.filter { $0 < lowHz }.sorted()
        let fh = Float(high.count) / Float(hz.count), fl = Float(low.count) / Float(hz.count)
        // Two clusters an octave apart are usually one voice with octave
        // errors from the tracker, not a duet.
        var octaveApart = false
        if !high.isEmpty && !low.isEmpty {
            let ratio = high[high.count / 2] / low[low.count / 2]
            octaveApart = ratio > 1.9 && ratio < 2.1
        }
        let both = min(fh, fl)
        if hz.count >= 16 && !octaveApart && both >= (previous == .duet ? 0.12 : 0.25) { return .duet }
        let median = hz.sorted()[hz.count / 2]
        switch previous {
        case .female?: return median < lowHz ? .male : .female
        case .male?: return median > 210 ? .female : .male
        default: return median > 197 ? .female : .male
        }
    }

    /// Audio thread: called with every mono buffer written to the ring buffer.
    func push(_ samples: UnsafePointer<Float>, count: Int) {
        guard isEnabled else { return }
        var offset = 0
        while offset < count {
            let n = min(count - offset, Self.chunkFrames - stagingCount)
            staging.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.advanced(by: stagingCount).update(from: samples.advanced(by: offset), count: n)
            }
            stagingCount += n
            offset += n
            if stagingCount == Self.chunkFrames {
                let chunk = staging
                stagingCount = 0
                queue.async { [weak self] in self?.analyze(chunk) }
            }
        }
    }

    private func analyze(_ chunk: [Float]) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(chunk.count)
        chunk.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: chunk.count)
        }
        analyzer.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(chunk.count)
        trackVocalPitch(chunk)
    }

    /// Runs on the analysis queue for each 0.1s chunk.
    private func trackVocalPitch(_ chunk: [Float]) {
        let now = Double(framePosition) / Self.sampleRate
        lock.lock()
        chunkTime = now
        let singing = confidence[Part.vocals.rawValue]
        lock.unlock()
        guard singing > 0.25 else { return }

        // High-pass (~150Hz) to drop bass and kick, then average down 4x to
        // 12kHz, which also low-passes.
        var x = [Float](repeating: 0, count: chunk.count / 4)
        let a: Float = 0.98
        for i in 0..<x.count {
            var acc: Float = 0
            for j in 0..<4 {
                let s = chunk[i * 4 + j]
                hpState = a * (hpState + s - hpPrev)
                hpPrev = s
                acc += hpState
            }
            x[i] = acc / 4
        }
        guard let f0 = Self.yin(x, sampleRate: 12000, minHz: 80, maxHz: 1000) else { return }

        lock.lock(); defer { lock.unlock() }
        pitchSamples.append((now, f0))
        pitchSamples.removeAll { now - $0.time > Self.lineupWindow }
        lineup = Self.lineup(from: pitchSamples.map(\.hz), previous: lineup)
        let recent = pitchSamples.filter { now - $0.time <= Self.currentWindow }.map(\.hz).sorted()
        if !recent.isEmpty { currentHigh = recent[recent.count / 2] > 197 }
    }

    /// YIN pitch estimate (de Cheveigné & Kawahara), or nil if not clearly voiced.
    static func yin(_ x: [Float], sampleRate: Float, minHz: Float, maxHz: Float) -> Float? {
        let maxLag = Int(sampleRate / minHz), minLag = Int(sampleRate / maxHz)
        let w = x.count - maxLag - 1
        guard w > 64 else { return nil }
        var d = [Float](repeating: 0, count: maxLag + 2)
        for tau in 1...(maxLag + 1) {
            var sum: Float = 0
            for i in 0..<w { let diff = x[i] - x[i + tau]; sum += diff * diff }
            d[tau] = sum
        }
        // cumulative mean normalised difference
        var running: Float = 0
        var cmnd = [Float](repeating: 1, count: d.count)
        for tau in 1..<d.count {
            running += d[tau]
            cmnd[tau] = running > 0 ? d[tau] * Float(tau) / running : 1
        }
        // First dip under the strict threshold; failing that (dense mixes are
        // less periodic), the deepest dip if it's still reasonably clear.
        var found: Int?
        var tau = minLag
        while tau < maxLag {
            if cmnd[tau] < 0.15 {
                while tau + 1 < maxLag && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        if found == nil {
            var best = minLag
            for t in minLag..<maxLag where cmnd[t] < cmnd[best] { best = t }
            if cmnd[best] < 0.3 { found = best }
        }
        guard let t = found else { return nil }
        let a = cmnd[t - 1], b = cmnd[t], c = cmnd[t + 1]
        let denom = a - 2 * b + c
        let shift = denom != 0 ? 0.5 * (a - c) / denom : 0
        return sampleRate / (Float(t) + shift)
    }

    // MARK: - SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        var next = [Float](repeating: 0, count: Part.allCases.count)
        for part in Part.allCases {
            next[part.rawValue] = Self.labels[part]!
                .compactMap { result.classification(forIdentifier: $0)?.confidence }
                .map(Float.init).max() ?? 0
        }
        lock.lock(); confidence = next; lock.unlock()
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastLog > 3 {
            lastLog = now
            lock.lock()
            let hz = pitchSamples.map(\.hz).sorted()
            let median = hz.isEmpty ? 0 : hz[hz.count / 2]
            let voice = lineup?.rawValue ?? "?"
            let samples = hz.count
            lock.unlock()
            NSLog("[BAND] drums %.2f bass %.2f guitar %.2f keys %.2f vocals %.2f | voice %@ (median %.0fHz, %d samples)",
                  next[0], next[1], next[2], next[3], next[4], voice, median, samples)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        NSLog("[BAND] classification failed: \(error.localizedDescription)")
    }
}
