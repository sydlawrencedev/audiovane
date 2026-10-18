import Foundation
import AVFoundation
import Combine

/// Orchestrates audio capture + analysis. Single source-of-truth for the app.
/// Render thread reads `snapshot` for GPU uniforms; SwiftUI binds to @Published vars.
final class AudioEngine: ObservableObject {
    @Published private(set) var sourceLabel: String = "idle"
    @Published private(set) var sourceState: SourceState = .idle
    @Published private(set) var showIntro: Bool = true
    @Published private(set) var bpm: Double = 0
    @Published private(set) var lastBeatStrength: Float = 0
    /// True while there's audible sound (RMS gate with hysteresis). Overlays
    /// fade out when false so silent modes are a single flat colour.
    @Published private(set) var isSounding: Bool = false

    /// String the render path uses to decide whether to redraw. Exposed so the
    /// OpenGL view can skip frames without going through Combine.
    var sourceKindForRender: String {
        switch sourceState {
        case .idle: return "idle"
        case .live: return "live"
        case .demo: return "demo"
        case .error: return "error"
        }
    }

    /// Monotonically increasing tick published at ~30Hz. SwiftUI views that
    /// need to refresh per-frame subscribe to this instead of using TimelineView,
    /// which otherwise re-evaluates the view tree on a fixed schedule and
    /// causes constant re-renders (and visible flicker on overlays).
    @Published private(set) var displayTick: Int = 0
    private var lastDisplayTickTime: CFTimeInterval = 0
    private let displayInterval: CFTimeInterval = 1.0 / 30.0

    /// Snapshot consumed by the Metal renderer. Atomic struct replacement.
    private(set) var snapshot = AudioSnapshot()

    let ringBuffer: AudioRingBuffer
    let analyzer: AudioAnalyzer
    let instruments = InstrumentDetector()
    let tracks = TrackChangeWatcher()
    let genreDetector = GenreDetector()

    private var systemCapture: SystemAudioCapture!
    private let demoTone = DemoTone()
    private let micEngine = AVAudioEngine()
    private var micTapInstalled = false

    init() {
        let rb = AudioRingBuffer(seconds: 1.5, sampleRate: 48000)
        self.ringBuffer = rb
        self.analyzer = AudioAnalyzer(ringBuffer: rb)
        rb.onWrite = { [instruments] samples, count in instruments.push(samples, count: count) }
        self.systemCapture = SystemAudioCapture(ringBuffer: rb)
        self.systemCapture.onError = { [weak self] msg in
            DispatchQueue.main.async {
                self?.sourceLabel = "error"
                self?.sourceState = .error
                self?.showIntro = true
            }
        }
    }

    // MARK: - Source switching

    func startSystemCapture() async {
        stopAll()
        ringBuffer.reset()
        sourceLabel = "requesting system audio…"
        sourceState = .idle
        do {
            try await systemCapture.start()
            sourceLabel = "system audio"
            sourceState = .live
            showIntro = false
        } catch {
            sourceLabel = "denied"
            sourceState = .error
            showIntro = true
            NSLog("System audio failed: \(error.localizedDescription)")
        }
    }

    func startMicrophone() {
        stopAll()
        ringBuffer.reset()
        sourceLabel = "requesting mic…"
        sourceState = .idle
        let inputNode = micEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            sourceLabel = "no mic input"
            sourceState = .error
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let data = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: count)
            for c in 0..<channels {
                let ptr = data[c]
                for i in 0..<count { mono[i] += ptr[i] }
            }
            if channels > 1 {
                for i in 0..<count { mono[i] /= Float(channels) }
            }
            mono.withUnsafeBufferPointer { ptr in
                self.ringBuffer.write(ptr.baseAddress!, count: count)
            }
        }
        micTapInstalled = true
        do {
            micEngine.prepare()
            try micEngine.start()
            sourceLabel = "microphone"
            sourceState = .live
            showIntro = false
        } catch {
            sourceLabel = "mic failed"
            sourceState = .error
            inputNode.removeTap(onBus: 0)
            micTapInstalled = false
        }
    }

    func startDemo() {
        stopAll()
        ringBuffer.reset()
        do {
            try demoTone.start(into: ringBuffer)
            sourceLabel = "demo tone"
            sourceState = .demo
            showIntro = false
        } catch {
            sourceLabel = "demo failed"
            sourceState = .error
        }
    }

    func disconnect() {
        stopAll()
        sourceLabel = "idle"
        sourceState = .idle
        showIntro = true
    }

    /// Inject synthetic audio into the ring buffer. Used by snapshot mode to
    /// produce visible reactions without spinning up AVAudioEngine.
    func injectSyntheticTone(seconds: Double = 2.0, sampleRate: Double = 48000) {
        NSLog("[VIZ] injectSyntheticTone start")
        ringBuffer.reset()
        let total = Int(seconds * sampleRate)
        var samples = [Float](repeating: 0, count: total)
        for i in 0..<total {
            let t = Double(i) / sampleRate
            let beatPhase = (t.truncatingRemainder(dividingBy: 60.0 / 124.0)) / (60.0 / 124.0)
            var kick: Double = 0
            if beatPhase < 0.2 {
                kick = exp(-beatPhase * 30.0) * sin(2 * .pi * 60 * beatPhase)
            }
            let pad = sin(2 * .pi * (220 + 100 * sin(t * 0.5)) * t) * 0.3
            let sparkle = sin(2 * .pi * 4400 * t) * 0.05 * (0.5 + 0.5 * sin(t * 4))
            samples[i] = Float(kick + pad + sparkle)
        }
        // Snapshot mode: bypass the FFT pipeline (which has issues in headless mode)
        // and write plausible analyzer state directly. The visualizers then react
        // as if real audio were playing.
        analyzer.setSyntheticState()
    }

    private func stopAll() {
        systemCapture.stop()
        demoTone.stop()
        if micTapInstalled {
            micEngine.inputNode.removeTap(onBus: 0)
            micTapInstalled = false
        }
        if micEngine.isRunning { micEngine.stop() }
    }

    // MARK: - Render hook

    /// Called once per render frame.
    func tick() {
        analyzer.tick()
        refreshSnapshot()
        // Genre detection runs regardless of source state — even the demo tone
        // or silence yields useful features (zeros), and we want a smooth fade
        // when audio cuts out rather than freezing on the last call.
        let vocals = instruments.presence()
        let now = CACurrentMediaTime()
        genreDetector.update(snapshot: snapshot, beat: snapshot.beat,
                             vocal: vocals.indices.contains(4) ? vocals[4] : 0,
                             now: now)
        // In idle/error states, do NOT advance displayTick — that would
        // trigger SwiftUI body re-evaluations and force the OpenGL view's
        // drawable to be re-rasterized, which is the source of the perceived
        // flicker. When audio is flowing, the SwiftUI overlays need updates
        // for the meter/footer to show real values.
        guard sourceState == .live || sourceState == .demo else { return }
        if now - lastDisplayTickTime >= displayInterval {
            lastDisplayTickTime = now
            displayTick &+= 1
        }
    }

    /// Just rebuild the snapshot from current analyzer state, without ticking the
    /// analyzer. Used by snapshot mode to avoid running the FFT pipeline.
    func refreshSnapshot() {
        var snap = AudioSnapshot()
        snap.rms = analyzer.rms
        snap.bass = analyzer.bass
        snap.mid = analyzer.mid
        snap.treble = analyzer.treble
        snap.level = analyzer.level
        snap.beat = analyzer.beat
        snap.beatStrength = analyzer.beatStrength
        snap.bpm = analyzer.bpm
        snap.sourceIsIdle = (sourceState == .live || sourceState == .demo) ? 0.0 : 1.0
        analyzer.copyBands(into: &snap.bands, count: AudioAnalyzer.bandCount)
        self.snapshot = snap

        // Only update the @Published SwiftUI bindings when audio is actually
        // flowing. In idle/error states, every assignment to a @Published
        // property fires objectWillChange → SwiftUI body re-evaluation
        // 60 times per second → AppKit re-composites the OpenGL view's
        // drawable → visible shimmer. The footer just shows 0.00 in idle
        // anyway, so there's nothing for the user to lose.
        guard sourceState == .live || sourceState == .demo else { return }
        bpm = analyzer.bpm
        lastBeatStrength = analyzer.beatStrength

        let live = sourceState == .live || sourceState == .demo
        let sounding = live && (isSounding ? snap.rms > 0.003 : snap.rms > 0.008)
        if sounding != isSounding { isSounding = sounding }
    }
}

/// Snapshot of audio analysis — replaced atomically by AudioEngine.tick().
/// Read by the Metal renderer; safe because value-type replacement is atomic in Swift.
struct AudioSnapshot {
    var rms: Float = 0
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var level: Float = 0
    var beat: Bool = false
    var beatStrength: Float = 0
    var bpm: Double = 0
    var sourceIsIdle: Float = 1.0
    var bands: [Float] = Array(repeating: 0, count: AudioAnalyzer.bandCount)
}