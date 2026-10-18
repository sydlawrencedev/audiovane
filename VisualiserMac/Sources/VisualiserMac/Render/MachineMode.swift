import Foundation
import simd
import OpenGL.GL3

/// "MACHINE" mode — a port of the MIDEM Music Hack Day piece by @mrdoob and
/// @plamere (github.com/mrdoob/midemhackday).
///
/// The original is two "machines" driven by an Echo Nest score:
///
///   * Machine 1 — a corridor of drums receding into the distance. Every note
///     event launches a white ball that arcs over the drums; the drum it came
///     from recoils and flashes white.
///   * Machine 2 — a ring of pads around the origin. Notes bounce off the
///     pads in the same way.
///
/// The camera flies a fixed path through both.
///
/// We don't have an Echo Nest score, so note events are synthesised from the
/// live spectrum: spectral flux peaks become notes, the dominant band picks
/// the drum (which sets the ball's launch height) and the flux strength picks
/// the volume (which sets how hard the drum is hit and how high the arc goes).
struct MachineMode {

    // MARK: - Layout constants (from the original)
    /// Stations along the corridor, one per pitch.
    static let stations = 12
    /// Drums per station — one per loudness bucket.
    static let volumes = 3
    /// Pads around the ring.
    static let ringCount = 40
    /// Spacing between stations along Z.
    static let stationSpacing: Float = 13
    /// The corridor starts clear of the ring, so the two machines don't
    /// interpenetrate. (In the original, Machine 1's container sits at
    /// z = 60 while Machine 2's ring is at the origin.)
    static let corridorStart: Float = 70
    /// Base colour of the drums and pads (the original's 0xff8020).
    static let machineColor = SIMD3<Float>(1.0, 0.502, 0.125)
    /// Colour of the bouncing balls (the original's white icosahedron).
    static let ballColor = SIMD3<Float>(0.96, 0.96, 0.94)

    // MARK: - Animation state

    /// A note event in flight.
    struct Note {
        var born: CFTimeInterval
        var pitch: Int        // 0..<stations
        var volume: Int       // 0..<volumes
        var ringIndex: Int    // 0..<ringCount
    }

    /// Live per-drum recoil, 0 = at rest, 1 = fully struck.
    var drumHits = [Float](repeating: 0, count: stations * volumes)
    /// Live per-pad recoil.
    var padHits = [Float](repeating: 0, count: ringCount)
    /// Notes currently bouncing.
    var notes: [Note] = []

    /// Previous band values, for spectral flux.
    private var prevBands: [Float] = []
    private var lastNoteAt: CFTimeInterval = 0

    /// Called every frame with the live spectrum.
    mutating func update(bands: [Float], rms: Float, now: CFTimeInterval, dt: Float) {
        if prevBands.count != bands.count {
            prevBands = [Float](repeating: 0, count: bands.count)
        }

        // --- spectral flux → note events -------------------------------
        // The dominant band of the flux decides the pitch; the total flux
        // decides the loudness, same split the original gets from the score's
        // pitch_list and loudness_bucket.
        var flux = Float(0)
        var domBand = 0
        var domMag = Float(0)
        for i in bands.indices {
            let f = max(0, bands[i] - prevBands[i])
            flux += f
            if f > domMag { domMag = f; domBand = i }
        }
        prevBands = bands

        // A note needs a real transient, and not too many of them.
        let quiet = rms < 0.004
        let minGap: CFTimeInterval = 0.11
        if !quiet, flux > 0.09, domMag > 0.02, now - lastNoteAt > minGap {
            lastNoteAt = now
            let pitch = min(Self.stations - 1, domBand * Self.stations / max(1, bands.count))
            let volume = min(Self.volumes - 1, Int(flux * 14))
            let ringIndex = (pitch + volume * Self.stations) % Self.ringCount
            notes.append(Note(born: now, pitch: pitch, volume: volume, ringIndex: ringIndex))
        }

        // --- advance the bouncing balls --------------------------------
        // The original runs the ball over 1s and the ring ball over 1.8s.
        notes.removeAll { now - $0.born > Self.ballLifetime }
        for n in notes.indices {
            // nothing to do per-frame beyond age, which the draw reads
        }

        // --- drum + pad recoil -----------------------------------------
        // A struck drum springs back over ~0.35s.
        for i in drumHits.indices { drumHits[i] = max(0, drumHits[i] - dt * 2.9) }
        for i in padHits.indices { padHits[i] = max(0, padHits[i] - dt * 2.9) }
    }

    /// How long a corridor ball is in flight (the original: 1.0s).
    static let ballLifetime: CFTimeInterval = 1.0

    /// Debug/snapshot helper: seed a spread of notes so the bouncing balls are
    /// visible at different points along their arcs. Live playback never uses
    /// this — notes come from the spectral flux detector instead.
    mutating func seedNotes(count: Int, now: CFTimeInterval) {
        for i in 0..<count {
            let pitch = i % MachineMode.stations
            let volume = (i / MachineMode.stations) % MachineMode.volumes
            let ringIndex = (pitch + volume * MachineMode.stations) % MachineMode.ringCount
            // Spread the spawn times so they're at different stages of flight.
            let age = Double(i % 7) * 0.13
            notes.append(Note(born: now - age, pitch: pitch, volume: volume, ringIndex: ringIndex))
        }
    }

    /// The arc a corridor ball follows, ported from Bounce1Effect.
    ///
    /// Three points: launch, apex (over the drums — the apex height depends
    /// on the drum's volume), and landing. The first half of the flight
    /// swings up, the second half falls.
    static func corridorBallPosition(progress: Float, volume: Int, stationZ: Float) -> SIMD3<Float> {
        let p0 = SIMD3<Float>(0, 16, stationZ)
        let p1 = SIMD3<Float>(42 + Float(volume) * 6, 8 + Float(volume) * 4, stationZ)
        let p2 = SIMD3<Float>(9, 0, stationZ)
        if progress < 0.5 {
            var p = p1 - p0
            p *= progress * 2
            p += p0
            p.y += sin(.pi * progress * 2) * 16
            return p
        } else {
            var p = p2 - p1
            p *= progress * 2 - 1
            p += p1
            p.y += abs(sin(.pi * (progress * 2 - 1))) * 13
            return p
        }
    }

    /// The arc a ring ball follows, ported from Bounce2Effect.
    static func ringBallPosition(progress: Float, angle: Float) -> SIMD3<Float> {
        let p0 = SIMD3<Float>(0, 9, 0)
        let p1 = SIMD3<Float>(40, 6, 0)
        let p2 = SIMD3<Float>(78, 1, 0)
        var p: SIMD3<Float>
        if progress < 0.5 {
            p = p1 - p0
            p *= progress * 2
            p += p0
            p.y += sin(.pi * progress * 2) * 26
        } else {
            p = p2 - p1
            p *= progress * 2 - 1
            p += p1
            p.y += abs(sin(.pi * (progress * 2 - 1))) * 13
        }
        // Rotate the whole path around the ring.
        let c = cos(angle), s = sin(angle)
        return SIMD3<Float>(p.x * c - p.z * s, p.y, p.x * s + p.z * c)
    }
}

// MARK: - Shaders

extension Shaders {
    /// Instanced, lit geometry. One program covers the drums, the pads and
    /// the balls — they differ only in base mesh and per-instance data.
    static let machineVS = """
    #version 330 core
    layout(location = 0) in vec3 aPos;
    layout(location = 1) in vec3 aNormal;
    // instanced
    layout(location = 3) in vec4 iXform;   // pos.xyz, rotY
    layout(location = 4) in vec4 iScale;   // scale.xyz, flash
    layout(location = 5) in vec4 iColor;   // rgb, unused

    uniform mat4 uViewProj;
    uniform vec3 uCameraPos;

    out vec3 vNormal;
    out vec3 vColor;
    out vec3 vWorld;

    void main() {
        vec3 s = max(iScale.xyz, vec3(1e-4));
        vec3 p = aPos * s;

        float c = cos(iXform.w), sn = sin(iXform.w);
        p = vec3(p.x * c - p.z * sn, p.y, p.x * sn + p.z * c);

        vec3 n = normalize(aNormal / s);
        n = vec3(n.x * c - n.z * sn, n.y, n.x * sn + n.z * c);

        vec3 world = p + iXform.xyz;
        vWorld = world;
        vNormal = n;
        // Flash toward white as the drum is struck.
        vColor = mix(iColor.rgb, vec3(1.0), iScale.w);
        gl_Position = uViewProj * vec4(world, 1.0);
    }
    """

    static let machineFS = """
    #version 330 core
    in vec3 vNormal;
    in vec3 vColor;
    in vec3 vWorld;

    uniform vec3 uCameraPos;
    uniform float uTime;

    out vec4 fragColor;

    void main() {
        vec3 n = normalize(vNormal);
        vec3 v = normalize(uCameraPos - vWorld);

        // Key light from above and slightly behind, a fill from below (the
        // original has a directional light at y = -300), and a rim.
        vec3 keyDir = normalize(vec3(-0.35, 1.0, 0.45));
        vec3 fillDir = normalize(vec3(0.25, -1.0, -0.35));
        float key = max(dot(n, keyDir), 0.0);
        float fill = max(dot(n, fillDir), 0.0);
        float rim = pow(1.0 - max(dot(n, v), 0.0), 3.0);

        vec3 ambient = vec3(0.26, 0.24, 0.28);
        vec3 col = vColor * (ambient + key * 0.80 + fill * 0.22);

        // Blinn-Phong-ish highlight.
        vec3 h = normalize(keyDir + v);
        col += vec3(0.9, 0.9, 0.85) * pow(max(dot(n, h), 0.0), 40.0) * 0.45;

        // Rim light picks the silhouettes out of the dark.
        col += vec3(0.35, 0.55, 0.75) * rim * 0.30;

        fragColor = vec4(col, 1.0);
    }
    """
}

// MARK: - Mesh construction

/// A small mesh: positions + normals + triangle indices.
struct MachineMesh {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    /// A tapered drum: radius `bottom` at the base, `top` at the top, `height`
    /// tall, centred on the origin. Matches the original's CylinderGeometry.
    static func drum(top: Float, bottom: Float, height: Float, sides: Int) -> MachineMesh {        var m = MachineMesh()
        let hy = height / 2
        for i in 0...sides {
            let a = Float(i) / Float(sides) * 2 * .pi
            let cx = cos(a), cz = sin(a)
            m.positions.append(SIMD3<Float>(cx * top, hy, cz * top))
            m.normals.append(normalize(SIMD3<Float>(cx, (bottom - top) / height, cz)))
            m.positions.append(SIMD3<Float>(cx * bottom, -hy, cz * bottom))
            m.normals.append(normalize(SIMD3<Float>(cx, (bottom - top) / height, cz)))
        }
        // Cap the top and bottom so the drums read as solid discs.
        let topCentre = UInt32(m.positions.count)
        m.positions.append(SIMD3<Float>(0, hy, 0))
        m.normals.append(SIMD3<Float>(0, 1, 0))
        let botCentre = UInt32(m.positions.count)
        m.positions.append(SIMD3<Float>(0, -hy, 0))
        m.normals.append(SIMD3<Float>(0, -1, 0))

        for i in 0..<sides {
            let a = UInt32(i * 2), b = UInt32(i * 2 + 1)
            let c = UInt32((i + 1) * 2), d = UInt32((i + 1) * 2 + 1)
            m.indices.append(contentsOf: [a, b, c, c, b, d])
            m.indices.append(contentsOf: [topCentre, a, c])
            m.indices.append(contentsOf: [botCentre, b, d])
        }
        return m
    }

    /// A unit box centred on the origin, 1×1×1.
    static func box() -> MachineMesh {
        var m = MachineMesh()
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3<Float>( 0, 0,  1), SIMD3<Float>(-1, -1, 0), SIMD3<Float>( 1, -1, 0), SIMD3<Float>( 1,  1, 0)), // +Z
            (SIMD3<Float>( 0, 0, -1), SIMD3<Float>( 1, -1, 0), SIMD3<Float>(-1, -1, 0), SIMD3<Float>(-1,  1, 0)), // -Z
            (SIMD3<Float>( 1, 0,  0), SIMD3<Float>( 1, -1, 0), SIMD3<Float>( 1,  1, 0), SIMD3<Float>( 1,  1, 0)), // +X
            (SIMD3<Float>(-1, 0,  0), SIMD3<Float>(-1,  1, 0), SIMD3<Float>(-1, -1, 0), SIMD3<Float>(-1, -1, 0)), // -X
            (SIMD3<Float>( 0, 1,  0), SIMD3<Float>(-1,  1, 0), SIMD3<Float>( 1,  1, 0), SIMD3<Float>( 1,  1, 0)), // +Y
            (SIMD3<Float>( 0,-1,  0), SIMD3<Float>( 1, -1, 0), SIMD3<Float>(-1, -1, 0), SIMD3<Float>(-1, -1, 0)), // -Y
        ]
        for (n, a, b, c) in faces {
            let base = UInt32(m.positions.count)
            for v in [a, b, c] {
                m.positions.append(v)
                m.normals.append(n)
            }
            m.indices.append(contentsOf: [base, base + 1, base + 2])
        }
        return m
    }

    /// An octahedron of the given radius — the original uses an icosahedron;
    /// an octahedron reads the same at this scale and is a third of the faces.
    static func octahedron(radius: Float) -> MachineMesh {
        var m = MachineMesh()
        let r = radius
        let top = SIMD3<Float>(0, r, 0)
        let bot = SIMD3<Float>(0, -r, 0)
        let ring = [
            SIMD3<Float>( r, 0, 0),
            SIMD3<Float>(0, 0,  r),
            SIMD3<Float>(-r, 0, 0),
            SIMD3<Float>(0, 0, -r),
        ]
        for i in 0..<4 {
            let a = ring[i], b = ring[(i + 1) % 4]
            let base = UInt32(m.positions.count)
            for v in [a, b, top] {
                m.positions.append(v)
                m.normals.append(normalize(v))
            }
            m.indices.append(contentsOf: [base, base + 1, base + 2])
            let base2 = UInt32(m.positions.count)
            for v in [b, a, bot] {
                m.positions.append(v)
                m.normals.append(normalize(v))
            }
            m.indices.append(contentsOf: [base2, base2 + 1, base2 + 2])
        }
        return m
    }
}
