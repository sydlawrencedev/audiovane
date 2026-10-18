import SwiftUI
import AppKit
import MetalKit

@main
struct VisualiserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("AUDIVANE") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
        WindowGroup("AUDIVANE") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Visualizer") {
                ForEach(VisualizerMode.allCases) { mode in
                    Button(mode.displayName.capitalized) { app.activeMode = mode }
                        .keyboardShortcut(KeyEquivalent(mode.shortcutKey), modifiers: [])
                }
                Divider()
                Button("Start System Audio") { Task { await app.audio.startSystemCapture() } }
                Button("Use Microphone")     { app.audio.startMicrophone() }
                Button("Use Demo Tone")      { app.audio.startDemo() }
                Divider()
                Button("Open Hamster Folder…") {
                    SpriteAtlas.ensureFolder()
                    NSWorkspace.shared.open(SpriteAtlas.folder)
                }
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

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
        let shots: [(String, VisualizerMode, DropdownID?)] = [
            ("modes", .tunnel, nil),
            ("band", .band, nil),
            ("mode-open", .tunnel, .mode),
            ("genre-open", .band, .genre),
        ]
        for (name, mode, open) in shots {
            app.showIntro = false
            app.activeMode = mode
            app.openDropdown = open
            // let the body re-evaluate with the new mode
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            let renderer = ImageRenderer(content: ContentView()
                .environmentObject(app)
                .frame(width: size.width, height: size.height)
                .background(Color.black))
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
                app.renderer.setMode(.band)
                for g in Genre.allCases {
                    app.renderer.genre = g
                    // let a couple of frames go by so the shader settles
                    Thread.sleep(forTimeInterval: 0.3)
                    let path = "\(outDir)/band_\(g.rawValue)_\(g.name.lowercased()).png"
                    app.renderer.renderToPNG(width: 1280, height: 720, mode: .band,
                                             frames: 60, path: path)
                    NSLog("[SNAP] genre=\(g.name) saved=\(FileManager.default.fileExists(atPath: path))")
                }
                NSLog("[SNAP] genre sweep done")
                exit(0)
            }
            for mode in VisualizerMode.allCases {
                app.renderer.renderToPNG(width: 1280, height: 720, mode: mode,
                                         frames: 60,
                                         path: "\(outDir)/viz-\(mode.rawValue).png")
            }
            app.renderer.singerVoice = .duet
            app.renderer.renderToPNG(width: 1280, height: 720, mode: .band, frames: 60,
                                     path: "\(outDir)/viz-band-duet.png")
            app.renderer.singerVoice = .auto
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