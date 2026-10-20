import Foundation

/// Embedded GLSL 330 core shaders. Plain strings — no build step needed.
enum Shaders {

    /// Full-screen palette grade. Samples the finished scene and maps its
    /// luminance ramp between a shadow and a highlight colour, then applies
    /// saturation and a black lift. Runs after every vibscape, so one palette
    /// themes the whole app.
    static let gradeVS = """
    #version 330 core
    layout(location = 0) in vec2 aPos;
    out vec2 vUV;
    void main() {
        vUV = aPos * 0.5 + 0.5;
        gl_Position = vec4(aPos, 0.0, 1.0);
    }
    """

    static let gradeFS = """
    #version 330 core
    in vec2 vUV;
    uniform sampler2D uTex;
    uniform vec3 uShadow;
    uniform vec3 uHighlight;
    uniform float uSaturation;
    uniform float uDuotone;
    uniform float uLift;
    out vec4 fragColor;

    void main() {
        vec3 c = texture(uTex, vUV).rgb;
        float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));

        // Duotone: stretch the luminance ramp between the two palette colours.
        vec3 graded = uShadow + (uHighlight - uShadow) * luma;
        c = mix(c, graded, uDuotone);

        // Saturation, around the graded luminance.
        luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
        c = mix(vec3(luma), c, uSaturation);

        // Lift the blacks toward the shadow colour so the image doesn't crush.
        c += uShadow * uLift * (1.0 - luma);

        fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
    }
    """

    static let tunnelVS = """
    #version 330 core
    layout(location = 0) in vec3 aPos;
    layout(location = 1) in vec3 aColor;

    uniform mat4 uMVP;
    uniform float uTime;
    uniform float uBass;
    uniform float uBeat;
    uniform float uBeatStrength;

    out vec3 vColor;
    out float vDepth01;

    void main() {
        const float kTunnelLength = 64.0 * 0.95;

        float scrollSpeed = 5.5 + (length(aColor) * 5.0) + (uBeat > 0.5 ? 18.0 : 0.0);
        scrollSpeed += uBass * 22.0;

        float scrollOffset = uTime * scrollSpeed;
        float z = mod(aPos.z - scrollOffset, kTunnelLength);
        if (z < 0.0) z += kTunnelLength;

        // perspective: rings get smaller into the distance.
        // close ring (z=0): big; far ring (z=kTunnelLength): small.
        float invZ = (kTunnelLength - z * 0.85) / kTunnelLength;
        invZ = clamp(invZ, 0.06, 1.0);

        float bassPulse = 1.0 + uBass * 0.2;
        float ringExpand = bassPulse;

        // global scale so the visible ring just fills the viewport
        float scale = 0.18;

        vec3 worldPos = vec3(
            aPos.x * invZ * ringExpand * scale,
            aPos.y * invZ * ringExpand * scale,
            z
        );

        gl_Position = uMVP * vec4(worldPos, 1.0);
        vColor = aColor;
        vDepth01 = z / kTunnelLength;
    }
    """

    static let tunnelFS = """
    #version 330 core
    in vec3 vColor;
    in float vDepth01;
    uniform float uBass;
    out vec4 fragColor;
    void main() {
        float fade = 1.0 - vDepth01 * 0.85;
        vec3 col = vColor * fade * 1.2;
        fragColor = vec4(col, fade);
    }
    """

    static let particleVS = """
    #version 330 core
    layout(location = 0) in vec3 aPos;
    layout(location = 1) in vec3 aColor;
    layout(location = 2) in float aSize;
    layout(location = 3) in float aSeed;
    layout(location = 4) in float aRadius;
    layout(location = 5) in float aBandIdx;

    uniform mat4 uMVP;
    uniform float uTime;
    uniform float uBass;
    uniform float uMid;
    uniform float uTreble;
    uniform float uBeat;
    uniform float uBeatStrength;
    uniform float uLevel;
    uniform vec2 uResolution;
    uniform float uActive;      // 0 in silence, 1 with sound
    uniform float uBands[96];

    out vec3 vColor;
    out float vBeat;

    float hash11(float n) { return fract(sin(n * 43758.5453) * 1.0); }

    void main() {
        // orbital motion
        float speed = 0.18 + aSeed * 0.42;
        float angle = uTime * speed + aSeed * 6.2831;

        float r = length(aPos.xz);
        vec2 dir = r > 0.0001 ? aPos.xz / r : vec2(1.0, 0.0);
        float ca = cos(angle);
        float sa = sin(angle);
        vec2 rotated = vec2(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);

        // How many orbs are lit follows loudness (none in silence); each orb
        // belongs to one frequency band and is pushed out by that band's energy.
        float lit = uActive * (0.08 + 0.92 * clamp(uLevel * 1.8, 0.0, 1.0));
        if (aSeed > lit) {
            gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
            gl_PointSize = 0.0;
            vColor = vec3(0.0);
            vBeat = 0.0;
            return;
        }
        float band = uBands[int(clamp(aBandIdx, 0.0, 0.999) * 96.0)];
        float bassExpand = 1.0 + uBass * 0.85;
        float beatBlast = 1.0 + uBeatStrength * 1.4;
        float bandPush = 1.0 + band * 1.3;
        float newRadius = aRadius * bassExpand * bandPush * beatBlast;

        float turb = uTreble * 0.7;
        vec3 jitter = vec3(
            sin(uTime * 2.3 + aSeed * 9.7),
            cos(uTime * 1.8 + aSeed * 7.3),
            sin(uTime * 2.1 + aSeed * 11.1)
        ) * turb;

        float axialSquash = mix(1.0, 0.7, uBass);

        vec3 worldPos = vec3(
            rotated.x * newRadius + jitter.x,
            aPos.y * axialSquash + jitter.y,
            rotated.y * newRadius + jitter.z
        );

        worldPos.y += uMid * 0.5 * sin(aSeed * 6.28);

        float groupRot = uTime * 0.05;
        float cg = cos(groupRot);
        float sg = sin(groupRot);
        vec3 r1 = vec3(worldPos.x * cg - worldPos.z * sg, worldPos.y, worldPos.x * sg + worldPos.z * cg);

        float tilt = sin(uTime * 0.13) * 0.18 + 0.5;
        float ct = cos(tilt);
        float st = sin(tilt);
        vec3 r2 = vec3(r1.x, r1.y * ct - r1.z * st, r1.y * st + r1.z * ct);

        vec3 cameraOffset = vec3(sin(uTime * 0.2) * 0.4, cos(uTime * 0.15) * 0.3, 14.0 + uLevel * 1.5);
        vec3 viewPos = r2 - cameraOffset;

        gl_Position = uMVP * vec4(viewPos, 1.0);
        vColor = aColor;
        vBeat = uBeatStrength * (0.5 + band * 0.5);

        // point size with perspective shrink
        float dist = max(0.001, -viewPos.z);
        gl_PointSize = aSize * (260.0 / dist) * (1.0 + uBeatStrength * 1.2 + band * 0.4);
    }
    """

    static let particleFS = """
    #version 330 core
    in vec3 vColor;
    in float vBeat;
    out vec4 fragColor;
    void main() {
        vec2 c = gl_PointCoord - 0.5;
        float d = length(c);
        if (d > 0.5) discard;
        float core = smoothstep(0.5, 0.0, d);
        float glow = pow(core, 1.5);
        vec3 col = vColor + vec3(0.4, 0.2, 0.5) * vBeat;
        fragColor = vec4(col, glow * (0.55 + vBeat * 0.5));
    }
    """

    static let liquidVS = """
    #version 330 core
    layout(location = 0) in vec2 aPos;
    out vec2 vUV;
    void main() {
        vUV = aPos * 0.5 + 0.5;
        gl_Position = vec4(aPos, 0.0, 1.0);
    }
    """

    static let liquidFS = """
    #version 330 core
    in vec2 vUV;
    uniform float uTime;
    uniform float uBass;
    uniform float uMid;
    uniform float uTreble;
    uniform float uBeat;
    uniform float uBeatStrength;
    uniform float uLevel;
    uniform vec2 uResolution;
    uniform float uIdle;
    uniform float uBands[96];
    uniform float uActive;
    out vec4 fragColor;

    float lhash(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }
    float lnoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        float a = lhash(i);
        float b = lhash(i + vec2(1.0, 0.0));
        float c = lhash(i + vec2(0.0, 1.0));
        float d = lhash(i + vec2(1.0, 1.0));
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }
    float lfbm(vec2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 5; i++) {
            v += a * lnoise(p);
            p = p * 2.04 + vec2(1.7, 9.2);
            a *= 0.52;
        }
        return v;
    }
    vec3 lpalette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
        return a + b * cos(6.28318 * (c * t + d));
    }

    void main() {
        vec2 res = uResolution;
        vec2 p = (gl_FragCoord.xy * 2.0 - res) / min(res.x, res.y);

        float t = uTime * 0.16;

        vec2 q = vec2(
            lfbm(p * 1.4 + vec2(0.0, t)),
            lfbm(p * 1.4 + vec2(5.2, -t * 0.8))
        );

        vec2 r = vec2(
            lfbm(p * 1.6 + 4.0 * q + vec2(1.7 + t * 1.5, 9.2)),
            lfbm(p * 1.6 + 4.0 * q + vec2(8.3 - t * 1.2, 2.8))
        );

        float f = lfbm(p * 1.8 + 4.0 * r + vec2(0.0, t * 2.0));

        float kSegments = 6.0 + floor(uMid * 4.0);
        float ang = atan(p.y, p.x);
        float radius = length(p);
        float seg = 6.2831853 / kSegments;
        ang = mod(ang, seg);
        ang = abs(ang - seg * 2.0);
        vec2 kp = vec2(cos(ang), sin(ang)) * radius;
        float kField = lfbm(kp * 2.2 + t * 0.6 + uBass * 1.3);

        float distAmp = 0.4 + uBass * 0.9 + uTreble * 0.4 + uIdle * 0.25;
        float beatFlash = uBeatStrength * 0.8;

        float v = f * (1.0 - distAmp * 0.4) + kField * 0.55 * distAmp;
        v += beatFlash;

        vec3 col = lpalette(v + t * 0.6,
                            vec3(0.5, 0.45, 0.55),
                            vec3(0.55, 0.5, 0.5),
                            vec3(1.0, 1.0, 1.0),
                            vec3(0.0, 0.33, 0.67));

        vec3 neon = vec3(1.0, 0.17, 0.84);
        vec3 cyan = vec3(0.17, 0.95, 1.0);
        vec3 violet = vec3(0.54, 0.30, 1.0);
        vec3 tint = mix(neon, cyan, smoothstep(0.0, 1.0, v + 0.3));
        tint = mix(tint, violet, smoothstep(0.4, 1.0, v));
        col = mix(col, tint, 0.55);

        col += neon * beatFlash * 0.6;

        float vig = smoothstep(1.4, 0.3, length(p));
        col *= 0.55 + vig * 0.7;

        float grain = lhash(gl_FragCoord.xy + uTime * 0.01) - 0.5;
        col += grain * 0.025;

        col += vec3(0.04, 0.02, 0.08) * uIdle;

        // Flat single colour in silence, fading into the full palette with sound.
        col = mix(vec3(0.05, 0.02, 0.08), col, uActive);
        fragColor = vec4(col, 1.0);
    }
    """
}