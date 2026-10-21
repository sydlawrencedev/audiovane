import Foundation
import Accelerate
import Darwin

/// FFT + log-binned spectrum + adaptive beat detection + BPM.
/// Pulls fresh samples from a ring buffer on demand.
final class AudioAnalyzer {
    static let fftSize = 2048
    static let bandCount = 96
    static let sampleRate: Double = 48000

    private let ringBuffer: AudioRingBuffer

    // vDSP FFT setup
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    /// SIMD-aligned buffers (16-byte alignment required by vDSP). Allocated
    /// via posix_memalign in init; deallocated in deinit. Using Swift `[Float]`
    /// for these is unsafe because the arrays are only 4-byte aligned, which
    /// causes vDSP_fft_zrip to segfault on real audio.
    private let realBuf: UnsafeMutablePointer<Float>
    private let imagBuf: UnsafeMutablePointer<Float>
    private let fftBinsBuf: UnsafeMutablePointer<Float>
    private let halfSize: Int

    private var window: [Float]
    private var timeDomain: [Float]
    private var bandsRaw: [Float]  // per-band 0..1 (instant)
    private var bandsSmoothBuf: [Float] // smoothed
    private var scratchBuf: [Float]

    // smoothed state
    private(set) var rms: Float = 0
    private(set) var bass: Float = 0
    private(set) var mid: Float = 0
    private(set) var treble: Float = 0
    private(set) var level: Float = 0
    private(set) var beat: Bool = false
    private(set) var beatStrength: Float = 0
    private(set) var bpm: Double = 0

    // beat detection
    private var bassHistory: [Float]
    private var historyIndex: Int = 0
    private var framesSinceLastBeat: Int = 0
    private var _tickCounter: Int = 0

    // automatic gain
    private static let gainAttack: Float = 0.5     // per tick, toward a louder peak
    private static let gainRelease: Float = 0.995  // per tick, ~2s to halve at 60fps
    private static let gainFloor: Float = 0.05     // raw magnitude treated as silence
    private static let gainHeadroom: Float = 0.9   // loudest band maps to this
    private var bandPeak: Float = AudioAnalyzer.gainFloor
    // noise gate on time-domain RMS (~-54 dBFS closed, ~-40 dBFS fully open)
    private static let gateLow: Float = 0.002
    private static let gateHigh: Float = 0.01

    // BPM — onset timestamps
    private var onsetTimes: [Double] = []
    private let maxOnsets = 64
    private static let bpmTimeout: Double = 3.0
    private var lastTickTime: Double = 0

    init(ringBuffer: AudioRingBuffer) {
        self.ringBuffer = ringBuffer
        self.log2n = vDSP_Length(log2(Float(AudioAnalyzer.fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.halfSize = AudioAnalyzer.fftSize / 2

        // 16-byte aligned allocations for vDSP SIMD routines
        let size = halfSize * MemoryLayout<Float>.size
        var rp: UnsafeMutableRawPointer?
        var ip: UnsafeMutableRawPointer?
        var fbp: UnsafeMutableRawPointer?
        posix_memalign(&rp, 16, size)
        posix_memalign(&ip, 16, size)
        posix_memalign(&fbp, 16, size)
        self.realBuf = rp!.assumingMemoryBound(to: Float.self)
        self.imagBuf = ip!.assumingMemoryBound(to: Float.self)
        self.fftBinsBuf = fbp!.assumingMemoryBound(to: Float.self)
        for i in 0..<halfSize {
            self.realBuf[i] = 0
            self.imagBuf[i] = 0
            self.fftBinsBuf[i] = 0
        }

        self.window = [Float](repeating: 0, count: AudioAnalyzer.fftSize)
        self.timeDomain = [Float](repeating: 0, count: AudioAnalyzer.fftSize)
        self.bandsRaw = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
        self.bandsSmoothBuf = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
        self.scratchBuf = [Float](repeating: 0, count: AudioAnalyzer.fftSize)
        self.bassHistory = [Float](repeating: 0, count: 43)
        self.historyIndex = 0
        self._tickCounter = 0

        vDSP_hann_window(&window, vDSP_Length(AudioAnalyzer.fftSize), Int32(vDSP_HANN_NORM))

        // pre-compute band edges (Hz -> bin index)
        bandEdges = Self.computeBandEdges(count: AudioAnalyzer.bandCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        let size = halfSize * MemoryLayout<Float>.size
        realBuf.deinitialize(count: halfSize)
        realBuf.deallocate()
        imagBuf.deinitialize(count: halfSize)
        imagBuf.deallocate()
        fftBinsBuf.deinitialize(count: halfSize)
        fftBinsBuf.deallocate()
        _ = size
    }

    private let bandEdges: [Int]

    private static func computeBandEdges(count: Int) -> [Int] {
        let sampleRate = AudioAnalyzer.sampleRate
        let nyquist = sampleRate / 2
        let binCount = AudioAnalyzer.fftSize / 2
        let binHz = nyquist / Double(binCount)
        let fMin = 40.0
        let fMax = min(16000.0, nyquist)
        var edges: [Int] = []
        edges.reserveCapacity(count + 1)
        for i in 0...count {
            let t = Double(i) / Double(count)
            let f = fMin * pow(fMax / fMin, t)
            let bin = max(1, min(binCount - 1, Int(round(f / binHz))))
            edges.append(bin)
        }
        return edges
    }

    /// Call once per render frame. Drains the ring buffer of the latest FFT window.
    func tick() {
        let needed = AudioAnalyzer.fftSize
        // Sliding window: analyse the newest `needed` samples every frame
        // (overlapping), rather than consuming a full window per frame, which
        // starves at 60fps and makes the analysis update in bursts.
        let ok = timeDomain.withUnsafeMutableBufferPointer { buf -> Bool in
            guard let p = buf.baseAddress else { return false }
            return ringBuffer.readLatest(into: p, count: needed)
        }
        guard ok else { return }
        // Onsets are timestamped in audio time (samples received), not wall
        // time, so frame-scheduling jitter doesn't skew the tempo estimate.
        let audioTime = Double(ringBuffer.totalWritten) / AudioAnalyzer.sampleRate

        var rmsVal: Float = 0
        vDSP_rmsqv(timeDomain, 1, &rmsVal, vDSP_Length(needed))
        self.rms = rmsVal
        // 0 below the noise floor, 1 once there's clearly sound; fades between.
        let gate = min(1, max(0, (rmsVal - AudioAnalyzer.gateLow) / (AudioAnalyzer.gateHigh - AudioAnalyzer.gateLow)))

        // Apply window function.
        vDSP_vmul(timeDomain, 1, window, 1, &scratchBuf, 1, vDSP_Length(needed))

        // vDSP_fft_zrip expects the real signal packed as split-complex:
        //   real[i] = x[2i], imag[i] = x[2i + 1]
        var split = DSPSplitComplex(realp: realBuf, imagp: imagBuf)
        scratchBuf.withUnsafeBufferPointer { fp in
            guard let fpAddr = fp.baseAddress else { return }
            fpAddr.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cp in
                vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(halfSize))
            }
        }

        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, fftBinsBuf, 1, vDSP_Length(halfSize))

        // normalize and sqrt to get magnitude
        var n = Int32(halfSize)
        var scale: Float = 1.0 / Float(AudioAnalyzer.fftSize)
        vDSP_vsmul(fftBinsBuf, 1, &scale, fftBinsBuf, 1, vDSP_Length(halfSize))
        vvsqrtf(fftBinsBuf, fftBinsBuf, &n)

        // log-band averaging
        for b in 0..<AudioAnalyzer.bandCount {
            let lo = bandEdges[b]
            let hi = max(lo + 1, bandEdges[b + 1])
            var sum: Float = 0
            for i in lo..<hi { sum += fftBinsBuf[i] }
            bandsRaw[b] = sum / Float(hi - lo)
        }

        // Automatic gain: follow the loudest band with fast attack / slow
        // release and normalise against it, so quiet and loud sources both
        // fill the 0..1 range. The floor stops silence being amplified to noise.
        var frameMax: Float = 0
        vDSP_maxv(bandsRaw, 1, &frameMax, vDSP_Length(AudioAnalyzer.bandCount))
        // Hold the gain while gated so silence doesn't wind it up to full boost.
        if gate > 0 {
            if frameMax > bandPeak {
                bandPeak += (frameMax - bandPeak) * AudioAnalyzer.gainAttack
            } else {
                bandPeak *= AudioAnalyzer.gainRelease
            }
            bandPeak = max(bandPeak, AudioAnalyzer.gainFloor)
        }
        let gain = AudioAnalyzer.gainHeadroom / bandPeak * gate
        for b in 0..<AudioAnalyzer.bandCount {
            bandsRaw[b] = min(1.0, bandsRaw[b] * gain)
        }

        // band averages
        let third = AudioAnalyzer.bandCount / 3
        var bSum: Float = 0, mSum: Float = 0, tSum: Float = 0
        for i in 0..<third { bSum += bandsRaw[i] }
        for i in third..<(third * 2) { mSum += bandsRaw[i] }
        for i in (third * 2)..<AudioAnalyzer.bandCount { tSum += bandsRaw[i] }
        let bassInstant = bSum / Float(third)
        let midInstant  = mSum / Float(third)
        let trebInstant = tSum / Float(AudioAnalyzer.bandCount - third * 2)

        // smoothing
        let a: Float = 0.32
        bass  += (bassInstant - bass)  * a
        mid   += (midInstant  - mid)   * a
        treble += (trebInstant - treble) * a
        level = (bass + mid + treble) / 3
        for i in 0..<AudioAnalyzer.bandCount {
            bandsSmoothBuf[i] += (bandsRaw[i] - bandsSmoothBuf[i]) * a
        }

        // beat detection on bass
        var histAvg: Float = 0
        vDSP_meanv(bassHistory, 1, &histAvg, vDSP_Length(bassHistory.count))
        var histStd: Float = 0
        var histMean = histAvg
        var negMean = -histMean
        vDSP_vsadd(bassHistory, 1, &negMean, &scratchBuf, 1, vDSP_Length(bassHistory.count))
        var sqSum: Float = 0
        vDSP_svesq(scratchBuf, 1, &sqSum, vDSP_Length(bassHistory.count))
        histStd = sqrtf(sqSum / Float(bassHistory.count))

        let threshold = histAvg * 1.32 + histStd * 0.6 + 0.04
        var isBeat = false
        if bassInstant > threshold && bassInstant > 0.18 && gate >= 1 {
            if framesSinceLastBeat > 12 {
                isBeat = true
                framesSinceLastBeat = 0
                onsetTimes.append(audioTime)
                if onsetTimes.count > maxOnsets { onsetTimes.removeFirst() }
            }
        }
        bassHistory[historyIndex] = bassInstant
        historyIndex = (historyIndex + 1) % bassHistory.count
        framesSinceLastBeat += 1
        beat = isBeat
        beatStrength = isBeat ? min(1.0, bassInstant) : beatStrength * 0.86

        // No beats for a few seconds (silence, or a break in the music): forget
        // the tempo, so the HUD doesn't show a stale BPM and the next song's
        // estimate isn't mixed with old onsets.
        if let last = onsetTimes.last, audioTime - last > AudioAnalyzer.bpmTimeout {
            onsetTimes.removeAll()
            bpm = 0
        }

        // BPM
        if onsetTimes.count >= 8 {
            var intervals: [Double] = []
            for i in 1..<onsetTimes.count {
                let d = onsetTimes[i] - onsetTimes[i - 1]
                if d > 0.25 && d < 1.2 { intervals.append(d) }
            }
            if intervals.count >= 4 {
                intervals.sort()
                let med = intervals[intervals.count / 2]
                // Average the intervals close to the median: rejects missed or
                // extra beats like the median does, but cancels out the
                // one-frame rounding of individual onset times.
                let near = intervals.filter { abs($0 - med) < med * 0.08 }
                var est = 60.0 / (near.reduce(0, +) / Double(near.count))
                while est < 70 { est *= 2 }
                while est > 180 { est /= 2 }
                let target = est.rounded()
                if bpm == 0 { bpm = target } else { bpm += (target - bpm) * 0.05 }
            }
        }
    }

    /// Copy smoothed bands into a destination buffer.
    func copyBands(into dest: UnsafeMutablePointer<Float>, count: Int) {
        let n = min(count, AudioAnalyzer.bandCount)
        for i in 0..<n {
            dest[i] = bandsSmoothBuf[i]
        }
    }

    /// Helper for debug logging.
    func copyBandsHelper(_ index: Int) -> Float {
        guard index >= 0, index < AudioAnalyzer.bandCount else { return 0 }
        return bandsSmoothBuf[index]
    }

    /// Direct-write bands + analysis state for snapshots. Bypasses FFT so we
    /// don't have to debug the vDSP pipeline offline.
    /// Plausible analyzer state without any audio, so a vibescape can be drawn
    /// with something to react to.
    ///
    /// `kick` and `barPhase` let a caller drive this from a beat clock. One
    /// call with no arguments is right for a still; a video needs the numbers
    /// to move, because the spectrum, band and waveform vibescapes draw
    /// `uBands`, and a frozen spectrum is a flat line with nothing happening on
    /// it.
    func setSyntheticState(kick: Float = 1, barPhase: Float = 0) {
        let n = AudioAnalyzer.bandCount
        for i in 0..<n {
            let t = Float(i) / Float(n)
            // Bass-heavy with treble sparkle. Mimics what we'd get from the
            // synthetic kick + pad.
            let base = (1.0 - t) * 0.7 + 0.3 * sinf(t * 18.0)
            // A kick swells the low end hardest, the way a real one does.
            let swell = 1.0 + kick * 0.30 * (1.0 - t)
            // Bar position slides a lobe up the spectrum, so the shape shifts
            // rather than only getting louder.
            let drift = 0.12 * sinf(t * 18.0 + barPhase * 2 * .pi)
            bandsRaw[i] = max(0, min(1, base * swell + drift + 0.08 * Float.random(in: 0...1)))
            bandsSmoothBuf[i] = bandsRaw[i]
        }
        rms = 0.35 + 0.18 * kick
        bass = min(1, 0.62 + 0.28 * kick)
        mid = 0.42 + 0.12 * kick
        treble = min(1, 0.22 + 0.20 * barPhase)
        level = 0.42 + 0.22 * kick
        beat = kick > 0.75
        beatStrength = 0.62 * max(0.15, kick)
        bpm = 124
    }

    var bandCountValue: Int { AudioAnalyzer.bandCount }
}