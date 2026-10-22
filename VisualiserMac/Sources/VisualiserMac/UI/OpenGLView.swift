import SwiftUI
import AppKit
import OpenGL.GL3
import CoreVideo
import os

/// NSViewRepresentable wrapping a custom NSOpenGLView.
struct OpenGLVisualizerView: NSViewRepresentable {
    let renderer: OpenGLRenderer
    let mode: VibescapeID
    @EnvironmentObject var app: AppState

    func makeNSView(context: Context) -> GLVisualizerNSView {
        let view = GLVisualizerNSView(renderer: renderer)
        renderer.setVibescape(mode)
        // The OpenGL context now exists, so the user's own vibescapes can be
        // compiled for the first time.
        app.loadCustomVibescapesOnce()
        return view
    }

    func updateNSView(_ nsView: GLVisualizerNSView, context: Context) {
        renderer.setVibescape(mode)
    }
}

/// NSOpenGLView subclass driven by CVDisplayLink for true vsync-paced redraws.
final class GLVisualizerNSView: NSOpenGLView {
    private let renderer: OpenGLRenderer
    private var displayLink: CVDisplayLink?
    private var didSetup = false
    /// True after we've committed the static "idle" frame to the drawable.
    /// When idle, we stop calling render entirely so AppKit doesn't keep
    /// re-compositing the layer, which is what was causing the visible flicker.
    private var idleFrameCommitted = false
    private var lastSourceKind: String = ""
    /// Set when a render is queued on main, cleared when it runs. The display
    /// link skips queueing while one is pending, so a slow frame drops frames
    /// instead of building an unbounded backlog that freezes the app.
    private let renderPending = OSAllocatedUnfairLock(initialState: false)
    /// The area the mouse is watched over.
    private var tracking: NSTrackingArea?
    /// The keyboard, watched rather than taken.
    ///
    /// The view is not the first responder — SwiftUI's hosting view is — so
    /// the keys are watched instead. They are not consumed: the app's own
    /// shortcuts still work, and a vibescape can see the key as well.
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    /// The MIDI listener, kept here so that it stays alive: a listener
    /// nobody holds is a listener nobody listens with.
    private var midiListener: MidiListener?

    init(renderer: OpenGLRenderer) {
        self.renderer = renderer
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 0,
            0
        ]
        let format = NSOpenGLPixelFormat(attributes: attrs)!
        super.init(frame: .zero, pixelFormat: format)!
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
    }

    // MARK: - What the person is doing

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A window does not deliver mouse-moved events unless it says it
        // will, and a vibescape that follows the pointer needs them.
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // `.activeAlways` rather than `.activeInKeyWindow`: the pointer
        // keeps being tracked when the app is in the background, so a
        // vibescape that follows it does not stop dead the moment
        // somebody clicks somewhere else.
        let area = NSTrackingArea(rect: bounds,
                                 options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    /// The pointer, in the shader's own coordinates.
    ///
    /// The same numbers `screenP()` produces, so a shader can use it
    /// without knowing anything about the window: x across the screen, y up
    /// from the middle, both scaled by the height.
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let height = bounds.height
        guard height > 0 else { return }
        renderer.input.setMouse(CGPoint(
            x: (point.x - bounds.width / 2) / height,
            y: (point.y - bounds.height / 2) / height))
    }

    override func mouseDown(with event: NSEvent) { renderer.input.setMouseDown(true) }
    override func mouseUp(with event: NSEvent) { renderer.input.setMouseDown(false) }
    override func rightMouseDown(with event: NSEvent) { renderer.input.setMouseDown(true) }
    override func rightMouseUp(with event: NSEvent) { renderer.input.setMouseDown(false) }

    /// The keyboard, watched.
    ///
    /// The last key is the character code of the key that was pressed, so
    /// a shader can ask whether it was the space bar (32) or a letter (65
    /// for A). Zero means nothing has been pressed.
    private func watchKeys() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Typing a name into a text field is not a performance.
            if let field = self?.window?.firstResponder as? NSTextView,
               field.isEditable {
                return event
            }
            // A key with no character — an arrow, a function key — leaves
            // the last character alone rather than blanking it: a shader
            // that asks "was that the space bar?" should not be told "no"
            // because somebody pressed an arrow afterwards.
            if let characters = event.characters,
               let first = characters.unicodeScalars.first {
                self?.renderer.input.pressKey(Float(first.value))
            }
            self?.renderer.input.pressKeyDown()
            return event
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.renderer.input.releaseKey()
            return event
        }
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        if didSetup { return }
        didSetup = true

        // The keyboard, and the MIDI ports.
        watchKeys()
        let midi = MidiListener(state: renderer.input)
        midi.start()
        midiListener = midi

        // Render at 1x: full-screen shaders at Retina resolution are ~4x the
        // GPU work and can't hold 60fps in a large window.
        wantsBestResolutionOpenGLSurface = false
        var swapInt: GLint = 1
        openGLContext?.setValues(&swapInt, for: .swapInterval)

        renderer.attach(to: self)
        renderer.setSize(width: bounds.width, height: bounds.height)

        startDisplayLink()
    }

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link = link else { return }
        self.displayLink = link

        // The CVDisplayLink callback fires on a system thread at the display's
        // refresh rate. We schedule a single render on the main thread per
        // fire; CVDisplayLink's per-frame timing is the most reliable way to
        // stay vsync-aligned without the jitter that NSTimer introduces.
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, contextPtr) -> CVReturn in
            guard let contextPtr = contextPtr else { return kCVReturnSuccess }
            let view = Unmanaged<GLVisualizerNSView>.fromOpaque(contextPtr).takeUnretainedValue()
            let alreadyQueued = view.renderPending.withLock { pending -> Bool in
                defer { pending = true }
                return pending
            }
            if !alreadyQueued {
                DispatchQueue.main.async {
                    view.renderPending.withLock { $0 = false }
                    view.renderFrame()
                }
            }
            return kCVReturnSuccess
        }, opaqueSelf)
        CVDisplayLinkStart(link)
    }

    override func reshape() {
        super.reshape()
        guard didSetup else { return }
        let backing = bounds.size  // 1x surface, see prepareOpenGL
        renderer.setSize(width: backing.width, height: backing.height)
        openGLContext?.update()
    }

    /// Called on the main thread from the CVDisplayLink callback.
    func renderFrame() {
        guard didSetup else { return }

        // An offscreen render — a video export, a share image, a preview —
        // borrows the renderer's size to draw into its own framebuffer, and
        // the two would fight over it. The window holds its last frame
        // until the render is done, which is what stops the canvas appearing
        // to zoom while one is in flight.
        if renderer.isRenderingOffscreen { return }

        let sourceKind = renderer.audio.sourceKindForRender
        let isIdle = (sourceKind == "idle" || sourceKind == "error")

        // Reset the "idle frame committed" flag whenever the source changes.
        if sourceKind != lastSourceKind {
            idleFrameCommitted = false
            lastSourceKind = sourceKind
        }

        // In idle, commit one frame, then stop drawing. Continuing to
        // flushBuffer() each vsync forces AppKit to re-composite the layer
        // and that re-rasterization is what the user perceives as flicker.
        //
        // Auto-scan is the exception: it has to keep drawing in silence,
        // because the scanner is supposed to keep cycling through the vibescapes
        // whether or not music is playing.
        let keepsDrawing = renderer.isAutoScanning
        if isIdle && idleFrameCommitted && !keepsDrawing {
            return
        }

        openGLContext?.makeCurrentContext()
        let backing = bounds.size  // 1x surface, see prepareOpenGL
        renderer.setSize(width: backing.width, height: backing.height)
        renderer.render()
        openGLContext?.flushBuffer()

        if isIdle {
            idleFrameCommitted = true
        }
    }
}