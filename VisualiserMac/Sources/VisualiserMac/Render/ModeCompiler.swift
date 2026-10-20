import Foundation
import OpenGL.GL3
import AppKit

/// Compiles a user's mode and draws a picture of it, outside the app.
///
/// The app compiles a mode when the user picks one; the MCP server compiles
/// one when an agent asks whether theirs works. Both need the same thing —
/// a real GLSL compiler, with the driver's own error text — so it lives
/// here rather than in either of them.
///
/// It runs against whatever OpenGL context is current, which is why the
/// caller makes one first. Nothing here touches the app's state: it reads a
/// shader, and writes a picture.
enum ModeCompiler {

    /// The result of trying to compile a mode.
    enum Outcome {
        case compiled
        /// It didn't compile, and this says why in words.
        case failed(ShaderProblem)
    }

    /// The context used for compiling, made once and kept.
    ///
    /// A GL call with no current context doesn't return an error — it
    /// crashes. So this is checked before every compile, and the context is
    /// made current each time because "current" is a per-thread thing.
    private static var context: NSOpenGLContext?

    private static func ensureContext() -> Bool {
        if let c = context {
            c.makeCurrentContext()
            return true
        }
        guard let c = makeContext() else { return false }
        context = c
        return true
    }

    /// Compiles a mode body and says what happened.
    ///
    /// The cheap shape checks come first — a mode that writes `main()` or
    /// leaves a `#version` line in is never going to compile, and saying so
    /// plainly is more use than the driver's complaint about it.
    static func compile(body: String) -> Outcome {
        switch ShaderValidator.checkShape(body) {
        case .failed(let problem):
            return .failed(problem)
        case .ok:
            break
        }

        guard ensureContext() else {
            return .failed(ShaderProblem(
                kind: .compileFailed,
                message: "This Mac wouldn't give the graphics system a context, so the mode couldn't be checked."))
        }

        let source = FunShaders.customSource(body: body)
        let built = buildProgram(vs: Shaders.liquidVS, fs: source, label: "custom")
        guard built.ok else {
            return .failed(ShaderValidator.explain(built.log,
                                                   preludeLines: FunShaders.customPreludeLineCount))
        }
        glDeleteProgram(built.program)
        return .compiled
    }

    /// Compiles a mode and draws a still of it, for the agent to look at.
    ///
    /// Returns the picture, or the reason it couldn't be drawn.
    static func preview(body: String, width: Int, height: Int) -> Result<NSImage, ShaderProblem> {
        switch ShaderValidator.checkShape(body) {
        case .failed(let problem):
            return .failure(problem)
        case .ok:
            break
        }

        guard ensureContext() else {
            return .failure(ShaderProblem(
                kind: .compileFailed,
                message: "This Mac wouldn't give the graphics system a context, so the mode couldn't be drawn."))
        }

        let source = FunShaders.customSource(body: body)
        let built = buildProgram(vs: Shaders.liquidVS, fs: source, label: "custom-preview")
        guard built.ok else {
            return .failure(ShaderValidator.explain(built.log,
                                                   preludeLines: FunShaders.customPreludeLineCount))
        }
        defer { glDeleteProgram(built.program) }

        guard let image = draw(built.program, width: width, height: height) else {
            return .failure(ShaderProblem(
                kind: .compileFailed,
                message: "It compiled, but it couldn't be drawn. Try making it simpler."))
        }
        return .success(image)
    }

    // MARK: - The OpenGL part

    /// A context for compiling and drawing when there isn't a window.
    ///
    /// The app's own renderer shares state with the window's context; this
    /// one stands alone, because the MCP server has no window to share with.
    static func makeContext() -> NSOpenGLContext? {
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFADepthSize), 0,
            0,
        ]
        guard let format = NSOpenGLPixelFormat(attributes: attrs) else { return nil }
        let ctx = NSOpenGLContext(format: format, share: nil)
        ctx?.makeCurrentContext()
        return ctx
    }

    /// Compiles a shader pair and reports what went wrong, rather than
    /// logging it and handing back a program that doesn't work.
    static func buildProgram(vs: String, fs: String, label: String) -> (program: GLuint, ok: Bool, log: String) {
        let v = compileShader(type: GLenum(GL_VERTEX_SHADER), source: vs, "\(label).vs")
        let f = compileShader(type: GLenum(GL_FRAGMENT_SHADER), source: fs, "\(label).fs")
        guard v.ok, f.ok else {
            return (0, false, v.log + f.log)
        }
        let p = glCreateProgram()
        glAttachShader(p, v.shader)
        glAttachShader(p, f.shader)
        glLinkProgram(p)
        var status: GLint = 0
        glGetProgramiv(p, GLenum(GL_LINK_STATUS), &status)
        if status == 0 {
            var logLen: GLint = 0
            glGetProgramiv(p, GLenum(GL_INFO_LOG_LENGTH), &logLen)
            var log = [GLchar](repeating: 0, count: Int(max(logLen, 1)))
            glGetProgramInfoLog(p, logLen, nil, &log)
            let text = String(cString: log)
            NSLog("Link error (\(label)): \(text)")
            return (0, false, text)
        }
        glDeleteShader(v.shader)
        glDeleteShader(f.shader)
        return (p, true, "")
    }

    private static func compileShader(type: GLenum, source: String, _ label: String) -> (shader: GLuint, ok: Bool, log: String) {
        let s = glCreateShader(type)
        var src = (source as NSString).utf8String
        var srcs: [UnsafePointer<GLchar>?] = [src]
        glShaderSource(s, 1, &srcs, nil)
        glCompileShader(s)
        var status: GLint = 0
        glGetShaderiv(s, GLenum(GL_COMPILE_STATUS), &status)
        if status == 0 {
            var logLen: GLint = 0
            glGetShaderiv(s, GLenum(GL_INFO_LOG_LENGTH), &logLen)
            var log = [GLchar](repeating: 0, count: Int(max(logLen, 1)))
            glGetShaderInfoLog(s, logLen, nil, &log)
            let text = String(cString: log)
            NSLog("Compile error (\(label)): \(text)")
            return (s, false, text)
        }
        return (s, true, "")
    }

    /// Draws a full-screen quad with the program and reads it back.
    private static func draw(_ program: GLuint, width: Int, height: Int) -> NSImage? {
        // A triangle strip covering the screen, in clip space.
        let vertices: [GLfloat] = [-1, -1, 1, -1, -1, 1, 1, 1]
        var vao: GLuint = 0
        glGenVertexArrays(1, &vao)
        glBindVertexArray(vao)
        var vbo: GLuint = 0
        glGenBuffers(1, &vbo)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        vertices.withUnsafeBytes { raw in
            glBufferData(GLenum(GL_ARRAY_BUFFER), raw.count, raw.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, nil)

        var fbo: GLuint = 0
        var tex: GLuint = 0
        glGenFramebuffers(1, &fbo)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glGenTextures(1, &tex)
        glBindTexture(GLenum(GL_TEXTURE_2D), tex)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GLint(GL_RGBA8),
                     GLsizei(width), GLsizei(height), 0,
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), tex, 0)
        guard glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE) else {
            return nil
        }

        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glClearColor(0.02, 0.004, 0.03, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        glUseProgram(program)
        glDisable(GLenum(GL_BLEND))
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        glReadPixels(0, 0, GLsizei(width), GLsizei(height),
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
        let glError = glGetError()

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glDeleteFramebuffers(1, &fbo)
        glDeleteTextures(1, &tex)
        glDeleteBuffers(1, &vbo)
        glDeleteVertexArrays(1, &vao)

        guard glError == GLenum(GL_NO_ERROR) else { return nil }

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
        guard let provider = CGDataProvider(data: Data(flipped) as CFData),
              let cg = CGImage(width: width, height: height,
                               bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: rowBytes,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(NSBitmapImageRep(cgImage: cg))
        return image
    }
}
