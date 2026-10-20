import SwiftUI
import AppKit
import OpenGL.GL3
import CoreVideo
import os

/// NSViewRepresentable wrapping a custom NSOpenGLView.
struct OpenGLVisualizerView: NSViewRepresentable {
    let renderer: OpenGLRenderer
    let mode: ModeID
    @EnvironmentObject var app: AppState

    func makeNSView(context: Context) -> GLVisualizerNSView {
        let view = GLVisualizerNSView(renderer: renderer)
        renderer.setMode(mode)
        // The OpenGL context now exists, so the user's own modes can be
        // compiled for the first time.
        app.loadCustomModesOnce()
        return view
    }

    func updateNSView(_ nsView: GLVisualizerNSView, context: Context) {
        renderer.setMode(mode)
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
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        if didSetup { return }
        didSetup = true

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
        // because the scanner is supposed to keep cycling through the modes
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