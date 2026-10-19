import Foundation
import AppKit
import simd
import OpenGL.GL3

/// GL resources and draw logic for MACHINE mode.
///
/// Four smooth meshes (cannon, drum, pad, ball), each drawn instanced with a
/// per-instance model matrix and colour. The machine renders into its own
/// 4x multisampled buffer with a depth buffer — the shared scene target has
/// neither, and without depth testing the 3D shapes draw through each other —
/// then resolves into whatever framebuffer the caller had bound.
final class MachineRenderer {
    private var program: GLuint = 0
    private var uViewProj: GLint = -1
    private var uCameraPos: GLint = -1

    private struct Batch {
        var vao: GLuint = 0
        var vbo: GLuint = 0
        var ebo: GLuint = 0
        var inst: GLuint = 0
        var indexCount: GLsizei = 0
        var capacity = 0
        var count = 0
    }
    private var cannons = Batch()
    private var drums = Batch()
    private var pads = Batch()
    private var balls = Batch()

    /// Animation state shared with the audio analysis.
    var mode = MachineMode()

    private static let floatsPerInstance = 20   // mat4 + vec4 colour
    private let maxBalls = 256

    /// Multisampled render targets, one per GL context (the snapshot path
    /// renders from a second context, and framebuffers aren't shared).
    private struct Target { var fbo: GLuint = 0; var color: GLuint = 0; var depth: GLuint = 0; var w = 0; var h = 0 }
    private var targets: [ObjectIdentifier: Target] = [:]

    // MARK: - Setup

    func buildProgram() {
        program = makeGLProgram(vs: Shaders.machineVS, fs: Shaders.machineFS, "machine")
        uViewProj = glGetUniformLocation(program, "uViewProj")
        uCameraPos = glGetUniformLocation(program, "uCameraPos")

        // The original's cannon profile (Machine1.js / Machine2.js), turned
        // on a lathe about Z exactly as THREE.LatheGeometry does.
        let profile: [SIMD2<Float>] = [
            SIMD2(6, 0), SIMD2(6, 1), SIMD2(5, 3), SIMD2(9, 31),
            SIMD2(10, 32), SIMD2(10, 33), SIMD2(8, 33), SIMD2(4, 0),
        ]
        let cannonInstances = Self.cannonMatrices()
        cannons = makeBatch(MachineMesh.lathe(profile, segments: 48), capacity: cannonInstances.count)
        upload(cannonInstances.map { ($0, MachineMode.machineColor, 0) }, into: &cannons)

        drums = makeBatch(MachineMesh.cylinder(top: 4, bottom: 5, height: 1, segments: 48),
                          capacity: MachineMode.stations * MachineMode.volumes)
        pads = makeBatch(MachineMesh.box(width: 15, height: 1, depth: 3), capacity: MachineMode.ringCount)
        balls = makeBatch(MachineMesh.sphere(radius: 1.5, segments: 32, rings: 20), capacity: maxBalls)
    }

    private func makeBatch(_ mesh: MachineMesh, capacity: Int) -> Batch {
        var b = Batch()
        b.capacity = capacity
        glGenVertexArrays(1, &b.vao)
        glBindVertexArray(b.vao)

        var verts: [Float] = []
        verts.reserveCapacity(mesh.positions.count * 6)
        for i in mesh.positions.indices {
            let p = mesh.positions[i], n = mesh.normals[i]
            verts += [p.x, p.y, p.z, n.x, n.y, n.z]
        }
        glGenBuffers(1, &b.vbo)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), b.vbo)
        verts.withUnsafeBufferPointer {
            glBufferData(GLenum(GL_ARRAY_BUFFER), $0.count * 4, $0.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        let stride = GLsizei(6 * 4)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride, nil)
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride, UnsafeRawPointer(bitPattern: 12))

        glGenBuffers(1, &b.ebo)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), b.ebo)
        mesh.indices.withUnsafeBufferPointer {
            glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), $0.count * 4, $0.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        b.indexCount = GLsizei(mesh.indices.count)

        // Per instance: model matrix as four vec4 columns, then colour + flash.
        glGenBuffers(1, &b.inst)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), b.inst)
        glBufferData(GLenum(GL_ARRAY_BUFFER), capacity * Self.floatsPerInstance * 4, nil, GLenum(GL_DYNAMIC_DRAW))
        let iStride = GLsizei(Self.floatsPerInstance * 4)
        for k in 0..<5 {
            let loc = GLuint(3 + k)
            glEnableVertexAttribArray(loc)
            glVertexAttribPointer(loc, 4, GLenum(GL_FLOAT), GLboolean(GL_FALSE), iStride,
                                  UnsafeRawPointer(bitPattern: k * 16))
            glVertexAttribDivisor(loc, 1)
        }
        glBindVertexArray(0)
        return b
    }

    private func upload(_ items: [(simd_float4x4, SIMD3<Float>, Float)], into b: inout Batch) {
        let n = min(items.count, b.capacity)
        b.count = n
        guard n > 0 else { return }
        var data = [Float]()
        data.reserveCapacity(n * Self.floatsPerInstance)
        for (m, c, flash) in items.prefix(n) {
            for col in [m.columns.0, m.columns.1, m.columns.2, m.columns.3] { data += [col.x, col.y, col.z, col.w] }
            data += [c.x, c.y, c.z, flash]
        }
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), b.inst)
        data.withUnsafeBufferPointer {
            glBufferSubData(GLenum(GL_ARRAY_BUFFER), 0, $0.count * 4, $0.baseAddress)
        }
    }

    // MARK: - Scene layout (the original's transforms)

    private static let machine1 = Mat.translate(MachineMode.machine1Origin)
    private static func ringGroup(_ i: Int) -> simd_float4x4 {
        Mat.rotateY(Float(i) / Float(MachineMode.ringCount) * 2 * .pi)
    }
    /// THREE's default Euler order: R = Rx · Ry · Rz.
    private static func euler(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        Mat.rotateX(x) * Mat.rotateY(y) * Mat.rotateZ(z)
    }
    private static let deg: Float = .pi / 180

    private static func cannonMatrices() -> [simd_float4x4] {
        var out: [simd_float4x4] = []
        for i in 0..<MachineMode.stations {
            let z = Float(i) * 10
            out.append(machine1 * Mat.translate(SIMD3(0, 50, z)) * euler(90 * deg, 127 * deg, 0) * Mat.scale(0.5))
            out.append(machine1 * Mat.translate(SIMD3(17, 0, z)) * euler(90 * deg, 145 * deg, 0) * Mat.scale(0.5))
        }
        out.append(Mat.translate(SIMD3(0, 20, 0)) * euler(90 * deg, .pi, 0) * Mat.scale(0.75))
        out.append(Mat.translate(SIMD3(0, 15, 0)) * euler(90 * deg, .pi, 0) * Mat.scale(0.75))
        for i in 0..<MachineMode.ringCount {
            out.append(ringGroup(i) * Mat.translate(SIMD3(75, 0, 0)) * euler(90 * deg, .pi, 0) * Mat.scale(0.5))
        }
        return out
    }

    // MARK: - Per-frame update

    /// Advance the notes and upload the moving parts. `now` is the note clock
    /// (wall-clock live; synthetic for snapshots).
    func update(bands: [Float], rms: Float, now: CFTimeInterval) {
        mode.update(bands: bands, rms: rms, now: now)
        let color = MachineMode.machineColor

        // Drums recoil along (1.5, -1.5, 0) and flash white (HitEffect).
        var drumItems: [(simd_float4x4, SIMD3<Float>, Float)] = []
        for i in 0..<MachineMode.stations {
            for v in 0..<MachineMode.volumes {
                let h = MachineMode.hitAmount(since: mode.drumHitAt[i * MachineMode.volumes + v], now: now)
                let p = MachineMode.drumPos[v]
                let m = Self.machine1 * Mat.translate(SIMD3(p.x + 1.5 * h, p.y - 1.5 * h, Float(i) * 10))
                    * Mat.rotateZ(45 * Self.deg) * Mat.scale(MachineMode.drumScale[v])
                drumItems.append((m, color, h * 0.5))
            }
        }
        upload(drumItems, into: &drums)

        // Pads sit at x = 40, y = 25 in their ring group, widening around the
        // ring, and dip by 1.5 when struck.
        var padItems: [(simd_float4x4, SIMD3<Float>, Float)] = []
        for i in 0..<MachineMode.ringCount {
            let h = MachineMode.hitAmount(since: mode.padHitAt[i], now: now)
            let m = Self.ringGroup(i) * Mat.translate(SIMD3(40, 25 - 1.5 * h, 0))
                * Mat.scale(SIMD3(Float(i) / Float(MachineMode.ringCount) + 1, 1, 1))
            padItems.append((m, color, h * 0.5))
        }
        upload(padItems, into: &pads)

        // Balls: one in Machine 1 and one in Machine 2 per note.
        var ballItems: [(simd_float4x4, SIMD3<Float>, Float)] = []
        for note in mode.notes {
            let age = now - note.born
            if let p = MachineMode.corridorBall(age: age, volume: note.volume) {
                ballItems.append((Self.machine1 * Mat.translate(SIMD3(p.x, p.y, Float(note.pitch) * 10)),
                                  MachineMode.ballColor, 0))
            }
            if let p = MachineMode.ringBall(age: age) {
                ballItems.append((Self.ringGroup(note.ringIndex) * Mat.translate(SIMD3(p.x, p.y, 0)),
                                  MachineMode.ballColor, 0))
            }
        }
        upload(ballItems, into: &balls)
    }

    // MARK: - Draw

    /// Draws the machine and resolves it into the framebuffer that was bound.
    func render(viewProj: [GLfloat], cameraPos: SIMD3<Float>, width: Int, height: Int) {
        guard program != 0, width > 0, height > 0 else { return }
        var previous: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &previous)
        let target = ensureTarget(width: width, height: height)

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), target.fbo)
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT) | GLbitfield(GL_DEPTH_BUFFER_BIT))
        glEnable(GLenum(GL_DEPTH_TEST))
        glDisable(GLenum(GL_BLEND))

        glUseProgram(program)
        glUniformMatrix4fv(uViewProj, 1, GLboolean(GL_FALSE), viewProj)
        glUniform3f(uCameraPos, cameraPos.x, cameraPos.y, cameraPos.z)
        for b in [cannons, drums, pads, balls] where b.count > 0 {
            glBindVertexArray(b.vao)
            glDrawElementsInstanced(GLenum(GL_TRIANGLES), b.indexCount, GLenum(GL_UNSIGNED_INT), nil, GLsizei(b.count))
        }
        glBindVertexArray(0)
        glDisable(GLenum(GL_DEPTH_TEST))

        // Resolve the multisampled image into the caller's framebuffer.
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), target.fbo)
        glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), GLuint(previous))
        glBlitFramebuffer(0, 0, GLint(width), GLint(height), 0, 0, GLint(width), GLint(height),
                          GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_NEAREST))
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(previous))
    }

    private func ensureTarget(width: Int, height: Int) -> Target {
        let key = ObjectIdentifier(NSOpenGLContext.current ?? NSOpenGLContext())
        var t = targets[key] ?? Target()
        if t.fbo != 0 && t.w == width && t.h == height { return t }
        if t.fbo == 0 {
            glGenFramebuffers(1, &t.fbo)
            glGenRenderbuffers(1, &t.color)
            glGenRenderbuffers(1, &t.depth)
        }
        var maxSamples: GLint = 4
        glGetIntegerv(GLenum(GL_MAX_SAMPLES), &maxSamples)
        let samples = min(4, max(1, maxSamples))
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), t.color)
        glRenderbufferStorageMultisample(GLenum(GL_RENDERBUFFER), samples, GLenum(GL_RGBA8), GLsizei(width), GLsizei(height))
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), t.depth)
        glRenderbufferStorageMultisample(GLenum(GL_RENDERBUFFER), samples, GLenum(GL_DEPTH_COMPONENT24), GLsizei(width), GLsizei(height))
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), t.fbo)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), t.color)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT), GLenum(GL_RENDERBUFFER), t.depth)
        if glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) != GL_FRAMEBUFFER_COMPLETE {
            NSLog("[MACHINE] multisample framebuffer incomplete")
        }
        t.w = width
        t.h = height
        targets[key] = t
        return t
    }
}

// MARK: - Matrices

enum Mat {
    static func translate(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t.x, t.y, t.z, 1)
        return m
    }
    static func scale(_ s: Float) -> simd_float4x4 { scale(SIMD3(s, s, s)) }
    static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(s.x, s.y, s.z, 1))
    }
    static func rotateX(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0), SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
    }
    static func rotateY(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(columns: (SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
    }
    static func rotateZ(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    }
}

/// Builds a view-projection matrix (column-major, GL convention) for a camera
/// at `eye` looking at `target`.
func makeViewProj(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>,
                  aspect: Float, fovY: Float, near: Float, far: Float) -> [GLfloat] {
    let f = simd_normalize(target - eye)
    let s = simd_normalize(simd_cross(f, up))
    let u = simd_cross(s, f)

    var v = [GLfloat](repeating: 0, count: 16)
    v[0] = s.x;  v[1] = u.x;  v[2] = -f.x; v[3] = 0
    v[4] = s.y;  v[5] = u.y;  v[6] = -f.y; v[7] = 0
    v[8] = s.z;  v[9] = u.z;  v[10] = -f.z; v[11] = 0
    v[12] = -simd_dot(s, eye)
    v[13] = -simd_dot(u, eye)
    v[14] =  simd_dot(f, eye)
    v[15] = 1

    let p = perspective(fovY: fovY, aspect: aspect, near: near, far: far)
    var m = [GLfloat](repeating: 0, count: 16)
    for col in 0..<4 {
        for row in 0..<4 {
            var sum: GLfloat = 0
            for k in 0..<4 { sum += p[k * 4 + row] * v[col * 4 + k] }
            m[col * 4 + row] = sum
        }
    }
    return m
}

// MARK: - Shaders

extension Shaders {
    static let machineVS = """
    #version 330 core
    layout(location = 0) in vec3 aPos;
    layout(location = 1) in vec3 aNormal;
    layout(location = 3) in vec4 iM0;
    layout(location = 4) in vec4 iM1;
    layout(location = 5) in vec4 iM2;
    layout(location = 6) in vec4 iM3;
    layout(location = 7) in vec4 iColor;   // rgb, flash

    uniform mat4 uViewProj;

    out vec3 vNormal;
    out vec3 vWorld;
    out vec4 vColor;

    void main() {
        mat4 m = mat4(iM0, iM1, iM2, iM3);
        vec4 world = m * vec4(aPos, 1.0);
        vWorld = world.xyz;
        vNormal = transpose(inverse(mat3(m))) * aNormal;
        vColor = iColor;
        gl_Position = uViewProj * world;
    }
    """

    /// Lit like the original's MeshPhongMaterial: a strong white spotlight
    /// from overhead, a directional light from below, faint ambient, a small
    /// specular, and a 25% mix toward a reflected environment.
    static let machineFS = """
    #version 330 core
    in vec3 vNormal;
    in vec3 vWorld;
    in vec4 vColor;

    uniform vec3 uCameraPos;
    out vec4 fragColor;

    vec3 environment(vec3 r) {
        // Soft studio: bright overhead, grey horizon, dark floor.
        float y = r.y;
        vec3 sky = mix(vec3(0.55, 0.55, 0.58), vec3(1.0, 0.97, 0.92), smoothstep(0.0, 0.8, y));
        vec3 ground = mix(vec3(0.45, 0.43, 0.42), vec3(0.08, 0.07, 0.07), smoothstep(0.0, -0.6, y));
        return y >= 0.0 ? sky : ground;
    }

    void main() {
        vec3 n = normalize(vNormal);
        vec3 v = normalize(uCameraPos - vWorld);
        if (dot(n, v) < 0.0) n = -n;          // inside of the cannon bores

        vec3 base = clamp(vColor.rgb + vColor.a, 0.0, 1.0);   // HitEffect flash toward white
        vec3 toSpot = normalize(vec3(0.0, 300.0, 0.0) - vWorld);
        vec3 toFill = vec3(0.0, -1.0, 0.0);

        float diff = 2.0 * max(dot(n, toSpot), 0.0) + 1.0 * max(dot(n, toFill), 0.0);
        vec3 col = base * (0.06 + diff * 0.55);
        vec3 h = normalize(toSpot + v);
        col += vec3(0.25) * pow(max(dot(n, h), 0.0), 30.0);
        col = mix(col, environment(reflect(-v, n)) * base, 0.25);

        fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
    }
    """
}

// MARK: - Meshes

/// Positions + normals + triangle indices.
struct MachineMesh {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    /// Average face normals into shared vertices (smooth shading).
    mutating func smoothNormals() {
        normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            let fn = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            normals[a] += fn; normals[b] += fn; normals[c] += fn
        }
        normals = normals.map { simd_length($0) > 0 ? simd_normalize($0) : SIMD3(0, 1, 0) }
    }

    /// THREE.LatheGeometry: profile points (radius, z) revolved about Z.
    /// The seam shares vertices so the shading has no line.
    static func lathe(_ profile: [SIMD2<Float>], segments: Int) -> MachineMesh {
        var m = MachineMesh()
        for s in 0..<segments {
            let a = Float(s) / Float(segments) * 2 * .pi
            for p in profile { m.positions.append(SIMD3(p.x * cos(a), p.x * sin(a), p.y)) }
        }
        let n = profile.count
        for s in 0..<segments {
            let s2 = (s + 1) % segments
            for j in 0..<(n - 1) {
                let a = UInt32(s * n + j), b = UInt32(s2 * n + j)
                let c = UInt32(s2 * n + j + 1), d = UInt32(s * n + j + 1)
                m.indices += [a, b, d, b, c, d]
            }
        }
        m.smoothNormals()
        return m
    }

    /// THREE.CylinderGeometry about Y: smooth sides, flat capped ends.
    static func cylinder(top: Float, bottom: Float, height: Float, segments: Int) -> MachineMesh {
        var m = MachineMesh()
        let hy = height / 2
        let slope = (bottom - top) / height
        for s in 0..<segments {
            let a = Float(s) / Float(segments) * 2 * .pi
            let c = cos(a), sn = sin(a)
            let n = simd_normalize(SIMD3(c, slope, sn))
            m.positions += [SIMD3(c * top, hy, sn * top), SIMD3(c * bottom, -hy, sn * bottom)]
            m.normals += [n, n]
        }
        for s in 0..<segments {
            let a = UInt32(s * 2), b = UInt32(s * 2 + 1)
            let c = UInt32(((s + 1) % segments) * 2), d = UInt32(((s + 1) % segments) * 2 + 1)
            m.indices += [a, c, b, b, c, d]
        }
        for (y, r, up) in [(hy, top, Float(1)), (-hy, bottom, Float(-1))] {
            let centre = UInt32(m.positions.count)
            m.positions.append(SIMD3(0, y, 0)); m.normals.append(SIMD3(0, up, 0))
            let ring = UInt32(m.positions.count)
            for s in 0..<segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                m.positions.append(SIMD3(cos(a) * r, y, sin(a) * r)); m.normals.append(SIMD3(0, up, 0))
            }
            for s in 0..<segments {
                let i = ring + UInt32(s), j = ring + UInt32((s + 1) % segments)
                m.indices += up > 0 ? [centre, j, i] : [centre, i, j]
            }
        }
        return m
    }

    /// Axis-aligned box centred on the origin, flat-shaded faces.
    static func box(width: Float, height: Float, depth: Float) -> MachineMesh {
        var m = MachineMesh()
        let h = SIMD3(width / 2, height / 2, depth / 2)
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [   // normal, u, v
            (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0)), (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1)), (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)), (SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, 1, 0)),
        ]
        for (n, u, v) in faces {
            let base = UInt32(m.positions.count)
            for (su, sv) in [(Float(-1), Float(-1)), (1, -1), (1, 1), (-1, 1)] {
                m.positions.append((n + u * su + v * sv) * h)
                m.normals.append(n)
            }
            m.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return m
    }

    /// UV sphere with smooth normals.
    static func sphere(radius: Float, segments: Int, rings: Int) -> MachineMesh {
        var m = MachineMesh()
        for r in 0...rings {
            let phi = Float(r) / Float(rings) * .pi
            for s in 0...segments {
                let theta = Float(s) / Float(segments) * 2 * .pi
                let n = SIMD3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                m.positions.append(n * radius)
                m.normals.append(n)
            }
        }
        let w = UInt32(segments + 1)
        for r in 0..<UInt32(rings) {
            for s in 0..<UInt32(segments) {
                let a = r * w + s, b = a + w
                m.indices += [a, a + 1, b, b, a + 1, b + 1]
            }
        }
        return m
    }
}
