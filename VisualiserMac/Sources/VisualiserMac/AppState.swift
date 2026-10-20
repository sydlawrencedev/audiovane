import SwiftUI
import Combine
import AppKit

final class AppState: ObservableObject {
    @Published var activeMode: ModeID = .builtin(.tunnel) {
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
    @Published private(set) var scanTarget: ModeID = .builtin(.tunnel)

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
        // Auto-scan is the right first impression with this many modes: nobody
        // should have to guess that the good ones are behind a menu, and a
        // visualiser that sits on one scene forever looks like it missed
        // something.
        self.activeMode = Self.savedMode ?? .builtin(.autoScan)
        self.renderer.setMode(self.activeMode)
        NSLog("[DD] starting in mode \(self.activeMode.rawValue)")
        // How long each mode holds in Auto Scan, in bars of the song.
        let bars = UserDefaults.standard.integer(forKey: Self.scanBarsKey)
        self.scanBars = bars > 0 ? bars : 4
        self.renderer.barsPerMode = self.scanBars
        // Restore the genre the user last chose so a relaunch doesn't snap
        // back to Rock. Genre *detection* still re-arms per song as usual.
        self.genre = Self.savedGenre
        self.renderer.genre = self.genre
        // `--autoscan` starts straight into the scanner (used for testing).
        if CommandLine.arguments.contains("--autoscan") {
            self.activeMode = .builtin(.autoScan)
            self.renderer.setMode(.builtin(.autoScan))
        }
        // `--mode <name>` jumps straight to a mode (used for testing).
        if let i = CommandLine.arguments.firstIndex(of: "--mode"),
           i + 1 < CommandLine.arguments.count,
           let m = ModeID(rawValue: CommandLine.arguments[i + 1]) {
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
        let autoscan = activeMode == .builtin(.autoScan)
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
        if drawing == .builtin(.band) {
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
    private static var savedMode: ModeID? {
        get {
            guard let raw = UserDefaults.standard.object(forKey: modeDefaultsKey) as? String else { return nil }
            return ModeID(rawValue: raw)
        }
        set {
            // Storing auto-scan is pointless: it's the default, and clearing
            // the key instead keeps one source of truth for "nothing chosen".
            if let newValue, newValue != .builtin(.autoScan) {
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

    func setMode(_ mode: ModeID) {
        activeMode = mode
    }

    // MARK: - The mode list

    /// The name to show for a mode. A custom mode's name lives with the
    /// mode, not with the identifier, so it has to be looked up.
    func displayName(for id: ModeID) -> String {
        switch id {
        case .builtin(let v):
            return v.displayName
        case .custom(let slug):
            return customModes.first(where: { $0.id == slug })?.name ?? "Custom Mode"
        }
    }

    /// What the Custom Mode sheet is doing: making a new one, or editing
    /// one the user already has. One sheet, so the two can't both be up.
    enum CustomModeSheet: Identifiable {
        case new
        case editing(CustomMode)

        var id: String {
            switch self {
            case .new: return "new"
            case .editing(let mode): return mode.id
            }
        }

        /// The mode being edited, if any.
        var mode: CustomMode? {
            if case .editing(let m) = self { return m }
            return nil
        }
    }

    /// The Custom Mode sheet, if it's open.
    @Published var customModeSheet: CustomModeSheet?

    /// Whether the View All panel is open.
    @Published var showAllModesSheet = false

    /// The user's mode with this id, if it still exists.
    func customMode(id: String) -> CustomMode? {
        customModes.first { $0.id == id }
    }

    /// Opens the Custom Mode sheet on one of the user's own modes.
    func editCustomMode(id: String) {
        guard let mode = customMode(id: id) else { return }
        customModeSheet = .editing(mode)
    }

    /// The user's own modes, newest last. Loaded from disk at launch and
    /// whenever the Custom Mode sheet saves something.
    @Published private(set) var customModes: [CustomMode] = []

    /// Built-in modes the user has switched off, by raw value.
    ///
    /// Stored as a list of names rather than a set of booleans, so a mode
    /// added in a later version shows up by default rather than being
    /// silently off because nobody has heard of it yet.
    private static let hiddenModesKey = "audiovane.hiddenModes"
    private var hiddenBuiltins: Set<String> {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: Self.hiddenModesKey) ?? []
            return Set(raw)
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.hiddenModesKey)
        }
    }

    /// The order the user has arranged the modes in.
    ///
    /// Stored separately from the enum, because the enum is fixed at compile
    /// time and the list is meant to be rearrangeable. Modes that aren't in
    /// the stored order — a mode added in a later version, or a custom mode
    /// the user hasn't placed yet — are appended in their natural order, so
    /// nothing ever goes missing just because the list was written down
    /// before they existed.
    private static let modeOrderKey = "audiovane.modeOrder"
    private var storedModeOrder: [ModeID] {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: Self.modeOrderKey) ?? []
            return raw.compactMap { ModeID(rawValue: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.map { $0.rawValue }, forKey: Self.modeOrderKey)
        }
    }

    /// The order the modes ship in.
    ///
    /// Kept separate from the enum's declaration order on purpose. The enum
    /// order decides the keyboard shortcuts — 1, 2, 3 … and then - [ ] ; ' \ —
    /// and those shouldn't move because someone rearranged the list. This is
    /// the order a fresh install gets; once the user rearranges it, their
    /// arrangement is what counts.
    static let defaultModeOrder: [VisualizerMode] = [
        .ribbons, .silk, .flux, .spectrum, .tunnel, .liquid, .kaleidoscope,
        .waveform, .machine, .warp, .particles, .nyan, .hamster, .badger,
        .llama, .danceFloor, .band,
    ]

    /// Every mode, in the order the user arranged them.
    var allModes: [ModeEntry] {
        let hidden = hiddenBuiltins
        let builtins = VisualizerMode.allCases
            .filter { $0 != .autoScan }
            .map { mode -> ModeEntry in
                var entry = ModeEntry(builtin: mode)
                entry.isEnabled = !hidden.contains(mode.rawValue)
                return entry
            }
        let customs = customModes.map { ModeEntry(custom: $0) }

        var entries: [ModeEntry] = []
        var used = Set<ModeID>()
        let stored = storedModeOrder
        let order = stored.isEmpty ? Self.defaultModeOrder.map { ModeID.builtin($0) } : stored
        for id in order {
            guard let entry = (builtins.first { $0.id == id } ?? customs.first { $0.id == id }),
                  !used.contains(id) else { continue }
            entries.append(entry)
            used.insert(id)
        }
        // Anything the stored order doesn't mention yet goes after it.
        for entry in builtins + customs where !used.contains(entry.id) {
            entries.append(entry)
            used.insert(entry.id)
        }
        return entries
    }

    /// The modes that show in the list and take part in Auto Scan.
    var enabledModes: [ModeEntry] {
        allModes.filter { $0.isEnabled }
    }

    /// The Auto Scan rotation, as the renderer wants it.
    var scanCycle: [ModeID] {
        enabledModes.map { $0.id }
    }

    /// Moves a mode to a new place in the list.
    ///
    /// The list is the order of the whole set, switched-on or not, so
    /// switching a mode off and on again doesn't shuffle it.
    func moveMode(_ id: ModeID, to destination: Int) {
        var order = allModes.map { $0.id }
        guard let from = order.firstIndex(of: id) else { return }
        let clamped = min(max(0, destination), order.count - 1)
        guard from != clamped else { return }
        order.remove(at: from)
        order.insert(id, at: clamped)
        // If the arrangement is back to how it ships, forget it rather than
        // pinning it. That way a later change to the default order reaches
        // people who hadn't actually rearranged anything.
        if order.compactMap({ $0.builtin }) == Self.defaultModeOrder {
            UserDefaults.standard.removeObject(forKey: Self.modeOrderKey)
        } else {
            storedModeOrder = order
        }
        pushScanCycle()
    }

    /// Switches a mode on or off. Turning the last one off would leave the
    /// scanner with nothing to do, so Tunnel is always kept.
    func setModeEnabled(_ id: ModeID, enabled: Bool) {
        switch id {
        case .builtin(let v):
            var hidden = hiddenBuiltins
            if enabled {
                hidden.remove(v.rawValue)
            } else {
                // Tunnel is the fallback when everything else is off, and
                // hiding it would leave the list empty.
                guard v != .tunnel else { return }
                hidden.insert(v.rawValue)
            }
            hiddenBuiltins = hidden
        case .custom(let slug):
            guard let i = customModes.firstIndex(where: { $0.id == slug }) else { return }
            customModes[i].enabled = enabled
            try? CustomModeStore.save(customModes[i])
        }
        pushScanCycle()
    }

    /// Re-reads the user's modes from disk and recompiles them.
    func reloadCustomModes() {
        customModes = CustomModeStore.loadAll()
        var problems: [String: ShaderProblem] = [:]
        for mode in customModes {
            // A mode that no longer compiles is kept on disk — the user may
            // want to fix it — but it can't be drawn, so it's switched off
            // and the reason is kept to show in the View All panel.
            if case .failure(let problem) = renderer.installCustomShader(id: mode.id, body: mode.shader) {
                NSLog("[CUSTOM] \(mode.id) failed to compile: \(problem.message)")
                problems[mode.id] = problem
                if let i = customModes.firstIndex(where: { $0.id == mode.id }), customModes[i].enabled {
                    customModes[i].enabled = false
                    try? CustomModeStore.save(customModes[i])
                }
            }
        }
        customModeProblems = problems
        pushScanCycle()
    }

    /// Loads the user's modes once the graphics context exists.
    ///
    /// Compiling a shader needs an OpenGL context, and the context is only
    /// created when the view is attached to a window — which is after
    /// `init`. So the first load is triggered from the view, and the
    /// published changes are pushed a turn later so we're not mutating
    /// published state from inside a view update.
    private var didLoadCustomModes = false
    func loadCustomModesOnce() {
        guard !didLoadCustomModes else { return }
        didLoadCustomModes = true
        Task { @MainActor in
            self.reloadCustomModes()
        }
    }

    /// Why a custom mode isn't working, if it isn't.
    @Published private(set) var customModeProblems: [String: ShaderProblem] = [:]

    /// A rendered picture of each of the user's modes, for the View All
    /// panel — so the panel shows what a mode actually looks like rather
    /// than a made-up cover.
    @Published private(set) var customModePreviews: [String: NSImage] = [:]

    /// Draws a picture of each of the user's modes.
    ///
    /// The picture is drawn with a plausible amount of music going on, so a
    /// mode isn't a black rectangle when the room is quiet. The analyser is
    /// given that state for the length of one render; the audio itself is
    /// never touched, and the next frame of real sound puts the analyser
    /// back.
    func refreshCustomModePreviews() {
        let modes = customModes
        guard !modes.isEmpty else { return }
        Task { @MainActor in
            for mode in modes {
                audio.analyzer.setSyntheticState()
                let path = (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("audiovane-preview-\(mode.id).png")
                renderer.renderToPNG(width: 320, height: 180,
                                     mode: .custom(mode.id), frames: 90, path: path)
                if let image = NSImage(contentsOfFile: path) {
                    customModePreviews[mode.id] = image
                }
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    /// Adds a user's mode, once it has been shown to compile.
    func addCustomMode(name: String, author: String, url: String?, shader: String) -> Result<CustomMode, ShaderProblem> {
        let id = CustomModeStore.uniqueSlug(from: name)
        switch renderer.installCustomShader(id: id, body: shader) {
        case .failure(let problem):
            return .failure(problem)
        case .success:
            let mode = CustomMode(id: id, name: name, author: author, url: url,
                                  shader: shader, enabled: true, modified: Date())
            do {
                try CustomModeStore.save(mode)
            } catch {
                return .failure(ShaderProblem(
                    kind: .compileFailed,
                    message: "Couldn't save the mode to disk: \(error.localizedDescription)"))
            }
            customModes.append(mode)
            pushScanCycle()
            refreshCustomModePreviews()
            return .success(mode)
        }
    }

    /// Replaces a user's mode with a new version, once it has been shown to
    /// compile.
    func updateCustomMode(id: String, name: String, author: String, url: String?, shader: String) -> Result<CustomMode, ShaderProblem> {
        guard let i = customModes.firstIndex(where: { $0.id == id }) else {
            return .failure(ShaderProblem(kind: .compileFailed, message: "That mode no longer exists."))
        }
        switch renderer.installCustomShader(id: id, body: shader) {
        case .failure(let problem):
            return .failure(problem)
        case .success:
            customModes[i].name = name
            customModes[i].author = author
            customModes[i].url = url
            customModes[i].shader = shader
            customModes[i].modified = Date()
            do {
                try CustomModeStore.save(customModes[i])
            } catch {
                return .failure(ShaderProblem(
                    kind: .compileFailed,
                    message: "Couldn't save the mode to disk: \(error.localizedDescription)"))
            }
            pushScanCycle()
            refreshCustomModePreviews()
            return .success(customModes[i])
        }
    }

    /// Removes a user's mode, from the list and from disk.
    func deleteCustomMode(id: String) {
        customModes.removeAll { $0.id == id }
        renderer.removeCustomShader(id: id)
        CustomModeStore.delete(id: id)
        // If the deleted mode was on screen, fall back to something real.
        if activeMode == .custom(id) {
            let fallback = enabledModes.first?.id ?? .builtin(.tunnel)
            setMode(fallback)
        }
        pushScanCycle()
    }

    /// Tells the renderer which modes Auto Scan should walk.
    private func pushScanCycle() {
        renderer.setScanCycle(scanCycle)
    }

    /// How many bars of the song each mode gets in Auto Scan.
    ///
    /// Counted in bars rather than seconds so the change lands on a beat —
    /// a mode that swaps halfway through a bar looks like a glitch, and one
    /// that swaps on the downbeat looks like part of the music.
    @Published var scanBars: Int = 4 {
        didSet {
            UserDefaults.standard.set(scanBars, forKey: Self.scanBarsKey)
            renderer.barsPerMode = scanBars
        }
    }

    private static let scanBarsKey = "audiovane.scanBars"

    /// The choices offered in the menu.
    static let scanBarChoices = [1, 2, 4, 8, 16]

    /// True while the window is in its own full-screen Space.
    @Published private(set) var isFullScreen = false
    /// Full screen and "float above other apps" are mutually exclusive at the OS
    /// level: macOS will not put a window above the normal level into a
    /// full-screen Space. Left alone, turning float on silently kills the green
    /// button's job and it just zooms the window, which looks like a full
    /// screen that stops under the menu bar.
    ///
    /// So this goes in the other direction: when the window is floating and
    /// full screen is asked for, drop to the normal level first and put the
    /// float back on the way out. A full-screen Space is above everything in
    /// that Space anyway, so nothing is lost while it's there — and both
    /// features keep working.
    func toggleFullScreen() {
        guard let window else { return }
        guard !isFullScreen, alwaysOnTop, window.level != .normal else {
            window.toggleFullScreen(nil)
            return
        }
        restoringFloatAfterFullScreen = true
        window.level = .normal
        // macOS needs a turn of the run loop to notice the level change and
        // hand full-screen capability back to the window. Asking in the same
        // turn does nothing at all, which is what the first version did.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            window.toggleFullScreen(nil)
        }
    }

    /// Set when the level was dropped to make full screen possible.
    private var restoringFloatAfterFullScreen = false

    private func handleEnteredFullScreen() {
        isFullScreen = true
        NSLog("[window] entered full screen (level %@)", windowLevelName)
    }

    private func handleExitedFullScreen() {
        isFullScreen = false
        // Put the float back, or the user comes out of full screen into a
        // window that no longer floats and has to notice.
        if restoringFloatAfterFullScreen, alwaysOnTop {
            restoringFloatAfterFullScreen = false
            applyWindowLevel()
        }
        NSLog("[window] left full screen (level %@)", windowLevelName)
    }

    private var windowLevelName: String {
        guard let window else { return "none" }
        return window.level == .floating ? "floating" : "normal"
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

    /// Only installed while the window is floating; see `applyWindowLevel`.
    private var greenButtonProxy: GreenButtonProxy?

    private func startWatchingWidth() {
        guard Self.resizeObserver == nil, let window else { return }
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window,
                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnteredFullScreen() }
        }
        center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window,
                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleExitedFullScreen() }
        }
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
        if window.level != wanted {
            window.level = wanted
        }
        // While the window is floating, macOS refuses it a full-screen Space,
        // so the green button zooms instead — which looks like a full screen
        // that stops under the menu bar. Point the button at the path that
        // works for those windows, and hand it straight back to AppKit for
        // every other window, which should keep its own behaviour untouched.
        if alwaysOnTop {
            if greenButtonProxy == nil { greenButtonProxy = GreenButtonProxy() }
            greenButtonProxy?.takeOverGreenButton(in: window)
        } else {
            greenButtonProxy?.releaseGreenButton(in: window)
        }
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
    // Declaration order is the mode list order: it drives the `01`…`17`
    // glyphs, the keyboard shortcuts, and Auto Scan's rotation.
    /// Luminous ribbons twisting through floating glass shapes.
    case ribbons
    /// Flying forward through satin ribbons and tumbling glass cubes.
    case silk
    /// Abstract sheets of pink and gold light swirling into a vanishing point.
    case flux
    case spectrum
    case tunnel
    case particles
    case liquid
    case kaleidoscope
    case warp
    /// Glowing neon-green waveforms shaped by the spectrum.
    case waveform
    case nyan
    case hamster
    case badger
    case llama
    /// A perspective grid of Rubik's-cube tiles that re-solve to the beat.
    /// Electro, nu-wave, chrome.
    case danceFloor
    case band
    /// MIDEM Music Hack Day machine — drums, pads and bouncing balls.
    case machine
    /// Cycles through every other mode, 20 seconds each.
    /// Keep this the LAST case: the mode list shows Auto Scan at the bottom.
    case autoScan
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ribbons: return "RIBBONS"
        case .silk: return "SILK FLIGHT"
        case .flux: return "FLUX"
        case .spectrum: return "SPECTRUM"
        case .tunnel: return "TUNNEL"
        case .particles: return "CONSTELLATION"
        case .liquid: return "LIQUID"
        case .kaleidoscope: return "KALEIDOSCOPE"
        case .warp: return "WARP"
        case .waveform: return "NEON WAVE"
        case .nyan: return "NYAN CAT"
        case .hamster: return "HAMSTER DANCE"
        case .badger: return "BADGER BADGER"
        case .llama: return "WHOOPING LLAMA"
        case .danceFloor: return "DANCE FLOOR"
        case .band: return "THE BAND"
        case .machine: return "MACHINE"
        case .autoScan: return "AUTO SCAN"
        }
    }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
    /// Keyboard shortcut: 1...9 and 0 for the first ten modes, then - [ ] ; ' \ ,
    /// then = for Auto Scan. Adding a mode past 17 needs another key here.
    var shortcutKey: Character {
        if self == .autoScan { return "=" }
        if index < 10 { return Character(String((index + 1) % 10)) }
        let extra: [Character] = ["-", "[", "]", ";", "'", "\\", ","]
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
/// Sits behind the window's green button while that window is floating.
///
/// `NSWindow.standardWindowButton(.zoomButton)` is public API, so handing it a
/// different target is a supported thing to do; clearing the target again puts
/// AppKit's own behaviour back.
final class GreenButtonProxy: NSObject {
    weak var window: NSWindow?

    func takeOverGreenButton(in window: NSWindow) {
        let button = window.standardWindowButton(.zoomButton)
        guard let button else { return }
        button.target = self
        button.action = #selector(greenButtonClicked)
        self.window = window
    }

    func releaseGreenButton(in window: NSWindow) {
        guard let button = window.standardWindowButton(.zoomButton) else { return }
        button.target = nil
        button.action = nil
    }

    @objc private func greenButtonClicked() {
        MainActor.assumeIsolated {
            guard let state = AppState.shared else { return }
            state.toggleFullScreen()
        }
    }
}

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