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
                // The vibescapes in the order the user arranged them, each with
                // the key that picks it. The keys follow the list, so moving
                // a vibescape moves its shortcut with it.
                ForEach(app.enabledVibescapes) { entry in
                    let button = Button(entry.title) { app.activeVibescape = entry.id }
                    // A vibescape past the end of the key list has no shortcut at
                    // all, rather than one that fights with something else.
                    if let shortcut = entry.shortcut {
                        button.keyboardShortcut(KeyEquivalent(shortcut), modifiers: [])
                    } else {
                        button
                    }
                }
                Divider()
                // How long each vibescape holds in Auto Scan, counted in bars of
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

    /// macOS hands a `vibresia://` URL to whichever app owns the scheme. We
    /// register for the Apple Event in `applicationWillFinishLaunching` so the
    /// handler is in place before the runloop starts, whether the URL is the
    /// reason the app was cold-launched or one a running app receives. The
    /// handler is skipped in MCP vibescape — no window, no state — so a tool
    /// invocation can't be mistaken for a share.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !CommandLine.arguments.contains("--mcp") else { return }
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    /// Pulls the URL string out of the Apple Event and hands it to the
    /// importer. Every failure mode is already classified by
    /// `ShareImporter.decode` and reported through PostHog from there, so
    /// this stays tiny.
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else { return }
        let request = ShareImporter.decode(url)
        Task { @MainActor in
            ShareImporter.apply(request)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // MCP vibescape: this process is a tool server for an AI agent, not the
        // app. It has no window, no analytics, no update check and no audio
        // — it answers requests on stdin. Everything below is skipped.
        if CommandLine.arguments.contains("--mcp") {
            // No dock icon and no menu bar: this is a tool, not a window
            // somebody is going to look at.
            NSApp.setActivationPolicy(.accessory)
            // Any window the scene would have made is hidden rather than
            // shown: an agent launching the server shouldn't flash a window.
            NSApp.windows.forEach { $0.orderOut(nil) }
            DispatchQueue.main.async {
                MCPServer().run()
            }
            return
        }

        // Analytics setup enables PostHog's global exception autocapture. Do
        // not install a second signal or uncaught-exception handler here: that
        // would make both handlers process the same crash.
        _ = Analytics.shared
        // Older builds may have left reports on disk. Keep draining those
        // after migrating global crash capture to the PostHog SDK.
        Task { await CrashReporter.shared.uploadPendingReports() }

        // The music-app watcher points at a binary inside this bundle, which the
        // in-app updater just replaced. Put the agent back where it belongs.
        Task { @MainActor in StartupManager.shared.reconcile() }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Offer to move the app to Applications, if it isn't already there.
        // A moment's delay so the window is up before the sheet appears on
        // top of it.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            AppState.shared?.checkInstallLocation()
            // If the app was just moved here from Downloads, this is the
            // instance that can safely clear the old copy away — it is
            // running from Applications, not from there.
            AppState.shared?.clearDownloadsCopyIfPending()
        }

        // Look for a newer release on every launch (not in the test vibescapes).
        let testVibescape = ["--snapshot", "--record", "--video", "--share-image"].contains { CommandLine.arguments.contains($0) }
        if !testVibescape { UpdateChecker.shared.check(userInitiated: false) }

        // Snapshot vibescape — render a few frames then exit. Used for verification.
        if CommandLine.arguments.contains("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runSnapshot()
            }
        }

        // Share picture — render the picture a share link shows, with the
        // brand and the credit on it, and write it out. The share sheet is
        // the only other way to see it, and it needs a window and a click.
        if CommandLine.arguments.contains("--share-image") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runShareImage()
            }
        }

        // Video export — record the last ten seconds of the vibescape, with
        // the music, and say where it went.
        if CommandLine.arguments.contains("--export-video") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runExportVideo()
            }
        }

        // Song lookup — ask the catalogue what a song is, and say. Used to
        // check the lookup without a music app in the picture.
        if CommandLine.arguments.contains("--song-lookup") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.runSongLookup()
            }
        }

        // Shazam spike — one match against Shazam's catalogue, and what came
        // back. Needs a music app playing something; the demo tone will not
        // match anything.
        if CommandLine.arguments.contains("--shazam-spike") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runShazamSpike()
            }
        }

        // Record vibescape — capture consecutive frames for diffing.
        if CommandLine.arguments.contains("--record") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runRecord()
            }
        }

        // Video vibescape — render every vibescape to a numbered PNG sequence for
        // `scripts/make-demo-video.sh` to encode. Needs no audio source and no
        // window, so it's grouped with the other offline renderers.
        if CommandLine.arguments.contains("--video") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runVideo()
            }
        }

        // A song, made up — so the chrome can be looked at with one in it
        // without a music app playing something.
        if let i = CommandLine.arguments.firstIndex(of: "--fake-song"), i + 1 < CommandLine.arguments.count {
            let title = CommandLine.arguments[i + 1]
            let artist = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                AppState.shared?.setFakeSong(title: title, artist: artist)
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

        // `--move-prompt` opens the "move to Applications" sheet on launch,
        // so the panel can be looked at without having to run the app from
        // somewhere it shouldn't be.
        if CommandLine.arguments.contains("--move-prompt") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                AppState.shared?.showMoveToApplications = true
            }
        }

        // `--vibescapes` and `--custom-vibescape` open the two panels straight
        // away, so they can be looked at without going through the list.
        if CommandLine.arguments.contains("--vibescapes") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                AppState.shared?.showVibescapesSheet = true
            }
        }
        if CommandLine.arguments.contains("--custom-vibescape") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                AppState.shared?.customVibescapeSheet = .new
            }
        }

        // `--simulate-crash` faults on purpose so PostHog's SDK autocapture can
        // be verified without waiting for a real band-vibescape crash to turn up.
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
                // --toggle-float turns the float on and off again first,
                // which is the sequence that used to leave the green button
                // dead: the proxy took it over for the float and never gave
                // AppKit's own behaviour back.
                let pressGreen = CommandLine.arguments.contains("--green-button")
                let toggleFloat = CommandLine.arguments.contains("--toggle-float")
                if toggleFloat {
                    let state = AppState.shared
                    print("[window] float was: \(state?.alwaysOnTop == true)")
                    state?.setAlwaysOnTop(true)
                    print("[window] float now: \(state?.alwaysOnTop == true)")
                    state?.setAlwaysOnTop(false)
                    print("[window] float now: \(state?.alwaysOnTop == true)")
                    let button = w.standardWindowButton(.zoomButton)
                    print("[window] green button target: \(button?.target.map { String(describing: type(of: $0)) } ?? "AppKit (default)")")
                }
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

    /// Session tallies (vibescape switches, palette switches) only reach PostHog on
    /// the next flush — 2.5s after the last event — so without this they'd be
    /// lost every time someone quit shortly after fiddling with the controls.
    func applicationWillTerminate(_ notification: Notification) {
        Task { await Analytics.shared.flushNow() }
        // The live uniform values are only true while the app is running, and
        // the file is left behind on quit. Removing it means an agent asking
        // straight after the app closes is told the app isn't running, rather
        // than being handed one last frozen frame as though it were live.
        LiveUniforms.clearPublishedFile()
        // If the app was just moved to Applications, the copy that is
        // quitting is the old one. Launch the new one on the way out, so
        // the two never run at once: the app restores whatever audio source
        // it had last, and two of them after the same capture session would
        // leave the new one with no sound.
        if let pending = InstallLocation.pendingRelaunch {
            InstallLocation.pendingRelaunch = nil
            InstallLocation.launch(at: pending)
        }
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
        // the genre pill only appears in band vibescape — so shoot both.
        let shots: [(String, VibescapeID, DropdownID?)] = [
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
            app.activeVibescape = mode
            app.openDropdown = open
            for (suffix, shotSize) in sizes {
                // The chrome reads the tier from the window's width, which the
                // shot has to fake — ImageRenderer has no window.
                app.setWindowWidthForTesting(shotSize.width)
                // let the body re-evaluate with the new vibescape
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
        // A stand-in for a vibescape the user already has, so the editing view
        // can be reviewed without one on disk.
        let sampleVibescape = CustomVibescape(id: "shot", name: "My Mode", author: "Minith Labs",
                                    url: "https://minithlabs.com",
                                    shader: CustomVibescapeGuide.starterTemplate,
                                    enabled: true, modified: Date())
        // The share sheet for a vibescape the user wrote, so the name and the
        // gallery tickbox can be looked at. In memory only — nothing is
        // written to the user's folder by a screenshot.
        let sampleAuthor = "Syd Lawrence"
        let sampleForShare = CustomVibescape(
            id: "shot", name: "My Mode", author: sampleAuthor,
            url: "https://minithlabs.com",
            shader: CustomVibescapeGuide.starterTemplate,
            enabled: true, modified: Date())
        app.previewVibescape(sampleForShare)

        for (name, view, width, height) in [
            ("all-modes", AnyView(VibescapesView(scrollable: false, height: 1400)), CGFloat(720), CGFloat(1400)),
            ("all-modes-drop", AnyView(VibescapesView(scrollable: false, height: 1400, dropTargetIndex: 4)), CGFloat(720), CGFloat(1400)),
            ("custom-mode", AnyView(CustomVibescapeView()), CGFloat(720), CGFloat(560)),
            ("custom-mode-write", AnyView(CustomVibescapeView(initialStep: .write)), CGFloat(720), CGFloat(560)),
            ("custom-mode-ai", AnyView(CustomVibescapeView(initialStep: .ai, scrollable: false)), CGFloat(720), CGFloat(560)),
            ("custom-mode-edit", AnyView(CustomVibescapeView(editing: sampleVibescape)), CGFloat(720), CGFloat(560)),
            ("custom-mode-mcp", AnyView(CustomVibescapeView(initialStep: .mcp, scrollable: false)), CGFloat(720), CGFloat(560)),
            ("move-to-apps", AnyView(MoveToApplicationsView()), CGFloat(520), CGFloat(360)),
            ("share", AnyView(ShareVibescapeView(vibescape: .builtin(.band))), CGFloat(540), CGFloat(620)),
            ("share-custom", AnyView(ShareVibescapeView(vibescape: .custom("shot"))), CGFloat(540), CGFloat(760)),
        ] {
            let renderer = ImageRenderer(content: view
                .environmentObject(app)
                .frame(width: width, height: height)
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
        // In MCP vibescape the window is hidden on purpose and the server is the
        // app, so hiding it mustn't be the end of the process.
        if CommandLine.arguments.contains("--mcp") { return false }
        return true
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
                app.renderer.setVibescape(.builtin(.band))
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
            for mode in Vibescape.allCases {
                app.renderer.renderToPNG(width: 1280, height: 720, mode: .builtin(mode),
                                         frames: 60,
                                         path: "\(outDir)/viz-\(mode.rawValue).png")
            }
            // The user's own vibescapes, if they have any, so a snapshot shows
            // everything the app can draw.
            for custom in app.customVibescapes {
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

    /// Writes the picture a share link shows: the vibescape, with the brand
    /// and the credit on it.
    ///
    ///   Vibresia --share-image [slug] [out.jpg]
    ///
    /// The same code path the share sheet uses, so what comes out here is
    /// what goes into the link preview.
    private func runShareImage() {
        let args = CommandLine.arguments
        func value(_ flag: String, _ fallback: String) -> String {
            if let i = args.firstIndex(of: flag), i + 1 < args.count { return args[i + 1] }
            return fallback
        }
        let slug = value("--share-image", "tunnel")
        let out = value("--share-image-out", "/tmp/vibresia-share.jpg")

        guard let app = AppState.shared else { exit(1) }
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            attempts += 1
            guard app.renderer.isReady else {
                if attempts > 200 { NSLog("[SHARE-IMAGE] timeout renderer"); exit(1) }
                return
            }
            t.invalidate()

            let mode: VibescapeID
            if let builtin = Vibescape(rawValue: slug) {
                mode = .builtin(builtin)
            } else if let custom = app.customVibescapes.first(where: { $0.id == slug }) {
                mode = .custom(custom.id)
            } else {
                NSLog("[SHARE-IMAGE] no vibescape called \(slug)")
                exit(1)
            }
            let author = app.customVibescape(id: mode.slug)?.author ?? VibescapeMetadata.author
            Task { @MainActor in
                guard let data = await ShareImageBuilder.jpeg(
                    renderer: app.renderer, mode: mode,
                    width: 1200, height: 630, time: 6.0,
                    author: author.isEmpty ? VibescapeMetadata.author : author) else {
                    NSLog("[SHARE-IMAGE] could not render")
                    exit(1)
                }
                do {
                    try data.write(to: URL(fileURLWithPath: out), options: .atomic)
                    NSLog("[SHARE-IMAGE] saved=\(out) bytes=\(data.count)")
                    exit(0)
                } catch {
                    NSLog("[SHARE-IMAGE] could not write: \(error)")
                    exit(1)
                }
            }
        }
    }

    /// Records the last ten seconds of the vibescape, with the music, and
    /// writes it to a movie.
    ///
    ///   Vibresia --export-video [slug] [out.mp4]
    ///
    /// The same code the share sheet uses, so what comes out here is what
    /// comes out there.
    private func runExportVideo() {
        let args = CommandLine.arguments
        func value(_ flag: String, _ fallback: String) -> String {
            if let i = args.firstIndex(of: flag), i + 1 < args.count { return args[i + 1] }
            return fallback
        }
        let slug = value("--export-video", "tunnel")
        let out = value("--export-video-out", "/tmp/vibresia-export.mp4")

        guard let app = AppState.shared else { exit(1) }
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
            attempts += 1
            guard app.renderer.isReady else {
                if attempts > 60 { NSLog("[VIDEO] timeout renderer"); exit(1) }
                return
            }
            t.invalidate()

            let mode: VibescapeID
            if let builtin = Vibescape(rawValue: slug) {
                mode = .builtin(builtin)
            } else if let custom = app.customVibescapes.first(where: { $0.id == slug }) {
                mode = .custom(custom.id)
            } else {
                NSLog("[VIDEO] no vibescape called \(slug)")
                exit(1)
            }

            // Something to record. The demo tone if nothing is playing, so
            // the export has audio to put in it.
            if app.audio.sourceState != .live && app.audio.sourceState != .demo {
                app.audio.startDemo()
            }
            // And a moment for the ring buffer to fill.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.exportVideoNow(mode: mode, out: out)
            }
        }
    }

    private func exportVideoNow(mode: VibescapeID, out: String) {
        guard let app = AppState.shared else { exit(1) }
        Task { @MainActor in
            do {
                try await VideoExporter.export(renderer: app.renderer, mode: mode,
                                              audio: app.audio,
                                              to: URL(fileURLWithPath: out))
                NSLog("[VIDEO] saved=\(out)")
                exit(0)
            } catch {
                NSLog("[VIDEO] failed: \(error)")
                exit(1)
            }
        }
    }

    /// Looks a song up in Apple's catalogue and says what it found.
    ///
    ///   Vibresia --song-lookup "bad guy" "Billie Eilish"
    ///
    /// The same lookup the app makes when a music app says what it is
    /// playing, so the answer here is the answer there.
    private func runSongLookup() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--song-lookup"), i + 1 < args.count else {
            NSLog("[SONG] needs a title: --song-lookup \"title\" [artist]")
            exit(1)
        }
        let title = args[i + 1]
        let artist = i + 2 < args.count ? args[i + 2] : ""

        Task {
            let song = await SongIdentifier.shared.identify(title: title, artist: artist)
            guard let song else {
                NSLog("[SONG] no match for \(title) — \(artist)")
                exit(1)
            }
            NSLog("[SONG] \(song.title) — \(song.artist)")
            NSLog("[SONG] catalogue genre: \(song.catalogueGenre)")
            NSLog("[SONG] our genre: \(song.genre?.name ?? "none")")
            exit(0)
        }
    }

    /// Asks Shazam's catalogue what is playing, once, and says what happened.
    ///
    ///   Vibresia --shazam-spike
    ///
    /// The point of it is the answer, not the song: matching against the
    /// catalogue needs the ShazamKit capability enabled on the app's
    /// identifier, and error 202 means the app wasn't allowed to ask rather
    /// than that the catalogue didn't know the song.
    private func runShazamSpike() {
        guard let app = AppState.shared else { exit(1) }
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
            attempts += 1
            guard app.renderer.isReady else {
                if attempts > 60 { NSLog("[SHAZAM] timeout renderer"); exit(1) }
                return
            }
            t.invalidate()

            // A couple of seconds of audio, so there is something to sign.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
                guard let buffer = app.audio.recentAudioBuffer(seconds: ShazamIdentifier.seconds) else {
                    NSLog("[SHAZAM] no audio captured")
                    exit(1)
                }
                Task {
                    let outcome = await ShazamIdentifier().match(buffer)
                    switch outcome {
                    case .matched(let match):
                        NSLog("[SHAZAM] matched: \(match.title) — \(match.artist)")
                        NSLog("[SHAZAM] genres: \(match.genres.joined(separator: ", "))")
                    case .noMatch:
                        NSLog("[SHAZAM] the catalogue didn't know it")
                    case .failed(let reason):
                        NSLog("[SHAZAM] failed: \(reason)")
                    }
                    exit(0)
                }
            }
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

        // In idle vibescape, don't start the demo tone — we want to see if the
        // static (no-audio) render is stable.
        let idle = args.contains("--idle")
        if !idle {
            app.audio.startDemo()
        } else {
            NSLog("[REC] idle mode — no audio source")
        }
        // Record whatever vibescape is active (the --vibescape flag can set it).
        app.renderer.setVibescape(app.activeVibescape)
        NSLog("[REC] recording mode \(app.activeVibescape.rawValue)")

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

    /// Renders every built-in vibescape to a numbered sequence of PNG frames.
    ///
    /// This is the same draw the app does, into an offscreen target, through
    /// the same palette grade — so a frame here is a frame of the real thing.
    /// The video is assembled from the PNGs afterwards (see
    /// `scripts/make-demo-video.sh`), which keeps the app out of the business
    /// of encoding video and makes a re-render of one vibescape cheap.
    private func runVideo() {
        let args = CommandLine.arguments
        func value(_ flag: String, _ fallback: String) -> String {
            if let i = args.firstIndex(of: flag), i + 1 < args.count { return args[i + 1] }
            return fallback
        }
        let outDir = value("--video", "/tmp/vib_video")
        // 960x632 is the size the site has always used, so the layout of the
        // page doesn't move when the video is replaced.
        let size = value("--video-size", "960x632").split(separator: "x")
        let width = size.count == 2 ? Int(size[0]) ?? 960 : 960
        let height = size.count == 2 ? Int(size[1]) ?? 632 : 632
        let fps = Double(value("--video-fps", "30")) ?? 30
        let seconds = Double(value("--video-seconds", "3.0")) ?? 3.0
        let frames = max(2, Int((fps * seconds).rounded()))

        // `--video-only ribbons,silk` renders a subset, for re-rendering one
        // vibescape without paying for all of them.
        let only: Set<String>? = {
            guard let i = args.firstIndex(of: "--video-only"), i + 1 < args.count else { return nil }
            return Set(args[i + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }()

        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            attempts += 1
            guard let app = AppState.shared else {
                if attempts > 200 { NSLog("[VIDEO] timeout AppState"); exit(1) }
                return
            }
            if !app.renderer.isReady {
                if attempts > 200 { NSLog("[VIDEO] timeout renderer"); exit(1) }
                return
            }
            t.invalidate()

            // Auto Scan isn't a look in itself — it's the thing that hands over
            // to other looks — so a reel skips it and shows what it switches to.
            let vibescapes = Vibescape.allCases.filter {
                $0 != .autoScan && (only == nil || only!.contains($0.rawValue))
            }
            NSLog("[VIDEO] \(vibescapes.count) vibescapes, \(frames) frames each at \(Int(width))x\(Int(height))")

            for (index, vibescape) in vibescapes.enumerated() {
                let prefix = String(format: "%02d_%@_", index, vibescape.rawValue)
                app.renderer.renderFrameSequence(
                    width: width, height: height, mode: .builtin(vibescape),
                    frames: frames, syntheticAudio: true, fps: fps,
                    directory: outDir, prefix: prefix)
                NSLog("[VIDEO] \(index + 1)/\(vibescapes.count) \(vibescape.rawValue)")
            }

            // A plain list, so the shell script doesn't have to re-derive the
            // order and risk putting the reel in a different order than the app.
            let list = vibescapes.enumerated()
                .map { String(format: "%02d_%@", $0.offset, $0.element.rawValue) }
                .joined(separator: "\n") + "\n"
            try? list.write(toFile: outDir + "/_order.txt", atomically: true, encoding: .utf8)
            NSLog("[VIDEO] done")
            exit(0)
        }
}
}
