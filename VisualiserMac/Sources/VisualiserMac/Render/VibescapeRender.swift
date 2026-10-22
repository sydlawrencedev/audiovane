import Foundation
import OpenGL.GL3
import AppKit
import simd

// MARK: - What the caller can steer

/// The audio uniforms a preview can be pointed at by hand.
///
/// Anything left `nil` is taken from the music the app is actually hearing, or
/// — when the app isn't running — from a stand-in that behaves like busy music.
/// The point of the type being all-optionals is that a preview with nothing set
/// is still a useful picture.
struct UniformOverrides {
    var bass: Float?
    var mid: Float?
    var treble: Float?
    var level: Float?
    var levelSmooth: Float?
    var bassSmooth: Float?
    var beat: Float?
    var beatStrength: Float?
    var beats: Float?
    var active: Float?
    var idle: Float?
    var presence: Float?
    var scroll: Float?
    var clock: Float?
    /// Up to 96 values, low to high. Fewer are padded, more are truncated.
    var bands: [Float]?
    /// Where in the track we are, in seconds.
    var trackPos: Float?
    /// How long the track is, in seconds.
    var trackDuration: Float?
    /// The pointer, in the shader's own coordinates: x across the screen, y
    /// up from the middle. Two numbers, because a shader wants both.
    var mouse: [Float]?
    /// Whether a mouse button is down.
    var mouseDown: Float?
    /// Whether there is a pointer to react to.
    var mouseHere: Float?
    /// The key that was pressed, as its character code. 32 is the space bar.
    var key: Float?
    /// Whether a key is held.
    var keyDown: Float?
    /// The MIDI note, 0..127.
    var midiNote: Float?
    /// How hard it was hit, 0..1.
    var midiVelocity: Float?
    /// How many notes are held.
    var midiNotes: Float?
    /// The MIDI controller number, 0..127.
    var midiCC: Float?
    /// Where that controller is, 0..1.
    var midiCCValue: Float?

    var isEmpty: Bool {
        bass == nil && mid == nil && treble == nil && level == nil
            && levelSmooth == nil && bassSmooth == nil && beat == nil
            && beatStrength == nil && beats == nil && active == nil
            && idle == nil && presence == nil && scroll == nil && clock == nil
            && bands == nil && trackPos == nil && trackDuration == nil
            && mouse == nil && mouseDown == nil && key == nil && keyDown == nil
            && midiNote == nil && midiVelocity == nil && midiNotes == nil
            && midiCC == nil && midiCCValue == nil
    }

    var names: [String] {
        var out: [String] = []
        if bass != nil { out.append("uBass") }
        if mid != nil { out.append("uMid") }
        if treble != nil { out.append("uTreble") }
        if level != nil { out.append("uLevel") }
        if levelSmooth != nil { out.append("uLevelSmooth") }
        if bassSmooth != nil { out.append("uBassSmooth") }
        if beat != nil { out.append("uBeat") }
        if beatStrength != nil { out.append("uBeatStrength") }
        if beats != nil { out.append("uBeats") }
        if active != nil { out.append("uActive") }
        if idle != nil { out.append("uIdle") }
        if presence != nil { out.append("uPresence") }
        if scroll != nil { out.append("uScroll") }
        if clock != nil { out.append("uClock") }
        if bands != nil { out.append("uBands") }
        if trackPos != nil { out.append("uTrackPos") }
        if trackDuration != nil { out.append("uTrackDuration") }
        if mouse != nil { out.append("uMouse") }
        if mouseDown != nil { out.append("uMouseDown") }
        if mouseHere != nil { out.append("uMouseHere") }
        if key != nil { out.append("uKey") }
        if keyDown != nil { out.append("uKeyDown") }
        if midiNote != nil { out.append("uMidiNote") }
        if midiVelocity != nil { out.append("uMidiVelocity") }
        if midiNotes != nil { out.append("uMidiNotes") }
        if midiCC != nil { out.append("uMidiCC") }
        if midiCCValue != nil { out.append("uMidiCCValue") }
        return out
    }
}

/// Everything that shapes a preview.
struct PreviewOptions {
    var width = 512
    var height = 512
    /// 1 draws one picture. More lays them out in a grid, left to right.
    var frames = 1
    var timeStart: Double = 0
    /// Seconds between frames in a strip.
    var timeStep: Double = 0.1
    /// Which palette to grade through. Nil means the app's current one, or
    /// NEON when the app isn't running.
    var palette: Palette?
    /// `false` shows the shader's own colours, before the palette touches them.
    var grade = true
    var uniforms = UniformOverrides()
    /// A strip wider than this gets its frames laid out in more than one row,
    /// so eight frames don't come back as one 4096-pixel-wide picture.
    var maxStripExtent = 1600
}

/// A rendered preview, and what went into it.
struct PreviewImage {
    let image: NSImage
    let frames: Int
    let columns: Int
    let rows: Int
    /// The size of one frame, which is smaller than the image when a strip had
    /// to be scaled down to fit.
    let frameWidth: Int
    let frameHeight: Int
    /// The palette the frame was graded through, or "none".
    let paletteName: String
    /// "the music playing now" or "stand-in values".
    let source: String
    /// The times each frame was drawn at, so the motion is legible.
    let times: [Double]
}

// MARK: - Drawing

/// Draws vibescapes off-screen, outside the app's window.
///
/// The app already knows how to draw a vibescape, but it draws it into a window
/// with whatever the music happens to be doing at the time. That is the right
/// thing for the app and the wrong thing for someone writing one: to ask "what
/// does this look like with the bass at 0.8" you need to choose the uniforms and
/// get the same answer twice.
///
/// So this does the drawing with the uniforms handed to it, applies the same
/// palette grade the app applies, and hands back a picture. It runs against
/// `VibescapeCompiler`'s standalone context, which is why the MCP server needs no
/// window and can't freeze the app if a shader hangs the GPU.
enum VibescapeRender {

    // MARK: Cached GL objects

    /// Compiled programs, keyed by source.
    ///
    /// The whole point of previewing is the loop "render, change a constant,
    /// render again" — so the expensive half, compiling, is done once per
    /// distinct shader and thrown away only when it falls out of the cache.
    private static var programCache: [String: GLuint] = [:]
    private static var programOrder: [String] = []
    private static let programCacheLimit = 12

    private static var gradeProgram: GLuint = 0
    private static var quadVAO: GLuint = 0

    /// Scene target: where the vibescape draws.
    private static var sceneFBO: GLuint = 0
    private static var sceneTex: GLuint = 0
    private static var sceneSize = (width: 0, height: 0)

    /// Output target: where the graded result lands, one frame at a time.
    private static var outFBO: GLuint = 0
    private static var outTex: GLuint = 0
    private static var outSize = (width: 0, height: 0)

    fileprivate static func location(_ program: GLuint, _ name: String) -> GLint {
        glGetUniformLocation(program, name)
    }

    // MARK: - Entry point

    /// Renders a vibescape and returns the picture.
    ///
    /// Broken code comes back as a `ShaderProblem`, in words, rather than a
    /// picture of nothing — but a vibescape that compiles and then draws badly
    /// still gets its picture, because seeing the wrong thing is how you work
    /// out that it's wrong.
    static func render(body: String, options: PreviewOptions) -> Result<PreviewImage, ShaderProblem> {
        switch ShaderValidator.checkShape(body) {
        case .failed(let problem):
            return .failure(problem)
        case .ok:
            break
        }
        return renderSource(FunShaders.customSource(body: body),
                            options: options,
                            label: "vibescape-preview")
    }

    /// Renders one of the built-in vibescapes, for the gallery.
    ///
    /// The built-ins aren't `render()` bodies — each writes its own `main()` —
    /// so they take a different path through the same machinery. They're drawn
    /// ungraded: some of them opt out of the grade anyway, and the point here
    /// is to show what a vibescape looks like, not what the current palette does
    /// to it.
    static func render(builtin vibescape: Vibescape, options: PreviewOptions) -> Result<PreviewImage, ShaderProblem> {
        guard let entry = FunShaders.modes.first(where: { $0.0 == vibescape }) else {
            return .failure(ShaderProblem(
                kind: .compileFailed,
                message: "There isn't a shader for \(vibescape.displayName)."))
        }
        var ungraded = options
        ungraded.grade = false
        return renderSource(FunShaders.prelude + entry.1,
                            options: ungraded,
                            label: "builtin-\(vibescape.rawValue)")
    }

    /// The shared pipeline: compile once, draw every frame, grade, compose.
    private static func renderSource(_ source: String, options: PreviewOptions,
                                      label: String) -> Result<PreviewImage, ShaderProblem> {
        guard VibescapeCompiler.ensureContext() else {
            return .failure(ShaderProblem(
                kind: .compileFailed,
                message: "This Mac wouldn't give the graphics system a context, so the vibescape couldn't be drawn."))
        }

        let width = max(1, min(options.width, 2048))
        let height = max(1, min(options.height, 2048))
        let frames = max(1, min(options.frames, 64))
        let step = options.timeStep.isFinite ? options.timeStep : 0.1

        let program: GLuint
        switch cachedProgram(source: source, label: label) {
        case .failure(let problem):
            return .failure(problem)
        case .success(let handle):
            program = handle
        }
        guard buildGradeIfNeeded(), buildQuadIfNeeded() else {
            return .failure(ShaderProblem(
                kind: .compileFailed,
                message: "The preview couldn't set up its drawing surface."))
        }

        let palette = options.grade ? resolvePalette(options.palette) : nil
        var values = UniformValues.resolve(overrides: options.uniforms)
        let source_ = values.source

        // Draw each frame and read it back before moving on. Reading back per
        // frame keeps the read exactly one frame's worth of pixels no matter
        // how many frames there are.
        var pictures: [CGImage] = []
        var times: [Double] = []
        for index in 0..<frames {
            let t = options.timeStart + Double(index) * step
            values.time = Float(t)
            values.beats = values.beatsAt(time: t)
            values.clock = values.clockAt(time: t)
            values.scroll = values.scrollAt(time: t)
            times.append(t)
            guard let frame = drawFrame(program: program,
                                        values: values,
                                        palette: palette,
                                        width: width,
                                        height: height) else {
                return .failure(ShaderProblem(
                    kind: .compileFailed,
                    message: "It compiled, but it couldn't be drawn. Try making it simpler."))
            }
            pictures.append(frame)
        }

        let layout = grid(for: frames, frameWidth: width, frameHeight: height,
                          maxExtent: options.maxStripExtent)
        let resized = scaled(pictures, to: layout.scale)
        let frameWidth = resized.first.map { $0.width } ?? width
        let frameHeight = resized.first.map { $0.height } ?? height
        guard let sheet = compose(resized, columns: layout.columns, rows: layout.rows,
                                  frameWidth: frameWidth, frameHeight: frameHeight) else {
            return .failure(ShaderProblem(
                kind: .compileFailed,
                message: "It drew, but the picture couldn't be put together."))
        }
        let image = NSImage(size: NSSize(width: sheet.width, height: sheet.height))
        image.addRepresentation(NSBitmapImageRep(cgImage: sheet))

        return .success(PreviewImage(
            image: image,
            frames: frames,
            columns: layout.columns,
            rows: layout.rows,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            paletteName: palette?.name ?? "none",
            source: source_,
            times: times))
    }

    // MARK: - Programs

    private static func cachedProgram(source: String, label: String) -> Result<GLuint, ShaderProblem> {
        if let cached = programCache[source] { return .success(cached) }

        let built = VibescapeCompiler.buildProgram(vs: Shaders.liquidVS, fs: source, label: label)
        guard built.ok else {
            return .failure(ShaderValidator.explain(built.log,
                                                    preludeLines: FunShaders.customPreludeLineCount))
        }
        programCache[source] = built.program
        programOrder.append(source)
        while programOrder.count > programCacheLimit {
            let oldest = programOrder.removeFirst()
            if let stale = programCache.removeValue(forKey: oldest) {
                glDeleteProgram(stale)
            }
        }
        return .success(built.program)
    }

    private static func buildGradeIfNeeded() -> Bool {
        if gradeProgram != 0 { return true }
        let built = VibescapeCompiler.buildProgram(vs: Shaders.gradeVS, fs: Shaders.gradeFS, label: "preview-grade")
        guard built.ok else { return false }
        gradeProgram = built.program
        return true
    }

    private static func buildQuadIfNeeded() -> Bool {
        if quadVAO != 0 { return true }
        let vertices: [GLfloat] = [-1, -1, 1, -1, -1, 1, 1, 1]
        var vbo: GLuint = 0
        glGenVertexArrays(1, &quadVAO)
        glBindVertexArray(quadVAO)
        glGenBuffers(1, &vbo)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        vertices.withUnsafeBytes { raw in
            glBufferData(GLenum(GL_ARRAY_BUFFER), raw.count, raw.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, nil)
        glBindVertexArray(0)
        return true
    }

    // MARK: - One frame

    private static func drawFrame(program: GLuint, values: UniformValues, palette: Palette?,
                                  width: Int, height: Int) -> CGImage? {
        guard ensureTarget(&sceneFBO, &sceneTex, &sceneSize, width, height) else { return nil }

        // Pass one: the vibescape itself, into the scene target.
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), sceneFBO)
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        glUseProgram(program)
        glDisable(GLenum(GL_BLEND))
        glDisable(GLenum(GL_DEPTH_TEST))
        values.bind(to: program, width: width, height: height, palette: palette)
        glBindVertexArray(quadVAO)
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        glBindVertexArray(0)

        // Pass two: the palette grade, so the picture matches what the app puts
        // on screen. A user's vibescape is graded like ribbons or silk, so
        // skipping this is how you end up picking cyan and getting teal.
        guard ensureTarget(&outFBO, &outTex, &outSize, width, height) else { return nil }
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), outFBO)
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        if let palette {
            glUseProgram(gradeProgram)
            glActiveTexture(GLenum(GL_TEXTURE0))
            glBindTexture(GLenum(GL_TEXTURE_2D), sceneTex)
            glUniform1i(location(gradeProgram, "uTex"), 0)
            glUniform3f(location(gradeProgram, "uShadow"),
                        palette.shadow.x, palette.shadow.y, palette.shadow.z)
            glUniform3f(location(gradeProgram, "uHighlight"),
                        palette.highlight.x, palette.highlight.y, palette.highlight.z)
            glUniform1f(location(gradeProgram, "uSaturation"), palette.saturation)
            glUniform1f(location(gradeProgram, "uDuotone"), palette.duotone)
            glUniform1f(location(gradeProgram, "uLift"), palette.lift)
            glBindVertexArray(quadVAO)
            glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
            glBindVertexArray(0)
        } else {
            // Ungraded: the scene target already is the answer. A blit needs
            // the read and draw targets named separately — binding only
            // GL_FRAMEBUFFER points both at the destination, which quietly
            // copies nothing and comes back black.
            glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), sceneFBO)
            glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), outFBO)
            glBlitFramebuffer(0, 0, GLsizei(width), GLsizei(height),
                              0, 0, GLsizei(width), GLsizei(height),
                              GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_NEAREST))
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        glReadPixels(0, 0, GLsizei(width), GLsizei(height),
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
        let error = glGetError()
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        guard error == GLenum(GL_NO_ERROR) else { return nil }

        return cgImage(from: pixels, width: width, height: height)
    }

    private static func ensureTarget(_ fbo: inout GLuint, _ tex: inout GLuint,
                                     _ size: inout (width: Int, height: Int),
                                     _ width: Int, _ height: Int) -> Bool {
        if fbo != 0 && size.width == width && size.height == height { return true }
        if fbo != 0 { glDeleteFramebuffers(1, &fbo) }
        if tex != 0 { glDeleteTextures(1, &tex) }
        fbo = 0
        glGenFramebuffers(1, &fbo)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glGenTextures(1, &tex)
        glBindTexture(GLenum(GL_TEXTURE_2D), tex)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GLint(GL_RGBA8),
                     GLsizei(width), GLsizei(height), 0,
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_LINEAR))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLint(GL_LINEAR))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLint(GL_CLAMP_TO_EDGE))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLint(GL_CLAMP_TO_EDGE))
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), tex, 0)
        let ok = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        size = (width, height)
        return ok
    }

    // MARK: - Laying out a strip

    /// Pixels between frames in a strip.
    private static let gap = 4

    /// Works out how many frames go across, and how far to shrink them.
    ///
    /// The obvious answer — as many across as fit — leaves dead space: eight
    /// frames at five across is a row of five and a row of three, with a black
    /// gap filling the rest of the second row and a few kilobytes of base64
    /// spent on nothing. So candidates are ranked: least wasted cells first,
    /// then widest. Eight frames wants four across, not five.
    private static func grid(for frames: Int, frameWidth: Int, frameHeight: Int,
                             maxExtent: Int) -> (columns: Int, rows: Int, scale: CGFloat) {
        guard frames > 1 else { return (1, 1, 1) }

        struct Candidate {
            let columns: Int
            let rows: Int
            let waste: Int
            let width: Int
            let height: Int
        }
        var candidates: [Candidate] = []
        for columns in 1...frames {
            let rows = Int((Double(frames) / Double(columns)).rounded(.up))
            candidates.append(Candidate(
                columns: columns,
                rows: rows,
                waste: columns * rows - frames,
                width: columns * frameWidth + (columns - 1) * gap,
                height: rows * frameHeight + (rows - 1) * gap))
        }

        // Prefer a grid that fits at full size. Only shrink if none will.
        let fitting = candidates.filter { $0.width <= maxExtent && $0.height <= maxExtent }
        let pool = fitting.isEmpty ? candidates : fitting
        let best = pool.min {
            if $0.waste != $1.waste { return $0.waste < $1.waste }
            return $0.width > $1.width
        } ?? candidates[0]

        var scale: CGFloat = 1
        if best.width > maxExtent || best.height > maxExtent {
            let byWidth = CGFloat(maxExtent) / CGFloat(best.width)
            let byHeight = CGFloat(maxExtent) / CGFloat(best.height)
            scale = max(0.1, min(byWidth, byHeight))
        }
        return (best.columns, best.rows, scale)
    }


    private static func scaled(_ images: [CGImage], to scale: CGFloat) -> [CGImage] {
        guard scale < 0.999, let first = images.first else { return images }
        let width = max(1, Int((CGFloat(first.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(first.height) * scale).rounded()))
        return images.map { redraw($0, width: width, height: height) }
    }

    /// Composites the frames into one image, in reading order.
    private static func compose(_ images: [CGImage], columns: Int, rows: Int,
                                frameWidth: Int, frameHeight: Int) -> CGImage? {
        guard images.first != nil else { return nil }
        let gap = Self.gap
        let totalWidth = columns * frameWidth + (columns - 1) * gap
        let totalHeight = rows * frameHeight + (rows - 1) * gap

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: totalWidth, height: totalHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return images[0]
        }
        // A dark backdrop so a dark frame doesn't read as a gap in the strip.
        ctx.setFillColor(red: 0.04, green: 0.02, blue: 0.06, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

        for (index, image) in images.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = column * (frameWidth + gap)
            // CoreGraphics counts from the bottom; index 0 is top-left to the
            // person looking at it.
            let y = totalHeight - (row + 1) * frameHeight - row * gap
            ctx.draw(image, in: CGRect(x: x, y: y, width: frameWidth, height: frameHeight))
        }
        return ctx.makeImage()
    }

    // MARK: - Pixels

    private static func cgImage(from pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        // OpenGL reads bottom-up; an image wants top-down.
        var flipped = [UInt8](repeating: 0, count: width * height * 4)
        let rowBytes = width * 4
        for y in 0..<height {
            let src = (height - 1 - y) * rowBytes
            let dst = y * rowBytes
            flipped[dst..<(dst + rowBytes)].withUnsafeMutableBytes { dst in
                pixels[src..<(src + rowBytes)].withUnsafeBytes { src in
                    dst.copyBytes(from: src)
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(flipped) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: rowBytes,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func redraw(_ image: CGImage, width: Int, height: Int) -> CGImage {
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    // MARK: - Palette

    private static func resolvePalette(_ requested: Palette?) -> Palette {
        if let requested { return requested }
        // Whatever the app is showing, so a preview and the screen agree.
        if let live = LiveUniforms.shared.paletteName ?? LiveUniforms.readFromDisk()?["palette"] as? String,
           let match = Palette.all.first(where: { $0.name.caseInsensitiveCompare(live) == .orderedSame }) {
            return match
        }
        return Palette.all[0]
    }
}

// MARK: - The uniform values a frame is drawn with

/// A resolved set of uniforms: the music, adjusted by whatever the caller asked
/// for.
private struct UniformValues {
    var time: Float = 0
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var level: Float = 0
    var levelSmooth: Float = 0
    var bassSmooth: Float = 0
    var beat: Float = 0
    var beatStrength: Float = 0
    var beats: Float = 0
    var active: Float = 1
    var idle: Float = 0
    var presence: Float = 1
    var scroll: Float = 0
    var clock: Float = 0
    var bands = [Float](repeating: 0, count: 96)
    /// Where the playhead is, and how long the track is. Zero when there is
    /// no position to know.
    var trackPos: Float = 0
    var trackDuration: Float = 0
    var trackProgress: Float = 0
    var trackKnown: Float = 0
    /// The pointer, in the shader's own coordinates.
    var mouseX: Float = 0
    var mouseY: Float = 0
    /// Whether a mouse button is down.
    var mouseDown: Float = 0
    /// Whether there is a pointer to react to.
    var mouseHere: Float = 0
    /// The last key pressed, as its character code.
    var key: Float = 0
    /// Whether a key is held.
    var keyDown: Float = 0
    /// The last MIDI note, 0..127.
    var midiNote: Float = 0
    /// How hard it was hit, 0..1.
    var midiVelocity: Float = 0
    /// How many notes are held.
    var midiNotes: Float = 0
    /// The last MIDI controller that moved.
    var midiCC: Float = 0
    /// Where that controller is, 0..1.
    var midiCCValue: Float = 0
    /// Whether these numbers came from the app or from a stand-in.
    var source = "stand-in values"

    /// The seconds each frame is drawn at.
    var beatsPerSecond: Float = 2

    func beatsAt(time: Double) -> Float {
        (Float(time) * beatsPerSecond).truncatingRemainder(dividingBy: 1024)
    }
    func clockAt(time: Double) -> Float {
        Float(time).truncatingRemainder(dividingBy: 3600)
    }
    func scrollAt(time: Double) -> Float {
        (Float(time) * 0.7).truncatingRemainder(dividingBy: 4096)
    }

    /// Reads the music if the app is running, otherwise stands in for it.
    ///
    /// The stand-in is deliberately busy — a vibescape previewed against silence
    /// looks broken even when it isn't, and the whole complaint is about not
    /// being able to see what you wrote.
    static func resolve(overrides: UniformOverrides) -> UniformValues {
        var v = UniformValues()
        if let live = (LiveUniforms.shared.snapshot ?? LiveUniforms.readFromDisk().map(LiveUniforms.Reading.init(fromDisk:))) {
            v.bass = live.bass
            v.mid = live.mid
            v.treble = live.treble
            v.level = live.level
            v.levelSmooth = live.levelSmooth
            v.bassSmooth = live.bassSmooth
            v.beat = live.beat
            v.beatStrength = live.beatStrength
            v.beats = live.beats
            v.active = live.active
            v.idle = live.idle
            v.presence = live.presence
            v.scroll = live.scroll
            v.clock = live.clock
            v.bands = live.bands
            v.beatsPerSecond = live.beatsPerSecond
            v.trackPos = live.trackPos
            v.trackDuration = live.trackDuration
            v.trackProgress = live.trackProgress
            v.trackKnown = live.trackKnown
            v.source = "the music playing now"
        } else {
            v.bass = 0.62
            v.mid = 0.44
            v.treble = 0.31
            v.level = 0.55
            v.levelSmooth = 0.50
            v.bassSmooth = 0.58
            v.beat = 0
            v.beatStrength = 0.55
            v.active = 1
            v.idle = 0
            v.presence = 0.9
            v.beatsPerSecond = 2
            v.bands = standInBands()
        }

        if let x = overrides.bass { v.bass = x }
        if let x = overrides.mid { v.mid = x }
        if let x = overrides.treble { v.treble = x }
        if let x = overrides.level { v.level = x }
        if let x = overrides.levelSmooth { v.levelSmooth = x }
        if let x = overrides.bassSmooth { v.bassSmooth = x }
        if let x = overrides.beat { v.beat = x }
        if let x = overrides.beatStrength { v.beatStrength = x }
        if let x = overrides.beats { v.beats = x }
        if let x = overrides.active { v.active = x }
        if let x = overrides.idle { v.idle = x }
        if let x = overrides.presence { v.presence = x }
        if let x = overrides.scroll { v.scroll = x }
        if let x = overrides.clock { v.clock = x }
        if let x = overrides.bands { v.bands = padded(x) }
        if let x = overrides.trackPos { v.trackPos = x }
        if let x = overrides.trackDuration { v.trackDuration = x }

        // The input. The app knows where the pointer is and what the person
        // is playing, so a preview in the app shows the real thing; a
        // preview from a server with no window shows the neutral values,
        // which are the same ones a shared page and an exported video get.
        let input = InputState.shared.snapshot()
        v.mouseX = Float(input.mouse.x)
        v.mouseY = Float(input.mouse.y)
        v.mouseDown = input.mouseDown ? 1 : 0
        v.mouseHere = input.mouseHere
        v.key = input.key
        v.keyDown = input.keyDown ? 1 : 0
        v.midiNote = input.midiNote
        v.midiVelocity = input.midiVelocity
        v.midiNotes = input.midiNotes
        v.midiCC = input.midiCC
        v.midiCCValue = input.midiCCValue

        if let x = overrides.mouse, x.count >= 2 {
            v.mouseX = x[0]
            v.mouseY = x[1]
        }
        if let x = overrides.mouseDown { v.mouseDown = x }
        if let x = overrides.mouseHere { v.mouseHere = x }
        // A pointer set by hand is a pointer there is: without this, an
        // agent asking for a pointer at the left of the screen would get a
        // vibescape that ignores it.
        if overrides.mouseHere == nil, overrides.mouse != nil { v.mouseHere = 1 }
        if let x = overrides.key { v.key = x }
        if let x = overrides.keyDown { v.keyDown = x }
        if let x = overrides.midiNote { v.midiNote = x }
        if let x = overrides.midiVelocity { v.midiVelocity = x }
        if let x = overrides.midiNotes { v.midiNotes = x }
        if let x = overrides.midiCC { v.midiCC = x }
        if let x = overrides.midiCCValue { v.midiCCValue = x }
        // The progress and the "is it real" flag follow the two, so an
        // override of one is enough.
        if overrides.trackPos != nil || overrides.trackDuration != nil {
            let progress = v.trackDuration > 0 ? v.trackPos / v.trackDuration : 0
            v.trackProgress = min(1, max(0, progress))
            v.trackKnown = (overrides.trackPos != nil || overrides.trackDuration != nil) ? 1 : 0
        }

        // uActive is forced on unless the caller says otherwise, and this is
        // not a convenience: it is the difference between a usable preview and
        // a black rectangle. Every vibescape multiplies by uActive at the end,
        // and uActive is 0 whenever the music isn't playing — which is most of
        // the time, and always true when the app is running but waiting on a
        // permission, or the room is quiet, or nothing is playing. Previewing
        // against silence would mean every shader looks broken in exactly the
        // situation where you're trying to write one.
        //
        // The same reasoning applies to presence and idle, which describe
        // whether there's music at all. A preview is a picture of a vibescape
        // working, not of the room it happens to be in. Pass uActive: 0 to see
        // what it looks like when it isn't.
        if overrides.active == nil { v.active = 1 }
        if overrides.idle == nil { v.idle = 0 }
        if overrides.presence == nil { v.presence = 1 }
        return v
    }

    private static func padded(_ input: [Float]) -> [Float] {
        var bands = input
        if bands.count < 96 {
            // Repeat the top of what's given rather than trailing off to zero,
            // so a 12-value band curve still looks like a spectrum.
            let pattern = bands
            while bands.count < 96, !pattern.isEmpty {
                bands.append(contentsOf: pattern.prefix(96 - bands.count))
            }
        }
        if bands.count > 96 { bands = Array(bands.prefix(96)) }
        return bands
    }

    /// A spectrum shaped the way music usually is: loud low down, falling away
    /// to the top, with a little movement so band-driven shaders have something
    /// to react to.
    private static func standInBands() -> [Float] {
        (0..<96).map { index in
            let x = Float(index) / 95
            let shape = exp(-x * 2.2) * 0.85 + 0.04
            let wobble = sin(Float(index) * 1.7) * 0.03 + sin(Float(index) * 0.4) * 0.05
            return max(0, min(1, shape + wobble))
        }
    }

    /// Feeds the shader. Uniforms the shader doesn't use come back as -1, and
    /// `glUniform` ignores those, so there's no need to check each one.
    fileprivate func bind(to program: GLuint, width: Int, height: Int, palette: Palette?) {
        func loc(_ name: String) -> GLint { VibescapeRender.location(program, name) }

        glUniform1f(loc("uTime"), time)
        glUniform1f(loc("uBass"), bass)
        glUniform1f(loc("uMid"), mid)
        glUniform1f(loc("uTreble"), treble)
        glUniform1f(loc("uBeat"), beat)
        glUniform1f(loc("uBeatStrength"), beatStrength)
        glUniform1f(loc("uLevel"), level)
        glUniform2f(loc("uResolution"), GLfloat(width), GLfloat(height))
        glUniform1f(loc("uIdle"), idle)
        glUniform1f(loc("uActive"), active)
        glUniform1f(loc("uBeats"), beats)
        glUniform1f(loc("uScroll"), scroll)
        glUniform1f(loc("uClock"), clock)
        glUniform1f(loc("uLevelSmooth"), levelSmooth)
        glUniform1f(loc("uBassSmooth"), bassSmooth)
        glUniform1f(loc("uPresence"), presence)
        glUniform1f(loc("uTrackPos"), trackPos)
        glUniform1f(loc("uTrackDuration"), trackDuration)
        glUniform1f(loc("uTrackProgress"), trackProgress)
        glUniform1f(loc("uTrackKnown"), trackKnown)
        glUniform2f(loc("uMouse"), mouseX, mouseY)
        glUniform1f(loc("uMouseDown"), mouseDown)
        glUniform1f(loc("uMouseHere"), mouseHere)
        glUniform1f(loc("uKey"), key)
        glUniform1f(loc("uKeyDown"), keyDown)
        glUniform1f(loc("uMidiNote"), midiNote)
        glUniform1f(loc("uMidiVelocity"), midiVelocity)
        glUniform1f(loc("uMidiNotes"), midiNotes)
        glUniform1f(loc("uMidiCC"), midiCC)
        glUniform1f(loc("uMidiCCValue"), midiCCValue)
        if !bands.isEmpty {
            glUniform1fv(loc("uBands[0]"), GLsizei(bands.count), bands)
        }
        if let palette {
            let mid = (palette.shadow + palette.highlight) * 0.5
            var colours: [GLfloat] = [palette.shadow.x, palette.shadow.y, palette.shadow.z,
                                     palette.highlight.x, palette.highlight.y, palette.highlight.z,
                                     mid.x, mid.y, mid.z]
            colours.withUnsafeBufferPointer { ptr in
                glUniform3fv(loc("uPalette[0]"), 3, ptr.baseAddress)
            }
        }
    }
}
