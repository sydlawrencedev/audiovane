import SwiftUI
import AppKit
import MetalKit

@main
struct VisualiserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("VIBRESIA") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: AppState.minimumWindowSize.width,
                       minHeight: AppState.minimumWindowSize.height)
                .preferredColorScheme(.dark)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
        WindowGroup("VIBRESIA") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: AppState.minimumWindowSize.width,
                       minHeight: AppState.minimumWindowSize.height)
                .preferredColorScheme(.dark)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdateChecker.shared.check(userInitiated: true) }
                Divider()
                // The pair a crashed user needs without having to know where
                // macOS keeps its reports: email us the latest, or open the
                // folder and attach it yourself.
                Button("Report a Problem…") { CrashReporter.shared.composeProblemReport() }
                Button("Reveal Crash Reports…") { CrashReporter.shared.revealReports() }
            }
            CommandMenu("Visualizer") {
                // The modes in the order the user arranged them, each with
                // the key that picks it. The keys follow the list, so moving
                // a mode moves its shortcut with it.
                ForEach(app.enabledModes) { entry in
                    let button = Button(entry.title) { app.activeMode = entry.id }
                    // A mode past the end of the key list has no shortcut at
                    // all, rather than one that fights with something else.
                    if let shortcut = entry.shortcut {
                        button.keyboardShortcut(KeyEquivalent(shortcut), modifiers: [])
                    } else {
                        button
                    }
                }
                Divider()
                // How long each mode holds in Auto Scan, counted in bars of
                // the song so the change lands on a beat.
                Menu("Auto Scan Length") {
                    ForEach(AppState.scanBarChoices, id: \.self) { bars in
                        Button {
                            app.scanBars = bars
                        } label: {
                            if app.scanBars == bars {
                                Label("\(bars) \(bars == 1 ? "bar" : "bars")", systemImage: "checkmark")
                            } else {
                                Text("\(bars) \(bars == 1 ? "bar" : "bars")")
                            }
                        }
                    }
                }
                Divider()
                // Routed through AppState so the menu, the header pill and the
                // intro all change the source the same way — and report it once.
                Button("Start System Audio") { app.selectSource(.system, via: "menu") }
                Button("Use Microphone")     { app.selectSource(.microphone, via: "menu") }
                Button("Use Demo Tone")      { app.selectSource(.demo, via: "menu") }
                Divider()
                Button("Open Hamster Folder…") {
                    SpriteAtlas.ensureFolder()
                    NSWorkspace.shared.open(SpriteAtlas.folder)
                }
                Divider()
                Toggle("Float Above All Windows", isOn: Binding(
                    get: { app.alwaysOnTop },
                    set: { app.setAlwaysOnTop($0) }))
                Button(app.isFullScreen ? "Exit Full Screen" : "Enter Full Screen") {
                    app.toggleFullScreen()
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
                Divider()
                Picker("Lead Singer", selection: $app.singerVoice) {
                    ForEach(SingerVoice.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Analytics.shared
        // First thing in: a crash handler that installs after the app has
        // already started crashing is a handler that misses the first crash.
        CrashReporter.shared.install()
        // Whatever the last run left behind. Safe to do now — the reports are
        // written to disk by the handler, not by the dying process, and the
        // upload happens once the user is actually up and running again.
        Task { await CrashReporter.shared.uploadPendingReports() }

        // The music-app watcher points at a binary inside this bundle, which the
        // in-app updater just replaced. Put the agent back where it belongs.
        Task { @MainActor in StartupManager.shared.reconcile() }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Look for a newer release on every launch (not in the test modes).
        let testMode = ["--snapshot", "--record"].contains { CommandLine.arguments.contains($0) }
        if !testMode { UpdateChecker.shared.check(userInitiated: false) }

        // Snapshot mode — render a few frames then exit. Used for verification.
        if CommandLine.arguments.contains("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runSnapshot()
            }
        }

        // Record mode — capture consecutive frames for diffing.
        if CommandLine.arguments.contains("--record") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runRecord()
            }
        }

        // UI snapshot — renders the SwiftUI overlay layer (header, HUD, meter)
        // to a PNG so the chrome can be reviewed without a screen recorder.
        if CommandLine.arguments.contains("--ui-shot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.captureUIShot()
            }
        }

        // `--about` opens the credits popover on launch (used to verify the
        // Stripe embed actually renders).
        if CommandLine.arguments.contains("--about") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                AppState.shared?.openAbout()
            }
        }

        // `--all-modes` and `--custom-mode` open the two panels straight
        // away, so they can be looked at without going through the list.
        if CommandLine.arguments.contains("--all-modes") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                AppState.shared?.showAllModesSheet = true
            }
        }
        if CommandLine.arguments.contains("--custom-mode") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                AppState.shared?.customModeSheet = .new
            }
        }

        // `--simulate-crash` faults on purpose so the crash-report path can be
        // verified end to end (report written, uploaded next launch) without
        // waiting for a real band-mode crash to turn up.
        if CommandLine.arguments.contains("--simulate-crash") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                CrashReporter.shared.log("simulated crash requested on the command line")
                CrashReporter.shared.simulateCrash()
            }
        }

        // `--window-info` prints the window's level and frame. Full screen is
        // the thing worth checking here: macOS refuses a full-screen Space to a
        // window above the normal level, which looks exactly like a full screen
        // that stops under the menu bar.
        if CommandLine.arguments.contains("--window-info") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard let w = NSApp.windows.first else { print("[window] no window"); exit(0) }
                let mask = w.styleMask
                print("[window] title: \(w.title)")
                print("[window] isFullScreen: \(w.styleMask.contains(.fullScreen))")
                print("[window] level: \(w.level == .floating ? "floating" : "normal")")
                print("[window] resizable: \(mask.contains(.resizable))")
                print("[window] fullScreenPrimary: \(w.collectionBehavior.contains(.fullScreenPrimary))")
                print("[window] frame: \(w.frame)")
                if let screen = w.screen ?? NSScreen.main {
                    print("[window] screen frame:  \(screen.frame)")
                    print("[window] visible frame: \(screen.visibleFrame)")
                }
                // With --full-screen, stay alive long enough to see what the
                // toggle actually did, then report the same numbers again.
                // --green-button presses the real traffic-light button instead
                // of the menu item, which is what a person actually clicks.
                let pressGreen = CommandLine.arguments.contains("--green-button")
                guard CommandLine.arguments.contains("--full-screen") || pressGreen else { exit(0) }
                if pressGreen {
                    let button = w.standardWindowButton(.zoomButton)
                    print("[window] green button target: \(button?.target.map { String(describing: type(of: $0)) } ?? "AppKit (default)")")
                    button?.performClick(nil)
                } else {
                    AppState.shared?.toggleFullScreen()
                }
                // Full screen is an animated transition into another Space, so
                // report a timeline rather than a single moment, which catches
                // the state mid-animation and calls it a failure.
                func report(_ label: String) {
                    print("\(label): fullScreen=\(w.styleMask.contains(.fullScreen)) " +
                          "level=\(w.level == .floating ? "floating" : "normal") " +
                          "w=\(Int(w.frame.width))x\(Int(w.frame.height))")
                    fflush(stdout)
                }
                report("t+0")
                for step in 1...4 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(step)) {
                        report("t+\(step)s")
                        if step == 4 { exit(0) }
                    }
                }
            }
        }

        // `--report-test` sends one report to the site's /api/notify and
        // prints whether the build is wired up to do it at all.
        if CommandLine.arguments.contains("--report-test") {
            ProblemReporter.report(.current(
                kind: "test",
                title: "Test report from a build",
                message: "Sent by --report-test. If this is in Discord, reporting works.",
                priority: "default",
                state: CrashReporter.shared.currentState()))
            print("[report] endpoint: \(ProblemReporter.isConfigured ? "configured" : "not configured (no ReportToken in this build)")")
            // Give the request a moment to land before the process goes away.
            Thread.sleep(forTimeInterval: 2.0)
            exit(0)
        }

        // `--login-on` / `--login-off`, `--watch-on` / `--watch-off` and
        // `--startup-status` exist for support and for testing: they do exactly
        // what the two toggles in the credits popover do, without needing a
        // window to click in.
        runStartupCommandIfRequested()
    }

    @MainActor
    private func runStartupCommandIfRequested() {
        let args = CommandLine.arguments
        let manager = StartupManager.shared
        if args.contains("--login-on") {
            manager.setLaunchAtLogin(true)
        } else if args.contains("--login-off") {
            manager.setLaunchAtLogin(false)
        } else if args.contains("--watch-on") {
            manager.setWatchMusicApps(true)
        } else if args.contains("--watch-off") {
            manager.setWatchMusicApps(false)
        } else if !args.contains("--startup-status") {
            return
        }

        manager.refresh()
        print("[startup] launch at login: \(manager.launchAtLogin) — \(manager.launchAtLoginDetail)")
        print("[startup] music watcher:   \(manager.watchMusicApps) — \(manager.watchMusicAppsDetail)")
        if let error = manager.errorMessage { print("[startup] error: \(error)") }
        exit(0)
    }

    /// Session tallies (mode switches, palette switches) only reach PostHog on
    /// the next flush — 2.5s after the last event — so without this they'd be
    /// lost every time someone quit shortly after fiddling with the controls.
    func applicationWillTerminate(_ notification: Notification) {
        Task { await Analytics.shared.flushNow() }
    }

    /// Renders the SwiftUI view tree to a PNG. The OpenGL layer won't appear
    /// (ImageRenderer can't snapshot an NSView-backed surface) but every
    /// overlay will, which is what we're checking.
    @MainActor
    private func captureUIShot() {
        let outDir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? "/tmp"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let size = CGSize(width: 1280, height: 720)
        guard let app = AppState.shared else { NSLog("[UI] no AppState"); exit(1) }

        // The intro overlay covers the chrome we're trying to look at, and
        // the genre pill only appears in band mode — so shoot both.
        let shots: [(String, ModeID, DropdownID?)] = [
            ("modes", .builtin(.tunnel), nil),
            ("band", .builtin(.band), nil),
            ("mode-open", .builtin(.tunnel), .mode),
            ("genre-open", .builtin(.band), .genre),
            ("source-open", .builtin(.tunnel), .source),
            ("dance-floor", .builtin(.danceFloor), nil),
            ("palette-open", .builtin(.tunnel), .palette),
        ]
        // Window widths that trigger each layout tier: wide shows everything,
        // compact drops the footer numbers, narrow drops the pill labels, tiny
        // drops the pills.
        let sizes: [(String, CGSize)] = [
            ("", size),
            ("-compact", CGSize(width: 1000, height: 420)),
            ("-narrow", CGSize(width: 760, height: 380)),
            ("-tiny", AppState.minimumWindowSize),
        ]
        for (name, mode, open) in shots {
            app.showIntro = false
            app.activeMode = mode
            app.openDropdown = open
            for (suffix, shotSize) in sizes {
                // The chrome reads the tier from the window's width, which the
                // shot has to fake — ImageRenderer has no window.
                app.setWindowWidthForTesting(shotSize.width)
                // let the body re-evaluate with the new mode
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                let renderer = ImageRenderer(content: ContentView()
                    .environmentObject(app)
                    .frame(width: shotSize.width, height: shotSize.height)
                    .background(Color.black))
                renderer.scale = 1
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    NSLog("[UI] could not encode \(name)"); continue
                }
                let path = "\(outDir)/ui-\(name)\(suffix).png"
                try? png.write(to: URL(fileURLWithPath: path))
                NSLog("[UI] wrote \(path)")
            }
        }

        // The two panels are sheets, and a sheet is presented by the window
        // system — `ImageRenderer` can't see one. They're rendered directly
        // instead, so the panels can be reviewed without a screen recorder.
        guard let app = AppState.shared else { exit(1) }
        // A stand-in for a mode the user already has, so the editing view
        // can be reviewed without one on disk.
        let sampleMode = CustomMode(id: "shot", name: "My Mode", author: "Minith Labs",
                                    url: "https://minithlabs.com",
                                    shader: CustomModeGuide.starterTemplate,
                                    enabled: true, modified: Date())
        for (name, view) in [("all-modes", AnyView(AllModesView(scrollable: false, height: 1400))),
                             ("all-modes-drop", AnyView(AllModesView(scrollable: false, height: 1400, dropTargetIndex: 4))),
                             ("custom-mode", AnyView(CustomModeView())),
                             ("custom-mode-write", AnyView(CustomModeView(initialStep: .write))),
                             ("custom-mode-ai", AnyView(CustomModeView(initialStep: .ai, scrollable: false))),
                             ("custom-mode-edit", AnyView(CustomModeView(editing: sampleMode)))] {
            let renderer = ImageRenderer(content: view
                .environmentObject(app)
                .frame(width: 720, height: name.hasPrefix("all-modes") ? 1400 : 560)
                .background(Color(red: 0.05, green: 0.02, blue: 0.09)))
            renderer.scale = 1
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                NSLog("[UI] could not encode \(name)"); continue
            }
            let path = "\(outDir)/ui-\(name).png"
            try? png.write(to: URL(fileURLWithPath: path))
            NSLog("[UI] wrote \(path)")
        }
        exit(0)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func runSnapshot() {
        let outDir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? "/tmp"
        let genresOnly = CommandLine.arguments.contains("--genres")
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            attempts += 1
            guard let app = AppState.shared else {
                if attempts > 200 { NSLog("[SNAP] timeout AppState"); exit(1) }
                return
            }
            if !app.renderer.isReady {
                if attempts > 200 { NSLog("[SNAP] timeout renderer"); exit(1) }
                return
            }
            t.invalidate()
            NSLog("[SNAP] ready")
            app.audio.injectSyntheticTone(seconds: 2.0)
            if genresOnly {
                app.renderer.setMode(.builtin(.band))
                for g in Genre.allCases {
                    app.renderer.genre = g
                    // let a couple of frames go by so the shader settles
                    Thread.sleep(forTimeInterval: 0.3)
                    let path = "\(outDir)/band_\(g.rawValue)_\(g.name.lowercased()).png"
                    app.renderer.renderToPNG(width: 1280, height: 720, mode: .builtin(.band),
                                             frames: 60, path: path)
                    NSLog("[SNAP] genre=\(g.name) saved=\(FileManager.default.fileExists(atPath: path))")
                }
                NSLog("[SNAP] genre sweep done")
                exit(0)
            }
            for mode in VisualizerMode.allCases {
                app.renderer.renderToPNG(width: 1280, height: 720, mode: .builtin(mode),
                                         frames: 60,
                                         path: "\(outDir)/viz-\(mode.rawValue).png")
            }
            // The user's own modes, if they have any, so a snapshot shows
            // everything the app can draw.
            for custom in app.customModes {
                app.renderer.renderToPNG(width: 1280, height: 720, mode: .custom(custom.id),
                                         frames: 60,
                                         path: "\(outDir)/viz-custom-\(custom.id).png")
            }
            app.renderer.singerVoice = .duet
            app.renderer.renderToPNG(width: 1280, height: 720, mode: .builtin(.band), frames: 60,
                                     path: "\(outDir)/viz-band-duet.png")
            app.renderer.singerVoice = .auto
            for genre in Genre.allCases {
                app.renderer.genre = genre
                app.renderer.renderToPNG(width: 1280, height: 720, mode: .builtin(.band), frames: 60,
                                         path: "\(outDir)/viz-band-\(genre.name.lowercased()).png")
            }
            NSLog("[SNAP] saved")
            exit(0)
        }
    }

    private func runRecord() {
        let args = CommandLine.arguments
        let outDir: String
        if let i = args.firstIndex(of: "--record"), i + 1 < args.count {
            outDir = args[i + 1]
        } else {
            outDir = "/tmp/viz_record"
        }
        let frames: Int
        if let i = args.firstIndex(of: "--frames"), i + 1 < args.count, let n = Int(args[i + 1]) {
            frames = n
        } else {
            frames = 20
        }
        let intervalMs: Int
        if let i = args.firstIndex(of: "--interval"), i + 1 < args.count, let n = Int(args[i + 1]) {
            intervalMs = n
        } else {
            intervalMs = 100
        }

        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        guard let app = AppState.shared else {
            NSLog("[REC] no AppState"); exit(1)
        }
        NSLog("[REC] AppState ready, renderer.isReady=\(app.renderer.isReady)")

        // In idle mode, don't start the demo tone — we want to see if the
        // static (no-audio) render is stable.
        let idle = args.contains("--idle")
        if !idle {
            app.audio.startDemo()
        } else {
            NSLog("[REC] idle mode — no audio source")
        }
        // Record whatever mode is active (the --mode flag can set it).
        app.renderer.setMode(app.activeMode)
        NSLog("[REC] recording mode \(app.activeMode.rawValue)")

        NSLog("[REC] writing \(frames) frames @ \(intervalMs)ms to \(outDir)")

        // Drive frame capture via chained DispatchQueue.main.asyncAfter — simplest
        // reliable way given how this run loop is set up.
        var n = 0
        let startedAt = Date()
        func captureNext() {
            n += 1
            let elapsed = Date().timeIntervalSince(startedAt) * 1000
            let path = "\(outDir)/frame_\(String(format: "%04d", n)).png"
            NSLog("[REC] fire n=\(n) t=\(Int(elapsed))ms ready=\(app.renderer.isReady)")
            app.renderer.captureScreen(to: path)
            let exists = FileManager.default.fileExists(atPath: path)
            NSLog("[REC] n=\(n) saved=\(exists) path=\(path)")
            if n >= frames {
                NSLog("[REC] done")
                exit(0)
            } else {
                let interval = DispatchTimeInterval.milliseconds(intervalMs)
                DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: captureNext)
            }
        }
        let interval = DispatchTimeInterval.milliseconds(intervalMs)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: captureNext)
    }
}