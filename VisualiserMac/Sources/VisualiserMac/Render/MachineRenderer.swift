import Foundation
import simd
import OpenGL.GL3

/// GL resources and draw logic for MACHINE mode.
///
/// Three instanced draws share one program: the corridor drums, the ring
/// pads, and the bouncing balls. Per-instance data is uploaded each frame
/// because the drums recoil, flash, and the balls move.
final class MachineRenderer {
    private var program: GLuint = 0
    private var uViewProj: GLint = -1
    private var uCameraPos: GLint = -1
    private var uTime: GLint = -1

    private var drumVAO: GLuint = 0
    private var drumVBO: GLuint = 0     // base mesh
    private var drumEBO: GLuint = 0
    private var drumInst: GLuint = 0
    private var drumIndexCount: GLsizei = 0

    private var padVAO: GLuint = 0
    private var padVBO: GLuint = 0
    private var padEBO: GLuint = 0
    private var padInst: GLuint = 0
    private var padIndexCount: GLsizei = 0

    private var ballVAO: GLuint = 0
    private var ballVBO: GLuint = 0
    private var ballEBO: GLuint = 0
    private var ballInst: GLuint = 0
    private var ballIndexCount: GLsizei = 0

    /// Animation state shared with the audio analysis.
    var mode = MachineMode()

    /// Scratch buffers reused every frame.
    private var drumData: [Float] = []
    private var padData: [Float] = []
    private var ballData: [Float] = []

    private let maxBalls = 64

    init() {
        drumData = [Float](repeating: 0, count: MachineMode.stations * MachineMode.volumes * 12)
        padData = [Float](repeating: 0, count: MachineMode.ringCount * 12)
        ballData = [Float](repeating: 0, count: maxBalls * 12)
    }

    // MARK: - Setup

    func buildProgram() {
        program = makeGLProgram(vs: Shaders.machineVS, fs: Shaders.machineFS, "machine")
        uViewProj = glGetUniformLocation(program, "uViewProj")
        uCameraPos = glGetUniformLocation(program, "uCameraPos")
        uTime = glGetUniformLocation(program, "uTime")

        // Drums — a squat tapered cylinder, unit radius so the instance
        // scale sets the real size. A little taller than the original's
        // (radius 4, height 1) so they read as drums rather than discs.
        buildMesh(MachineMesh.drum(top: 0.85, bottom: 1.0, height: 0.4, sides: 14),
                  vao: &drumVAO, vbo: &drumVBO, ebo: &drumEBO, inst: &drumInst,
                  instCapacity: MachineMode.stations * MachineMode.volumes,
                  indexCount: &drumIndexCount)

        // Pads — a unit box; the instance scale makes it a wide flat plate.
        buildMesh(MachineMesh.box(),
                  vao: &padVAO, vbo: &padVBO, ebo: &padEBO, inst: &padInst,
                  instCapacity: MachineMode.ringCount,
                  indexCount: &padIndexCount)

        // Balls — a faceted octahedron.
        buildMesh(MachineMesh.octahedron(radius: 1.0),
                  vao: &ballVAO, vbo: &ballVBO, ebo: &ballEBO, inst: &ballInst,
                  instCapacity: maxBalls,
                  indexCount: &ballIndexCount)
    }

    private func buildMesh(_ mesh: MachineMesh,
                           vao: inout GLuint, vbo: inout GLuint, ebo: inout GLuint,
                           inst: inout GLuint, instCapacity: Int, indexCount: inout GLsizei) {
        glGenVertexArrays(1, &vao)
        glBindVertexArray(vao)

        glGenBuffers(1, &vbo)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        // Interleave position + normal.
        var verts: [Float] = []
        verts.reserveCapacity(mesh.positions.count * 6)
        for i in mesh.positions.indices {
            verts.append(mesh.positions[i].x)
            verts.append(mesh.positions[i].y)
            verts.append(mesh.positions[i].z)
            verts.append(mesh.normals[i].x)
            verts.append(mesh.normals[i].y)
            verts.append(mesh.normals[i].z)
        }
        verts.withUnsafeBufferPointer { ptr in
            glBufferData(GLenum(GL_ARRAY_BUFFER), verts.count * 4, ptr.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        let stride = GLsizei(6 * MemoryLayout<Float>.size)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride, nil)
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride,
                              UnsafeRawPointer(bitPattern: 3 * MemoryLayout<Float>.size))

        glGenBuffers(1, &ebo)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), ebo)
        mesh.indices.withUnsafeBufferPointer { ptr in
            glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), mesh.indices.count * 4, ptr.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        indexCount = GLsizei(mesh.indices.count)

        // Per-instance data: 3 vec4s (xform, scale+flash, colour).
        glGenBuffers(1, &inst)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), inst)
        glBufferData(GLenum(GL_ARRAY_BUFFER), instCapacity * 12 * 4, nil, GLenum(GL_DYNAMIC_DRAW))
        let iStride = GLsizei(12 * MemoryLayout<Float>.size)
        for (i, attrib) in [3, 4, 5].enumerated() {
            glEnableVertexAttribArray(GLuint(attrib))
            glVertexAttribPointer(GLuint(attrib), 4, GLenum(GL_FLOAT), GLboolean(GL_FALSE), iStride,
                                  UnsafeRawPointer(bitPattern: i * 4 * MemoryLayout<Float>.size))
            glVertexAttribDivisor(GLuint(attrib), 1)
        }

        glBindVertexArray(0)
    }

    // MARK: - Per-frame update

    /// Advance the animation and upload instance data.
    ///
    /// `now` is the clock used for note ages. Live rendering passes wall-clock
    /// time; the snapshot path passes a synthetic clock so the balls are
    /// caught mid-flight instead of all sitting at their spawn point.
    func update(bands: [Float], rms: Float, now: CFTimeInterval, dt: Float) {
        mode.update(bands: bands, rms: rms, now: now, dt: dt)

        // --- corridor drums -------------------------------------------------
        var o = 0
        for station in 0..<MachineMode.stations {
            for vol in 0..<MachineMode.volumes {
                let idx = station * MachineMode.volumes + vol
                let radius = 4.0 + Float(vol) * 0.8
                let x = 42.0 + Float(vol) * 6.0
                let y = 10.0 + Float(vol) * 4.0
                let z = MachineMode.corridorStart + Float(station) * MachineMode.stationSpacing
                // The struck drum recoils along (1.5, -1.5, 0) and springs back.
                // The flash is 1 the instant it's hit and decays to 0 — at rest
                // the drum shows its base colour.
                let hit = mode.drumHits[idx]
                let flash = hit
                drumData[o + 0] = x + 1.5 * hit
                drumData[o + 1] = y - 1.5 * hit
                drumData[o + 2] = z
                drumData[o + 3] = 0                      // rotY
                drumData[o + 4] = radius                 // scale
                drumData[o + 5] = radius * 0.9
                drumData[o + 6] = radius
                drumData[o + 7] = flash
                drumData[o + 8] = MachineMode.machineColor.x
                drumData[o + 9] = MachineMode.machineColor.y
                drumData[o + 10] = MachineMode.machineColor.z
                drumData[o + 11] = 0
                o += 12
            }
        }
        upload(drumData, to: drumInst, count: MachineMode.stations * MachineMode.volumes)

        // --- ring pads -----------------------------------------------------
        o = 0
        for i in 0..<MachineMode.ringCount {
            let angle = Float(i) / Float(MachineMode.ringCount) * 2 * .pi
            let c = cos(angle), s = sin(angle)
            let radius: Float = 34
            let hit = mode.padHits[i]
            let flash = hit
            let width = 8.0 * (1.0 + Float(i) / Float(MachineMode.ringCount))
            padData[o + 0] = radius * c + 0.0 * hit
            padData[o + 1] = 6.0 - 1.5 * hit
            padData[o + 2] = radius * s + 0.0 * hit
            padData[o + 3] = angle
            padData[o + 4] = width
            padData[o + 5] = 2.0
            padData[o + 6] = 3.4
            padData[o + 7] = flash
            padData[o + 8] = MachineMode.machineColor.x
            padData[o + 9] = MachineMode.machineColor.y
            padData[o + 10] = MachineMode.machineColor.z
            padData[o + 11] = 0
            o += 12
        }
        upload(padData, to: padInst, count: MachineMode.ringCount)

        // --- bouncing balls -------------------------------------------------
        o = 0
        var ballCount = 0
        for note in mode.notes {
            if ballCount >= maxBalls { break }
            let age = now - note.born
            let progress = Float(age / MachineMode.ballLifetime)
            guard progress >= 0, progress <= 1 else { continue }

            // The corridor ball arcs over the drum it belongs to.
            let stationZ = MachineMode.corridorStart + Float(note.pitch) * MachineMode.stationSpacing
            let p = MachineMode.corridorBallPosition(progress: progress, volume: note.volume, stationZ: stationZ)
            // The ring ball flies out along the pad's own angle.
            let angle = Float(note.ringIndex) / Float(MachineMode.ringCount) * 2 * .pi
            let rp = MachineMode.ringBallPosition(progress: progress, angle: angle)

            // The corridor ball.
            ballData[o + 0] = p.x
            ballData[o + 1] = p.y
            ballData[o + 2] = p.z
            ballData[o + 3] = 0
            ballData[o + 4] = 1.6
            ballData[o + 5] = 1.6
            ballData[o + 6] = 1.6
            ballData[o + 7] = 0
            ballData[o + 8] = MachineMode.ballColor.x
            ballData[o + 9] = MachineMode.ballColor.y
            ballData[o + 10] = MachineMode.ballColor.z
            ballData[o + 11] = 0
            o += 12
            ballCount += 1

            // The ring ball, offset to the other side of the scene so both
            // are visible at once.
            if ballCount < maxBalls {
                ballData[o + 0] = rp.x
                ballData[o + 1] = rp.y
                ballData[o + 2] = rp.z
                ballData[o + 3] = 0
                ballData[o + 4] = 1.6
                ballData[o + 5] = 1.6
                ballData[o + 6] = 1.6
                ballData[o + 7] = 0
                ballData[o + 8] = MachineMode.ballColor.x
                ballData[o + 9] = MachineMode.ballColor.y
                ballData[o + 10] = MachineMode.ballColor.z
                ballData[o + 11] = 0
                o += 12
                ballCount += 1
            }

            // Mark the drum and pad that were struck.
            let drumIdx = note.pitch * MachineMode.volumes + note.volume
            if drumIdx < mode.drumHits.count { mode.drumHits[drumIdx] = 1.0 }
            if note.ringIndex < mode.padHits.count { mode.padHits[note.ringIndex] = 1.0 }
        }
        upload(ballData, to: ballInst, count: ballCount)
    }

    private func upload(_ data: [Float], to buffer: GLuint, count: Int) {
        guard count > 0 else { return }
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), buffer)
        data.withUnsafeBufferPointer { ptr in
            glBufferSubData(GLenum(GL_ARRAY_BUFFER), 0, count * 12 * 4, ptr.baseAddress)
        }
    }

    // MARK: - Draw

    func draw(viewProj: [GLfloat], cameraPos: SIMD3<Float>, time: Float) {
        guard program != 0 else { return }
        glUseProgram(program)
        glUniformMatrix4fv(uViewProj, 1, GLboolean(GL_FALSE), viewProj)
        glUniform3f(uCameraPos, cameraPos.x, cameraPos.y, cameraPos.z)
        glUniform1f(uTime, time)

        glBindVertexArray(drumVAO)
        glDrawElementsInstanced(GLenum(GL_TRIANGLES), drumIndexCount, GLenum(GL_UNSIGNED_INT), nil,
                               GLsizei(MachineMode.stations * MachineMode.volumes))

        glBindVertexArray(padVAO)
        glDrawElementsInstanced(GLenum(GL_TRIANGLES), padIndexCount, GLenum(GL_UNSIGNED_INT), nil,
                               GLsizei(MachineMode.ringCount))

        glBindVertexArray(ballVAO)
        let ballCount = min(maxBalls, mode.notes.count * 2)
        if ballCount > 0 {
            glDrawElementsInstanced(GLenum(GL_TRIANGLES), ballIndexCount, GLenum(GL_UNSIGNED_INT), nil,
                                   GLsizei(ballCount))
        }

        glBindVertexArray(0)
    }

    // MARK: - Camera

    /// The camera path. The original flies a spline over the course of the
    /// track: it starts high at the far end of the drum corridor, drops down
    /// through it, then swings out around the ring and back. This loops.
    private static let camPath: [SIMD3<Float>] = [
        SIMD3<Float>(  30,  46, 258),   // far end of the corridor, looking down it
        SIMD3<Float>(  78,  40, 198),   // closer, angled across the drums
        SIMD3<Float>( 112,  32, 118),   // off to the side of the corridor
        SIMD3<Float>(  96,  34,  30),   // approaching the ring
        SIMD3<Float>(  16,  44, -18),   // out over the ring
    ]
    private static let targetPath: [SIMD3<Float>] = [
        SIMD3<Float>(48, 12, 165),   // down the corridor
        SIMD3<Float>(48, 12, 130),
        SIMD3<Float>(42, 10,  78),
        SIMD3<Float>(12,  8,  22),   // out toward the ring
        SIMD3<Float>( 0,  7,   0),   // the ring itself
    ]

    /// Sample a closed Catmull-Rom loop.
    static func sample(_ pts: [SIMD3<Float>], t: Float) -> SIMD3<Float> {
        let n = pts.count
        let f = t * Float(n)
        let i = Int(f) % n
        let s = f - floor(f)
        let p0 = pts[(i - 1 + n) % n]
        let p1 = pts[i]
        let p2 = pts[(i + 1) % n]
        let p3 = pts[(i + 2) % n]
        let s2 = s * s
        let s3 = s2 * s
        // Catmull-Rom basis, written out so the type-checker doesn't choke.
        let c0: SIMD3<Float> = 2 * p1
        let c1: SIMD3<Float> = (-p0 + p2) * s
        let c2: SIMD3<Float> = (2 * p0 - 5 * p1 + 4 * p2 - p3) * s2
        let c3: SIMD3<Float> = (-p0 + 3 * p1 - 3 * p2 + p3) * s3
        return 0.5 * (c0 + c1 + c2 + c3)
    }

    /// Camera position and look-at target for a given loop parameter.
    static func camera(t: Float) -> (pos: SIMD3<Float>, target: SIMD3<Float>) {
        (sample(camPath, t: t), sample(targetPath, t: t))
    }
}

/// Builds a view-projection matrix (column-major, GL convention) for a camera
/// at `eye` looking at `target`.
func makeViewProj(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>,
                  aspect: Float, fovY: Float, near: Float, far: Float) -> [GLfloat] {
    let f = simd_normalize(target - eye)
    let s = simd_normalize(simd_cross(f, up))
    let u = simd_cross(s, f)

    // View matrix, column-major: element [col*4 + row].
    var v = [GLfloat](repeating: 0, count: 16)
    v[0] = s.x;  v[1] = u.x;  v[2] = -f.x; v[3] = 0
    v[4] = s.y;  v[5] = u.y;  v[6] = -f.y; v[7] = 0
    v[8] = s.z;  v[9] = u.z;  v[10] = -f.z; v[11] = 0
    v[12] = -simd_dot(s, eye)
    v[13] = -simd_dot(u, eye)
    v[14] =  simd_dot(f, eye)
    v[15] = 1

    let p = perspective(fovY: fovY, aspect: aspect, near: near, far: far)

    // M = P * V
    var m = [GLfloat](repeating: 0, count: 16)
    for col in 0..<4 {
        for row in 0..<4 {
            var sum: GLfloat = 0
            for k in 0..<4 {
                sum += p[k * 4 + row] * v[col * 4 + k]
            }
            m[col * 4 + row] = sum
        }
    }
    return m
}
