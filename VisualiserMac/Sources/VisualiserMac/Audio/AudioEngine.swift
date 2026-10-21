import Foundation
import AVFoundation
import Combine

/// Orchestrates audio capture + analysis. Single source-of-truth for the app.
/// Render thread reads `snapshot` for GPU uniforms; SwiftUI binds to @Published vars.
final class AudioEngine: ObservableObject {
    @Published private(set) var sourceLabel: String = "idle"
    @Published private(set) var sourceState: SourceState = .idle
    @Published private(set) var showIntro: Bool = true
    /// What's actually running, nil while idle or errored. The picker shows
    /// this as the current choice; the header pill shows its label.
    @Published private(set) var activeSource: AudioSource? = nil
    @Published private(set) var bpm: Double = 0
    @Published private(set) var lastBeatStrength: Float = 0
    /// True while there's audible sound (RMS gate with hysteresis). Overlays
    /// fade out when false so silent vibescapes are a single flat colour.
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
        // Six seconds of history, which is twenty-one once it is rounded up to
        // a power of two — enough for the ten-second recording the share
        // sheet makes, and the extra room is four megabytes.
        let rb = AudioRingBuffer(seconds: 6, sampleRate: 48000)
        self.ringBuffer = rb
        self.analyzer = AudioAnalyzer(ringBuffer: rb)
        rb.onWrite = { [instruments] samples, count in instruments.push(samples, count: count) }
        self.systemCapture = SystemAudioCapture(ringBuffer: rb)
        self.systemCapture.onError = { [weak self] msg in
            DispatchQueue.main.async {
                self?.fail(reason: "capture stopped", detail: msg)
            }
        }
    }

    /// The last `seconds` of audio, as much of it as there is.
    ///
    /// A recording wants the music that is actually there: ten seconds of it
    /// if there has been ten seconds of it, and what there is if there isn't.
    /// The buffer's length is the length of the recording.
    func recentAudio(upTo seconds: Double) -> AVAudioPCMBuffer? {
        let sampleRate = 48000.0
        let wanted = Int(seconds * sampleRate)
        guard wanted > 0 else { return nil }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(wanted)) else {
            return nil
        }
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        let got = ringBuffer.readLatestAvailable(into: samples, count: wanted)
        guard got > 0 else { return nil }
        buffer.frameLength = AVAudioFrameCount(got)
        return buffer
    }

    /// The last few seconds of audio, as a buffer something else can sign.
    ///
    /// ShazamKit takes a buffer of audio and turns it into a signature. It
    /// wants a few seconds of it — the app's ring buffer holds about five and
    /// a half — and it wants float samples at 48kHz, which is what the
    /// capture is.
    func recentAudioBuffer(seconds: Double) -> AVAudioPCMBuffer? {
        let sampleRate = 48000.0
        let wanted = Int(seconds * sampleRate)
        guard wanted > 0 else { return nil }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(wanted)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(wanted)

        guard let samples = buffer.floatChannelData?[0] else { return nil }
        let ok = ringBuffer.readLatest(into: samples, count: wanted)
        guard ok else { return nil }
        return buffer
    }

    // MARK: - Source switching

    // Still filed under the old name, so the chosen source survives the rename.
    private static let sourceDefaultsKey = "audiovane.source"

    /// The source to pick next time. System audio is the default because the
    /// app exists to visualise it; the microphone is remembered too, but is
    /// never started without being asked for (see `restoreLastSource`).
    private(set) var savedSource: AudioSource {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.sourceDefaultsKey),
                  let source = AudioSource(rawValue: raw) else { return .system }
            return source
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.sourceDefaultsKey) }
    }

    /// Whether a source has ever been chosen on this install. A fresh install
    /// hasn't, so the intro still explains what's about to happen before macOS
    /// asks for anything.
    private var hasChosenSource: Bool {
        UserDefaults.standard.string(forKey: Self.sourceDefaultsKey) != nil
    }

    /// Reconnects the source the user was last on, so granting system audio is
    /// a one-time thing rather than a question on every launch.
    ///
    /// The microphone is the exception: it can pick up a room, so it always
    /// takes a deliberate click, even when it was the last thing in use. If the
    /// remembered source can't start — permission revoked, no mic attached —
    /// the intro comes back with the error, which is the honest answer.
    func restoreLastSource() async {
        guard hasChosenSource else { return }
        let source = savedSource
        guard source.restoresOnLaunch else { return }
        // Don't flash the intro on the way past it. Every start path below puts
        // it back if the attempt fails.
        showIntro = false
        switch source {
        case .system: await startSystemCapture()
        case .demo: startDemo()
        case .microphone: break
        }
    }

    /// Every failure lands here, so the UI state, the crash breadcrumb and the
    /// Discord report can never disagree about what happened. `detail` is the
    /// human-readable reason; `report` is whether it's worth telling us — a
    /// user who declines the permission prompt is a normal outcome, not a bug,
    /// so those don't get reported.
    private func fail(reason: String, detail: String, report: Bool = true) {
        sourceLabel = reason
        sourceState = .error
        showIntro = true
        activeSource = nil
        CrashReporter.shared.log("audio failed: \(reason) — \(detail)")
        guard report else { return }
        ProblemReporter.report(.current(
            kind: "audio_error",
            title: "Audio source failed: \(reason)",
            message: detail,
            state: CrashReporter.shared.currentState()))
    }

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
            activeSource = .system
            savedSource = .system
        } catch {
            // A denied permission is a choice, not a fault. It arrives as a
            // CoreAudio status like any other failure and there's no public
            // constant for it, so it's identified by the text the system
            // produces — which is a heuristic, and deliberately one that only
            // *suppresses* a report rather than inventing one.
            let denied = error.localizedDescription.lowercased()
                .contains("permi") || error.localizedDescription.lowercased().contains("denied")
            fail(reason: denied ? "denied" : "system audio failed",
                 detail: error.localizedDescription,
                 report: !denied)
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
            fail(reason: "no mic input", detail: "The input device reports a zero sample rate.")
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
            activeSource = .microphone
            savedSource = .microphone
        } catch {
            fail(reason: "mic failed", detail: error.localizedDescription)
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
            activeSource = .demo
            savedSource = .demo
        } catch {
            fail(reason: "demo failed", detail: error.localizedDescription)
        }
    }

    func disconnect() {
        stopAll()
        sourceLabel = "idle"
        sourceState = .idle
        showIntro = true
        activeSource = nil
    }

    /// Inject synthetic audio into the ring buffer. Used by snapshot vibescape to
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
        // Snapshot vibescape: bypass the FFT pipeline (which has issues in headless vibescape)
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
    /// analyzer. Used by snapshot vibescape to avoid running the FFT pipeline.
    /// Drives the analyzer from a beat clock, for offline rendering.
    ///
    /// Nothing is playing, but the vibescapes still need to move — a video of
    /// eighteen vibescapes all reacting to one frozen moment reads as a bug.
    /// Time drives everything, so this is deterministic: the same seconds give
    /// the same frame every time, which is what makes a re-render comparable.
    func syntheticState(at seconds: Double, bpm: Double = 124) {
        let beat = 60.0 / bpm
        let phase = seconds.truncatingRemainder(dividingBy: beat) / beat
        // Sharp attack, exponential decay: 1 on the beat, gone by the next.
        let kick = Float(exp(-phase * 5.5))
        let barPhase = Float(seconds.truncatingRemainder(dividingBy: beat * 4) / (beat * 4))
        analyzer.setSyntheticState(kick: kick, barPhase: barPhase)
    }

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