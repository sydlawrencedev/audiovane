import SwiftUI
import Combine
import AppKit

final class AppState: ObservableObject {
    @Published var activeMode: VisualizerMode = .tunnel {
        didSet {
            if activeMode != oldValue {
                NSLog("[DD] mode changed \(oldValue.rawValue) -> \(activeMode.rawValue)")
                // Remembered, so the next launch opens where they left off
                // rather than snapping back to auto-scan.
                Self.savedMode = activeMode
                // The breadcrumb half of a crash report: "it crashed in band
                // mode" is only half a bug report, "…after switching jazz to
                // country, mid cross-fade" is the other half.
                CrashReporter.shared.log("mode \(oldValue.rawValue) -> \(activeMode.rawValue)")
                // Tallied rather than sent individually: a user cycling
                // through modes generates 40 events in a minute and PostHog
                // only wants the histogram.
                Task { await Analytics.shared.countInSession("mode_switches") }
                Task {
                    await Analytics.shared.countInSession("mode:\(activeMode.rawValue)")
                }
                Task {
                    await Analytics.shared.track("mode_changed", [
                        "mode": activeMode.rawValue,
                        "from_mode": oldValue.rawValue,
                        "via": viaPicker ? "picker" : (viaAutoScan ? "auto_scan" : "system"),
                    ])
                }
                viaPicker = false
                viaAutoScan = false
            }
        }
    }
    /// Set by the mode picker so the event can distinguish a deliberate click
    /// from the auto-scan cycling the stage underneath you.
    @Published var viaPicker: Bool = false
    @Published var viaAutoScan: Bool = false
    @Published var sourceLabel: String = "idle"
    @Published var sourceState: SourceState = .idle
    /// Mirrors `audio.activeSource`, so the header pill can say what's flowing.
    @Published var activeSource: AudioSource? = nil
    @Published var showIntro: Bool = true
    @Published var bpm: Double = 0
    @Published var lastBeat: Double = 0
    @Published var isSounding: Bool = false
    /// The Band's lead singer: detected from the vocal pitch, or forced.
    @Published var singerVoice: SingerVoice = .auto {
        didSet { renderer.singerVoice = singerVoice }
    }

    /// Which genre the band mode is showing. By default Rock, because the
    /// existing theatre stage looks like a rock venue. Auto-detect writes
    /// into this when `genreIsAuto` is true; the user clicking a genre in
    /// the picker locks the value for the rest of the current song.
    @Published var genre: Genre = .rock {
        didSet {
            // Pushing to the renderer is fire-and-forget; the renderer's own
            // genre-change handler in `bindBand` does the per-frame work.
            renderer.genre = genre
            // Any user-initiated change disables auto until the next song.
            if !genreIsAuto {
                genreLockAtChange = audio.tracks.changeCount
            }
            guard genre != oldValue else { return }
            CrashReporter.shared.log("genre \(oldValue.name) -> \(genre.name) (\(genreIsAuto ? "auto" : "locked"))")
            Task {
                await Analytics.shared.track(
                    genreIsAuto ? "genre_detected" : "genre_locked",
                    [
                        "genre": genre.name,
                        "from_genre": oldValue.name,
                        "genre_id": genre.rawValue,
                        "confidence": Double(round(genreConfidence * 100) / 100),
                        "auto": genreIsAuto,
                    ]
                )
            }
        }
    }
    /// When true, `GenreDetector` writes into `genre` over time. When false,
    /// the user's manual pick is locked.
    @Published var genreIsAuto: Bool = true
    /// Detector's confidence in its last decision (0..1). Drives the AUTO pill
    /// glow in the picker so the user can see when the detector is confident.
    @Published private(set) var genreConfidence: Float = 0
    /// While auto-scanning, the mode currently on screen. Mirrors the
    /// renderer's scanner so the header can show what's playing right now.
    @Published private(set) var scanTarget: VisualizerMode = .tunnel

    /// The colour palette applied to every mode. Index into `Palette.all`.
    @Published var paletteIndex: Int = 0 {
        didSet {
            renderer.paletteIndex = paletteIndex
            guard paletteIndex != oldValue else { return }
            let name = paletteIndex < Palette.all.count ? Palette.all[paletteIndex].name : "?"
            let from = oldValue < Palette.all.count ? Palette.all[oldValue].name : "?"
            Task { await Analytics.shared.countInSession("palette_switches") }
            Task { await Analytics.shared.track("palette_changed", [
                    "palette": name,
                    "from_palette": from,
                    "index": paletteIndex,
                ])
            }
        }
    }

    /// How much room the window has, which decides how much of the chrome is
    /// worth drawing. Driven by the window's own resize notifications rather
    /// than a GeometryReader, because the HUD is in an overlay and would
    /// otherwise have to measure a container it isn't in.
    @Published private(set) var windowWidth: CGFloat = 1280
    private static var resizeObserver: NSObjectProtocol?

    /// The main window, once the view tree has built it. Owned here so the
    /// window's level can be set from a toggle, from the menu, or at launch —
    /// none of which are the view that found the window.
    @Published var window: NSWindow?

    /// Whether the window floats above other apps. `.floating` rather than
    /// anything higher: it stays above normal windows but still yields to full
    /// screen apps and the menu bar, which is what someone watching a
    /// visualiser over their editor wants.
    @Published private(set) var alwaysOnTop: Bool = {
        UserDefaults.standard.bool(forKey: "audiovane.alwaysOnTop")
    }()

    /// Whether the credits / support popover is open.
    @Published var showAbout: Bool = false

    func openAbout() { showAbout = true }

    /// The track-change count at the moment the user manually picked a genre.
    /// Compared to `audio.tracks.changeCount` to know when the lock should
    /// expire and auto should re-arm.
    private var genreLockAtChange: Int = 0

    /// Which header dropdown is currently open, if any. Lives here rather
    /// than inside the dropdown views so the click-away catcher can cover
    /// the whole window — an `.overlay` on the pill would only catch clicks
    /// on the pill itself.
    @Published var openDropdown: DropdownID? = nil

    let audio: AudioEngine
    let renderer: OpenGLRenderer

    private var cancellables: Set<AnyCancellable> = []

    init() {
        Self.primeDefaults()
        let audio = AudioEngine()
        self.audio = audio
        self.renderer = OpenGLRenderer(audio: audio)
        // Whatever mode the user was last in, or auto-scan on a fresh install.
        // Auto-scan is the right first impression for thirteen modes: nobody
        // should have to guess that the good ones are behind a menu, and a
        // visualiser that sits on one scene forever looks like it missed
        // something.
        self.activeMode = Self.savedMode ?? .autoScan
        self.renderer.setMode(self.activeMode)
        NSLog("[DD] starting in mode \(self.activeMode.rawValue)")
        // Restore the genre the user last chose so a relaunch doesn't snap
        // back to Rock. Genre *detection* still re-arms per song as usual.
        self.genre = Self.savedGenre
        self.renderer.genre = self.genre
        // `--autoscan` starts straight into the scanner (used for testing).
        if CommandLine.arguments.contains("--autoscan") {
            self.activeMode = .autoScan
            self.renderer.setMode(.autoScan)
        }
        // `--mode <name>` jumps straight to a mode (used for testing).
        if let i = CommandLine.arguments.firstIndex(of: "--mode"),
           i + 1 < CommandLine.arguments.count,
           let m = VisualizerMode(rawValue: CommandLine.arguments[i + 1]) {
            self.activeMode = m
            self.renderer.setMode(m)
        }
        // `--genre <name>` pins The Band's genre for this run (used for testing
        // and the demo reel); it isn't remembered.
        if let i = CommandLine.arguments.firstIndex(of: "--genre"),
           i + 1 < CommandLine.arguments.count,
           let g = Genre.allCases.first(where: { $0.name.lowercased() == CommandLine.arguments[i + 1].lowercased() }) {
            self.genreIsAuto = false
            self.genre = g
        }
        // `--palette N` picks a colour palette at launch (used for testing).
        if let i = CommandLine.arguments.firstIndex(of: "--palette"),
           i + 1 < CommandLine.arguments.count,
           let p = Int(CommandLine.arguments[i + 1]) {
            self.paletteIndex = p
            self.renderer.paletteIndex = p
        }

        audio.$sourceLabel
            .receive(on: RunLoop.main)
            .assign(to: &$sourceLabel)
        audio.$sourceState
            .receive(on: RunLoop.main)
            .assign(to: &$sourceState)
        audio.$activeSource
            .receive(on: RunLoop.main)
            .assign(to: &$activeSource)
        // System audio / mic / demo / denied are all the states that have gone
        // wrong before, so they're worth a line in a crash report.
        audio.$sourceState
            .receive(on: RunLoop.main)
            .sink { state in
                CrashReporter.shared.log("audio source \(state.rawValue)")
            }
            .store(in: &cancellables)
        audio.$showIntro
            .receive(on: RunLoop.main)
            .assign(to: &$showIntro)
        audio.$isSounding
            .receive(on: RunLoop.main)
            .assign(to: &$isSounding)
        audio.$bpm
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.bpm = $0 }
            .store(in: &cancellables)
        audio.$lastBeatStrength
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastBeat = Double($0) }
            .store(in: &cancellables)

        // Snapshot mode is driven from outside (AppDelegate) — leave a hook here
        // so the snapshot can grab the renderer after the GL context is ready.
        AppState.shared = self

        emitLaunchEvent()

        // Watch track changes — when one happens, re-arm auto. We compare the
        // change count so a song skip counts but a frame-by-frame jitter doesn't.
        // The renderer reads `audio.tracks.changeCount` directly, but the
        // genre-lock bookkeeping is the AppState's concern.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.reEvaluateAutoGenre()
            self?.pumpAutoGenre()
            self?.syncScanTarget()
            self?.writeEvalLine()
            self?.refreshCrashState()
        }
        // `--genre-auto` forces auto-detect on (ignoring a remembered lock) and
        // `--system-audio` starts listening straight away: both used by the
        // band evaluation runner.
        if CommandLine.arguments.contains("--genre-auto") { genreIsAuto = true }
        if CommandLine.arguments.contains("--system-audio") {
            Task { await audio.startSystemCapture() }
        } else if !isHeadlessRun {
            // Otherwise reconnect whatever was in use last time. Granting
            // system audio should be a one-time thing, not a question every
            // launch — and if it can't be restored the intro comes back with
            // the reason, which is what the user needs to see.
            Task { await audio.restoreLastSource() }
        }
    }

    /// Snapshot and record modes have no window and no audio; starting capture
    /// there would fight them for the same device.
    private var isHeadlessRun: Bool {
        let args = CommandLine.arguments
        return args.contains("--snapshot") || args.contains("--record") || args.contains("--ui-shot")
    }

    /// One `app_launched` per run. Fired from init rather than from
    /// `applicationDidFinishLaunching`, because SwiftUI has not necessarily
    /// built the scene yet when that delegate callback lands and the launch
    /// properties would come back empty.
    private func emitLaunchEvent() {
        let args = CommandLine.arguments
        // Skip the headless verification modes so the dev loop doesn't show
        // up in PostHog as a room full of phantom users.
        let isHeadless = args.contains("--snapshot")
            || args.contains("--record")
            || args.contains("--ui-shot")
        guard !isHeadless else { return }

        let mode = activeMode.rawValue
        let palette = paletteIndex < Palette.all.count ? Palette.all[paletteIndex].name : "?"
        let autoscan = activeMode == .autoScan
        let isRelease = !args.contains("--debug")
        let fresh = !UserDefaults.standard.bool(forKey: "analytics.seenBefore")

        Task {
            await Analytics.shared.bootstrapOptIn()
            await Analytics.shared.track("app_launched", [
                "mode": mode,
                "palette": palette,
                "autoscan": autoscan,
                "is_release": isRelease,
                "fresh_install": fresh,
            ])
            await Analytics.shared.setSeenBefore()
        }
    }

    /// Keeps the app-state half of the crash report current. Once a second,
    /// alongside the genre bookkeeping that already runs on this timer.
    ///
    /// Band mode is the reason this exists: a stage with a cross-fade mid-way,
    /// three musicians held on and two more waiting to be re-confirmed is a
    /// crash nobody can reason about from a stack trace alone.
    private func refreshCrashState() {
        let drawing = renderer.effectiveMode
        var snapshot: [String: String] = [
            "mode": activeMode.rawValue,
            "drawing": drawing.rawValue,
            "palette": paletteIndex < Palette.all.count ? Palette.all[paletteIndex].name : "?",
            "genre": genre.name,
            "genre_auto": genreIsAuto ? "yes" : "no",
            "genre_confidence": String(format: "%.2f", genreConfidence),
            "singer": singerVoice.rawValue,
            "source": sourceLabel,
            "source_state": sourceState.rawValue,
        ]
        if drawing == .band {
            let band = renderer.bandEvalState()
            let onStage = (band["on_stage"] as? [String] ?? []).joined(separator: "+")
            snapshot["band_on_stage"] = onStage.isEmpty ? "(empty stage)" : onStage
            if let singers = band["singers"] as? String, !singers.isEmpty {
                snapshot["band_singers"] = singers
            }
            if let parts = band["parts"] as? [String: Double] {
                snapshot["band_parts"] = parts
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key) \(String(format: "%.2f", $0.value))" }
                    .joined(separator: " ")
            }
        }
        CrashReporter.shared.setState(snapshot)
    }

    /// Mirror the renderer's auto-scan position into the UI. The renderer
    /// owns the scanner (it's the thing that knows which mode is being
    /// drawn); this just republishes it so SwiftUI can show it.
    private func syncScanTarget() {
        let e = renderer.effectiveMode
        if scanTarget != e { scanTarget = e }
    }

    static private(set) var shared: AppState?

    private static let genreDefaultsKey = "audiovane.genre"
    private static let genreAutoDefaultsKey = "audiovane.genreAuto"
    private static let modeDefaultsKey = "audiovane.mode"

    /// The mode they were last looking at. Nil on a fresh install, which is
    /// how "no choice made yet" is distinguished from "chose Tunnel" — the
    /// caller falls back to auto-scan, and the first deliberate switch writes
    /// this.
    private static var savedMode: VisualizerMode? {
        get {
            guard let raw = UserDefaults.standard.object(forKey: modeDefaultsKey) as? String else { return nil }
            return VisualizerMode(rawValue: raw)
        }
        set {
            // Storing auto-scan is pointless: it's the default, and clearing
            // the key instead keeps one source of truth for "nothing chosen".
            if let newValue, newValue != .autoScan {
                UserDefaults.standard.set(newValue.rawValue, forKey: modeDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: modeDefaultsKey)
            }
        }
    }

    /// Last manually-picked genre, so a relaunch starts on the genre the
    /// user actually chose rather than defaulting to Rock.
    private static var savedGenre: Genre {
        get {
            guard let raw = UserDefaults.standard.object(forKey: genreDefaultsKey) as? Int,
                  let g = Genre(rawValue: raw) else { return .rock }
            return g
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: genreDefaultsKey) }
    }

    // Make sure there's a value stored on first launch so the get above
    // always has something coherent to return.
    static func primeDefaults() {
        let d = UserDefaults.standard
        // Carry the preference across the app's previous names so a user's
        // chosen genre doesn't reset when the app is renamed.
        for (old, new) in [("signal.genre", genreDefaultsKey),
                           ("audivane.genre", genreDefaultsKey),
                           ("signal.genreAuto", genreAutoDefaultsKey),
                           ("audivane.genreAuto", genreAutoDefaultsKey)] {
            if d.object(forKey: new) == nil, let v = d.object(forKey: old) {
                d.set(v, forKey: new)
            }
            d.removeObject(forKey: old)
        }
        if d.object(forKey: genreDefaultsKey) == nil {
            d.set(Genre.rock.rawValue, forKey: genreDefaultsKey)
        }
        if d.object(forKey: genreAutoDefaultsKey) == nil {
            d.set(true, forKey: genreAutoDefaultsKey)
        }
    }

    /// For the headless UI shots, which render the view tree with no window
    /// behind it. Never called in the running app.
    func setWindowWidthForTesting(_ width: CGFloat) { windowWidth = width }

    /// Which layer of chrome fits in the window right now.
    var layout: LayoutTier { LayoutTier.tier(forWidth: windowWidth) }

    func setMode(_ mode: VisualizerMode) {
        activeMode = mode
    }

    func setAlwaysOnTop(_ on: Bool) {
        alwaysOnTop = on
        UserDefaults.standard.set(on, forKey: "audiovane.alwaysOnTop")
        applyWindowLevel()
        Task { await Analytics.shared.track("always_on_top_changed", ["on": on]) }
    }

    /// Called when the window first appears, so a preference set last session
    /// takes effect without the user touching anything.
    func windowDidAppear() {
        applyWindowLevel()
        startWatchingWidth()
    }

    /// A visualiser is worth having in a corner of the screen as much as full
    /// screen, so the window goes down to a fraction of a full-screen one. The
    /// chrome sheds pieces as it narrows (see `LayoutTier`) rather than the
    /// window refusing to get there.
    static let minimumWindowSize = CGSize(width: 420, height: 280)

    private func startWatchingWidth() {
        guard Self.resizeObserver == nil, let window else { return }
        windowWidth = window.frame.width
        Self.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            guard let self, let w = self.window else { return }
            self.windowWidth = w.frame.width
        }
    }

    private func applyWindowLevel() {
        guard let window else { return }
        let wanted: NSWindow.Level = alwaysOnTop ? .floating : .normal
        guard window.level != wanted else { return }
        window.level = wanted
        // Logged because "it's behind everything" is the kind of report that
        // arrives with no way to check it, and this is the only line that says
        // what the window is actually doing.
        NSLog("[window] level = %@", alwaysOnTop ? "floating" : "normal")
    }

    /// The single path into `AudioEngine`'s source switching, so the header
    /// pill and the intro can't drift apart, and so switching is reported once
    /// whichever control was used.
    func selectSource(_ source: AudioSource, via origin: String) {
        Task { await Analytics.shared.track("source_changed", [
            "source": source.rawValue,
            "via": origin,
        ]) }
        switch source {
        case .system: Task { await audio.startSystemCapture() }
        case .microphone: audio.startMicrophone()
        case .demo: audio.startDemo()
        }
    }

    func restart() {
        audio.disconnect()
        audio.startDemo()
    }

    /// User picked a genre in the drop-down. Lock it until the next song,
    /// and remember it across launches so reopening the app doesn't snap
    /// you back to Rock mid-set.
    func userPickedGenre(_ g: Genre) {
        genreIsAuto = false
        genreLockAtChange = audio.tracks.changeCount
        genre = g
        UserDefaults.standard.set(g.rawValue, forKey: Self.genreDefaultsKey)
    }

    /// User toggled the AUTO pill. Restore auto-detection.
    func userToggledAuto(_ on: Bool) {
        genreIsAuto = on
        if on {
            genreLockAtChange = audio.tracks.changeCount
        }
        UserDefaults.standard.set(on, forKey: Self.genreAutoDefaultsKey)
    }

    /// When a new track shows up, the manual lock should expire and auto
    /// should re-engage so a Rock user isn't stuck with Rock when the next
    /// song is clearly jazz.
    private func reEvaluateAutoGenre() {
        guard !genreIsAuto else { return }
        if audio.tracks.changeCount != genreLockAtChange {
            genreIsAuto = true
            // The actual `genre` value gets updated by the GenreDetector;
            // we don't have to set it here.
        }
    }

    /// Below this detector confidence we stop changing the genre on our own.
    /// The heuristic is genuinely ambiguous in the middle of its range — a
    /// 100bpm track with a strong vocal could reasonably be Pop, Country or
    /// R&B — and silently swapping the whole stage between those three every
    /// few seconds is worse than sitting on the first reasonable guess. The
    /// user can still override at any time; this only limits *automatic*
    /// changes.
    static let autoGenreMinConfidence: Float = 0.30

    /// True when the detector is confident enough to be driving the genre
    /// itself. False while it's still deciding (or when the user has locked
    /// a genre manually). The picker uses this to draw the confidence bar.
    var genreIsDecided: Bool {
        genreIsAuto && genreConfidence >= Self.autoGenreMinConfidence
    }

    /// Band evaluation log: with AUDIOVANE_EVAL_LOG set, append one JSON line a
    /// second describing what the genre detector and the band make of the
    /// music. scripts/band-eval.py scores it against labelled videos.
    private lazy var evalLog: FileHandle? = {
        guard let path = ProcessInfo.processInfo.environment["AUDIOVANE_EVAL_LOG"] else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    private func writeEvalLine() {
        guard let log = evalLog else { return }
        let det = audio.genreDetector
        var line: [String: Any] = [
            "t": Date().timeIntervalSince1970,
            "detected": det.genre.name.lowercased(),
            "confidence": Double(det.confidence),
            "active": genre.name.lowercased(),
            "auto": genreIsAuto,
            "bpm": audio.snapshot.bpm,
            "rms": Double(audio.snapshot.rms),
            "features": det.lastFeatures.mapValues(Double.init),
            "scores": Dictionary(uniqueKeysWithValues: det.lastScores.map { ($0.key.name.lowercased(), Double($0.value)) }),
        ]
        for (k, v) in renderer.bandEvalState() { line[k] = v }
        if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) {
            log.write(data)
            log.write(Data("\n".utf8))
        }
    }

    /// Pump the detector's output into the active genre. Called from the
    /// 1Hz timer in `init` (cheaper than doing it every frame, and the
    /// detector itself only refreshes every 1.5s).
    private func pumpAutoGenre() {
        let detected = audio.genreDetector.genre
        let conf = audio.genreDetector.confidence
        if genreConfidence != conf { genreConfidence = conf }
        guard genreIsAuto else { return }
        // Too unsure to act on: keep whatever's already showing. The
        // confidence bar in the picker tells the user why it isn't moving.
        guard conf >= Self.autoGenreMinConfidence else { return }
        if genre != detected {
            genre = detected
        }
    }
}

enum VisualizerMode: String, CaseIterable, Identifiable {
    case tunnel, particles, liquid
    case badger, llama, hamster, nyan
    case spectrum, kaleidoscope, warp
    case band
    /// MIDEM Music Hack Day machine — drums, pads and bouncing balls.
    case machine
    /// Glowing neon-green waveforms shaped by the spectrum.
    case waveform
    /// Cycles through every other mode, 20 seconds each.
    /// Keep this the LAST case: the mode list shows Auto Scan at the bottom.
    case autoScan
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .tunnel: return "TUNNEL"
        case .particles: return "CONSTELLATION"
        case .liquid: return "LIQUID"
        case .badger: return "BADGER BADGER"
        case .llama: return "WHOOPING LLAMA"
        case .hamster: return "HAMSTER DANCE"
        case .nyan: return "NYAN CAT"
        case .spectrum: return "SPECTRUM"
        case .kaleidoscope: return "KALEIDOSCOPE"
        case .warp: return "WARP"
        case .band: return "THE BAND"
        case .autoScan: return "AUTO SCAN"
        case .machine: return "MACHINE"
        case .waveform: return "NEON WAVE"
        }
    }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
    var glyph: String { String(format: "%02d", index + 1) }
    /// Keyboard shortcut: 1...9 and 0 for the first ten modes, then - [ ] ;
    /// Auto Scan is always =.
    var shortcutKey: Character {
        if self == .autoScan { return "=" }
        if index < 10 { return Character(String((index + 1) % 10)) }
        let extra: [Character] = ["-", "[", "]", ";", "'"]
        return extra[min(index - 10, extra.count - 1)]
    }
}

enum SingerVoice: String, CaseIterable, Identifiable {
    case auto, female, male, duet
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto-detect"
        case .female: return "Female"
        case .male: return "Male"
        case .duet: return "Duet (female + male)"
        }
    }
}

/// How much of the header and footer there is room for.
///
/// The order matters and is the reverse of what people actually use: the footer
/// numbers go first (they're diagnostics for us, not for the person watching),
/// then the pill labels, then the pills themselves. What's left at the narrowest
/// size is the brand and the thing on screen.
enum LayoutTier: Int, Comparable {
    case wide, compact, narrow, tiny

    static func tier(forWidth width: CGFloat) -> LayoutTier {
        switch width {
        case 1100...: return .wide
        case 880..<1100: return .compact
        case 620..<880: return .narrow
        default: return .tiny
        }
    }

    static func < (lhs: LayoutTier, rhs: LayoutTier) -> Bool { lhs.rawValue < rhs.rawValue }

    // The raw values run wide → tiny, so "at least this much room" is `<=`.
    var showsFooterNumbers: Bool { self == .wide }
    var showsPillText: Bool { self <= .compact }
    var showsPills: Bool { self <= .narrow }
}

enum SourceState: String {
    case idle, live, demo, error
}

/// Where the audio comes from. Ordered as it appears in the picker: system
/// audio first because it's what the app is for, the microphone second because
/// it's the fallback people reach for, the demo tone last because it needs no
/// permissions at all.
enum AudioSource: String, CaseIterable, Identifiable {
    case system, microphone, demo
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "SYSTEM AUDIO"
        case .microphone: return "MICROPHONE"
        case .demo: return "DEMO TONE"
        }
    }

    var menuTitle: String {
        switch self {
        case .system: return "Share System Audio"
        case .microphone: return "Use Microphone"
        case .demo: return "Use Demo Tone"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "Spotify, YouTube, anything playing"
        case .microphone: return "Plays whatever the mic hears"
        case .demo: return "No permissions needed"
        }
    }

    /// Nothing is captured from these, so switching between them needs no
    /// permission of its own.
    var restoresOnLaunch: Bool { self != .microphone }
}