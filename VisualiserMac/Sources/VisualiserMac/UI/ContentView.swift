import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var app: AppState

    /// The HUD hides (slides out) while the pointer is away from the window,
    /// leaving just the visuals and the credits button.
    @StateObject private var pointer = PointerWatcher()
    @State private var window: NSWindow?
    private var pointerInside: Bool { pointer.inside }

    /// Shown when the pointer is over the window, or a drop-down / the intro
    /// needs the UI on screen.
    private var chromeVisible: Bool {
        pointerInside || app.openDropdown != nil || app.showIntro
    }

    var body: some View {
        ZStack {
            // OpenGL-rendered visualizer (full-bleed)
            OpenGLVisualizerView(renderer: app.renderer, mode: app.activeMode)
                .ignoresSafeArea()

            // CRT overlay — scanlines, vignette, glow. Faded out in silence so
            // the resting visual is one flat colour.
            CRTOverlay()
                .opacity(app.isSounding ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: app.isSounding)

            // HUD overlays
            VStack {
                HUDView()
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .offset(y: chromeVisible ? 0 : -110)
                    .opacity(chromeVisible ? 1 : 0)
                Spacer()
                FooterView()
                    .padding(.leading, 28)
                    // Leave room for the credits button in the corner.
                    .padding(.trailing, 215)
                    .padding(.bottom, 14)
                    .offset(y: chromeVisible ? 0 : 80)
                    .opacity(chromeVisible ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.35), value: chromeVisible)
            .opacity(app.showIntro ? 0 : 1)
            .allowsHitTesting(!app.showIntro)
            // The open drop-down list lives inside HUDView, and zIndex only
            // orders *siblings* — so the HUD has to sit above the click-away
            // catcher for the list to receive taps. Without this the catcher
            // paints over the list and swallows every row click.
            .zIndex(60)

            HStack {
                Spacer()
                MeterView()
                    .padding(.trailing, 28)
                    .padding(.top, 60)
                    .padding(.bottom, 90)
                    .offset(x: chromeVisible ? 0 : 300)
                    .opacity(chromeVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.35), value: chromeVisible)
            }
            .opacity(app.showIntro ? 0 : 0.85)
            .allowsHitTesting(!app.showIntro)
            .animation(.easeOut(duration: 0.4), value: app.showIntro)
            .zIndex(60)

            // Credits / support button, bottom-right corner, with the
            // "Proudly Shareware" link above it. Both stay when the rest of
            // the UI hides.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        SharewareLink()
                            .padding(.trailing, 10)
                        AboutButton()
                    }
                    .padding(.trailing, 28)
                    .padding(.bottom, 16)
                }
            }
            .opacity(app.showIntro ? 0 : 1)
            .allowsHitTesting(!app.showIntro)
            .zIndex(60)

            // beat flash
            BeatFlash(strength: app.lastBeat)
                .allowsHitTesting(false)

            // intro overlay
            if app.showIntro {
                IntroView()
                    .transition(.opacity)
                    .zIndex(80)
            }

            // Click-away catcher for the header drop-downs. Above the
            // visualiser so a click anywhere outside an open list dismisses
            // it, but below the HUD so the list itself stays clickable.
            if app.openDropdown != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.14)) { app.openDropdown = nil }
                    }
                    .zIndex(50)
            }
        }
        .background(WindowReader(window: $window))
        .onChange(of: window) { _, w in pointer.window = w }
    }
}

struct CRTOverlay: View {
    var body: some View {
        // Pre-rasterized at the screen size. Drawing this image costs nothing
        // per frame and the gradient detail can't shimmer between draws.
        Image(nsImage: CRTCache.image)
            .resizable()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Singleton cache for the rasterized CRT overlay image.
enum CRTCache {
    static let image: NSImage = render()
    private static let renderSize = CGSize(width: 1280, height: 720)

    private static func render() -> NSImage {
        let s = renderSize
        let img = NSImage(size: s)
        img.lockFocus()
        defer { img.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return img }

        // 1. scanlines
        let scan = CGGradient(
            colorsSpace: nil,
            colors: [
                NSColor.clear.cgColor,
                NSColor.black.withAlphaComponent(0.10).cgColor,
                NSColor.clear.cgColor,
                NSColor.black.withAlphaComponent(0.10).cgColor
            ] as CFArray,
            locations: [0.0, 0.33, 0.66, 1.0]
        )!
        ctx.drawLinearGradient(
            scan,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: s.height),
            options: []
        )

        // 2. vignette
        let vig = CGGradient(
            colorsSpace: nil,
            colors: [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.55).cgColor] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            vig,
            startCenter: CGPoint(x: s.width / 2, y: s.height / 2),
            startRadius: 200,
            endCenter: CGPoint(x: s.width / 2, y: s.height / 2),
            endRadius: 700,
            // fill inside startRadius too, so there's no unpainted centre disc
            // (it showed as a hard-edged oval once stretched to the window)
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        // 3. soft color glow
        ctx.setBlendMode(.screen)
        let glow = CGGradient(
            colorsSpace: nil,
            colors: [
                NSColor(red: 1, green: 0.17, blue: 0.84, alpha: 0.04).cgColor,
                NSColor.clear.cgColor
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: s.width / 2, y: s.height / 2),
            startRadius: 100,
            endCenter: CGPoint(x: s.width / 2, y: s.height / 2),
            endRadius: 800,
            options: [.drawsBeforeStartLocation]
        )

        return img
    }
}

struct BeatFlash: View {
    let strength: Double

    /// Beat flashes are visually invisible below this, so we hide the whole
    /// overlay rather than re-rendering an imperceptible tint 60 times a second.
    /// The animation only fires when crossing the threshold, not on every
    /// strength tick.
    private static let visibleThreshold: Double = 0.04

    var body: some View {
        let isVisible = strength > Self.visibleThreshold
        RadialGradient(
            colors: [
                Color(red: 1, green: 0.17, blue: 0.84).opacity(min(0.4, strength * 0.6)),
                .clear
            ],
            center: .center,
            startRadius: 50,
            endRadius: 600
        )
        .opacity(isVisible ? strength : 0)
        .animation(.easeOut(duration: 0.18), value: isVisible)
    }
}
/// Hands back the NSWindow hosting this view (for the pointer check).
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        if window == nil { DispatchQueue.main.async { window = view.window } }
    }
}

/// Polls the pointer against the window frame. Hover events alone stop
/// arriving when the app isn't frontmost, which is exactly when the
/// visualiser is usually being watched. Reports "outside" after half a second
/// away. Owns its timer, so view re-renders (30 a second) don't reset it.
final class PointerWatcher: ObservableObject {
    @Published private(set) var inside = true
    weak var window: NSWindow?
    private var leftAt: Date?
    private var timer: Timer?

    init() {
        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    private func poll() {
        guard let host = window ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        if host.frame.contains(NSEvent.mouseLocation) {
            leftAt = nil
            if !inside { inside = true }
        } else {
            let left = leftAt ?? Date()
            leftAt = left
            if inside && Date().timeIntervalSince(left) > 0.5 { inside = false }
        }
    }
}
