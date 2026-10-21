import Foundation

/// Full-screen fragment shaders for the extra visualizer vibescapes. Each body is
/// appended to `prelude` and drawn on the shared full-screen quad with
/// `Shaders.liquidVS`. Everything is drawn procedurally with 2D signed
/// distance fields: no textures or sprite assets.
enum FunShaders {
    static let modes: [(Vibescape, String)] = [
        (.badger, badger),
        (.llama, llama),
        (.hamster, hamster),
        (.nyan, nyan),
        (.spectrum, spectrum),
        (.kaleidoscope, kaleidoscope),
        (.warp, warp),
        (.band, band),
        (.waveform, waveform),
        (.ribbons, ribbons),
        (.silk, silk),
        (.flux, flux),
        (.danceFloor, danceFloor),
        (.vortex, vortex),
    ]

    static let prelude = """
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
    uniform float uActive;      // 0 in silence, eases to 1 with sound
    uniform float uBeats;       // beat counter at the detected tempo; continuous, never steps or runs back
    uniform float uScroll;      // forward-only distance, faster when louder
    uniform float uClock;       // wall-clock seconds; keeps running in silence (use sparingly)
    uniform float uLevelSmooth; // slow loudness, 0..1: rises over ~0.3 s, falls over ~1.5 s
    uniform float uBassSmooth;  // the same slow easing applied to uBass
    uniform float uPresence;    // music presence, 0..1: eases in and out over ~2.3 s, no chatter
    out vec4 fragColor;

    const float PI = 3.14159265;

    // Centered coords: y spans -0.5..0.5, x scales with aspect ratio.
    vec2 screenP() { return (gl_FragCoord.xy - 0.5 * uResolution) / uResolution.y; }
    // Anti-alias width for a shape drawn at scale `s`.
    float aaw(float s) { return 1.5 / (uResolution.y * s); }

    float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
    float hash21(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    // Smooth noise, and four octaves of it. This is what anything that looks
    // like a cloud, a flame or smoke is built from — and it wasn't here, so
    // everyone was writing their own, or reaching for sin() and wondering why
    // the result looked like a gradient.
    //
    // The trap: scale matters more than anything else. Sampled at about the
    // screen's scale these are too smooth to see — across a shape a few tenths
    // wide you'd be looking at a single slow ramp. Multiply by something like
    // 7.0 so several cells land inside the shape.
    float vnoise(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);              // smooth, so no grid
        return mix(mix(hash21(i),                hash21(i + vec2(1.0, 0.0)), f.x),
                   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
                   f.y);
    }

    // Roughly 0..1, averaging a shade under half. Layering two of these and
    // pushing the result is usually what turns noise into something with
    // structure rather than grain.
    //
    // The rotation matrix is written out rather than using rot(), which is
    // declared further down: GLSL has no forward declarations, and this block
    // sits above it.
    float fbm(vec2 p) {
        float sum = 0.0, amp = 0.5;
        for (int i = 0; i < 4; i++) {
            sum += amp * vnoise(p);
            // Rotate as well as scale, so the octaves don't stack into a grid.
            p = mat2(0.8, -0.6, 0.6, 0.8) * p * 2.03 + vec2(1.7, 9.2);
            amp *= 0.5;
        }
        return sum;
    }
    float bandAt(float x) { return uBands[int(clamp(x, 0.0, 0.999) * 96.0)]; }
    mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }

    float sdCircle(vec2 p, float r) { return length(p) - r; }
    float sdEllipse(vec2 p, vec2 r) {
        float k0 = length(p / r);
        float k1 = length(p / (r * r));
        return k0 * (k0 - 1.0) / max(k1, 1e-5);
    }
    float sdBox(vec2 p, vec2 b) {
        vec2 d = abs(p) - b;
        return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    }
    float sdRoundBox(vec2 p, vec2 b, float r) { return sdBox(p, b - r) - r; }
    float sdSeg(vec2 p, vec2 a, vec2 b) {
        vec2 pa = p - a, ba = b - a;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        return length(pa - ba * h);
    }
    float fill(float d, float w) { return 1.0 - smoothstep(-w, w, d); }

    // Dance timing: one move per beat at the detected tempo (up on one beat,
    // down on the next), mostly in unison. Size follows the music; at rest
    // (silence) groove() is 0 so dancers settle into their rest pose.
    float dance(float phase) { return 0.5 + 0.5 * sin(uBeats * PI + phase * 0.35); }
    float groove() { return (0.25 + uBass * 0.9 + uBeatStrength * 0.6) * uActive; }

    """

    // MARK: - Custom vibescapes

    /// Wraps a user-written vibescape so the author only has to supply
    /// `vec3 render(vec2 p, float t)` and return a colour.
    ///
    /// Every vibescape in this file writes `main()` and assigns `fragColor`
    /// directly, because they're ours and terseness costs them nothing. A
    /// person pasting in a vibescape they've never seen shouldn't have to learn
    /// that: `fragColor` is an output slot with no meaning to someone who
    /// just wants a colour back. Returning a `vec3` is the one concept that
    /// transfers from every other drawing API.
    ///
    /// `uPalette` is declared here rather than in the prelude because the
    /// built-in vibescapes each declare it themselves and the prelude predates
    /// it. Declaring it for custom vibescapes means "themed by the current
    /// palette" works the same way it does for Dance Floor — and if the
    /// author never mentions it, the location lookup returns -1 and the
    /// palette bind is skipped, so an unused uniform costs nothing.
    static let customWrapper = """
    uniform vec3 uPalette[3];

    void main() {
        vec2 p = screenP();
        vec3 c = render(p, uTime);
        fragColor = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
    }
    """

    /// A complete shader for a user's vibescape: the same prelude the built-ins
    /// get, plus their code, plus the friendly wrapper.
    ///
    /// The order matters. GLSL has no forward declarations, so the function
    /// that calls `render` can only come after the one that defines it —
    /// hence the wrapper goes last, not first.
    static func customSource(body: String) -> String {
        prelude + body + customWrapper
    }

    /// Lines in `customSource` before the user's first line, so a driver
    /// error can be mapped back to a line they can actually edit.
    static let customPreludeLineCount =
        prelude.split(separator: "\n", omittingEmptySubsequences: false).count

    // MARK: - Badger Badger

    static let badger = """
    void badgerAt(inout vec3 col, vec2 p, vec2 pos, float s, float ph) {
        vec2 q = (p - pos) / s;
        float w = aaw(s);
        float d = dance(ph);
        q.y += d * 0.1 * groove();               // squat down on the beat
        vec3 fur = vec3(0.42, 0.42, 0.46), dark = vec3(0.1), white = vec3(0.96);

        // arms pump up and down
        float up = d * uActive;                  // arms rest down in silence
        vec2 hl = mix(vec2(-0.3, -0.22), vec2(-0.33, 0.36), up);
        vec2 hr = mix(vec2(0.3, -0.22), vec2(0.33, 0.36), up);
        col = mix(col, dark * 2.2, fill(sdSeg(q, vec2(-0.18, 0.02), hl) - 0.055, w));
        col = mix(col, dark * 2.2, fill(sdSeg(q, vec2(0.18, 0.02), hr) - 0.055, w));

        col = mix(col, fur, fill(sdEllipse(q - vec2(0.0, -0.18), vec2(0.25, 0.3)), w));
        col = mix(col, fur * 0.72, fill(sdEllipse(q - vec2(0.0, -0.25), vec2(0.14, 0.19)), w));
        col = mix(col, dark, fill(sdCircle(vec2(abs(q.x), q.y) - vec2(0.14, 0.35), 0.055), w));

        // white head with the two black stripes running back over the eyes
        vec2 hq = q - vec2(0.0, 0.2);
        vec3 hc = white;
        float stripe = max(abs(abs(hq.x) - 0.085) - 0.038, -hq.y - 0.05);
        hc = mix(hc, dark, fill(stripe, w));
        col = mix(col, hc, fill(sdEllipse(hq, vec2(0.19, 0.17)), w));
        col = mix(col, white, fill(sdCircle(vec2(abs(hq.x), hq.y) - vec2(0.085, 0.0), 0.017), w));
        col = mix(col, dark, fill(sdEllipse(hq - vec2(0.0, -0.12), vec2(0.04, 0.028)), w));
    }

    void mushroomAt(inout vec3 col, vec2 p, float s) {
        vec2 q = p / s;
        float w = aaw(s);
        col = mix(col, vec3(0.97, 0.93, 0.82), fill(sdRoundBox(q - vec2(0.0, -0.17), vec2(0.12, 0.2), 0.06), w));
        float cap = max(sdEllipse(q - vec2(0.0, 0.0), vec2(0.4, 0.32)), -(q.y + 0.02));
        col = mix(col, vec3(0.86, 0.1, 0.12), fill(cap, w));
        for (int k = 0; k < 5; k++) {
            vec2 c = vec2(-0.24 + 0.12 * float(k), 0.1 + 0.07 * sin(float(k) * 2.3));
            col = mix(col, vec3(1.0), fill(sdCircle(q - c, 0.045), w) * fill(cap, w));
        }
    }

    void snakeAt(inout vec3 col, vec2 p, float rise) {
        float w = aaw(1.0);
        float headY = -0.5 + rise * (0.62 + uBass * 0.08);
        float sway = 0.07 * sin(p.y * 11.0 - uTime * 6.0);
        float body = max(abs(p.x - sway) - 0.045, p.y - headY);
        vec3 green = vec3(0.25, 0.7, 0.2);
        // zigzag markings along the body
        float marks = step(0.5, fract(p.y * 10.0 + (p.x - sway) * 6.0));
        col = mix(col, mix(green, green * 0.6, marks), fill(body, w));
        vec2 hp = vec2(0.07 * sin(headY * 11.0 - uTime * 6.0), headY);
        vec2 hq = p - hp;
        // flicking forked tongue
        float tl = 0.06 + 0.04 * step(0.5, fract(uTime * 3.0));
        float tongue = min(sdSeg(hq, vec2(0.0, 0.0), vec2(0.0, -tl - 0.04)),
                           sdSeg(hq, vec2(0.0, -tl - 0.04), vec2(0.02 * sign(hq.x), -tl - 0.07)));
        col = mix(col, vec3(0.9, 0.1, 0.15), fill(tongue - 0.006, w));
        col = mix(col, green * 1.1, fill(sdEllipse(hq, vec2(0.08, 0.06)), w));
        col = mix(col, vec3(1.0), fill(sdCircle(vec2(abs(hq.x), hq.y) - vec2(0.035, 0.015), 0.016), w));
        col = mix(col, vec3(0.0), fill(sdCircle(vec2(abs(hq.x), hq.y) - vec2(0.035, 0.015), 0.008), w));
    }

    uniform float uEventKind;   // 0 none, 1 mushroom, 2 snake (set on big beats)
    uniform float uEventAge;    // seconds since the event started

    void main() {
        vec2 p = screenP();
        float w = aaw(1.0);

        vec3 col = mix(vec3(0.6, 0.85, 1.0), vec3(0.25, 0.5, 0.95), p.y + 0.5);
        col = mix(col, vec3(1.0, 0.93, 0.5), fill(sdCircle(p - vec2(0.62, 0.32), 0.07 + uBass * 0.03), w));
        col = mix(col, vec3(0.38, 0.72, 0.32), fill(p.y - (-0.02 + 0.04 * sin(p.x * 3.0)), w));

        for (int r = 0; r < 3; r++) {
            float fr = float(r);
            float s = 0.2 + fr * 0.06;
            float y = 0.0 - fr * 0.17;
            int n = 5 - r;
            for (int i = 0; i < 5; i++) {
                if (i >= n) break;
                float x = (float(i) - float(n - 1) * 0.5) * (0.4 + fr * 0.12);
                badgerAt(col, p, vec2(x, y), s, float(i) * 1.3 + fr * 0.7);
            }
            float grassTop = y - s * 0.32 + 0.012 * sin(p.x * 70.0 + fr);
            col = mix(col, vec3(0.27 + 0.05 * fr, 0.6 + 0.05 * fr, 0.24), fill(p.y - grassTop, w));
        }

        // Big-beat overlays, drawn over the badgers: pop in fast, hold, drop away.
        float env = smoothstep(0.0, 0.15, uEventAge) * (1.0 - smoothstep(1.3, 1.6, uEventAge));
        if (uEventKind > 0.5 && uEventKind < 1.5) {
            col = mix(col, vec3(1.0, 0.95, 0.97), 0.2 * env);
            mushroomAt(col, p - vec2(0.0, -0.08 - (1.0 - env) * 0.5), 0.55 + uBass * 0.1 + uBeatStrength * 0.1);
        } else if (uEventKind > 1.5) {
            snakeAt(col, p, env);
        }
        fragColor = vec4(col, 1.0);
    }
    """

    // MARK: - Whooping Llama

    static let llama = """
    void llamaAt(inout vec3 col, vec2 p, vec2 pos, float s, float ph, float seed) {
        vec2 q = (p - pos) / s;
        float w = aaw(s);
        float d = dance(ph);
        float g = groove();
        q.y -= abs(sin(uBeats * PI + ph * 0.35)) * 0.08 * g;   // hop on each beat
        vec3 wool = mix(vec3(0.97, 0.94, 0.88), vec3(0.72, 0.5, 0.32), step(0.6, seed));
        vec3 legC = wool * 0.8;

        // legs: the front pair kicks
        float kick = (d - 0.5) * 0.25 * g;
        float legs = min(min(sdSeg(q, vec2(-0.18, -0.1), vec2(-0.2, -0.42)),
                             sdSeg(q, vec2(-0.08, -0.1), vec2(-0.1, -0.42))),
                         min(sdSeg(q, vec2(0.1, -0.1), vec2(0.12 + kick, -0.42 + abs(kick) * 0.4)),
                             sdSeg(q, vec2(0.2, -0.1), vec2(0.22 - kick, -0.42 + abs(kick) * 0.4))));
        col = mix(col, legC, fill(legs - 0.035, w));

        // fluffy body with a striped blanket
        float body = sdEllipse(q - vec2(0.0, -0.04), vec2(0.3, 0.15));
        body = min(body, sdCircle(q - vec2(-0.3, 0.02), 0.05));   // tail
        col = mix(col, wool, fill(body, w));
        vec3 blanket = 0.5 + 0.5 * cos(PI * 2.0 * (floor(q.x * 14.0) * 0.17 + seed + vec3(0.0, 0.33, 0.67)));
        float bl = max(sdBox(q - vec2(-0.02, 0.03), vec2(0.16, 0.07)), body);
        col = mix(col, blanket, fill(bl, w));

        // swaying neck and head
        float sway = (d - 0.5) * 0.14 * g;
        vec2 top = vec2(0.24 + sway, 0.36);
        col = mix(col, wool, fill(sdSeg(q, vec2(0.2, 0.0), top) - 0.065, w));
        vec2 hq = q - top;
        col = mix(col, wool, fill(sdEllipse(hq - vec2(0.05, 0.0), vec2(0.11, 0.07)), w));
        vec2 eq = vec2(abs(hq.x + 0.01), hq.y) - vec2(0.04, 0.1);
        col = mix(col, wool * 0.85, fill(sdEllipse(rot(0.25) * eq, vec2(0.022, 0.06)), w));
        col = mix(col, vec3(0.05), fill(sdCircle(hq - vec2(0.04, 0.025), 0.014), w));

        // the whoop: mouth opens and sound rings burst out on beats
        float whoop = smoothstep(0.35, 0.8, uBeatStrength);
        col = mix(col, vec3(0.25, 0.05, 0.08), fill(sdEllipse(hq - vec2(0.14, -0.03), vec2(0.03, 0.005 + 0.03 * whoop)), w));
        float ringR = 0.06 + (1.0 - uBeatStrength) * 0.3;
        float ring = abs(sdCircle(hq - vec2(0.16, -0.03), ringR)) - 0.008;
        ring = max(ring, -(hq.x - 0.16));      // only the half in front of the mouth
        col = mix(col, vec3(1.0, 0.95, 0.6), fill(ring, w) * whoop);
    }

    void main() {
        vec2 p = screenP();
        float w = aaw(1.0);
        // Andes sunset
        vec3 col = mix(vec3(1.0, 0.6, 0.35), vec3(0.35, 0.15, 0.5), p.y + 0.5);
        col = mix(col, vec3(1.0, 0.85, 0.5), fill(sdCircle(p - vec2(-0.45, 0.05), 0.1 + uBass * 0.04), w));
        float far = p.y - (0.02 + 0.12 * abs(fract(p.x * 1.3 + 0.2) - 0.5) * 2.0 * (0.6 + 0.4 * sin(p.x * 5.0)));
        col = mix(col, vec3(0.45, 0.25, 0.55), fill(far, w));
        float snow = max(far + 0.06, -(far + 0.0));
        col = mix(col, vec3(0.95, 0.9, 1.0), fill(snow, w) * step(0.09, p.y));
        float near = p.y - (-0.12 + 0.05 * sin(p.x * 4.0 + 1.0));
        col = mix(col, vec3(0.3, 0.55, 0.3), fill(near, w));

        for (int r = 0; r < 2; r++) {
            float fr = float(r);
            float s = 0.22 + fr * 0.08;
            float y = -0.05 - fr * 0.2;
            int n = 4 - r;
            for (int i = 0; i < 4; i++) {
                if (i >= n) break;
                float x = (float(i) - float(n - 1) * 0.5) * (0.42 + fr * 0.12);
                float seed = hash11(float(i) + fr * 10.0);
                llamaAt(col, p, vec2(x, y), s, float(i) * 1.7 + fr * 0.9, seed);
            }
        }
        fragColor = vec4(col, 1.0);
    }
    """

    // MARK: - Hamster Dance

    static let hamster = """
    void hamsterAt(inout vec3 col, vec2 q, float w, float kind, float ph) {
        float d = dance(ph);
        float g = groove();
        // four dance styles, picked per tile
        if (kind < 0.25)      q.y -= abs(sin(uBeats * PI + ph * 0.35)) * 0.15 * g;   // bounce
        else if (kind < 0.5)  q = rot(uTime * 3.0 + ph) * q;                        // spin
        else if (kind < 0.75) q.x -= (d - 0.5) * 0.25 * g;                          // shuffle
        else                  q = rot((d - 0.5) * 0.7 * g) * q;                     // wiggle

        vec3 fur = vec3(0.9, 0.6, 0.28), belly = vec3(1.0, 0.95, 0.85), pink = vec3(1.0, 0.65, 0.7);
        // feet and waving arms
        col = mix(col, pink, fill(sdEllipse(vec2(abs(q.x), q.y) - vec2(0.12, -0.3), vec2(0.07, 0.035)), w));
        float armUp = d * 0.18;
        col = mix(col, fur * 0.85, fill(sdSeg(vec2(abs(q.x), q.y), vec2(0.18, -0.05), vec2(0.3, 0.02 + armUp)) - 0.04, w));
        // round body, head blended in
        float body = min(sdCircle(q - vec2(0.0, -0.08), 0.24), sdCircle(q - vec2(0.0, 0.14), 0.19));
        col = mix(col, fur, fill(body, w));
        col = mix(col, belly, fill(sdEllipse(q - vec2(0.0, -0.1), vec2(0.15, 0.16)), w));
        col = mix(col, belly, fill(sdCircle(vec2(abs(q.x), q.y) - vec2(0.1, 0.08), 0.075), w));
        col = mix(col, pink, fill(sdCircle(vec2(abs(q.x), q.y) - vec2(0.13, 0.3), 0.06), w));
        col = mix(col, vec3(0.05), fill(sdCircle(vec2(abs(q.x), q.y) - vec2(0.07, 0.17), 0.028), w));
        col = mix(col, vec3(1.0), fill(sdCircle(vec2(abs(q.x), q.y) - vec2(0.062, 0.18), 0.009), w));
        col = mix(col, pink * 0.9, fill(sdEllipse(q - vec2(0.0, 0.11), vec2(0.025, 0.018)), w));
    }

    // User-supplied sprites (see SpriteAtlas); uSpriteKinds == 0 means draw our own.
    uniform sampler2DArray uSprites;
    uniform int uSpriteKinds;
    uniform float uSpriteFirst[16];
    uniform float uSpriteFrames[16];
    uniform float uSpriteDelay[16];

    uniform vec2 uSpriteCell;   // layer size in image pixels
    uniform float uSpriteClock; // GIF playback time, scaled to the detected BPM

    // Tile the user's GIFs edge to edge at their native pixels, scaled up by a
    // whole number so pixel art stays crisp. All tiles animate in sync like the
    // original page; the wall bounces and pumps with the music.
    void spriteWallpaper(inout vec3 col) {
        float scale = max(1.0, floor(uResolution.y / (uSpriteCell.y * 1.4)));
        vec2 px = (gl_FragCoord.xy - 0.5 * uResolution) / (scale * (1.0 + uBeatStrength * 0.04));
        px.y -= floor(abs(sin(uBeats * PI)) * uBass * uActive * 6.0);   // whole-pixel bounce per beat
        px += 0.5 * uSpriteCell;                                      // a tile sits centered
        vec2 cellId = floor(px / uSpriteCell);
        vec2 st = fract(px / uSpriteCell);
        int kind = int(mod(cellId.x + cellId.y, float(uSpriteKinds)));
        float frame = floor(mod(uSpriteClock / uSpriteDelay[kind], uSpriteFrames[kind]));
        vec4 c = texture(uSprites, vec3(st.x, 1.0 - st.y, uSpriteFirst[kind] + frame));
        col = col * (1.0 - c.a) + c.rgb;     // premultiplied alpha
    }

    void main() {
        vec2 p = screenP();
        float tile = 0.25;
        vec2 sp = p + vec2(uTime * 0.03, uTime * 0.02);   // slow scroll
        vec2 id = floor(sp / tile);
        vec2 q = (fract(sp / tile) - 0.5) * 1.0;
        float h = hash21(id);

        // pastel checkerboard that shifts hue on beats
        float checker = mod(id.x + id.y, 2.0);
        vec3 bg = 0.78 + 0.22 * cos(PI * 2.0 * (h * 0.3 + checker * 0.5 + uTime * 0.05 + vec3(0.0, 0.33, 0.67)));
        bg = mix(bg, vec3(1.0), 0.35 * uBeatStrength * checker);
        vec3 col = bg;
        if (uSpriteKinds > 0) {
            col = mix(vec3(1.0), vec3(1.0, 0.92, 0.97), uBeatStrength);   // white page, flashes on beats
            spriteWallpaper(col);
        } else {
            hamsterAt(col, q * 1.25, aaw(tile / 1.25), hash21(id + 7.0), h * 6.28);
        }
        fragColor = vec4(col, 1.0);
    }
    """

    // MARK: - Nyan Cat

    static let nyan = """
    const float PIX = 1.0 / 72.0;   // chunky pixel grid, in screen-height units

    void main() {
        vec2 p = screenP();
        vec2 q = (floor(p / PIX) + 0.5) * PIX;     // pixelate everything
        float step8 = floor(uBeats * 2.0);         // sprite steps twice per beat

        vec3 col = vec3(0.04, 0.2, 0.4);

        // stars rushing left, faster when louder
        vec2 sg = vec2(q.x + uScroll, q.y);
        vec2 sid = floor(sg / 0.16);
        vec2 sl = sg - (sid + 0.5) * 0.16;
        float sh = hash21(sid);
        if (sh > 0.55) {
            vec2 off = (vec2(hash21(sid + 3.0), hash21(sid + 9.0)) - 0.5) * 0.08;
            vec2 a = abs(sl - off);
            float tw = floor(mod(step8 + sh * 7.0, 4.0));
            float arm = PIX * (1.0 + tw);
            float star = (a.x < PIX * 0.6 && a.y < arm) || (a.y < PIX * 0.6 && a.x < arm) ? 1.0 : 0.0;
            col = mix(col, vec3(1.0), star);
        }

        float catX = 0.12;
        float bob = (mod(step8, 2.0) < 1.0 ? 0.0 : PIX) + floor(uBeatStrength * 3.0) * PIX;
        float cy = bob;

        // rainbow trail: six stripes, stepping up and down in 8-pixel segments
        float stripeH = PIX * (3.0 + floor(uBass * 3.0));
        // full-length trail while music plays; it grows out from the cat as
        // the music starts and shrinks back into it in silence
        float trail = uActive * 3.0;
        if (q.x < catX - 0.1 && q.x > catX - 0.1 - trail) {
            float seg = floor((catX - q.x) / (PIX * 8.0));
            float wave = mod(seg + step8, 2.0) < 1.0 ? 0.0 : PIX;
            float rel = (q.y - cy - wave + stripeH * 3.0) / stripeH;
            if (rel >= 0.0 && rel < 6.0) {
                int k = int(rel);
                vec3 c = k == 5 ? vec3(1.0, 0.0, 0.0) : k == 4 ? vec3(1.0, 0.6, 0.0) :
                         k == 3 ? vec3(1.0, 1.0, 0.0) : k == 2 ? vec3(0.2, 1.0, 0.0) :
                         k == 1 ? vec3(0.0, 0.6, 1.0) : vec3(0.4, 0.2, 1.0);
                col = mix(c, vec3(1.0), 0.25 * uBeatStrength);
            }
        }

        vec2 c = q - vec2(catX, cy);
        float legStep = mod(step8, 2.0) * PIX;
        // tail and legs (grey, black outline)
        float tail = sdBox(c - vec2(-0.13, 0.01 + legStep), vec2(PIX * 4.0, PIX * 1.0));
        float legs = min(min(sdBox(c - vec2(-0.08 + legStep, -0.09), vec2(PIX * 1.5)),
                             sdBox(c - vec2(-0.03 + legStep, -0.09), vec2(PIX * 1.5))),
                         min(sdBox(c - vec2(0.04 + legStep, -0.09), vec2(PIX * 1.5)),
                             sdBox(c - vec2(0.09 + legStep, -0.09), vec2(PIX * 1.5))));
        float limbs = min(tail, legs);
        if (limbs < PIX) col = vec3(0.0);
        if (limbs < 0.0) col = vec3(0.6);

        // pastry body: crust, frosting, sprinkles
        float crust = sdRoundBox(c, vec2(0.11, 0.085), PIX * 3.0);
        if (crust < PIX) col = vec3(0.0);
        if (crust < 0.0) col = vec3(1.0, 0.8, 0.6);
        float frost = sdRoundBox(c, vec2(0.09, 0.065), PIX * 3.0);
        if (frost < 0.0) {
            col = vec3(1.0, 0.6, 0.85);
            vec2 spid = floor(c / (PIX * 4.0));
            if (hash21(spid) > 0.8 && mod(floor(c.x / PIX) + floor(c.y / PIX), 2.0) < 1.0)
                col = vec3(1.0, 0.2, 0.6);
        }

        // head with ears, eyes, cheeks, mouth
        vec2 h = c - vec2(0.1, -0.02);
        float head = sdRoundBox(h, vec2(0.065, 0.05), PIX * 2.0);
        float ears = min(sdBox(h - vec2(-0.045, 0.055), vec2(PIX * 1.5, PIX * 2.0)),
                         sdBox(h - vec2(0.045, 0.055), vec2(PIX * 1.5, PIX * 2.0)));
        float cat = min(head, ears);
        if (cat < PIX) col = vec3(0.0);
        if (cat < 0.0) col = vec3(0.6);
        if (sdBox(vec2(abs(h.x), h.y) - vec2(0.028, 0.012), vec2(PIX * 1.0)) < 0.0) col = vec3(0.0);
        if (sdBox(vec2(abs(h.x), h.y) - vec2(0.045, -0.016), vec2(PIX * 1.0)) < 0.0) col = vec3(1.0, 0.6, 0.65);
        if (sdBox(h - vec2(0.0, -0.022), vec2(PIX * 2.0, PIX * 0.5)) < 0.0) col = vec3(0.0);

        fragColor = vec4(col, 1.0);
    }
    """
}

extension FunShaders {
    // MARK: - Spectrum (classic segmented LED bars)

    static let spectrum = """
    uniform float uPeaks[48];   // per-bar peak hold, decayed on the CPU

    void main() {
        vec2 uv = vUV;
        vec3 col = vec3(0.02, 0.02, 0.04) + vec3(0.08, 0.02, 0.1) * uBeatStrength;
        // faint grid
        vec2 gp = gl_FragCoord.xy / 24.0;
        float grid = max(step(0.95, fract(gp.x)), step(0.95, fract(gp.y)));
        col += vec3(0.03, 0.03, 0.06) * grid;

        const float BARS = 48.0;
        float peak = uPeaks[int(min(floor(uv.x * BARS), BARS - 1.0))] * (1.0 - 0.18 - 0.06);
        const float SEGS = 28.0;
        float base = 0.18;
        float bi = floor(uv.x * BARS);
        float bx = fract(uv.x * BARS);
        float v = max(bandAt(bi / BARS), bandAt((bi + 0.5) / BARS));
        float h = v * (1.0 - base - 0.06);
        if (bx > 0.12 && bx < 0.88) {
            float y = uv.y - base;
            float seg = floor(y / (1.0 / SEGS));
            float sy = fract(y * SEGS);
            float t = seg / SEGS / (1.0 - base);
            vec3 led = t < 0.55 ? mix(vec3(0.1, 1.0, 0.3), vec3(0.9, 1.0, 0.1), t / 0.55)
                                : mix(vec3(0.9, 1.0, 0.1), vec3(1.0, 0.15, 0.1), (t - 0.55) / 0.45);
            if (y >= 0.0 && sy < 0.75) {
                float lit = step(seg / SEGS, h);
                col = mix(col, led * (0.12 + 0.88 * lit), 1.0);
                // falling peak cap
                if (peak > 0.01 && seg == floor(peak * SEGS)) col = vec3(1.0);
            }
            // reflection
            float ry = base - uv.y;
            if (ry > 0.0 && ry < h * 0.5 && fract(ry * SEGS * 2.0) < 0.75) {
                col = mix(col, led * 0.6, 0.35 * (1.0 - ry / (h * 0.5 + 1e-4)));
            }
        }
        fragColor = vec4(col, 1.0);
    }
    """

    // MARK: - Kaleidoscope

    static let kaleidoscope = """
    void main() {
        vec2 p = screenP();
        p *= 1.15 - uBass * 0.3 - uBeatStrength * 0.15;     // punch in on the bass
        float r = length(p);
        float a = atan(p.y, p.x) + uTime * 0.12;
        float segs = 8.0;
        float seg = 2.0 * PI / segs;
        a = mod(a, seg);
        a = abs(a - seg * 0.5);
        vec2 k = vec2(cos(a), sin(a)) * r;
        k += vec2(0.35 + 0.1 * sin(uTime * 0.21), 0.2 * cos(uTime * 0.17));

        // kaliset fractal folds
        float acc = 0.0;
        float c = 0.78 + 0.12 * uMid;
        for (int i = 0; i < 9; i++) {
            k = abs(k) / dot(k, k) - c;
            acc += exp(-abs(length(k) - 0.6) * 6.0);
        }
        acc /= 9.0;
        // hue walks a full cycle every 16 beats
        vec3 col = 0.5 + 0.5 * cos(PI * 2.0 * (acc * 1.4 + uBeats / 16.0 + vec3(0.0, 0.33, 0.67)));
        col *= 0.25 + acc * (1.4 + uLevel * 1.2);
        col *= 0.8 + 1.2 * bandAt(clamp(r, 0.0, 1.0));       // rings glow with their band
        col += vec3(1.0, 0.8, 1.0) * uBeatStrength * 0.25 * exp(-r * 4.0);
        col *= smoothstep(1.2, 0.2, r);
        col = mix(vec3(0.05, 0.02, 0.08), col, uActive);   // flat single colour in silence
        fragColor = vec4(col, 1.0);
    }
    """

    // MARK: - Warp (hyperspace streaks)

    static let warp = """
    void main() {
        vec2 p = screenP();
        float r = length(p);
        float a = atan(p.y, p.x);
        vec3 col = vec3(0.01, 0.0, 0.03);
        float px = 1.5 / uResolution.y;

        for (int layer = 0; layer < 3; layer++) {
            float fl = float(layer);
            float N = 90.0 + fl * 40.0;
            float slot = floor((a + PI) / (2.0 * PI) * N);
            float h = hash11(slot * 1.37 + fl * 91.0);
            float ac = (slot + 0.5) / N * 2.0 * PI - PI;
            float z = fract(h * 7.31 + uTime * (0.22 + 0.08 * fl));
            float sr = z * z * 1.3 + 0.02;                     // accelerates outward
            float len = 0.01 + (0.04 + uLevel * 0.4 + uBeatStrength * 0.2) * z;
            float da = abs(a - ac) * r;
            float along = step(sr - len, r) * step(r, sr);
            float fade = smoothstep(sr - len, sr, r);
            float width = px * (0.6 + z * 2.5);
            float s = (1.0 - smoothstep(0.0, width, da)) * along * fade * z;
            // more stars when louder, none in silence
            s *= step(h, uActive * (0.15 + 0.85 * clamp(uLevel * 1.8, 0.0, 1.0)));
            vec3 tint = mix(vec3(0.7, 0.85, 1.0), vec3(1.0, 0.5, 0.9), clamp(uTreble * 2.0, 0.0, 1.0) * h);
            col += tint * s * 1.6;
        }
        // core glow and a shock ring on beats
        col += vec3(0.5, 0.3, 1.0) * exp(-r * 9.0) * (0.3 + uBass + uBeatStrength) * uActive;
        float ringR = (1.0 - uBeatStrength) * 0.9;
        col += vec3(0.8, 0.6, 1.0) * uBeatStrength * (1.0 - smoothstep(0.0, 0.015, abs(r - ringR))) * 0.6;
        fragColor = vec4(col, 1.0);
    }
    """
}

extension FunShaders {
    // MARK: - The Band (colour pixel art)

    /// Five pixel-art musicians on a theatre stage, in a warm Theme Hospital-ish
    /// palette, lead singer front and centre. uParts says who the sound
    /// classifier hears (0..1, smoothed);
    /// the playing motion follows the beat clock (uBeats) so it stays in time
    /// and fluid, and uHits / uPluck / uVocal / uKeys add accents. Anyone not
    /// heard fades back to a rest pose; in silence everyone does.
    static let band = """
    // -- Genre palette + motion (per-frame uniforms from Swift) --
    uniform int uGenre;             // Genre enum value: 0 classical … 9 ambient
    uniform int uGenrePrev;         // outgoing genre during a cross-fade
    uniform float uGenreMix;        // 0 = previous genre, 1 = current genre
    uniform vec3 uPrimary;          // primary colour: curtain, lights, foreground
    uniform vec3 uSecondary;        // secondary colour: floor, structural
    uniform vec3 uAccent;           // accent colour: highlights, instruments
    uniform float uBassReactivity;  // 0..1 — scales bass-driven deformation
    uniform float uTrebleReactivity;// 0..1 — scales treble-driven deformation
    uniform float uBeatSharpness;   // 0..1 — beat pulse sharpness
    uniform float uStrobeIntensity;  // 0..1 — strobe overlay opacity

    // -- Per-part + per-walker uniforms (from the Swift walker code) --
    uniform float uParts[5];   // drums, bass, guitar, keys, vocals
    uniform vec4 uHits;        // kick, snare, hi-hat, strum accents (smoothed)
    uniform float uPluck;      // bass pluck accent
    uniform float uVocal;      // vocal-range energy (smoothed)
    uniform float uKeys[9];    // keyboard: energy per pitch range, low to high
    // Walk-on / walk-off, per musician: 0 drums, 1 bass, 2 guitar, 3 keys,
    // 4 female singer, 5 male singer.
    uniform float uMX[6];      // current stage x (drummer: how far sunk behind the kit)
    uniform float uHome[6];    // their mark (kit and keyboard stay there)
    uniform float uWalk[6];    // walk cycle phase, or -1 when standing
    uniform float uFace[6];    // walking direction -1 / +1, 0 standing
    uniform float uPlay[6];    // how much they're playing right now
    uniform int uLineupMask;   // bit per slot (0 drums … 5 male singer) in the genre's usual line-up
    uniform float uPresent[6]; // 1 while that musician is on stage or walking on/off

    // Cheap "genre-named" colours in case the palette uniforms don't make it
    // (helps shaders run in isolation; always overridden at runtime). Hoisted
    // before the room functions and ink/paint helpers so all of them can
    // reference these constants in any order.
    const vec3 INK = vec3(0.14, 0.07, 0.10);
    const vec3 GENRE_RED    = vec3(0.62, 0.10, 0.14);
    const vec3 GENRE_BLACK  = vec3(0.04, 0.04, 0.06);
    const vec3 GENRE_GOLD   = vec3(0.95, 0.75, 0.25);
    const vec3 GENRE_CYAN   = vec3(0.18, 0.95, 1.00);
    const vec3 GENRE_MAGEN  = vec3(1.00, 0.18, 0.85);
    const vec3 GENRE_WHITE  = vec3(0.95, 0.95, 0.92);
    const vec3 GENRE_WOOD   = vec3(0.55, 0.33, 0.17);
    const vec3 GENRE_WOOD_D = vec3(0.32, 0.20, 0.10);
    const vec3 GENRE_AMBER  = vec3(0.90, 0.60, 0.25);
    const vec3 GENRE_AMBER_D= vec3(0.55, 0.30, 0.10);
    const vec3 GENRE_BROWN  = vec3(0.42, 0.24, 0.13);
    const vec3 GENRE_PURPLE = vec3(0.45, 0.18, 0.50);
    const vec3 GENRE_PURP_D = vec3(0.20, 0.08, 0.25);
    const vec3 GENRE_PINK   = vec3(0.95, 0.55, 0.85);
    const vec3 GENRE_BLUE_P = vec3(0.65, 0.75, 0.95);
    const vec3 GENRE_GOLD_C = vec3(0.92, 0.78, 0.30);
    const vec3 GENRE_AMBER_C= vec3(0.78, 0.55, 0.30);
    const vec3 SKIN_A = vec3(0.98, 0.80, 0.64);
    const vec3 SKIN_B = vec3(0.78, 0.55, 0.38);
    const vec3 SKIN_C = vec3(0.52, 0.33, 0.22);
    const float VH = 200.0;    // virtual screen height in art pixels

    // Drawing primitives used by every genre's room. Hoisted to the top
    // of the band body so the genre room functions can call them — the
    // original code defined them further down and the GLSL compiler doesn't
    // forward-reference function bodies.
    void ink(inout vec3 col, float d, vec3 c) { if (d < 1.0) col = INK; if (d < 0.0) col = c; }
    void paint(inout vec3 col, float d, vec3 c) { if (d < 0.0) col = c; }
    // Forward declarations for helpers defined further down the file.
    float swing(float ph);
    vec2 onGuitar(vec2 at, float ang, vec2 local);
    // Two-tone shading: darker on the right-hand side of a shape.
    vec3 lit(vec3 c, float x, float edge) { return x > edge ? c * 0.78 : c; }
    // Forward declarations for the person / arm / guitar / singer helpers
    // that are defined further down. GLSL doesn't need the body to be in
    // scope, only the signature.
    void person(inout vec3 col, vec2 p, vec3 skin, vec3 hair, vec3 shirt, vec3 pants,
                float style, float mouth, bool legs, bool female, bool dress, float tap,
                float walk, float look);
    void arm(inout vec3 col, vec2 p, vec2 s, vec2 h, float side, vec3 sleeve, vec3 skin);
    void guitar(inout vec3 col, vec2 p, vec2 at, float ang, float dir, float neckLen, vec3 inner, vec3 outer);
    void singer(inout vec3 col, vec2 v, int i, bool female, float voc, float sway);

    // Helper: floor under a stage. Two-tone wood with the secondary palette
    // colour as the dominant board.
    float floorStripes(float y, float vmin, float vmax) {
        if (y < vmin) {
            float row = floor(y / 7.0);
            float a = mod(row, 2.0) < 1.0 ? 1.0 : 0.7;
            return a;
        }
        return 1.0;
    }

    // ========== Room 1: CLASSICAL — concert hall ==========
    // Warm spotlights from above, four columns, marley floor, the band in formal
    // attire (black suits, white shirts). Strings sit on the bass/guitar slots
    // and bow with the beat.
    vec3 roomClassical(vec2 v, vec3 col) {
        // hall background — a tall dim wall behind the performers
        if (v.y > 30.0) {
            float cy = (v.y - 30.0) / 80.0;
            col = mix(vec3(0.30, 0.18, 0.10), vec3(0.10, 0.05, 0.03), cy);
        }
        // wooden marley floor
        if (v.y < -30.0) {
            float row = floor(v.y / 6.0);
            col = mod(row, 2.0) < 1.0 ? GENRE_WOOD : GENRE_WOOD_D;
            if (mod(v.y, 6.0) < 0.8) col = vec3(0.20, 0.10, 0.05);
        }
        // organ pipes across the upper wall, glinting with the bass
        if (v.y > 30.0 && v.y < 64.0) {
            float px = mod(v.x + 300.0, 10.0) - 5.0;
            float idx = floor((v.x + 300.0) / 10.0);
            float top = 36.0 + 20.0 * (0.5 + 0.5 * cos(idx * 0.42)) ;
            if (abs(px) < 3.5 && v.y < top) {
                col = px < -1.0 ? vec3(0.95, 0.82, 0.45) : (px < 1.5 ? vec3(0.78, 0.62, 0.28) : vec3(0.55, 0.40, 0.16));
                col *= 0.85 + 0.3 * uBass;
                if (abs(v.y - (top - 3.0)) < 0.8) col = vec3(0.20, 0.10, 0.05);   // pipe mouth
            }
        }
        // four columns at the back
        for (int i = 0; i < 4; i++) {
            float cx = (float(i) - 1.5) * 110.0;
            float c = sdBox(v - vec2(cx, 30.0), vec2(7.0, 60.0));
            ink(col, c, GENRE_GOLD_C);
            ink(col, max(c, abs(v.x - cx) - 6.0) - 1.0, GENRE_AMBER_C);
        }
        // spotlight cones from above
        for (int i = 0; i < 3; i++) {
            float cx = (float(i) - 1.0) * 130.0;
            float cone = max(abs(v.x - cx) - abs(v.y - 60.0) * 0.7, v.y - 60.0);
            if (cone < 0.0) col = mix(col, GENRE_GOLD_C, 0.10);
        }
        // gold valance at the top
        float valY = 64.0;
        if (v.y > valY) {
            // a gold trim band, then a dark coffered ceiling above it
            col = v.y < valY + 8.0 ? vec3(0.55, 0.42, 0.10) : mix(vec3(0.16, 0.09, 0.05), vec3(0.06, 0.03, 0.02), clamp((v.y - valY) / 60.0, 0.0, 1.0));
            if (v.y > valY + 8.0 && (mod(v.x, 40.0) < 1.0 || mod(v.y - valY, 20.0) < 1.0)) col *= 0.6;
        }
        if (abs(v.y - valY) < 1.5 || abs(v.y - valY - 8.0) < 1.0) col = GENRE_GOLD_C;
        return col;
    }

    // ========== Room 2: ELECTRONIC — DJ booth ==========
    // Dark room with neon strips, two turntables, a mixer, a single DJ. Beat
    // strobes pulse on every kick. Cyan/magenta dominates.
    vec3 roomElectronic(vec2 v, vec3 col) {
        // dark background
        if (v.y > 0.0) {
            col = mix(vec3(0.02, 0.01, 0.04), vec3(0.05, 0.02, 0.10), v.y / 100.0);
        }
        // floor
        if (v.y < 0.0) {
            float row = floor(v.y / 5.0);
            col = mod(row, 2.0) < 1.0 ? vec3(0.06, 0.04, 0.10) : vec3(0.10, 0.06, 0.16);
        }
        // neon strips on the back wall, vertical, alternating cyan/magenta
        for (int i = 0; i < 5; i++) {
            float cx = (float(i) - 2.0) * 80.0;
            float s = abs(v.x - cx) - 1.5;
            if (s < 0.0 && v.y > 0.0 && v.y < 60.0) {
                vec3 neon = mod(float(i), 2.0) < 1.0 ? GENRE_CYAN : GENRE_MAGEN;
                float pulse = 0.6 + 0.4 * sin(uTime * 6.0 + float(i));
                col = mix(col, neon, pulse);
            }
        }
        // LED wall: a grid of tiles lit as a spectrum, cyan to magenta
        if (v.y > 4.0 && v.y < 58.0) {
            vec2 cell = floor(vec2(v.x + 400.0, v.y - 4.0) / 6.0);
            vec2 inCell = mod(vec2(v.x + 400.0, v.y - 4.0), 6.0);
            float cols = 800.0 / 6.0;
            float level = bandAt(fract(cell.x / cols * 2.0)) * 9.0 * uActive;
            if (inCell.x > 0.8 && inCell.y > 0.8 && inCell.x < 5.2 && inCell.y < 5.2) {
                bool on = cell.y < level;
                vec3 led = mix(GENRE_CYAN, GENRE_MAGEN, clamp(cell.y / 8.0, 0.0, 1.0));
                col = on ? led : mix(col, led, 0.06);
            }
        }
        // ceiling strip
        if (v.y > 60.0 && v.y < 66.0) col = mix(GENRE_CYAN, GENRE_MAGEN, 0.5 + 0.5 * sin(uTime * 2.0));
        return col;
    }

    // ========== Room 3: ROCK — theatre (the original) ==========
    // Velvet curtain with a gold valance, wooden stage, amp stacks, full
    // 5-piece band. This branch is the long one because it was the first
    // and has the most detail.
    vec3 roomRock(vec2 v, vec3 col) {
        // red velvet curtain
        float fold = sin(v.x * 0.33);
        col = fold > 0.5 ? vec3(0.62, 0.10, 0.14) : (fold > -0.4 ? vec3(0.50, 0.07, 0.11) : vec3(0.36, 0.04, 0.08));
        float val = 78.0 + 5.0 * abs(sin(v.x * 0.105));
        if (v.y > val) col = mod(v.x, 10.0) < 1.0 ? vec3(0.40, 0.05, 0.09) : vec3(0.55, 0.08, 0.12);
        if (abs(v.y - val) < 1.5) col = vec3(0.95, 0.75, 0.25);
        // wooden stage
        float floorY = -40.0;
        if (v.y < floorY) {
            float row = floor(v.y / 7.0);
            col = mod(row, 2.0) < 1.0 ? GENRE_WOOD : GENRE_WOOD_D;
            if (mod(v.y, 7.0) < 1.0 || mod(v.x + row * 13.0, 36.0) < 1.0) col = vec3(0.38, 0.21, 0.11);
        }
        if (abs(v.y - floorY) < 1.0) col = vec3(0.30, 0.15, 0.08);
        float edgeY = -88.0;
        if (v.y < edgeY) col = vec3(0.10, 0.05, 0.07);
        if (abs(v.y - edgeY) < 1.0) col = vec3(0.95, 0.75, 0.25);
        vec2 fl = vec2(mod(v.x, 30.0) - 15.0, v.y - (edgeY - 4.0));
        ink(col, sdEllipse(fl, vec2(4.0, 2.5)), vec3(1.0, 0.88, 0.45));
        // amp stacks
        for (int side = -1; side <= 1; side += 2) {
            vec2 a = v - vec2(float(side) * 232.0, -10.0);
            for (int k = 0; k < 2; k++) {
                vec2 c = a - vec2(0.0, k == 0 ? -22.0 : 6.0);
                float box = sdRoundBox(c, vec2(24.0, 13.0), 2.0);
                vec3 grille = mod(floor(c.x) + floor(c.y), 2.0) < 1.0 ? vec3(0.16, 0.15, 0.16) : vec3(0.22, 0.21, 0.22);
                grille *= 1.0 + uBass * 0.35 * uActive;
                ink(col, box, grille);
                if (box < 0.0 && abs(c.y - 10.0) < 1.0) col = vec3(0.85, 0.68, 0.25);
            }
        }
        return col;
    }

    // ========== Room 4: POP — clean studio ==========
    // Pink/purple gradient backdrop, a single mic on a stand, clean floor.
    vec3 roomPop(vec2 v, vec3 col) {
        if (v.y > 0.0) {
            // gradient from purple at top to pink at floor
            col = mix(vec3(0.42, 0.25, 0.55), vec3(0.95, 0.65, 0.85), clamp(1.0 - v.y / 80.0, 0.0, 1.0));
        }
        if (v.y < 0.0) {
            // glossy white floor
            col = mix(vec3(0.85, 0.85, 0.88), vec3(0.70, 0.70, 0.75), abs(v.y) / 30.0);
            if (mod(v.y, 8.0) < 1.0) col *= 0.9;
        }
        // twinkling star lights across the backdrop, blinking in time
        if (v.y > 6.0) {
            vec2 cell = floor(v / 14.0);
            vec2 sp = mod(v, 14.0) - 7.0 + (vec2(hash21(cell), hash21(cell + 3.1)) - 0.5) * 8.0;
            float on = step(0.5, fract(hash21(cell + 7.7) + floor(uBeats) * 0.37));
            float star = min(abs(sp.x) + abs(sp.y) * 3.0, abs(sp.y) + abs(sp.x) * 3.0);
            if (star < 2.0 && on > 0.5) col = mix(col, vec3(1.0, 0.95, 1.0), 0.85);
        }
        return col;
    }

    // ========== Room 5: HIP-HOP — urban ==========
    // Brick wall, gold chain curtain, low-rider, single MC at the mic and
    // a DJ behind decks. Heavy bass-driven low-end rumble.
    vec3 roomHipHop(vec2 v, vec3 col) {
        // brick wall above
        if (v.y > 0.0) {
            float bx = mod(v.x, 18.0);
            float by = mod(v.y, 9.0);
            float brick = step(9.0, mod(v.y, 18.0)) > 0.5 ? bx - 9.0 : bx;
            col = vec3(0.32, 0.14, 0.10);
            if (bx < 0.8 || by < 0.8) col = vec3(0.18, 0.08, 0.06);
        }
        if (v.y < 0.0) {
            // dark concrete floor
            col = mix(vec3(0.06, 0.05, 0.04), vec3(0.02, 0.02, 0.02), abs(v.y) / 30.0);
        }
        // graffiti: bubbly tags with drips, in the palette colours
        for (int i = 0; i < 4; i++) {
            float fi = float(i);
            vec2 c = vec2(-180.0 + fi * 120.0, 30.0 + 10.0 * sin(fi * 2.1));
            vec3 paint1 = i % 2 == 0 ? uPrimary : uAccent;
            float tag = 1e3;
            for (int j = 0; j < 4; j++) {
                float fj = float(j);
                tag = min(tag, sdCircle(v - c - vec2(fj * 11.0 - 16.0, 4.0 * sin(fj * 1.7 + fi)), 7.0 - mod(fj, 2.0)));
            }
            if (v.y > 0.0) {
                ink(col, tag, paint1);
                if (tag < -3.5) col = mix(paint1, vec3(1.0), 0.5);   // highlight
                float drip = abs(v.x - c.x - 6.0) - 0.8;
                if (drip < 0.0 && v.y < c.y - 6.0 && v.y > c.y - 16.0 - 4.0 * fi) col = paint1;
            }
        }
        return col;
    }

    // ========== Room 6: JAZZ — smoky club ==========
    // Dim purple/amber. Single spotlight, smoke particles, upright bass, sax.
    vec3 roomJazz(vec2 v, vec3 col) {
        // smoky background
        if (v.y > 0.0) {
            col = mix(vec3(0.20, 0.10, 0.15), vec3(0.05, 0.02, 0.05), v.y / 100.0);
        }
        if (v.y < 0.0) {
            col = mix(vec3(0.30, 0.18, 0.12), vec3(0.10, 0.05, 0.04), abs(v.y) / 30.0);
        }
        // spotlight from above
        float spotX = 0.0;
        float spotD = max(abs(v.x - spotX) - abs(v.y - 50.0) * 0.5, v.y - 50.0);
        if (spotD < 0.0) col = mix(col, GENRE_AMBER, 0.30);
        // drifting cigarette smoke
        float smoke = sin(v.x * 0.03 + uTime * 0.3 + sin(v.y * 0.05)) * sin(v.y * 0.04 - uTime * 0.2);
        if (v.y > 0.0) col = mix(col, vec3(0.55, 0.45, 0.50), smoothstep(0.55, 1.0, smoke) * 0.25);
        // little round tables with candles along the front
        for (int i = 0; i < 5; i++) {
            vec2 t = v - vec2(-200.0 + float(i) * 100.0, -93.0);
            float table = min(sdEllipse(t - vec2(0.0, 8.0), vec2(16.0, 3.0)), sdBox(t, vec2(1.5, 8.0)));
            if (table < 0.0) col = vec3(0.04, 0.02, 0.03);
            float flame = sdEllipse(t - vec2(0.0, 13.0 + 0.5 * sin(uTime * 9.0 + float(i))), vec2(1.0, 1.8));
            if (flame < 0.0) col = vec3(1.0, 0.75, 0.30);
        }
        return col;
    }

    // ========== Room 7: BLUES — bar ==========
    // Wood, neon "BAR" sign, a bottle, dim amber.
    vec3 roomBlues(vec2 v, vec3 col) {
        // wood wall
        col = vec3(0.30, 0.18, 0.10);
        if (mod(v.x, 16.0) < 0.8) col = vec3(0.18, 0.10, 0.06);
        if (mod(v.y, 24.0) < 0.8) col = vec3(0.18, 0.10, 0.06);
        // neon sign: a guitar in a rounded frame, flickering with the beat
        {
            vec2 n = v - vec2(140.0, 42.0);
            float flick = 0.75 + 0.25 * step(0.15, fract(uBeats * 0.5 + 0.1));
            vec3 red = vec3(1.0, 0.25, 0.20) * flick, blue = vec3(0.35, 0.55, 1.0) * flick;
            float frame = abs(sdRoundBox(n, vec2(26.0, 16.0), 5.0)) - 0.9;
            if (frame < 0.0) col = blue;
            float gtr = abs(min(sdCircle(n - vec2(-6.0, -4.0), 6.0), sdCircle(n - vec2(1.0, 0.0), 4.5))) - 0.8;
            gtr = min(gtr, sdSeg(n, vec2(4.0, 3.0), vec2(18.0, 11.0)) - 0.8);
            if (gtr < 0.0) col = red;
            if (min(frame, gtr) < 2.5 && min(frame, gtr) >= 0.0) col = mix(col, red, 0.15);   // glow
        }
        // bar counter
        if (v.y < -10.0 && v.y > -22.0) {
            col = vec3(0.20, 0.10, 0.05);
            if (mod(v.x, 30.0) < 0.8) col = vec3(0.10, 0.05, 0.02);
        }
        return col;
    }

    // ========== Room 8: COUNTRY — porch ==========
    // Wood floor, daylight, an old window, simple. Warm and friendly.
    vec3 roomCountry(vec2 v, vec3 col) {
        // sky behind
        if (v.y > 30.0) {
            col = mix(vec3(0.65, 0.80, 0.95), vec3(0.95, 0.85, 0.65), 1.0 - v.y / 100.0);
        }
        if (v.y < 30.0 && v.y > 0.0) {
            // sunlit wood wall
            col = mix(vec3(0.55, 0.36, 0.20), vec3(0.70, 0.48, 0.28), 1.0 - v.y / 30.0);
            if (mod(v.x, 12.0) < 0.8) col = vec3(0.32, 0.20, 0.10);
        }
        if (v.y < 0.0) {
            col = mix(GENRE_WOOD, GENRE_WOOD_D, abs(v.y) / 30.0);
            if (mod(v.y, 8.0) < 0.8) col *= 0.7;
        }
        // a split-rail fence on the horizon and rolling hills behind it
        float hill = 34.0 + 6.0 * sin(v.x * 0.012) + 3.0 * sin(v.x * 0.031 + 1.0);
        if (v.y > 30.0 && v.y < hill) col = mix(vec3(0.45, 0.62, 0.30), vec3(0.62, 0.74, 0.40), (v.y - 30.0) / 10.0);
        if (v.y > 30.0 && v.y < 44.0) {
            if (mod(v.x, 40.0) < 2.0) col = vec3(0.40, 0.26, 0.14);
            if (abs(v.y - 36.0) < 0.8 || abs(v.y - 41.0) < 0.8) col = vec3(0.48, 0.32, 0.18);
        }
        // a window in the porch wall, glowing warm
        vec2 w = v - vec2(-160.0, 14.0);
        if (abs(w.x) < 13.0 && abs(w.y) < 10.0) {
            col = vec3(1.0, 0.88, 0.55);
            if (abs(w.x) < 0.8 || abs(w.y) < 0.8 || abs(w.x) > 11.5 || abs(w.y) > 8.5) col = vec3(0.30, 0.18, 0.10);
        }
        // hay bales stage left and right
        for (int i = -1; i <= 1; i += 2) {
            vec2 h = v - vec2(float(i) * 225.0, -48.0);
            float bale = sdRoundBox(h, vec2(18.0, 9.0), 2.0);
            ink(col, bale, vec3(0.88, 0.72, 0.35));
            if (bale < 0.0 && mod(h.x + h.y * 0.3, 4.0) < 0.8) col = vec3(0.72, 0.56, 0.22);
        }
        return col;
    }

    // ========== Room 9: R&B — velvet stage ==========
    // Purple velvet curtain, gold trim, multiple spotlights. Five-piece band.
    vec3 roomRNB(vec2 v, vec3 col) {
        // velvet curtain
        float fold = sin(v.x * 0.28);
        col = fold > 0.0 ? vec3(0.40, 0.15, 0.42) : vec3(0.28, 0.08, 0.30);
        // gold valance
        float val = 75.0;
        if (v.y > val) col = mix(GENRE_PURPLE, vec3(0.18, 0.05, 0.20), 0.3);
        if (abs(v.y - val) < 1.5) col = GENRE_GOLD_C;
        // gold tassels
        for (int i = 0; i < 12; i++) {
            float tx = (float(i) - 5.5) * 30.0;
            float tc = sdCircle(v - vec2(tx, val + 3.0), 2.0);
            if (tc < 0.0) col = GENRE_GOLD_C;
        }
        // floor
        if (v.y < -30.0) {
            col = mix(GENRE_WOOD, GENRE_WOOD_D, abs(v.y + 30.0) / 30.0);
        }
        // multiple soft spotlights
        for (int i = 0; i < 4; i++) {
            float sx = (float(i) - 1.5) * 90.0;
            float sd = max(abs(v.x - sx) - abs(v.y - 55.0) * 0.6, v.y - 55.0);
            if (sd < 0.0) col = mix(col, GENRE_GOLD_C, 0.10);
        }
        return col;
    }

    // ========== Room 10: AMBIENT — pure soundscape ==========
    // No stage, no band. Soft colour field that breathes with the bass, with
    // grainy nebula-like wisps in the treble. No lfbm — we use a few cheap
    // sine fields instead since the band prelude doesn't pull in the
    // FBM stack.
    vec3 roomAmbient(vec2 v, vec3 col) {
        // base colour: a slow, warm gradient driven by uTime
        vec3 a = mix(uPrimary, uSecondary, 0.5 + 0.5 * sin(uTime * 0.15));
        vec3 b = mix(uAccent, uPrimary, 0.5 + 0.5 * cos(uTime * 0.21));
        float t = clamp(v.y / 100.0, 0.0, 1.0);
        col = mix(b, a, t);
        // wisps: a few overlapping sine fields, weighted by treble
        float w1 = sin(v.x * 0.022 + uTime * 0.10) * cos(v.y * 0.018 - uTime * 0.07);
        float w2 = sin((v.x + v.y) * 0.014 + uTime * 0.05);
        float wisps = smoothstep(0.4, 0.9, w1 * 0.6 + w2 * 0.4) *
                      (0.4 + 0.6 * uTrebleReactivity * (0.3 + uTreble));
        col = mix(col, uAccent, wisps * 0.6);
        // bass breath: a soft radial pulse that grows with uBass
        float r = length(v - vec2(0.0, -10.0));
        float pulse = exp(-r * 0.018) * (0.4 + 0.6 * uBassReactivity * (0.3 + uBass));
        col += uAccent * pulse * 0.5;
        return col;
    }

    // Draw one genre's room. Split out from pickRoom so the cross-fade can
    // call it for two genres and blend the results.
    vec3 roomForGenre(int g, vec2 v) {
        vec3 col = vec3(0.02, 0.004, 0.03);
        if (g == 0)      { col = roomClassical(v, col);  }
        else if (g == 1) { col = roomElectronic(v, col); }
        else if (g == 2) { col = roomRock(v, col);      }
        else if (g == 3) { col = roomPop(v, col);       }
        else if (g == 4) { col = roomHipHop(v, col);    }
        else if (g == 5) { col = roomJazz(v, col);      }
        else if (g == 6) { col = roomBlues(v, col);     }
        else if (g == 7) { col = roomCountry(v, col);   }
        else if (g == 8) { col = roomRNB(v, col);       }
        else if (g == 9) { col = roomAmbient(v, col);   }
        return col;
    }

    // Top-level room dispatch, with a cross-fade when uGenre != uGenrePrev.
    vec3 pickRoom(vec2 v) {
        if (uGenrePrev == uGenre || uGenreMix >= 1.0) {
            return roomForGenre(uGenre, v);
        }
        vec3 from = roomForGenre(uGenrePrev, v);
        vec3 to = roomForGenre(uGenre, v);
        return mix(from, to, uGenreMix);
    }

    // Beat-strobe overlay drawn on top of any room when strobeIntensity is
    // high. A bright full-screen flash that fades with each beat.
    void strobeOverlay(vec2 v, inout vec3 col) {
        if (uStrobeIntensity < 0.05) return;
        // only on the downbeat: weight by the per-beat envelope
        float beat = fract(uBeats);
        float env = exp(-beat * 8.0) * smoothstep(0.0, 0.05, beat);
        col = mix(col, mix(uPrimary, uAccent, 0.5), env * uStrobeIntensity * 0.65);
    }


    // ---------- Genre outfits & instruments ----------

    // Hats, drawn on a head whose centre is h (person-local p - (0, 50)).
    // kind: 0 none, 1 cowboy, 2 fedora, 3 cap, 4 beret, 5 visor shades
    void hat(inout vec3 col, vec2 h, float kind, vec3 c) {
        if (kind < 0.5) return;
        if (kind < 1.5) {
            ink(col, sdEllipse(h - vec2(0.0, 5.5), vec2(15.0, 2.2)), c * 0.85);
            ink(col, sdRoundBox(h - vec2(0.0, 9.5), vec2(7.0, 4.5), 2.5), c);
            paint(col, sdBox(h - vec2(0.0, 6.8), vec2(7.0, 0.8)), c * 0.55);
        } else if (kind < 2.5) {
            ink(col, sdEllipse(h - vec2(0.0, 5.0), vec2(12.0, 1.8)), c * 0.85);
            ink(col, sdRoundBox(h - vec2(0.0, 9.0), vec2(7.5, 4.0), 2.0), c);
            paint(col, sdBox(h - vec2(0.0, 6.5), vec2(7.5, 1.0)), vec3(0.60, 0.12, 0.12));
        } else if (kind < 3.5) {
            ink(col, max(sdCircle(h - vec2(0.0, 2.0), 9.0), -(h.y - 4.0)), c);
            ink(col, sdEllipse(h - vec2(8.5, 4.0), vec2(6.0, 1.5)), c * 0.8);
        } else if (kind < 4.5) {
            ink(col, sdEllipse(h - vec2(-1.5, 8.0), vec2(9.5, 3.5)), c);
        } else {
            ink(col, sdRoundBox(h - vec2(0.0, 0.3), vec2(7.0, 1.8), 1.0), c);
        }
    }

    // Per-genre outfit for a slot: shirt, pants, hair colour, hair style,
    // hat kind, hat colour, and extras (x: gold chain, y: shirt-front stripe,
    // z: sparkles, w: check pattern).
    struct Outfit { vec3 shirt; vec3 pants; vec3 hair; float style; float hatKind; vec3 hatCol; vec4 extra; };

    Outfit outfit(int g, int slot) {
        // rock defaults (the theatre band)
        vec3 shirts[6] = vec3[6](vec3(0.95, 0.85, 0.30), vec3(0.25, 0.55, 0.85), vec3(0.20, 0.60, 0.45),
                                 vec3(0.65, 0.35, 0.85), vec3(0.45, 0.15, 0.42), vec3(0.16, 0.16, 0.19));
        vec3 hairs[6] = vec3[6](vec3(0.20, 0.12, 0.08), vec3(0.10, 0.07, 0.06), vec3(0.62, 0.24, 0.10),
                                vec3(0.20, 0.12, 0.08), vec3(0.95, 0.85, 0.55), vec3(0.28, 0.16, 0.08));
        float styles[6] = float[6](1.0, 2.0, 3.0, 4.0, 3.0, 2.0);
        Outfit o = Outfit(shirts[slot], vec3(0.22, 0.24, 0.40), hairs[slot], styles[slot], 0.0, vec3(0.0), vec4(0.0));
        if (slot == 3) o.style = 4.0;
        if (g == 0) {            // classical: black tails, white shirt fronts
            o.shirt = vec3(0.07, 0.07, 0.09); o.pants = vec3(0.05);
            if (slot == 2 || slot == 4) o.shirt = vec3(0.42, 0.05, 0.10);   // the women in deep red
            o.extra.y = (slot == 2 || slot == 4) ? 0.0 : 1.0;
            if (slot == 3) o.style = 2.0;
        } else if (g == 1) {     // electronic: black with neon trim, visor shades
            o.shirt = vec3(0.06, 0.06, 0.09); o.pants = vec3(0.04);
            o.hatKind = 5.0; o.hatCol = uAccent; o.extra.y = 2.0;
            if (slot == 3) o.style = 0.0;
        } else if (g == 3) {     // pop: bright pastels with sparkles
            o.shirt = mix(uPrimary, vec3(1.0), 0.35 + 0.1 * float(slot % 3));
            o.pants = mix(uSecondary, vec3(1.0), 0.3); o.extra.z = 1.0;
            if (slot == 3) o.style = 3.0;
        } else if (g == 4) {     // hip-hop: hoodies, caps, chains
            o.shirt = mix(uSecondary, vec3(0.15), 0.3 + 0.2 * float(slot % 2));
            o.pants = vec3(0.12, 0.12, 0.14); o.hatKind = slot == 4 ? 0.0 : 3.0;
            o.hatCol = mix(uPrimary, uAccent, float(slot % 2)); o.extra.x = 1.0;
        } else if (g == 5) {     // jazz: suits, berets and fedoras
            o.shirt = slot % 2 == 0 ? vec3(0.18, 0.12, 0.22) : vec3(0.12, 0.12, 0.18);
            if (slot == 2 || slot == 4) o.shirt = vec3(0.50, 0.12, 0.25);
            o.pants = vec3(0.08); o.hatKind = slot == 3 ? 4.0 : (slot == 1 ? 2.0 : 0.0);
            o.hatCol = vec3(0.12, 0.10, 0.12); o.extra.y = slot == 1 || slot == 3 ? 1.0 : 0.0;
        } else if (g == 6) {     // blues: fedoras and waistcoats
            o.shirt = vec3(0.30, 0.20, 0.12); o.pants = vec3(0.14, 0.12, 0.12);
            o.hatKind = slot == 2 || slot == 4 ? 0.0 : 2.0; o.hatCol = vec3(0.20, 0.16, 0.12);
            if (slot == 2 || slot == 4) o.shirt = vec3(0.25, 0.30, 0.55);
        } else if (g == 7) {     // country: cowboy hats and check shirts
            o.shirt = slot % 2 == 0 ? vec3(0.70, 0.18, 0.15) : vec3(0.20, 0.35, 0.60);
            o.pants = vec3(0.22, 0.30, 0.52); o.hatKind = 1.0;
            o.hatCol = slot % 2 == 0 ? vec3(0.62, 0.42, 0.22) : vec3(0.92, 0.88, 0.80);
            o.extra.w = 1.0;
            if (slot == 2 || slot == 4) o.shirt = vec3(0.85, 0.75, 0.55);
        } else if (g == 8) {     // R&B: purple and gold suits
            o.shirt = slot % 2 == 0 ? vec3(0.40, 0.12, 0.45) : vec3(0.85, 0.68, 0.25);
            o.pants = vec3(0.10, 0.05, 0.12); o.extra.x = slot == 5 ? 1.0 : 0.0;
        }
        return o;
    }

    // Outfit details over a drawn person (p = person-local, feet at origin).
    void outfitExtras(inout vec3 col, vec2 p, Outfit o) {
        if (o.extra.y > 1.5) {          // neon trim across the chest
            if (abs(p.y - 30.0) < 0.8 && abs(p.x) < 9.0) col = uAccent;
        } else if (o.extra.y > 0.5) {   // white shirt front + bow tie
            paint(col, sdBox(p - vec2(0.0, 32.0), vec2(2.5, 7.0)), vec3(0.95, 0.95, 0.92));
            paint(col, sdBox(p - vec2(0.0, 38.0), vec2(2.0, 0.8)), INK);
        }
        if (o.extra.x > 0.5) {          // gold chain
            float e = abs(sdEllipse(p - vec2(0.0, 35.0), vec2(5.0, 6.0)));
            if (e < 0.7 && p.y < 38.0) col = vec3(0.98, 0.80, 0.25);
        }
        if (o.extra.z > 0.5 && sdRoundBox(p - vec2(0.0, 29.0), vec2(10.0, 11.0), 4.0) < -0.5) {
            if (hash21(floor(p * 0.5) + floor(uBeats * 2.0)) > 0.86) col = vec3(1.0);   // sparkles, twinkling in time
        }
        if (o.extra.w > 0.5 && sdRoundBox(p - vec2(0.0, 29.0), vec2(10.0, 11.0), 4.0) < -0.5) {
            if (mod(floor(p.x / 3.0) + floor(p.y / 3.0), 2.0) < 1.0) col *= 0.75;      // check shirt
        }
        hat(col, p - vec2(0.0, 50.0), o.hatKind, o.hatCol);
    }

    // Standard musician: outfit, walking legs, look direction.
    void musician(inout vec3 col, vec2 p, Outfit o, vec3 skin, float mouth, bool female, float tap, float walk, float look) {
        person(col, p, skin, o.hair, o.shirt, o.pants, o.style, mouth, true, female, female, tap, walk, look);
        outfitExtras(col, p, o);
    }

    // Violin under the chin, bowed by the right hand (p = player-local).
    void violin(inout vec3 col, vec2 p, float saw, vec3 skin, vec3 sleeve) {
        arm(col, p, vec2(-9.0, 36.0), vec2(-19.0, 43.0), -1.0, sleeve, skin);
        vec2 q = rot(-0.35) * (p - vec2(-8.0, 40.0));
        ink(col, min(sdEllipse(q - vec2(-2.0, 0.0), vec2(5.0, 3.2)), sdEllipse(q - vec2(3.0, 0.0), vec2(4.0, 2.8))), vec3(0.62, 0.30, 0.10));
        ink(col, sdSeg(p, vec2(-12.0, 41.5), vec2(-22.0, 45.0)) - 0.9, vec3(0.20, 0.10, 0.05));
        vec2 hand = mix(vec2(2.0, 34.0), vec2(14.0, 30.0), saw);
        arm(col, p, vec2(9.0, 36.0), hand, 1.0, sleeve, skin);
        ink(col, sdSeg(p, hand, hand + vec2(-24.0, 8.0)) - 0.4, vec3(0.80, 0.70, 0.50));
    }

    // Cello / double bass standing in front of the player. bowed: classical.
    void bigString(inout vec3 col, vec2 p, bool bowed, float motion, vec3 skin, vec3 sleeve) {
        vec3 wood = bowed ? vec3(0.55, 0.25, 0.08) : vec3(0.45, 0.22, 0.10);
        ink(col, sdSeg(p, vec2(6.0, 0.0), vec2(6.0, 8.0)) - 0.6, vec3(0.5));
        float body = min(sdEllipse(p - vec2(6.0, 20.0), vec2(10.0, 11.0)), sdEllipse(p - vec2(6.0, 34.0), vec2(8.0, 7.5)));
        body = min(body, sdBox(p - vec2(6.0, 27.0), vec2(6.5, 4.0)));
        ink(col, body, wood);
        if (body < -1.0 && abs(abs(p.x - 6.0) - 4.0) < 0.6 && abs(p.y - 25.0) < 4.0) col = INK;   // f-holes
        ink(col, sdSeg(p, vec2(6.0, 40.0), vec2(6.0, 66.0)) - 1.1, vec3(0.15, 0.08, 0.04));
        ink(col, sdCircle(p - vec2(6.0, 68.0), 2.0), wood);
        arm(col, p, vec2(-9.0, 36.0), vec2(3.0, 56.0 - motion * 3.0), -1.0, sleeve, skin);
        vec2 hand = bowed ? mix(vec2(-4.0, 22.0), vec2(18.0, 24.0), motion) : vec2(10.0 + motion * 2.0, 26.0 - motion * 2.0);
        arm(col, p, vec2(9.0, 36.0), hand, 1.0, sleeve, skin);
        if (bowed) ink(col, sdSeg(p, hand + vec2(-10.0, 0.5), hand + vec2(12.0, -0.5)) - 0.4, vec3(0.80, 0.70, 0.50));
    }

    // Saxophone, played at the mouth (p = player-local).
    void sax(inout vec3 col, vec2 p, float fingers, vec3 skin, vec3 sleeve) {
        vec3 brass = vec3(0.92, 0.72, 0.28);
        ink(col, sdSeg(p, vec2(1.0, 45.0), vec2(4.0, 34.0)) - 1.2, brass);
        ink(col, sdSeg(p, vec2(4.0, 34.0), vec2(6.0, 18.0)) - 2.0, brass);
        ink(col, sdSeg(p, vec2(6.0, 18.0), vec2(12.0, 16.0)) - 2.6, brass);
        ink(col, sdSeg(p, vec2(12.0, 16.0), vec2(15.0, 24.0)) - 3.0, brass);
        ink(col, sdEllipse(p - vec2(15.5, 26.0), vec2(4.5, 1.6)), brass * 0.8);
        for (int k = 0; k < 4; k++) paint(col, sdCircle(p - vec2(6.6, 22.0 + float(k) * 4.0), 0.9), brass * 0.6);
        arm(col, p, vec2(-9.0, 36.0), vec2(3.0, 37.0 + fingers), -1.0, sleeve, skin);
        arm(col, p, vec2(9.0, 36.0), vec2(8.0, 26.0 - fingers), 1.0, sleeve, skin);
    }

    // Keyboard-slot instruments, centred on k (keyboard-local, floor at 0).
    // kind: 0 synth on X-stand, 1 grand piano, 2 upright piano, 3 DJ decks
    void keysInstrument(inout vec3 col, vec2 k, float kind, float pKe) {
        if (kind < 0.5) {
            ink(col, sdSeg(k, vec2(-15.0, 0.0), vec2(15.0, 27.0)) - 0.8, vec3(0.70, 0.70, 0.75));
            ink(col, sdSeg(k, vec2(15.0, 0.0), vec2(-15.0, 27.0)) - 0.8, vec3(0.70, 0.70, 0.75));
            ink(col, sdBox(k - vec2(0.0, 29.0), vec2(20.0, 3.5)), vec3(0.20, 0.20, 0.23));
        } else if (kind < 1.5) {
            ink(col, sdSeg(k, vec2(-22.0, 0.0), vec2(-22.0, 22.0)) - 1.2, vec3(0.05));
            ink(col, sdSeg(k, vec2(22.0, 0.0), vec2(22.0, 22.0)) - 1.2, vec3(0.05));
            ink(col, sdSeg(k, vec2(-26.0, 38.0), vec2(24.0, 54.0)) - 1.0, vec3(0.06));   // raised lid
            ink(col, sdRoundBox(k - vec2(0.0, 29.0), vec2(28.0, 6.0), 2.0), vec3(0.06, 0.06, 0.08));
            if (abs(k.y - 34.5) < 0.6 && abs(k.x) < 27.0) col = vec3(0.30);
        } else if (kind < 2.5) {
            ink(col, sdRoundBox(k - vec2(0.0, 22.0), vec2(24.0, 22.0), 2.0), vec3(0.38, 0.20, 0.10));
            ink(col, sdBox(k - vec2(0.0, 33.0), vec2(22.0, 3.0)), vec3(0.30, 0.15, 0.08));
            paint(col, sdBox(k - vec2(0.0, 16.0), vec2(18.0, 8.0)), vec3(0.32, 0.17, 0.08));
        } else {
            // DJ table with two turntables and a mixer
            ink(col, sdBox(k - vec2(0.0, 14.0), vec2(34.0, 14.0)), vec3(0.08, 0.08, 0.10));
            if (abs(k.y - 20.0) < 0.6 && abs(k.x) < 33.0) col = uAccent;
            for (int s2 = -1; s2 <= 1; s2 += 2) {
                vec2 t = k - vec2(float(s2) * 17.0, 30.0);
                ink(col, sdEllipse(t, vec2(12.0, 3.0)), vec3(0.20));
                paint(col, sdEllipse(t, vec2(9.0, 2.2)), vec3(0.05));
                float spin = fract(uBeats * 0.5 * (s2 > 0 ? 1.0 : -1.0));
                if (sdEllipse(t, vec2(9.0, 2.2)) < 0.0 && abs(fract(atan(t.y * 4.0, t.x) / 6.2831 + spin) - 0.5) < 0.04) col = vec3(0.55);
                paint(col, sdEllipse(t, vec2(1.5, 0.6)), uPrimary);
            }
            ink(col, sdBox(k - vec2(0.0, 30.0), vec2(4.0, 2.5)), vec3(0.15));
            for (int j = 0; j < 3; j++) if (sdCircle(k - vec2(-2.0 + float(j) * 2.0, 30.5), 0.6) < 0.0)
                col = bandAt(float(j) * 0.3 + 0.1) * pKe > 0.3 ? uAccent : vec3(0.3);
            return;
        }
        // keys: lit by pitch range
        vec2 kq = k - vec2(0.0, kind < 1.5 && kind > 0.5 ? 34.0 : (kind > 1.5 ? 36.0 : 30.0));
        if (abs(kq.x) < 18.0 && abs(kq.y) < 2.0) {
            float wk = floor((kq.x + 18.0) / 3.0);
            int ki = int(clamp(wk * 9.0 / 12.0, 0.0, 8.0));
            col = uKeys[ki] * pKe * uActive > 0.35 ? mix(uAccent, vec3(1.0), 0.3) : vec3(0.97, 0.96, 0.92);
            if (mod(kq.x + 18.0, 3.0) < 1.0) col = vec3(0.55, 0.55, 0.58);
            float m7 = mod(wk, 7.0);
            bool hasBlack = m7 == 0.0 || m7 == 1.0 || m7 == 3.0 || m7 == 4.0 || m7 == 5.0;
            if (kq.y > 0.0 && hasBlack && mod(kq.x + 18.0, 3.0) > 2.0) col = INK;
        }
    }

    // Drum-slot instruments around the riser (k = kit-local, riser top at 0).
    // kind: 0 kit, 1 timpani, 2 pad controller
    void drumInstrument(inout vec3 col, vec2 k, float kind, float kick, float pDr, vec3 shellCol, vec3 metal) {
        if (kind > 1.5) {
            ink(col, sdBox(k - vec2(0.0, 12.0), vec2(26.0, 12.0)), vec3(0.08, 0.08, 0.10));
            ink(col, sdBox(k - vec2(0.0, 25.0), vec2(16.0, 2.0)), vec3(0.18));
            for (int j = 0; j < 4; j++) {
                vec2 pc = k - vec2(-10.5 + float(j) * 7.0, 25.5);
                float lit = (j % 2 == 0 ? uHits.x : uHits.y) * pDr;
                paint(col, sdBox(pc, vec2(2.6, 1.0)), lit > 0.3 ? uAccent : vec3(0.35));
            }
            return;
        }
        if (kind > 0.5) {
            for (int s2 = -1; s2 <= 1; s2 += 2) {
                vec2 t = k - vec2(float(s2) * 18.0, 12.0);
                float bowl = max(sdEllipse(t, vec2(14.0, 12.0)), t.y);
                ink(col, bowl, vec3(0.78, 0.46, 0.22));
                ink(col, sdEllipse(t, vec2(14.0, 2.5 + floor((s2 < 0 ? uHits.x : uHits.y) * pDr))), vec3(0.95, 0.92, 0.82));
                ink(col, sdSeg(t, vec2(-8.0, -11.0), vec2(-10.0, -12.0)) - 0.6, vec3(0.3));
            }
            return;
        }
        for (int s2 = -1; s2 <= 1; s2 += 2) {
            float sx = float(s2) * 30.0;
            if (abs(k.x - sx) < 0.6 && k.y > -4.0 && k.y < 38.0) col = vec3(0.70, 0.70, 0.75);
        }
        float rideTilt = 0.25 + uHits.z * pDr * 0.15;
        ink(col, sdEllipse(k - vec2(-30.0, 33.0), vec2(10.0, 2.0)), metal);
        ink(col, sdEllipse(rot(rideTilt) * (k - vec2(30.0, 38.0)), vec2(12.0, 2.0)), metal);
        ink(col, sdBox(k - vec2(-16.0, 19.0), vec2(8.0, 3.0)), vec3(0.62, 0.62, 0.68));
        ink(col, sdEllipse(k - vec2(-16.0, 22.0), vec2(8.0, 2.5)), vec3(0.92, 0.92, 0.95));
        ink(col, sdBox(k - vec2(13.0, 25.0), vec2(7.0, 3.5)), shellCol);
        ink(col, sdEllipse(k - vec2(13.0, 28.5), vec2(7.0, 2.2)), vec3(0.92, 0.88, 0.80));
        float br = 15.0 + floor(kick * pDr * 1.5);
        ink(col, sdCircle(k - vec2(0.0, 10.0), br), shellCol);
        paint(col, sdCircle(k - vec2(0.0, 10.0), br - 2.5), vec3(0.96, 0.92, 0.82));
        ink(col, sdCircle(k - vec2(0.0, 10.0), 4.0), metal);
    }

    void main() {
        float scale = max(1.0, floor(min(uResolution.y / VH, uResolution.x / 440.0)));
        vec2 v = floor((gl_FragCoord.xy - 0.5 * uResolution) / scale) + 0.5;
        // When the width limits the scale there's spare height: keep the stage
        // front near the bottom and give the extra room to the curtain above.
        v.y += max(0.0, floor(uResolution.y / scale * 0.5 - 108.0));

        // uPlay: singers and guitarists play as they walk; drums and keys at their instrument.
        float pDr = uPlay[0], pBa = uPlay[1], pGu = uPlay[2], pKe = uPlay[3];
        float beat = uBeats;
        float ph = fract(beat);
        float ph8 = fract(beat * 2.0);
        bool snareBeat = mod(floor(beat), 2.0) > 0.5;
        bool kickBeat = !snareBeat;
        float kick = max(kickBeat ? exp(-ph * 7.0) : 0.0, uHits.x) * uActive;

        // Room
        vec3 col = pickRoom(v);

        // Beat strobe on top of the room for electronic / metal
        strobeOverlay(v, col);

        vec3 roomCol = col;
        int G = uGenre;
        float accent = uHits.x * step(0.6, uHits.x);

        // Instruments per genre for the drum / keys / guitar / bass slots.
        float drumKind = G == 0 ? 1.0 : ((G == 1 || G == 4) ? 2.0 : 0.0);          // kit, timpani, pads
        float keysKind = G == 0 ? 1.0 : ((G == 5 || G == 6 || G == 7) ? 2.0 : ((G == 1 || G == 4) ? 3.0 : 0.0));
        bool violinSlot = G == 0, saxSlot = G == 5;
        bool cello = G == 0, upright = G == 5 || G == 7;
        vec3 shell = G == 2 ? vec3(0.75, 0.10, 0.15) : mix(uPrimary, vec3(0.1), 0.35);
        vec3 metal = vec3(0.95, 0.78, 0.32);

        // --- drums: rise up from behind the kit, sink back at the end
        {
            Outfit o = outfit(G, 0);
            vec2 d = v - vec2(0.0, -26.0 - floor(uMX[0]));
            bool aboveRiser = v.y > -21.5;
            if (aboveRiser) {
                person(col, d, SKIN_B, o.hair, o.shirt, o.pants, o.style, 0.0, false, false, false, 0.0, -1.0, 0.0);
                outfitExtras(col, d, o);
            }
            // Gear only for slots in this genre's line-up, or someone who's actually out.
            bool gear = (uLineupMask & 1) != 0 || uPresent[0] > 0.5;
            if (G != 9 && gear) {
                ink(col, sdBox(v - vec2(0.0, -30.0), vec2(52.0, 9.0)), mix(uSecondary, vec3(0.30, 0.18, 0.10), 0.5));
                if (abs(v.y + 21.5) < 1.0 && abs(v.x) < 51.0) col = mix(uAccent, vec3(0.7, 0.46, 0.26), 0.5);
            }
            if (gear) drumInstrument(col, v - vec2(0.0, -26.0), drumKind, kick, pDr, shell, metal);
            if (aboveRiser) {
                float lUp = snareBeat ? swing(ph) : 1.0 - smoothstep(0.7, 1.0, ph);
                float rUp = swing(ph8);
                vec2 lh, rh;
                if (drumKind > 1.5) {          // tapping pads
                    lh = mix(vec2(-10.0, 22.0), vec2(-8.0, 26.0 + (1.0 - uHits.x) * 3.0), pDr);
                    rh = mix(vec2(10.0, 22.0), vec2(8.0, 26.0 + (1.0 - uHits.y) * 3.0), pDr);
                } else if (drumKind > 0.5) {   // timpani mallets, alternating
                    lh = mix(vec2(-12.0, 24.0), vec2(-18.0, 16.0 + lUp * 8.0), pDr);
                    rh = mix(vec2(12.0, 24.0), vec2(18.0, 16.0 + rUp * 8.0), pDr);
                } else {
                    lh = mix(vec2(-12.0, 24.0), vec2(-15.0, 25.0 + lUp * 9.0), pDr);
                    rh = mix(vec2(12.0, 24.0), vec2(24.0, 41.0 + rUp * 7.0), pDr);
                }
                arm(col, d, vec2(-9.0, 34.0), lh, -1.0, o.shirt, SKIN_B);
                arm(col, d, vec2(9.0, 34.0), rh, 1.0, o.shirt, SKIN_B);
                if (drumKind < 1.5) {
                    vec3 stick = drumKind > 0.5 ? vec3(0.95) : vec3(0.90, 0.80, 0.55);
                    ink(col, sdSeg(d, lh, lh + vec2(-5.0, -4.0 + lUp * 2.0)) - 0.6, stick);
                    ink(col, sdSeg(d, rh, rh + vec2(6.0, -3.0 + rUp * 2.0)) - 0.6, stick);
                }
            }
        }

        // --- keys (stage right): player a step upstage of the instrument
        {
            Outfit o = outfit(G, 3);
            float walk = uWalk[3];
            float bob = walk >= 0.0 ? floor(abs(sin(walk)) * 1.5) : 0.0;
            vec2 k = v - vec2(uMX[3], -60.0 + floor(swing(ph) * pKe) + bob);
            vec2 kb = v - vec2(uHome[3], -76.0);
            musician(col, k, o, SKIN_A, 0.0, false, 0.0, walk, uFace[3]);
            if ((uLineupMask & 8) != 0 || uPresent[3] > 0.5) keysInstrument(col, kb, keysKind, pKe);
            int loud = 0; float best = -1.0; int loudR = 4; float bestR = -1.0;
            for (int i = 0; i < 9; i++) {
                if (i < 5 && uKeys[i] > best) { best = uKeys[i]; loud = i; }
                if (i >= 4 && uKeys[i] > bestR) { bestR = uKeys[i]; loudR = i; }
            }
            float keysY = (keysKind > 2.5 ? 30.0 : (keysKind > 0.5 && keysKind < 1.5 ? 34.0 : (keysKind > 1.5 ? 36.0 : 30.0))) - 16.0;
            float lx = -18.0 + (float(loud) + 0.5) / 9.0 * 36.0;
            float rx = -18.0 + (float(loudR) + 0.5) / 9.0 * 36.0;
            if (keysKind > 2.5) { lx = -17.0 + sin(uBeats * PI * 2.0) * 3.0 * pKe; rx = 2.0; }   // scratch + fader
            float dip = swing(ph8) * 1.5;
            arm(col, k, vec2(-9.0, 36.0), mix(vec2(-11.0, 23.0), vec2(lx, keysY + dip), pKe), -1.0, o.shirt, SKIN_A);
            arm(col, k, vec2(9.0, 36.0), mix(vec2(11.0, 23.0), vec2(rx, keysY + 1.5 - dip), pKe), 1.0, o.shirt, SKIN_A);
        }

        // --- bass slot (stage left): electric bass, or cello / upright bass
        {
            Outfit o = outfit(G, 1);
            float walk = uWalk[1];
            float bob = walk >= 0.0 ? floor(abs(sin(walk)) * 1.5) : 0.0;
            float sway = floor(sin(beat * PI * 0.25) * 2.5 * pBa);
            vec2 b = v - vec2(uMX[1] + sway, -70.0 + bob);
            float tap = floor((1.0 - swing(ph)) * 2.0 * pBa);
            musician(col, b, o, SKIN_C, 0.0, false, tap, walk, uFace[1]);
            if (cello || upright) {
                bigString(col, b, cello, cello ? swing(ph) * pBa : (1.0 - swing(ph)) * pBa, SKIN_C, o.shirt);
            } else {
                float lean = floor(sin(beat * PI * 0.25 + 1.0) * 2.0 * pBa);
                b.x -= lean * clamp((b.y - 18.0) / 30.0, 0.0, 1.0);
                vec2 at = vec2(2.0, 24.0);
                float ang = (0.10 * sin(beat * PI * 0.25) - 0.15 * accent) * pBa;
                vec3 body = G == 2 ? vec3(0.85, 0.15, 0.15) : mix(uPrimary, vec3(0.9), 0.15);
                guitar(col, b, at, ang, -1.0, 34.0, body, body * 0.6);
                float pl = max(1.0 - swing(ph), uPluck) * pBa;
                arm(col, b, vec2(-9.0, 36.0), onGuitar(at, ang, vec2(-24.0, 13.0)), -1.0, o.shirt, SKIN_C);
                arm(col, b, vec2(9.0, 36.0), onGuitar(at, ang, vec2(2.0 - pl * 2.0, -2.0 - pl * 2.0)), 1.0, o.shirt, SKIN_C);
            }
        }

        // --- guitar slot (left of centre, played by a woman): guitar, violin or sax
        {
            Outfit o = outfit(G, 2);
            float walk = uWalk[2];
            float bob = walk >= 0.0 ? floor(abs(sin(walk)) * 1.5) : 0.0;
            float sway = floor(sin(beat * PI * 0.25 + 2.0) * 2.5 * pGu);
            vec2 g = v - vec2(uMX[2] + sway, -70.0 + bob);
            float tap = floor((1.0 - swing(ph)) * 2.0 * pGu);
            musician(col, g, o, SKIN_A, 0.0, true, tap, walk, uFace[2]);
            if (violinSlot) {
                violin(col, g, swing(ph) * pGu, SKIN_A, o.shirt);
            } else if (saxSlot) {
                sax(col, g, floor(swing(ph8) * 2.0 * pGu), SKIN_A, o.shirt);
            } else {
                float lean = floor(sin(beat * PI * 0.25 + 3.0) * 2.5 * pGu);
                g.x -= lean * clamp((g.y - 18.0) / 30.0, 0.0, 1.0);
                vec2 at = vec2(-2.0, 24.0);
                float ang = (-0.10 * sin(beat * PI * 0.25 + 2.0) - 0.2 * accent) * pGu;
                vec3 inner = vec3(1.0, 0.75, 0.25), outer = vec3(0.55, 0.15, 0.08);   // rock sunburst
                if (G == 7) { inner = vec3(0.90, 0.68, 0.38); outer = vec3(0.62, 0.40, 0.18); }        // acoustic
                else if (G == 6) { inner = vec3(0.85, 0.12, 0.10); outer = vec3(0.55, 0.05, 0.05); }   // blues red
                else if (G == 3) { inner = vec3(1.0, 0.85, 0.92); outer = vec3(0.95, 0.45, 0.70); }    // pop pink
                else if (G == 8) { inner = vec3(1.0, 0.88, 0.45); outer = vec3(0.80, 0.60, 0.20); }    // R&B gold
                else if (G != 2) { inner = mix(uPrimary, vec3(1.0), 0.3); outer = uSecondary; }
                guitar(col, g, at, ang, 1.0, 30.0, inner, outer);
                float strum = (swing(ph8) - 0.5) * (0.7 + uHits.w * 0.6) * pGu;
                float fret = floor(mod(beat / 4.0, 3.0)) * 3.0 * pGu;
                arm(col, g, vec2(9.0, 36.0), onGuitar(at, ang, vec2(18.0 + fret, 11.0 + fret * 0.6)), 1.0, o.shirt, SKIN_A);
                arm(col, g, vec2(-9.0, 36.0), onGuitar(at, ang, vec2(-1.0, 1.0 + strum * 8.0)), -1.0, o.shirt, SKIN_A);
            }
        }

        // --- singers, front and centre with handheld mics
        {
            float voc = clamp(uVocal * 2.5, 0.0, 1.0) * uActive;
            for (int i = 4; i < 6; i++) {
                float p = uPlay[i];
                float sway = floor(sin(beat * PI * 0.5) * 2.0 * p * uActive) * (i == 4 ? 1.0 : -1.0);
                singer(col, v, i, i == 4, voc * p, sway);
            }
        }

        // Ambient has no stage: anyone performing is a dark silhouette
        // against the colour field, rim-lit in the accent colour.
        if (G == 9 && any(notEqual(col, roomCol))) {
            col = mix(vec3(0.02, 0.015, 0.04), uAccent, 0.12) + uAccent * 0.08 * (1.0 + uBass);
        }

        fragColor = vec4(col, 1.0);
    }

    // Hit curve for a stick or strum: down at phase 0, back up by 0.5,
    // starting down again from 0.7.
    float swing(float ph) { return ph < 0.5 ? smoothstep(0.0, 0.5, ph) : 1.0 - smoothstep(0.7, 1.0, ph); }

    void arm(inout vec3 col, vec2 p, vec2 s, vec2 h, float side, vec3 sleeve, vec3 skin) {
        vec2 e = (s + h) * 0.5 + vec2(side * 3.0, -2.0);
        ink(col, sdSeg(p, s, e) - 2.6, sleeve);
        ink(col, sdSeg(p, e, h) - 2.0, skin);
        ink(col, sdCircle(p - h, 2.6), skin);
    }

    // Musician with feet at the origin, ~60px tall.
    // style: 0 spiky, 1 afro, 2 side-parted, 3 long, 4 beanie.
    // female adds eyelashes and lips; dress swaps trousers for a skirt
    // in the shirt colour; tap lifts the right foot.
    // walk >= 0 steps the legs; look shifts the face toward the walking direction.
    void person(inout vec3 col, vec2 p, vec3 skin, vec3 hair, vec3 shirt, vec3 pants,
                float style, float mouth, bool legs, bool female, bool dress, float tap,
                float walk, float look) {
        vec2 h = p - vec2(0.0, 50.0);
        if (style > 0.5 && style < 1.5) ink(col, sdCircle(h - vec2(0.0, 3.0), 12.0), hair);
        if (style > 2.5 && style < 3.5) ink(col, sdRoundBox(h - vec2(0.0, -7.0), vec2(10.0, 14.0), 5.0), hair);
        if (legs) {
            float liftL = walk >= 0.0 ? floor(max(0.0, sin(walk)) * 3.0) : 0.0;
            float liftR = walk >= 0.0 ? floor(max(0.0, -sin(walk)) * 3.0) : tap;
            vec2 lp = vec2(abs(p.x), p.y - (p.x > 0.0 ? liftR : liftL));
            if (dress) ink(col, sdBox(lp - vec2(4.0, 9.0), vec2(2.2, 8.0)), skin * 0.92);
            else ink(col, sdBox(lp - vec2(4.5, 11.0), vec2(3.5, 9.0)), lit(pants, p.x, 4.0));
            ink(col, sdEllipse(lp - vec2(5.5, 2.0), vec2(5.0, 2.5)), dress ? vec3(0.55, 0.10, 0.18) : vec3(0.28, 0.16, 0.10));
            if (dress) ink(col, max(abs(p.x) - (9.0 + (22.0 - p.y) * 0.45), abs(p.y - 15.0) - 7.0), lit(shirt, p.x, 4.0));
        }
        ink(col, sdRoundBox(p - vec2(0.0, 29.0), vec2(10.0, 11.0), 4.0), lit(shirt, p.x, 4.0));
        paint(col, sdBox(p - vec2(0.0, 40.5), vec2(3.0, 2.0)), skin * 0.82);
        ink(col, sdCircle(vec2(abs(h.x) - 8.0, h.y + 1.0), 2.0), skin * 0.9);
        float hd = sdEllipse(h, vec2(8.0, 9.0));
        ink(col, hd, lit(skin, h.x, 4.5));
        if (hd < 0.0) {
            bool hr;
            if (style < 0.5)      hr = h.y > 3.0 - abs(fract(h.x / 4.0) - 0.5) * 4.0;
            else if (style < 1.5) hr = h.y > 2.0;
            else if (style < 2.5) hr = h.y > 4.0 || (h.y > -1.0 && h.x < -4.5);
            else if (style < 3.5) hr = h.y > 3.0 || abs(h.x) > 6.0;
            else                  hr = h.y > 3.0;
            if (hr) col = style > 3.5 ? vec3(0.85, 0.22, 0.20) : lit(hair, h.x, 4.0);
        }
        if (style > 3.5) {
            paint(col, sdBox(h - vec2(0.0, 3.5), vec2(8.5, 1.5)), vec3(0.62, 0.12, 0.12));
            ink(col, sdCircle(h - vec2(0.0, 10.5), 2.5), vec3(0.95, 0.93, 0.88));
        }
        vec2 f = h - vec2(floor(look * 2.0), 0.0);    // face features turn with the walk
        paint(col, sdBox(vec2(abs(f.x) - 3.0, f.y), vec2(0.6, 1.2)), INK);
        if (female) paint(col, sdBox(vec2(abs(f.x) - 4.2, f.y - 1.6), vec2(0.6, 0.5)), INK);
        paint(col, sdBox(vec2(abs(f.x) - 4.0, f.y + 3.5), vec2(1.2, 0.6)), mix(skin, vec3(1.0, 0.45, 0.45), 0.45));
        if (mouth > 0.08) ink(col, sdEllipse(f - vec2(0.0, -5.0), vec2(1.8, 0.6 + mouth * 2.2)), vec3(0.55, 0.08, 0.14));
        else paint(col, sdBox(f - vec2(0.0, -5.0), vec2(1.5, 0.4)), female ? vec3(0.80, 0.22, 0.32) : INK);
    }

    // Guitar-shaped body + neck. dir = +1 neck to the right, -1 to the left.
    // Guitar-local point to world, for a guitar at `at` tilted by `ang`.
    vec2 onGuitar(vec2 at, float ang, vec2 local) { return at + rot(-ang) * local; }

    void guitar(inout vec3 col, vec2 p, vec2 at, float ang, float dir, float neckLen, vec3 inner, vec3 outer) {
        vec2 q = rot(ang) * (p - at);
        vec2 tip = vec2(dir * neckLen, neckLen * 0.62);
        ink(col, sdSeg(q, vec2(dir * 4.0, 3.0), tip) - 1.6, vec3(0.45, 0.27, 0.12));
        ink(col, sdBox(q - tip - vec2(dir * 2.0, 1.0), vec2(2.5, 1.6)), vec3(0.30, 0.17, 0.08));
        float body = min(sdCircle(q - vec2(-dir * 2.0, -2.0), 8.5), sdCircle(q - vec2(dir * 3.0, 3.0), 6.5));
        float r = length(q - vec2(-dir * 1.0, 0.0));
        vec3 burst = r < 4.0 ? inner : (r < 7.0 ? mix(inner, outer, 0.5) : outer);
        ink(col, body, burst);
        paint(col, sdCircle(q - vec2(dir * 1.5, 1.0), 2.2), INK);
        if (body < 0.0 && sdSeg(q, vec2(-dir * 6.0, -3.0), tip) < 0.5) col = vec3(0.85, 0.85, 0.8);
    }

    // Lead singer at the front edge of the stage, carrying a handheld mic
    // (they sing as they walk on). side = -1 mirrors them.
    void singer(inout vec3 col, vec2 v, int i, bool female, float voc, float sway) {
        float home = uHome[i], x = uMX[i], walk = uWalk[i];
        float side = home < -1.0 ? -1.0 : 1.0;
        float bob = walk >= 0.0 ? floor(abs(sin(walk)) * 1.5) : 0.0;
        vec2 s = v - vec2(x + sway, -84.0 + bob);
        s.x *= side;
        vec3 skin = female ? SKIN_A : SKIN_B;
        Outfit o = outfit(uGenre, i);
        if (female) o.style = 3.0;
        person(col, s, skin, o.hair, o.shirt, o.pants, o.style, voc, true, female, female, 0.0, walk, uFace[i] * side);
        if (!female && uGenre == 2) paint(col, sdBox(s - vec2(0.0, 32.0), vec2(2.5, 7.0)), vec3(0.95, 0.95, 0.92));   // rock: white tee under the jacket
        outfitExtras(col, s, o);
        vec3 sleeve = o.shirt;
        // mic hand up at the mouth; the free arm rises with the vocals
        vec2 hand = vec2(7.0, 40.0);
        arm(col, s, vec2(9.0, 36.0), hand, 1.0, sleeve, skin);
        ink(col, sdSeg(s, hand, hand + vec2(-2.0, 4.0)) - 1.2, vec3(0.18, 0.18, 0.20));
        ink(col, sdCircle(s - hand - vec2(-2.5, 5.5), 2.4), vec3(0.62, 0.62, 0.66));
        arm(col, s, vec2(-9.0, 36.0), mix(vec2(-12.0, 22.0), vec2(-19.0, 52.0), voc), -1.0, sleeve, skin);
    }

    """
}

extension FunShaders {
    // MARK: - Neon Wave

    /// Layered glowing green waveforms, like an LED sound-analyser screen.
    /// Each wave's height at a point follows the spectrum at the matching
    /// frequency (bass on the left, treble on the right); they flow with the
    /// forward-only scroll and flare on beats. In silence: one flat line.
    static let waveform = """
    // Spectrum at x (0..1), interpolated between bands so it has no steps.
    float spectrumAt(float x01) {
        float f = clamp(x01, 0.0, 1.0) * 95.0;
        int i = int(floor(f));
        float t = fract(f);
        return mix(uBands[i], uBands[min(i + 1, 95)], t * t * (3.0 - 2.0 * t));
    }

    float wave(float x, float aspect, int i) {
        float fi = float(i);
        float x01 = x / aspect + 0.5;
        float edge = smoothstep(0.0, 0.12, x01) * smoothstep(1.0, 0.88, x01);
        float amp = (0.04 + 0.38 * spectrumAt(x01) * (1.0 - fi * 0.09)) * edge * uActive;
        return amp * sin(x * (2.5 + fi * 1.9) * PI + uScroll * (3.0 + fi * 1.4) + fi * 1.7)
                   * (0.65 + 0.35 * sin(x * 1.7 - uScroll * 0.8 + fi * 2.3));
    }

    void main() {
        vec2 p = screenP();
        float aspect = uResolution.x / uResolution.y;

        vec3 col = vec3(0.0, 0.025, 0.015);
        // faint HUD grid and centre line
        vec2 g = abs(fract(p * 10.0) - 0.5);
        col += vec3(0.0, 0.10, 0.05) * (1.0 - smoothstep(0.0, 0.03, min(g.x, g.y))) * 0.5;
        col += vec3(0.05, 0.35, 0.15) * (1.0 - smoothstep(0.0, 0.0025, abs(p.y))) * 0.6;

        float halo = 0.0, core = 0.0;
        const float eps = 0.002;
        for (int i = 0; i < 7; i++) {
            float y = wave(p.x, aspect, i);
            float slope = (wave(p.x + eps, aspect, i) - y) / eps;
            float d = abs(p.y - y) / sqrt(1.0 + slope * slope);   // distance to the curve, not just vertical
            float w = 0.0012 + 0.0006 * float(i);
            float weight = 1.0 - float(i) / 8.0;
            halo += weight * 0.012 / (d + 0.012);
            core += weight * (1.0 - smoothstep(0.0, w * 2.0, d));
        }
        float flare = 0.7 + uBeatStrength * 0.6 * uActive;
        vec3 green = vec3(0.15, 1.0, 0.45);
        col += green * halo * 0.07 * flare;
        col += mix(green, vec3(0.75, 1.0, 0.8), 0.3) * core * flare;
        fragColor = vec4(min(col, vec3(1.0)), 1.0);
    }
    """

    // MARK: - Dance Floor

    /// A dance floor seen from the front edge of the room: a grid of tiles
    /// running away to a vanishing line, each one a face of a cube that keeps
    /// re-solving itself. Deliberately reads as electro / nu-wave — near-black
    /// room, neon edges, chrome on the tiles — because that is the brief.
    static let danceFloor = """
    uniform vec3 uPalette[3];

    void main() {
        // --- the camera, on the beat --------------------------------------
        // Every axis runs off the beat clock rather than free-running, so the
        // motion lands with the music instead of drifting against it: a sharp
        // dip on each kick that settles, a roll on the two-beat, a strafe and a
        // slow sweep left and right underneath it. All of it stops dead in
        // silence, because the clocks that feed uBeats do.
        float phase = fract(uBeats);
        float kick = exp(-phase * 6.0) * uBeatStrength * uActive;
        float roll = (sin(uBeats * 0.5) * 0.05 + kick * 0.022) * uActive;
        vec2 p = rot(roll) * screenP();
        float pan = sin(uBeats * 0.25) * 1.15 * (0.3 + 0.7 * uBass) * uActive;   // strafe
        float travel = cos(uBeats * 0.5) * 0.55 * uActive;                      // up and down the floor
        float look = sin(uBeats * 0.125) * 0.30 * uActive;                      // which way we face
        float horizon = 0.10 - kick * 0.035 - uBass * 0.02 * uActive;            // dips on the kick

        vec3 col = vec3(0.015, 0.012, 0.03);         // the room is nearly dark

        // Above the horizon: a wash of the palette's shadow colour, and a bright
        // line where the floor meets it.
        col += uPalette[0] * 0.30 * smoothstep(horizon, 0.5, p.y);
        col += uPalette[1] * 0.10 * exp(-abs(p.y - horizon) * 26.0) * uActive;

        if (p.y < horizon) {
            // Perspective: solve the distance to the floor point, which is the
            // z of a camera ray hitting the horizon.
            float depth = 0.34 / (horizon - p.y) - travel;
            float fade = exp(-max(0.0, depth) * 0.30);         // and fade out into the room
            if (fade > 0.02) {
                float x = (p.x - look) * depth + pan;
                vec2 id = floor(vec2(x, depth));
                vec2 f = fract(vec2(x, depth));

                // The whole floor breathes with the bass; a wave travels out
                // from the middle of the room on each beat.
                float lift = (0.05 + 0.13 * uBass) * uActive;
                float wave = exp(-mod(uBeats * 0.5 - (id.x + id.y) * 0.5, 8.0) * 2.2) * uBeatStrength;
                float pop = lift + wave * 0.22;

                // Which face of the cube this tile is showing. The whole floor
                // re-solves over time, faster when the mids are busy. The hash
                // is offset per row as well as per tile so neighbouring tiles
                // don't all land on the same face.
                float pick = hash21(id) * 0.7 + hash21(id.yx) * 0.3;
                float idx = mod(floor(pick * 6.0 + uBeats * (0.2 + uMid * 0.8)), 6.0);
                vec3 face = uPalette[1];
                if (idx < 1.0)      face = vec3(0.85);                    // white
                else if (idx < 2.0) face = uPalette[0] * 3.4;             // a near-black face
                else if (idx < 3.0) face = vec3(0.04);
                else if (idx < 4.0) face = uPalette[2];                   // the mid tone
                else if (idx < 5.0) face = uPalette[1] * 0.42;            // deep magenta
                else                face = mix(uPalette[1], vec3(0.75, 0.95, 1.0), 0.55); // cold chrome

                // A little variation even within one face, so a run of the same
                // colour still has depth.
                face *= 0.82 + 0.36 * hash11(floor(pick * 97.0));

                // A moving sheen, so the tiles read as polished rather than flat.
                float sheen = pow(max(0.0, 1.0 - abs((f.x + f.y * 0.6) - 0.8)), 6.0);
                face += vec3(0.9) * sheen * (0.12 + 0.22 * uTreble * uActive);

                vec2 q = f - 0.5;
                q.y -= pop * 0.55;                    // the tile rises as it pops
                float tile = 0.44 - pop * 0.16;
                float d = sdRoundBox(q, vec2(tile), 0.05);
                float inside = fill(d, aaw(0.4));

                // The floor between the tiles, brightening toward the viewer.
                vec3 base = uPalette[0] * (0.35 + 0.5 * exp(-max(0.0, depth) * 0.16));
                col = mix(col, base, fade);
                col = mix(col, face * (0.30 + 0.85 * uBeatStrength * uActive), inside * fade);

                // Neon edges between the tiles, glittering on the hats.
                float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
                float line = 1.0 - smoothstep(0.0, 0.05 + 0.05 * uTreble * uActive, edge);
                col += uPalette[1] * line * (0.20 + 0.45 * uTreble * uActive) * fade;

                // A hint of the room bouncing off the floor on each kick.
                col += uPalette[1] * uBeatStrength * 0.05 * fade;
            }
        }
        fragColor = vec4(min(col, vec3(1.0)), 1.0);
    }
    """

}

extension FunShaders {
    // MARK: - Vortex

    /// A cyber tunnel of grid lines rushing past, twisting with the bass.
    ///
    /// Written by Alisan and shipped as a vibescape of its own.
    static let vortex = """
    void vortexAt(inout vec3 col, vec2 p, float t) {
        float r = length(p);
        float a = atan(p.y, p.x);

        // Speed advances with uClock; bass causes dynamic FOV expansion
        float speed = uClock * 1.5;
        float fovPulse = 1.0 + uBassSmooth * 0.4 + uBeat * 0.2;

        vec2 uv;
        uv.x = a / (2.0 * 3.14159265) + 0.5;
        uv.y = (0.25 * fovPulse) / (r + 0.01) + speed;

        // Bass-driven spiral twist
        uv.x += sin(uv.y * 2.0 + t) * (0.05 + uBass * 0.1);

        // Cyber grid geometry
        vec2 grid = abs(fract(uv * vec2(12.0, 24.0)) - 0.5);
        float gridLines = fill(max(grid.x, grid.y) - 0.45, aaw(1.0));

        // Cyber colors (cyan to magenta) with treble-reactive rings
        vec3 cyan = vec3(0.0, 0.85, 1.0);
        vec3 magenta = vec3(1.0, 0.15, 0.7);
        vec3 silver = vec3(0.8, 0.9, 1.0);

        float ring = pow(sin(uv.y * 31.4) * 0.5 + 0.5, 4.0) * (0.8 + uTreble * 1.5);

        vec3 c = vec3(0.01, 0.02, 0.08);
        c += mix(cyan, magenta, sin(uv.y * 3.0 + t) * 0.5 + 0.5) * gridLines;
        c += silver * ring * (1.0 / (r * 3.0 + 0.2));

        // Center glow pulsing with bass and beat strength
        c += vec3(0.6, 0.8, 1.0) * exp(-r * 8.0) * (1.0 + uBassSmooth * 2.0 + uBeatStrength);

        // Fade at outer edges and scale by silence factor
        c *= smoothstep(1.2, 0.3, r);
        col = c;
    }

    void main() {
        vec3 col = vec3(0.0);
        vortexAt(col, screenP(), uTime);
        fragColor = vec4(min(col * uActive, vec3(1.0)), 1.0);
    }
    """

    // MARK: - Ribbons

    /// Several braided sheaves of fine glowing silk, of clearly different
    /// sizes, weave through small clear glass polyhedra at different depths
    /// in a dark navy room above a glossy floor: the look of the screens in
    /// the AudioVane film. A big hero sheaf (18 round strands, each a few
    /// hairline fibres, around a luminous core) runs low through the middle;
    /// a medium one (12 strands) rides above and behind it, a thin thread
    /// sits high at the back and a fine hairline runs low up front. Each sits
    /// at its own height and depth and undulates on its own slow waves, so
    /// they cross with navy between them. The ribbons are hot pink at rest;
    /// every beat launches a band of cyan that races along each one
    /// the way it flows, some strands lighting a moment before others so it
    /// shimmers through, then shrinks away strand by strand so the ribbon
    /// flows back to pink. Each ribbon fires at its own point in the beat, so
    /// the bands ripple through one after another rather than all at once,
    /// and every band eases in and out with a soft head and tail. The bands
    /// follow the music: on the eased bass and loudness a loud kick sends a
    /// big, bright, long cyan surge and a quiet passage a faint, short one,
    /// and the treble glints along the pulse heads. The glass
    /// is ray-traced exactly (each shape is a set of paired face planes, so
    /// there is no raymarching loop): solid clear faces that reflect the
    /// lights, refract the hero ribbon behind them, catch pink light inside
    /// and burn cyan along their edges, and shapes far from the lens's focus
    /// go soft. The floor mirrors the hero ribbon and the glass, pulses
    /// included, and glows pink under the ribbons. Colours are chosen to land
    /// as pink and cyan after the NEON grade. The scene slides past the
    /// camera in both directions: the hero and the low hairline flow right to
    /// left, the medium ribbon and the high thread flow left to right, and
    /// most glass drifts left while three shapes drift right, a little
    /// slower. Near glass and near stretches of ribbon cross faster than far
    /// ones (parallax), and each shape comes back in from the other side once
    /// it has left. The slide speeds up with uScroll. Everything is smoothed
    /// so nothing snaps from frame to frame: instead of the raw bass and beat
    /// strength, a soft swell on the beat clock (easing in over about a third
    /// of a beat, dying away over the next one or two) bends, widens and
    /// brightens the ribbons and swells the glass; the glass turns and the
    /// ribbons reshape on an eased beat clock that never stops; the treble
    /// makes the edges and the dust sparkle a little.
    /// In silence the glass fades away and the four ribbons gather into one
    /// still set of ten perfectly level pink lines across the middle of the
    /// screen: 1 px tall, 2 px apart, on whole pixel rows at any resolution.
    /// When the music starts they unfurl back into the ribbons and the glass
    /// returns; when it stops they settle back. The morph is eased on
    /// uLevelSmooth (with uActive), so it never snaps or chatters.
    static let ribbons = """
    // Glass polyhedra as pairs of parallel planes: the first 4 axes make an
    // octahedron, all 10 an icosahedron (face normals, unit length).
    const vec3 kFaceAxes[10] = vec3[10](
        vec3(0.5774, 0.5774, 0.5774), vec3(0.5774, 0.5774, -0.5774),
        vec3(0.5774, -0.5774, 0.5774), vec3(-0.5774, 0.5774, 0.5774),
        vec3(0.0, 0.3568, 0.9342), vec3(0.0, 0.3568, -0.9342),
        vec3(0.3568, 0.9342, 0.0), vec3(-0.3568, 0.9342, 0.0),
        vec3(0.9342, 0.0, 0.3568), vec3(-0.9342, 0.0, 0.3568));

    const float kFloorY = -0.62;
    const int kGems = 8;
    const int kStrands = 18;

    // The film's palette: hot pink and electric cyan light over a dark navy room.
    const vec3 ribbonPink = vec3(1.0, 0.12, 0.40);
    const vec3 ribbonDeep = vec3(0.50, 0.0, 0.24);
    const vec3 ribbonCyan = vec3(0.0, 1.0, 0.72);
    const vec3 ribbonTeal = vec3(0.0, 0.55, 0.45);
    const vec3 glassCyan = vec3(0.0, 1.0, 0.64);

    // Spectrum at x (0..1), interpolated between bands so it has no steps.
    float ribbonSpec(float x01) {
        float f = clamp(x01, 0.0, 1.0) * 95.0;
        int i = int(floor(f));
        float t = fract(f);
        return mix(uBands[i], uBands[min(i + 1, 95)], t * t * (3.0 - 2.0 * t));
    }

    // How far the whole scene has slid to the left, in world units. A slow base
    // drift on the wall clock (so it never stops, even in silence) plus uScroll,
    // so it speeds up with the music. Both only ever increase. Because the world
    // itself moves, perspective gives the parallax: near glass and near stretches
    // of ribbon cross the screen faster than far ones.
    float sceneShift() { return uClock * 0.15 + uScroll * 0.85; }

    // The world turns with the beat: half at a steady pace on the beat clock and
    // half in an eased step per beat, so it surges a little on each beat but
    // never stops or snaps. Forward-only, so it never runs backwards.
    float beatTurn() { return 0.5 * uBeats + 0.5 * (floor(uBeats) + smoothstep(0.0, 1.0, fract(uBeats))); }

    // A soft swell on every beat, in place of the raw bass and beat-strength
    // inputs (which jump from one frame to the next): it eases in over about a
    // third of a beat and dies away over the next beat or two, and the swells
    // of the last beats overlap, so it rises and falls like breathing. Zero in
    // silence.
    float swellAt(float x) { return smoothstep(0.0, 0.32, x) * exp(-x * 1.4); }
    float beatSwell() {
        float ph = fract(uBeats);
        return (swellAt(ph) + swellAt(ph + 1.0) + swellAt(ph + 2.0) + swellAt(ph + 3.0)) * 1.2 * uActive;
    }
    float gSwell;   // beatSwell(), worked out once per pixel at the top of main()
    float gSpec;    // the low end of the spectrum, worked out once per pixel

    // Silence: with no music the glass fades away and the four ribbons gather
    // into one still set of ten perfectly level lines, 2 px apart, across the
    // middle of the screen. gPlay is how much music there is (0 in silence, 1
    // playing), eased on the slow loudness so it unfurls over about half a
    // second when the music starts and settles over a second or two when it
    // stops, with no chattering in quiet passages. At 1 everything is exactly
    // as when playing. gGlass is how visible the glass is: it goes first and
    // comes back last.
    float gPlay;
    float gGlass;
    float gCut = 1e9;   // ribbons further along the ray than this (behind fading glass) ...
    float gBehind = 1.0; // ... show this much
    // How hard the cyan pulses hit: from the eased bass and loudness, so a loud
    // kick sends a big, bright, long cyan surge racing through and a quiet
    // passage only a faint, short one, without flicker. 0..1.
    float gDrive;
    float pulseDrive() { return smoothstep(0.1, 0.27, uBassSmooth * 0.6 + uLevelSmooth * 1.6); }
    float gPx;      // one screen pixel, in world units, on the plane the lines settle on
    const float kIdleZ = 0.1;                            // the lines settle at the hero's depth...
    const float kIdleY = -0.40 + 0.24 * (kIdleZ + 3.3) / 1.3;   // ... at the height of the screen's middle
    float playAmount() {
        float m = uLevelSmooth * (0.3 + 0.7 * uActive);  // falls quickly once the sound has gone
        float x = smoothstep(0.004, 0.035, m);
        return x * x * (3.0 - 2.0 * x);
    }
    // The ten lines: 1 px tall, on whole pixel rows, 2 px apart, centred.
    float idleRow0() { return floor(uResolution.y * 0.5) - 8.5; }
    float idleLines() {
        float d = gl_FragCoord.y - idleRow0();
        float k = clamp(floor(d * 0.5 + 0.5), 0.0, 9.0);
        return clamp(1.0 - abs(d - 2.0 * k), 0.0, 1.0);
    }

    // The ribbons, from one big hero sheaf down to thin threads, each at its own
    // height and depth with its own slow undulation. Some flow left with the
    // scene, some flow right against it, and their pulses race the way they flow.
    //  x: base height  y: wave height  z: half-width of the sheaf  w: strands
    const vec4 kRibShape[4] = vec4[4](
        vec4(0.08, 0.32, 0.24, 18.0),
        vec4(0.95, 0.34, 0.145, 12.0),
        vec4(-0.26, 0.24, 0.014, 4.0),
        vec4(1.9, 0.45, 0.07, 7.0));
    //  x: strand radius  y: flow (+ left, - right, and how fast)  z: depth  w: depth swing
    const vec4 kRibFlow[4] = vec4[4](
        vec4(0.036, 1.0, 0.1, 0.65),
        vec4(0.028, -0.8, 1.55, 0.5),
        vec4(0.006, 1.3, -1.05, 0.3),
        vec4(0.018, -0.6, 2.7, 0.4));
    //  x, y: wave frequencies  z: phase  w: beat offset of its pulses
    const vec4 kRibWave[4] = vec4[4](
        vec4(1.2, 2.28, 0.0, 0.0),
        vec4(0.85, 1.85, 1.7, 0.37),
        vec4(1.55, 2.9, 3.1, 0.61),
        vec4(0.75, 1.6, 4.4, 0.83));

    // How far ribbon k's pattern has slid along itself.
    float ribbonShift(int k) { return sceneShift() * kRibFlow[k].y; }
    // Where ribbon k rests, as the music fades: its height and depth move to the
    // lines' and its depth swing flattens out.
    float ribbonBaseY(int k) { return mix(kIdleY, kRibShape[k].x, gPlay); }
    float ribbonBaseZ(int k) { return mix(kIdleZ, kRibFlow[k].z, gPlay); }

    // How cyan the ribbon is at x (position across its sheet, measured the way it
    // flows) for a strand that lights `delay` beats late: every beat launches a
    // band of bright cyan that races along the strands, born off screen, easing
    // in and fading out again over the next beat and a half, with a soft head
    // (`sharp`) and a long soft tail, so the ribbon flows back to pink without a
    // snap. Each ribbon's bands set off at their own point in the beat (`off`),
    // so they never all fire at once. In silence there are none.
    float pulseAmp(float ph) { return smoothstep(0.0, 0.2, ph) * (1.0 - smoothstep(0.45, 1.5, ph)); }
    float ribbonPulse(float x, float off, float delay, float spd, float energy, float sharp) {
        float ph = fract(uBeats - off) - delay;
        float s0 = x - 4.4 + spd * ph;                      // behind this beat's front
        float s1 = s0 + spd;                                // ... and the last beat's
        float tail = 1.2 / mix(0.55, 1.7, gDrive);           // louder: a longer tail
        float p0 = exp(-max(s0 - 1.1, 0.0) * tail - max(-s0, 0.0) * sharp) * pulseAmp(ph);
        float p1 = exp(-max(s1 - 1.1, 0.0) * tail - max(-s1, 0.0) * sharp) * pulseAmp(ph + 1.0);
        return max(p0, p1) * energy;
    }

    // Light from ribbon k at point q on its plane: a braided sheaf of fine
    // glowing strands, hot pink, with cyan pulses racing through it on the beat.
    // soft > 0 blurs it, for reflections in the floor.
    vec3 ribbonLight(vec2 q, float soft, int k) {
        vec4 shp = kRibShape[k], flw = kRibFlow[k], wav = kRibWave[k];
        float dir = sign(flw.y);
        float size = shp.z / 0.3;                            // 1 for the hero sheaf
        float turn = beatTurn();
        float X = q.x + ribbonShift(k);                      // position along the ribbon
        float xf = q.x * dir;                                // ... measured the way it flows
        float edge = smoothstep(-4.8, -3.6, q.x) * smoothstep(4.8, 3.6, q.x);
        // Broad waves; the beat swell bends the sheaf a little harder.
        float amp = shp.y * (1.0 + (0.14 * gSpec + 0.55 * gSwell) * size) * mix(0.75, 1.0, uActive) * gPlay;
        float ph = turn * 0.45 + wav.z;
        float s = uScroll * 0.3 * dir;                       // a gentle ripple along the ribbon on top of the slide
        float a1 = X * wav.x + s + ph;
        float a2 = X * wav.y - s * 0.6 + ph * 1.7;
        float yc = ribbonBaseY(k) + amp * sin(a1) + amp * 0.35 * sin(a2);
        float lo = kFloorY + shp.z * 0.6 + 0.06;             // skim the floor rather than sink into it
        yc = mix(yc, 0.5 * (yc + lo + sqrt((yc - lo) * (yc - lo) + 0.004)), gPlay);
        float slope = amp * (wav.x * cos(a1) + 0.35 * wav.y * cos(a2));
        float norm = inversesqrt(1.0 + slope * slope);
        float dc = abs(q.y - yc) * norm;
        // Far from a small ribbon there's nothing left of its glow to draw.
        if (k > 0 && dc > 1.4 * sqrt(size) + soft * 24.0) return vec3(0.0);
        // The sheaf twists as it travels: fanned wide where it faces you, gathered
        // where it turns, and each strand weaves a little on its own so they cross.
        float width = mix(10.0 * gPx, shp.z * (1.0 + 0.3 * gSwell) * (0.75 + 0.25 * sin(X * 0.6 + wav.z)), gPlay);
        float twist = X * 0.55 - uScroll * 0.25 * dir + turn * 0.2 + wav.z;
        float face = cos(twist);
        float sw = flw.x;                                    // strand radius: fine silk
        float energy = uActive * gPlay * mix(0.25, 1.25, gDrive);   // faint when quiet, a surge when loud
        const float spd = 7.5;                               // world units per beat
        vec3 bundle = vec3(0.0);
        float pc = smoothstep(0.15, 0.95, ribbonPulse(xf, wav.w, 0.06, spd, energy, 1.2));   // the wave through the sheaf as a whole
        vec3 hotC = mix(ribbonPink, ribbonCyan, pc);
        // Only pixels near the sheaf pay for its strands.
        if (dc < width * 1.6 + 0.12 * size + soft * 12.0) {
            vec3 strands = vec3(0.0);
            int n = int(shp.w);
            float fn = shp.w;
            // Per-strand phases advance by a fixed angle each strand (cheap rotations, not sin per strand).
            vec2 pw = vec2(sin(X * 0.8), cos(X * 0.8));      // thickness wobble, steps 1.3 rad per strand
            vec2 ps = vec2(sin(X * 0.9 - uScroll * 0.4), cos(X * 0.9 - uScroll * 0.4));   // shimmer, steps 2.3 rad
            const mat2 stepW = mat2(0.2675, -0.9636, 0.9636, 0.2675);
            const mat2 stepS = mat2(-0.6663, -0.7457, 0.7457, -0.6663);
            float aa = mix(max(soft, 0.5 * gPx), max(soft, 0.0025), gPlay);
            float lane = (idleRow0() - 0.5 * uResolution.y) * gPx;   // where strand lane 0 settles, from the middle
            for (int i = 0; i < kStrands; i++) {
                if (i >= n) break;
                float fi = float(i);
                float h1 = fract(fi * 0.6180), h2 = fract(fi * 0.7549 + 0.31), h3 = fract(fi * 0.5698 + 0.17);
                float u = fi / (fn - 1.0) * 2.0 - 1.0;
                float off = width * (u * (0.5 + 0.5 * abs(face)) + 0.45 * sin(X * (1.1 + 0.25 * h1) + fi * 2.4 + turn * 0.3));
                off = mix(lane + 2.0 * gPx * floor((u * 0.5 + 0.5) * 9.999), off, gPlay);   // in silence, onto one of the ten lines
                float sd = (q.y - yc - off) * norm;
                float d = abs(sd);
                float w = mix(0.5 * gPx, sw * (0.45 + 0.9 * h2) * (0.75 + 0.25 * pw.x), gPlay);
                float cov = 1.0 - smoothstep(w - aa, w + aa, d);     // the strand's outline, anti-aliased
                float x = min(d / (w + aa), 1.0);
                float tube = sqrt(1.0 - x * x);                       // round strand: hot in the middle, deep at the rim
                // each strand is itself a few hairline fibres, read where it's sharp enough
                float fib = mix(0.55 + 0.45 * cos(sd / (w + aa) * 9.4 + fi * 1.7), 1.0, max(smoothstep(0.3, 0.8, aa / w), 1.0 - gPlay));
                // some strands catch the wave before others, so it shimmers through the sheaf;
                // as a band fades, its strands drop back to pink one by one
                float pulse = smoothstep(0.08 + 0.55 * h2, 0.28 + 0.55 * h2, ribbonPulse(xf, wav.w, h3 * 0.14, spd, energy, 3.0));
                vec3 hot = mix(ribbonPink, ribbonCyan, pulse);
                vec3 deep = mix(ribbonDeep, ribbonTeal, pulse);
                float t2 = tube * tube, t8 = t2 * t2; t8 *= t8;
                float t32 = t8 * t8; t32 *= t32;
                // the hats glint on the pulse heads (a fine sparkle running along the strand)
                float glint = 1.0 + pulse * (0.45 * gDrive + 0.6 * uTreble * (0.5 + 0.5 * sin(X * 23.0 + fi * 2.1 - uScroll * 9.0)));
                vec3 c = mix(deep, hot, tube) * (0.35 + 1.35 * tube) * (1.0 - 0.25 * pulse) * glint * fib
                       + mix(vec3(1.0, 0.5, 0.75), vec3(0.3, 1.0, 1.0), pulse) * t32 * t8 * 0.6;
                strands = mix(strands, c * mix(1.0, 0.75 + 0.25 * ps.x, gPlay), cov * 0.8);   // later strands lie over earlier ones
                pw = stepW * pw;
                ps = stepS * ps;
            }
            // the strands' shared glow: bright through the sheaf, falling off outside it
            float halo = 5.0 * exp(-max(dc - width * 0.9, 0.0) / (0.06 * size + soft * 3.0));
            bundle = strands + (hotC * halo * 0.15
                   + hotC * mix(vec3(1.0, 0.55, 0.8), vec3(0.3, 1.0, 0.95), pc) * exp(-dc / (width * 0.45 + 0.02 * size + soft * 4.0)) * 0.55) * gPlay;   // thick luminous core
        }
        // the glow the sheaf throws on the air around it
        bundle += hotC * exp(-dc / (0.2 * sqrt(size) + soft * 4.0)) * 0.08 * sqrt(size) * gPlay;
        float glow = mix(1.6, (0.45 + 0.55 * uActive) * (0.95 + 0.3 * gSwell), gPlay);
        return bundle * 1.1 * edge * glow / (1.0 + soft * 20.0);
    }

    // Each ribbon lives on its own curved sheet that slides with its flow, so
    // stretches of ribbon swing towards the camera (and move faster) and back
    // away again. Where a ray meets it (a few fixed-point steps), or -1.
    float ribbonDepth(float x, int k) {
        return ribbonBaseZ(k) + kRibFlow[k].w * gPlay * sin((x + ribbonShift(k)) * 0.45 + 0.9 + kRibWave[k].z);
    }
    float ribbonT(vec3 ro, vec3 rd, int k) {
        if (abs(rd.z) < 1e-3) return -1.0;
        float t = (ribbonDepth(ro.x, k) - ro.z) / rd.z;
        int steps = k == 0 ? 4 : 2;                          // the small ones' sheets bend less
        for (int i = 0; i < 4; i++) {
            if (i >= steps) break;
            t = (ribbonDepth(ro.x + rd.x * max(t, 0.0), k) - ro.z) / rd.z;
        }
        return t;
    }

    // One ribbon as seen along a ray, or nothing if the ray doesn't reach it.
    // Blur is soft + softT per unit of distance, never thinner than a pixel.
    vec3 ribbonAlong(vec3 ro, vec3 rd, float soft, float softT, float tMax, int k) {
        if (k > 0) {
            // A cheap first look: rays that pass well above or below the band
            // this ribbon can wave through never reach its glow.
            float t0 = (ribbonBaseZ(k) - ro.z) / rd.z;
            float band = 2.6 * kRibShape[k].y + 1.4 * sqrt(kRibShape[k].z / 0.3)
                       + abs(rd.y / rd.z) * kRibFlow[k].w * 1.2 + (soft + (abs(t0) + 3.0) * (softT + 0.7 / uResolution.y)) * 24.0;
            if (abs(ro.y + rd.y * t0 - ribbonBaseY(k)) > band) return vec3(0.0);
        }
        float t = ribbonT(ro, rd, k);
        if (t <= 0.0 || t > tMax) return vec3(0.0);
        vec3 p = ro + rd * t;
        if (p.y < kFloorY) return vec3(0.0);
        float seen = t > gCut ? gBehind : 1.0;
        if (seen <= 0.0) return vec3(0.0);
        return ribbonLight(p.xy, soft + t * (softT + 0.7 / uResolution.y), k) * seen;
    }

    // All the ribbons along a ray (they glow, so their light adds). Written out
    // one by one, so each ribbon's settings are fixed when the shader compiles.
    // Reflections in the floor and the glass (`all` false) show only the hero
    // sheaf, which keeps the cost down.
    vec3 ribbonsAlong(vec3 ro, vec3 rd, float soft, float softT, float tMax, bool all) {
        vec3 acc = ribbonAlong(ro, rd, soft, softT, tMax, 0);
        if (all) acc += ribbonAlong(ro, rd, soft, softT, tMax, 1) + ribbonAlong(ro, rd, soft, softT, tMax, 2)
                      + ribbonAlong(ro, rd, soft, softT, tMax, 3);
        return acc;
    }

    // The room: deep navy, a little lighter up high, a faint pink haze behind the
    // pink ribbon, a hot line where the floor meets the dark, and a little dust
    // that sparkles with the treble.
    vec3 horizonGlow(vec3 rd) {
        float band = exp(-max(rd.y, 0.0) * 90.0 - max(-rd.y, 0.0) * 22.0) * 0.7;   // hugs the floor, barely rises into the air
        vec3 c = mix(ribbonCyan * 0.3, ribbonPink * 0.75, smoothstep(-0.7, 0.2, rd.x));
        return c * band * exp(-abs(rd.x - 0.05) * 1.2) * (0.45 + 0.55 * uActive);
    }
    vec3 skyColour(vec3 rd) {
        vec3 col = mix(vec3(0.0, 0.058, 0.074), vec3(0.0, 0.076, 0.094), smoothstep(-0.05, 0.5, rd.y));
        col += vec3(0.03, 0.004, 0.03) * exp(-length(rd.xy - vec2(0.12, 0.10)) * 3.5) * (0.3 + 0.4 * uActive);
        col += vec3(0.0, 0.04, 0.05) * exp(-length(rd.xy - vec2(-0.45, -0.12)) * 3.0) * (0.3 + 0.4 * uActive);
        vec2 sp = rd.xy / max(rd.z, 0.2) * 90.0 + vec2(sceneShift() * 5.0, 0.0);   // far dust drifts slowest
        vec2 cell = floor(sp);
        float h = hash21(cell);
        vec2 off = vec2(hash21(cell + 7.1), hash21(cell + 3.3)) - 0.5;
        float star = smoothstep(0.12, 0.0, length(fract(sp) - 0.5 - off * 0.6)) * step(0.95, h);
        float tw = 0.4 + 0.6 * sin(h * 50.0 + uTime * 2.0);
        col += vec3(0.5, 0.85, 1.0) * star * tw * (0.15 + 0.4 * uTreble) * (0.3 + 0.7 * uActive);
        return col + horizonGlow(rd);
    }

    // Lights for the glass to reflect: the pink and cyan of the ribbons.
    vec3 envColour(vec3 rd) {
        vec3 col = skyColour(rd);
        col += ribbonPink * 1.4 * pow(max(dot(rd, normalize(vec3(0.6, 0.25, -0.7))), 0.0), 14.0);
        col += ribbonCyan * 1.1 * pow(max(dot(rd, normalize(vec3(-0.7, 0.1, -0.6))), 0.0), 14.0);
        col += vec3(0.8, 0.95, 1.0) * 0.5 * pow(max(dot(rd, normalize(vec3(0.1, 1.0, -0.3))), 0.0), 16.0);
        return col;
    }

    // Where each glass shape is, how it's turned, and how big it is. Each one
    // sits at its own depth and slides with the scene, most of them left and a
    // few the other way; once it's off one edge it comes back in from the other
    // (a little higher or lower, a bit bigger or smaller, turned differently),
    // so the stream never runs dry. The starting points are staggered so the
    // shapes don't travel as one clump.
    void gemPose(int j, out vec3 c, out vec2 ang, out float r, out int faces) {
        float fj = float(j);
        if (j == 0)      { c = vec3(0.0, -0.40, -1.10); r = 0.17; faces = 10; }
        else if (j == 1) { c = vec3(0.0, 0.95, 2.60);   r = 0.34; faces = 10; }
        else if (j == 2) { c = vec3(0.0, 0.70, 0.40);   r = 0.30; faces = 10; }
        else if (j == 3) { c = vec3(0.0, -0.50, 1.20);  r = 0.22; faces = 4; }
        else if (j == 4) { c = vec3(0.0, 0.30, -0.60);  r = 0.13; faces = 10; }
        else if (j == 5) { c = vec3(0.0, 1.25, 1.60);   r = 0.24; faces = 10; }
        else if (j == 6) { c = vec3(0.0, -0.40, 3.20);  r = 0.34; faces = 10; }
        else             { c = vec3(0.0, 0.55, -1.50);  r = 0.10; faces = 10; }
        // Wrap span: wide enough that the jump happens off screen at this depth.
        float depth = c.z + 3.4;
        float span = 2.0 * (depth * 0.85 + r) + 0.4;
        // Three of them drift the other way, left to right, a little slower.
        float flow = (j == 1 || j == 3 || j == 6) ? -0.7 : 1.0;
        float x = fract(fj * 0.375 + 0.62) * span - sceneShift() * flow;
        float lap = floor(x / span);
        c.x = x - lap * span - 0.5 * span;
        float lh = hash11(lap * 3.7 + fj * 11.3);
        c.y = clamp(c.y + (lh - 0.5) * 0.4, kFloorY + r * 0.8, 2.0);
        r *= 0.85 + 0.3 * hash11(lap * 5.1 + fj * 2.9);
        c.y += 0.05 * sin(uTime * 0.45 + fj * 1.9);
        ang = vec2(uTime * (0.10 + 0.03 * fj) + uClock * 0.02 + fj * 1.3 + lh * 6.28,
                   beatTurn() * 0.32 + fj * 2.1);
        r *= 1.32 * (1.0 + 0.04 * gSwell);
    }

    vec3 toGem(vec3 v, vec2 ang) { v.xz = rot(ang.x) * v.xz; v.yz = rot(ang.y) * v.yz; return v; }
    vec3 fromGem(vec3 v, vec2 ang) { v.yz = rot(-ang.y) * v.yz; v.xz = rot(-ang.x) * v.xz; return v; }

    // Ray against a convex polyhedron (object space). Returns entry/exit distance
    // and the face normals there; tNear > tFar means a miss.
    void gemHit(vec3 ro, vec3 rd, int faces, float h, out float tNear, out float tFar, out vec3 nNear, out vec3 nFar) {
        tNear = -1e5; tFar = 1e5; nNear = vec3(0.0, 1.0, 0.0); nFar = nNear;
        for (int i = 0; i < 10; i++) {
            if (i >= faces) break;
            vec3 n = kFaceAxes[i];
            float dn = dot(rd, n), on = dot(ro, n);
            if (abs(dn) < 1e-5) { if (abs(on) > h) tNear = 1e5; continue; }
            float t1 = (-h - on) / dn, t2 = (h - on) / dn;
            vec3 sn = n * -sign(dn);
            if (min(t1, t2) > tNear) { tNear = min(t1, t2); nNear = sn; }
            if (max(t1, t2) < tFar) { tFar = max(t1, t2); nFar = -sn; }
        }
    }

    // How close a surface point is to an edge (x: 1 on an edge, 0 mid-face) and
    // to a corner (y: 1 where three faces meet).
    vec2 gemEdge(vec3 p, int faces, float h, float w) {
        float a = -1e5, b = -1e5, c = -1e5;
        for (int i = 0; i < 10; i++) {
            if (i >= faces) break;
            float d = abs(dot(p, kFaceAxes[i])) - h;
            if (d > a) { c = b; b = a; a = d; } else if (d > b) { c = b; b = d; } else if (d > c) { c = d; }
        }
        return vec2(1.0 - smoothstep(0.0, w, a - b), 1.0 - smoothstep(0.0, w * 2.5, a - c));
    }

    // Nearest glass shape along a ray, if any.
    bool nearestGem(vec3 ro, vec3 rd, float tMax, out int jHit, out float tHit) {
        jHit = -1; tHit = tMax;
        for (int j = 0; j < kGems; j++) {
            vec3 c; vec2 ang; float r; int faces;
            gemPose(j, c, ang, r, faces);
            vec3 oc = ro - c;
            float bb = dot(oc, rd), cc = dot(oc, oc) - r * r;
            if (bb * bb - cc < 0.0 || -bb + sqrt(max(bb * bb - cc, 0.0)) < 0.0) continue;
            float h = r * (faces == 4 ? 0.5774 : 0.7947);
            float tn, tf; vec3 nn, nf;
            gemHit(toGem(oc, ang), toGem(rd, ang), faces, h, tn, tf, nn, nf);
            if (tn < tf && tn > 0.0 && tn < tHit) { tHit = tn; jHit = j; }
        }
        return jHit >= 0;
    }

    // Cyan glow around each shape's silhouette, so the glass seems to give off
    // light. pool is the glow the shapes throw on the floor, if ro is on it.
    vec3 gemHalo(vec3 ro, vec3 rd, float tMax, out vec3 pool) {
        vec3 acc = vec3(0.0);
        pool = vec3(0.0);
        for (int j = 0; j < kGems; j++) {
            vec3 c; vec2 ang; float r; int faces;
            gemPose(j, c, ang, r, faces);
            vec2 gd = (ro.xz - c.xz) / r;
            pool += glassCyan * exp(-dot(gd, gd) * 0.8 - max(c.y - r - kFloorY, 0.0) * 2.5);
            float t = max(dot(c - ro, rd), 0.0);
            if (t > tMax) continue;
            float d = max(length(ro + rd * t - c) - r * 0.85, 0.0);
            acc += glassCyan * exp(-d * 9.0) * 0.06 / (1.0 + t * 0.15);
        }
        return acc * (0.4 + 0.6 * uActive + 0.5 * gSwell);
    }

    // One glass shape: reflection, refraction of the ribbons behind it, and its
    // glowing cyan edges, front and back. Shapes far from the focus distance
    // get softer, wider edges, like a lens out of focus.
    vec3 shadeGem(int j, vec3 ro, vec3 rd, float tHit, bool full) {
        vec3 c; vec2 ang; float r; int faces;
        gemPose(j, c, ang, r, faces);
        float h = r * (faces == 4 ? 0.5774 : 0.7947);
        vec3 oro = toGem(ro - c, ang), ord = toGem(rd, ang);
        float tn, tf; vec3 nn, nf;
        gemHit(oro, ord, faces, h, tn, tf, nn, nf);
        vec3 pIn = oro + ord * tn;
        vec3 nW = fromGem(nn, ang);
        float px = 2.0 / uResolution.y;
        float blur = smoothstep(4.8, 7.5, length(c - ro));
        float edgeW = min((px * tn * 1.6 + 0.004 + blur * 0.012) / r * h, h * 0.04);
        vec2 edgeFront = gemEdge(pIn, faces, h, edgeW);

        float fres = 0.07 + 0.93 * pow(1.0 - clamp(-dot(rd, nW), 0.0, 1.0), 4.0);
        vec3 rr = reflect(rd, nW);
        vec3 col = envColour(rr) * fres * 0.8;
        float facet = hash11(dot(nn, vec3(12.9, 78.2, 37.7)));   // each face catches the light a little differently
        // Solid clear glass: every face catches the room's pink or cyan light a
        // little differently, a cyan body that deepens with thickness, a hot
        // glint where a face turns a light at you, and pink caught inside.
        float faceLit = 0.5 + 0.5 * dot(nW, normalize(vec3(0.5, 0.6, -0.6)));
        col += mix(ribbonPink, ribbonCyan, step(0.55, facet)) * (0.02 + 0.1 * facet * facet) * faceLit * (0.5 + 0.5 * uActive);
        float thick = clamp((tf - tn) / r, 0.0, 2.0);
        col += glassCyan * 0.045 * thick * (0.5 + 0.5 * uActive);
        col += ribbonPink * 0.2 * smoothstep(h, -h, pIn.y) * thick * (0.4 + 0.6 * uActive);
        float g1 = max(dot(rr, normalize(vec3(0.6, 0.25, -0.7))), 0.0);
        float g2 = max(dot(rr, normalize(vec3(0.1, 1.0, -0.3))), 0.0);
        g1 *= g1; g1 *= g1; g1 *= g1; g1 *= g1; g1 *= g1;      // ^32
        g2 *= g2; g2 *= g2; g2 *= g2; g2 *= g2; g2 *= g2;
        col += (vec3(1.0, 0.75, 0.9) * g1 + vec3(0.85, 1.0, 1.0) * g2) * 1.6;
        float lit = (0.45 + 0.55 * uActive) * (0.9 + 0.2 * uTreble + 0.5 * gSwell);

        if (full) {
            // Through the glass: bend in, cross to the far face, bend out.
            vec3 d1 = refract(ord, nn, 1.0 / 1.15);
            float tn2, tf2; vec3 nn2, nf2;
            gemHit(pIn + d1 * 0.002, d1, faces, h, tn2, tf2, nn2, nf2);
            vec3 pOut = pIn + d1 * (0.002 + tf2);
            vec3 wOut = fromGem(pOut, ang) + c;
            // Leaving the glass. Its faces come in parallel pairs, so the light
            // leaves in the direction it came in, shifted sideways by its path
            // through the glass. That path is smooth across each face, so the
            // view through a face is too. (Bending it out by whichever far face
            // it happened to reach split each face into hard-edged patches, dark
            // where that face reflected the light back in.)
            vec3 behind = skyColour(rd) + ribbonsAlong(wOut, rd, 0.002, 0.0, 30.0, false) * 0.7;
            // Towards the rim more of the light reflects back inside, so the glass
            // shades down to the dark room there: one smooth roll-off over the
            // rounded shape, rather than face by face.
            float rim = 1.0 - abs(dot(ord, normalize(pIn)));
            behind = mix(behind, skyColour(fromGem(reflect(d1, -nf2), ang)) * 1.3, smoothstep(0.2, 0.75, rim) * 0.9);
            col += behind * vec3(0.8, 1.0, 1.05) * (1.0 - fres) * (1.0 + 0.5 * facet);
            vec2 edgeBack = gemEdge(pOut, faces, h, edgeW * 1.2);
            // A ribbon passing through the glass lights it from inside.
            float tz = ribbonT(ro, rd, 0);
            if (tz > tHit && tz < tHit + (tf - tn)) col += ribbonLight((ro + rd * tz).xy, 0.0, 0) * 0.6;
            col += glassCyan * (edgeBack.x * 0.12 + edgeBack.y * 0.15) * lit * (1.0 - 0.7 * blur);
        }
        vec2 edgeGlow = gemEdge(pIn, faces, h, min(edgeW * 3.0, h * 0.08));
        vec3 edgeHot = mix(glassCyan, vec3(0.75, 1.0, 1.0), 0.1);   // edges burn a little whiter than their glow
        col += edgeHot * (edgeFront.x * 1.5 + edgeFront.y * 1.4) * (1.0 - 0.6 * blur) * lit;
        col += glassCyan * edgeGlow.x * 0.75 * (1.0 - 0.6 * blur) * lit;
        return col;
    }

    void main() {
        gSwell = beatSwell();
        gSpec = (ribbonSpec(0.05) + ribbonSpec(0.15) + ribbonSpec(0.25)) / 3.0;
        gPlay = playAmount();
        gGlass = smoothstep(0.35, 1.0, gPlay);
        gPx = 3.4 / 1.3 / uResolution.y;
        gDrive = pulseDrive();
        float lines = 1.0 - smoothstep(0.0, 0.3, gPlay);  // the exact lines take over from the ribbons at the end
        vec2 p = screenP();
        // Camera sits low by the glossy floor and sways slowly (on the
        // sound-gated clock); it leans in a little on the bass. In silence it
        // turns to face straight ahead, so the lines lie level.
        // The scene itself slides left past it (sceneShift).
        float yaw = 0.12 * sin(uTime * 0.07) * gPlay;
        // The lens is shifted up rather than tilted, so the horizon sits low and
        // the glass stays upright.
        vec3 ro = vec3(0.0, -0.40, -3.3 + 0.06 * gSwell);
        ro.xz = rot(yaw) * ro.xz;
        vec3 fw = vec3(-sin(yaw), 0.0, cos(yaw));
        vec3 rt = vec3(cos(yaw), 0.0, sin(yaw));
        vec3 rd = normalize(p.x * rt + vec3(0.0, p.y + 0.24, 0.0) + 1.3 * fw);

        float tFloor = rd.y < 0.0 ? (kFloorY - ro.y) / rd.y : 1e5;
        vec3 sky = skyColour(rd);
        vec3 col = sky;
        bool ribbons = lines < 1.0;                      // fully settled: only the exact lines are left

        int j = -1; float tGem = tFloor;
        bool hitGem = gGlass > 0.0 && nearestGem(ro, rd, tFloor, j, tGem);
        if (tFloor < 1e4 && (!hitGem || gGlass < 1.0)) {
            // Glossy black floor: a near-mirror of the ribbons and the glass,
            // softening with distance and fading into the hot horizon line.
            vec3 fp = ro + rd * tFloor;
            vec3 rr = reflect(rd, vec3(0.0, 1.0, 0.0));
            float fres = 0.30 + 0.70 * pow(1.0 - clamp(-rd.y, 0.0, 1.0), 5.0);
            vec3 refl = skyColour(rr) * 0.8;
            vec3 glassPool = vec3(0.0);
            if (gGlass > 0.0) {
                int j2; float t2;
                if (nearestGem(fp, rr, 40.0, j2, t2)) refl = mix(refl, shadeGem(j2, fp, rr, t2, false), gGlass);
                refl += gemHalo(fp, rr, 40.0, glassPool) * 2.0 * gGlass;
            }
            if (ribbons) refl += ribbonsAlong(fp, rr, 0.01, 0.035, 40.0, false) * (1.0 - lines);
            col = vec3(0.002, 0.006, 0.014) + refl * fres * 0.75;
            // the ribbons' light pooling on the floor beneath them
            float pool = (exp(-abs(fp.z - ribbonDepth(fp.x, 0)) * 0.8) + 0.35 * exp(-abs(fp.z - ribbonDepth(fp.x, 2)) * 1.6))
                       * smoothstep(-4.8, -2.5, fp.x) * smoothstep(4.8, 2.5, fp.x);
            col += ribbonPink * 0.6 * pool * (0.4 + 0.6 * uActive) * (0.85 + 0.25 * gSwell);
            col += glassPool * 0.8 * (0.4 + 0.6 * uActive) * gGlass;
            col = mix(col, sky, smoothstep(8.0, 30.0, tFloor));
        }
        // Ribbons in front of whatever we hit; as the glass fades, the ribbons
        // behind it show through.
        if (hitGem) col = mix(col, shadeGem(j, ro, rd, tGem, true), gGlass);
        if (ribbons) {
            gCut = hitGem ? tGem : 1e9;
            gBehind = 1.0 - gGlass;
            col += ribbonsAlong(ro, rd, 0.0, 0.0, tFloor, true) * (1.0 - lines);
        }
        if (gGlass > 0.0) {
            vec3 unused;
            col += gemHalo(ro, rd, hitGem ? tGem : tFloor, unused) * gGlass;
        }
        col += ribbonPink * gSwell * 0.015;

        col = 1.0 - exp(-col * 1.8);                   // soft highlight roll-off
        col *= 1.0 - 0.3 * dot(p, p);                   // vignette
        col = mix(col * 0.5, col, uActive);             // dims in silence
        // The ten still lines, in the ribbons' resting pink.
        col = mix(col, vec3(0.92, 0.2, 0.52), idleLines() * lines);
        fragColor = vec4(col, 1.0);
    }
    """
}

extension FunShaders {
    // MARK: - Silk Flight

    /// Flying forward through the music, after the fly-through in the AudioVane
    /// brand film (0:11 to 0:13): a round, ribbed satin ribbon, glossy hot
    /// pink, sweeps in from one frame edge, twists away through a teal nebula
    /// (turning electric violet in the distance) and comes back out on the
    /// other, while chunky smoky glass blocks tumble past on near-black space.
    /// The ribbon is two branches that ease onto one line deeper in, so it
    /// reads as one band. Each has an elliptical cross-section; per pixel, the first
    /// depth step where the ray enters it is solved exactly (at most 31 depth
    /// steps for both ends together, out to where it has faded, stopping once
    /// both are found), with soft pixel-wide coverage at the outline. It is
    /// shaded as a cylinder: corded ribs along its length that each catch a
    /// highlight (softened where they would get finer than a few pixels), a
    /// long satin streak down the lit side, falloff to the edges, a cyan and
    /// lilac rim, and a soft violet self-shadow underneath. The glass blocks are exact ray/box slabs. The glass is
    /// clear: the satin and the space behind are drawn again through the
    /// nearest block, bent by its faces, smoky and much darker where it is
    /// thick, with broad bevelled, colour-fringed edges, fresnel rims, a reflection
    /// across one face, inner diagonals and a glint. Each block rides beside
    /// one tube, on its own side and further off than its reach plus the
    /// tube's thickness, so it never passes through it; the other tube pushes
    /// it aside with a soft minimum distance, and where that tube sweeps right
    /// across a block, the block fades out rather than jumping. Blocks never
    /// touch each other: they all fly at one speed in fixed depth slots, and
    /// any two slots are further apart than the two blocks' reaches added.
    /// The deep sky is a dim nebula that billows and drifts on uTime, brightens
    /// and swells with uLevelSmooth and uBassSmooth and the soft beat swell,
    /// and leans slightly violet with the mids and brighter with the highs.
    /// Smooth by design: the camera flies on uTime (the eased activity clock)
    /// plus a small share of uScroll, so it speeds up and slows down gently
    /// and never runs backwards. The folds sway slowly, like silk in slow air,
    /// and the glass turns steadily; nothing steps on the beat. Each kick is a
    /// soft swell on the beat clock (in over ~150 ms, out over ~1 s), sized by
    /// uBassSmooth, that widens and brightens the satin and throws glitter that
    /// drifts outward. Snares and claps (the upper mids) send a ripple running
    /// down the satin; hats and cymbals (the top of the spectrum) make glitter
    /// catch round the tubes, the glass glint and the specks twinkle.
    /// Each band is an average over many bins. In silence: dim, and still.
    static let silk = """
    // Silk Flight: flying forward through the music. A round satin ribbon, a
    // glossy hot-pink tube with twisting folds, sweeps in from both frame edges
    // and winds away into a teal nebula that billows and breathes with the
    // music, turning electric violet in the distance, while chunky cyan glass
    // blocks tumble past on near-black space, never touching it or each other.
    const int kSilkSteps = 31;       // depth samples per ribbon branch (out to z ~17, where it has faded out)
    const int kSilkGlass = 8;        // glass blocks
    const float kSilkRibs = 12.0;    // ribs round each tube (about half face us)

    const vec3 silkPink   = vec3(1.00, 0.36, 0.62);
    const vec3 silkPinkHi = vec3(1.00, 0.66, 0.84);
    const vec3 silkFold   = vec3(0.72, 0.14, 0.46);
    const vec3 silkLilac  = vec3(0.90, 0.49, 0.99);
    const vec3 silkViolet = vec3(0.31, 0.22, 0.86);
    const vec3 silkCyan   = vec3(0.00, 1.00, 0.89);
    const vec3 silkDust   = vec3(0.20, 0.43, 0.47);

    // Smooth clocks. uTime only runs while there's sound and eases in and out of
    // it, so flying on it makes the camera accelerate and decelerate smoothly; a
    // small share of uScroll (distance that runs faster when louder, and never
    // backwards) lets it speed up a little with the music. Nothing here steps
    // on the beat.
    float silkTravel() { return uTime * 1.2 + uScroll * 0.35; }
    float silkFlow() { return uTime; }

    // A soft swell on every kick, in place of the raw bass and beat-strength
    // inputs (which jump from one frame to the next): it eases in over about
    // 150 ms on the (continuous) beat clock and dies away over about a second,
    // sized by the slow bass. Summing the last few beats keeps it continuous.
    float silkSwellAt(float x) { return smoothstep(0.0, 0.3, x) * exp(-x * 1.5); }
    float silkSwell() {
        float ph = fract(uBeats);
        return (silkSwellAt(ph) + silkSwellAt(ph + 1.0) + silkSwellAt(ph + 2.0)) * clamp(0.3 + 2.8 * uBassSmooth, 0.0, 1.2) * uActive;
    }
    float gSilkSwell;   // silkSwell(), worked out once per pixel at the top of main()
    float gSilkFlow;
    float gSilkMid;     // snares and claps: the upper mids, shaped 0..1
    float gSilkHi;      // hats and cymbals: the top of the spectrum, shaped 0..1
    vec4 gSilkSway;    // slow phase drifts for the ribbon's curves, from gSilkFlow
    float gSilkW;      // the tube's half-width across its cross-section, swelling a little on each kick
    float gSilkH;      // the tube's half-thickness (its cross-section is an ellipse W x H)
    float gSilkLv;     // smoothed loudness and bass, shaped 0..1, for the sky
    float gSilkBs;

    // Ribbon centre (xy) and twist (z) at world depth s, for branch b (0 or 1).
    // Near the camera each branch is pushed out to its own side, so it sweeps
    // in from the frame edge and never closes over the lens.
    // Depth terms of the ribbon path, shared by both branches at depth z.
    vec4 silkDepth(float z) {
        return vec4(1.8 * exp(-0.5 * z), 1.5 * smoothstep(1.5, 7.0, z), 0.4 * exp(-0.12 * z), 0.75 * exp(-0.06 * z));
    }
    vec3 silkBranch(float s, float b, vec4 k) {
        float side = b < 0.5 ? -1.0 : 1.0;
        float cross = side * (0.75 + k.x - k.y);
        vec4 f = gSilkSway;   // slow air: each curve's phase drifts, so the ribbon sways
        return vec3(cross + 1.1 * sin(s * 0.7 + b * 2.4 + f.x) + k.z * sin(s * 1.13 + b * 5.1 + f.y),
                    side * (-0.25 - 0.55 * k.x) + 0.05 + 0.45 * sin(s * 0.47 + b * 1.7 + 2.0 + f.z),
                    0.5 + k.w * sin(s * 0.41 + b * 3.0 + 1.0 + f.w));
    }
    // The two branches are one band: deeper in, each eases onto their shared
    // middle line, so the ribbon comes in from one side, loops away through the
    // distance and comes back out on the other, all in one piece.
    float silkJoin(float z) { return smoothstep(2.6, 6.5, z); }
    vec3 silkJoined(vec3 c, vec3 o, float j) { return mix(c, 0.5 * (c + o), j); }
    vec3 silkPath(float s, float z, float b) {
        vec4 k = silkDepth(z);
        return silkJoined(silkBranch(s, b, k), silkBranch(s, 1.0 - b, k), silkJoin(z));
    }

    // The ray point at depth z in the tube's cross-section, scaled so the tube's
    // elliptical outline is the unit circle (x across its width, y through it).
    // The tube tapers into the distance, so a stretch heading away from us thins
    // to a silky tail instead of showing a blunt round end.
    float silkTaper(float z) { return mix(1.0, 0.32, smoothstep(1.5, 9.0, z)); }
    vec2 silkTube(vec2 rd, float z, vec3 c, vec2 iwh) {
        vec2 q = rd * z - c.xy;
        vec2 t = vec2(cos(c.z), sin(c.z));
        return vec2(dot(q, t), dot(q, vec2(-t.y, t.x))) * iwh / silkTaper(z);
    }

    // Where the ray, moving from a0 to a1 (cross-section coordinates) between
    // two depth samples, first enters the tube: depth, the entry point on the
    // outline, and coverage (soft over about a pixel at the silhouette, so the
    // edge stays smooth). Solved exactly for the straight segment, so a thin
    // part of the tube can't slip between samples.
    vec4 silkCross(vec2 a0, vec2 a1, float z0, float z1, float aa) {
        vec2 da = a1 - a0;
        float A = max(dot(da, da), 1e-8);
        float bq = dot(a0, da);
        float k = clamp(-bq / A, 0.0, 1.0);
        float dmin = length(a0 + da * k);
        // A near miss counts (as partial coverage) only where it is closest
        // inside this step; at either end the neighbouring step decides.
        if (dmin > 1.0 + aa || (dmin >= 1.0 && (k <= 0.0 || k >= 1.0))) return vec4(1e5, 0.0, 0.0, 0.0);
        float disc = bq * bq - A * (dot(a0, a0) - 1.0);
        float ke = disc > 0.0 ? clamp((-bq - sqrt(disc)) / A, 0.0, k) : k;
        vec2 a = a0 + da * ke;
        a /= max(length(a), 1e-4);
        // Coverage eases off over a pixel only where the ray grazes the outline
        // within this step; a ray still heading inward at the step's end is in.
        float cov = k >= 1.0 || k <= 0.0 ? 1.0 : 1.0 - smoothstep(1.0 - aa, 1.0 + aa, dmin);
        return vec4(mix(z0, z1, ke), a, cov);
    }

    float facingOf(vec3 n, vec2 rd) { return clamp(-dot(n, normalize(vec3(rd, 1.0))), 0.0, 1.0); }
    vec3 silkShade(vec2 rd, float z, float s, vec2 a, float b) {
        vec3 c = silkPath(s, z, b);
        vec3 c2 = silkPath(s + 0.15, z + 0.15, b);
        vec2 t = vec2(cos(c.z), sin(c.z));
        vec3 D = normalize(vec3((c2.xy - c.xy) / 0.15, 1.0));   // along the tube
        // The outline's normal at the entry point, turned square to the tube.
        vec2 g = vec2(a.x / gSilkW, a.y / gSilkH);       // the taper scales both alike
        vec3 N = vec3(t * g.x + vec2(-t.y, t.x) * g.y, 0.0);
        N = normalize(N - D * dot(N, D));
        vec3 V = normalize(vec3(rd, 1.0));
        vec3 R = normalize(cross(D, N));                 // round the tube
        float f = gSilkFlow;
        // Satin folds wound round the tube, twisting along its length and slowly
        // re-folding; snares and claps send a ripple running down it.
        float th = atan(a.y, a.x);
        float tw = th * 3.0 + s * 1.5 + c.z * 3.0 + 0.6 * sin(s * 0.3 + b * 3.0 + f * 0.21);
        float fold = sin(tw);
        float rip = gSilkMid * sin(s * 2.6 - f * 7.0 + b * 2.0);
        // Ribs: fine corded ridges running the length of the tube, like the
        // film's ribbed satin, turning with its twist; each catches its own
        // highlight. They soften away where they would get finer than a few
        // pixels (far off, and toward the outline) so they never shimmer.
        float rp = th * kSilkRibs + 0.3 * s + 0.5 * fold;
        float ribPx = 6.2832 * gSilkH * silkTaper(z) / kSilkRibs * uResolution.y / (1.25 * z) * (0.25 + 0.75 * facingOf(N, rd));
        float ribA = smoothstep(2.0, 5.0, ribPx) * 0.85;
        float ridge = sin(rp);
        vec3 Np = normalize(N + R * (0.16 * fold + 0.6 * ribA * cos(rp)) + D * (0.1 * sin(s * 0.8 + f * 0.4) + 0.05 * rip));
        float facing = clamp(-dot(N, V), 0.0, 1.0);
        vec3 L = normalize(vec3(0.35, 0.75, -0.55));
        float dif = max(dot(Np, L), 0.0);
        vec3 H = normalize(L - V);
        float spec = pow(max(dot(Np, H), 0.0), 40.0) * 1.6 + 0.3 * pow(max(dot(Np, H), 0.0), 6.0);
        // Satin's long highlight: the fibres run along the tube, so the sheen is
        // a streak down its length on the lit side.
        float dh = dot(D, H);
        float aniso = pow(sqrt(max(1.0 - dh * dh, 0.0)), 36.0) * smoothstep(-0.2, 0.5, dot(N, L))
                    * (0.75 + 0.25 * sin(th * 23.0 + 2.0 * fold));   // fine satin grain in the streak
        // Satin: a ramp from deep magenta through hot pink to a pale pink sheen.
        float k = clamp(0.2 + 0.75 * dif + 0.08 * fold, 0.0, 1.0);
        vec3 hot = vec3(1.0, 0.24, 0.7);                 // the film's hot magenta-pink
        vec3 col = k < 0.5 ? mix(silkFold * 0.8, hot, k * 2.0) : mix(hot, silkPinkHi, k * 2.0 - 1.0);
        // Round: falls away toward the edges, and the underside sits in its own
        // soft shadow, cooling to violet.
        float under = smoothstep(0.15, -0.75, Np.y);
        col *= (0.6 + 0.4 * sqrt(facing)) * (1.0 - 0.35 * under);
        col = mix(col, silkViolet * 0.8, under * 0.45);
        col *= 0.75 + 0.25 * smoothstep(-1.0, 0.4, fold);  // the creases between folds
        col *= 1.0 - ribA * 0.35 * smoothstep(0.2, -1.0, ridge);   // the grooves between ribs
        col += vec3(1.0, 0.8, 0.94) * (spec + 1.1 * aniso) * (1.2 + 0.3 * gSilkSwell + 0.4 * gSilkHi);
        // Rim light round the outline: cyan from above, lilac from below.
        float rim = pow(1.0 - facing, 3.0);
        col += mix(silkLilac * 0.8, vec3(0.45, 0.95, 1.0), smoothstep(-0.3, 0.6, N.y)) * rim * (0.55 + 0.15 * gSilkSwell);
        // Hats and cymbals: glitter catching round the sides of the tube.
        vec2 gq = vec2(th * 8.0, s * 40.0);
        vec2 gc = floor(gq);
        float gh = hash21(gc + b * 13.0);
        float glit = step(0.8, gh) * (gh * 4.0 - 3.0) * (1.0 - smoothstep(0.12, 0.38, length(fract(gq) - 0.5)))
                   * smoothstep(0.35, 0.8, 1.0 - facing) * (1.0 - smoothstep(3.0, 6.0, z));
        col += vec3(1.0, 0.9, 1.0) * glit * gSilkHi * 1.2;
        // Far away the ribbon cools to electric violet-blue and sinks into the dust.
        float far = smoothstep(1.8, 7.0, z);
        float band = 0.9 + 0.15 * bandAt(clamp(z / 18.0, 0.0, 1.0)) + 0.1 * gSilkSwell;     // a faint spectrum glow on the far ribbon
        col = mix(col, (mix(silkViolet, silkLilac, 0.35 * dif + spec) * (0.6 + 0.6 * dif) * (0.6 + 0.4 * sqrt(facing)) + spec * 0.4 + rim * silkLilac * 0.3) * band, far * 0.9);
        col = mix(col, silkDust * 0.6, smoothstep(12.0, 30.0, z));
        return col;
    }

    vec4 silkScene(vec2 p, vec2 rd, float travel);   // below

    // Glass block sizes (half-extents: a mix of big chunky slabs and small
    // cubes) and their depth slots.
    const vec3 kSilkSize[8] = vec3[8](vec3(0.739, 0.605, 0.694), vec3(0.358, 0.314, 0.347), vec3(0.560, 0.470, 0.538), vec3(0.806, 0.582, 0.672), vec3(0.336, 0.302, 0.370), vec3(0.582, 0.448, 0.526), vec3(0.694, 0.650, 0.627), vec3(0.403, 0.347, 0.381));
    const float kSilkSlot[8] = float[8](0.000, 1.820, 3.367, 5.524, 7.358, 8.896, 10.988, 12.831);

    // Glass block i: where it is, its size, how it is turned, and how faded in.
    // Each block keeps clear of both satin tubes: it is pushed out from the
    // nearest point of each tube's cross-section at its depth with a soft
    // minimum distance, so it glides round the satin instead of through it.
    // The blocks never touch each other either: they all fly at the same speed,
    // spaced in depth so that any two are always further apart than their two
    // reaches put together, so however they turn and drift, no two can overlap.
    void silkBlock(int i, float travel, out vec3 c, out vec3 hs, out vec2 ang, out float fade) {
        float n = float(i);
        // Depth slots: each gap is the two neighbours' reaches added (plus 0.05),
        // so any two blocks are always further apart in depth than they can reach.
        float span = 14.716;
        float z = 0.9 + mod(kSilkSlot[i] - travel, span);
        fade = smoothstep(13.0, 7.0, z) * smoothstep(1.5, 2.5, z);
        hs = kSilkSize[i];
        ang = vec2(uTime * (0.32 + 0.2 * hash11(n * 9.1)) + n, uTime * (0.12 + 0.15 * hash11(n * 1.3)) + n * 2.0);
        float clear = length(hs) + 0.4 + gSilkH;         // its reach, the tube's thickness, and room for its slope over the block's depth
        // Each block rides beside one satin band, on its own side of it and
        // never closer than its reach, so it drifts along with the satin and
        // can never pass through that band.
        float own = mod(n, 2.0);
        float side = hash11(n * 4.1 + 0.2) < 0.5 ? -1.0 : 1.0;
        vec3 rp = silkPath(travel + z, z, own);
        vec2 t = vec2(cos(rp.z), sin(rp.z));
        float gap = clear + 0.35 + (0.1 + 0.7 * hash11(n * 2.3 + 0.53)) * (0.3 + 0.12 * z);
        c = vec3(rp.xy + t * (hash11(n * 7.13 + 0.17) - 0.5) * 1.4 * gSilkW + vec2(-t.y, t.x) * side * gap, z);
        // The other band: pushed out of its way with a soft minimum distance.
        // Where that band sweeps right across the block's lane it would have to
        // jump to the far side, so it fades out as the band closes in instead.
        vec3 ro = silkPath(travel + z, z, 1.0 - own);
        vec2 to = vec2(cos(ro.z), sin(ro.z));
        vec2 P = ro.xy + to * clamp(dot(c.xy - ro.xy, to), -gSilkW, gSilkW);
        vec2 dv = c.xy - P;
        float d = max(length(dv), 1e-4);
        float co = clear + 0.25;                          // a little more room from the band it doesn't ride
        float nd = co + 0.15 * log(1.0 + exp((d - co) / 0.15));   // soft max(d, co)
        c.xy = P + dv / d * nd;
        fade *= smoothstep(0.3, 0.65, d / co);
    }

    // Ray/box slabs against block i, in the block's own frame.
    vec2 silkSlab(vec3 rd, vec3 c, vec3 hs, vec2 ang, out vec3 ro, out vec3 d) {
        mat2 r1 = rot(ang.x), r2 = rot(ang.y);
        ro = -c;
        ro.xz = r1 * ro.xz; ro.xy = r2 * ro.xy;
        d = rd;
        d.xz = r1 * d.xz; d.xy = r2 * d.xy;
        vec3 m = 1.0 / d;
        vec3 k = abs(m) * hs;
        vec3 t1 = -m * ro - k, t2 = -m * ro + k;
        return vec2(max(max(t1.x, t1.y), t1.z), min(min(t2.x, t2.y), t2.z));
    }

    // A box-space direction back in the world.
    vec3 silkUnturn(vec3 v, vec2 ang) {
        v.xy = rot(-ang.y) * v.xy;
        v.xz = rot(-ang.x) * v.xz;
        return v;
    }

    // Shade the glass: a clear, slightly cyan body that shows the satin and the
    // space behind it, bent by the faces; bright bevelled edges with a touch of
    // colour fringing; fresnel rims; inner reflections; and a sharp glint.
    vec3 silkGlassShade(vec3 col, vec2 p, vec3 rd, float travel, int i, vec3 c, vec3 hs, vec2 ang, float fade) {
        float n = float(i);
        vec3 ro, d;
        vec2 tt = silkSlab(rd, c, hs, ang, ro, d);
        float tN = tt.x, tF = tt.y;
        vec3 pf = (ro + d * tN) / hs, pb = (ro + d * tF) / hs;
        vec3 af = abs(pf), ab = abs(pb);
        float px = 1.5 * tN / uResolution.y * 1.6 / min(min(hs.x, hs.y), hs.z);
        vec3 ef = 1.0 - af, eb = 1.0 - ab;
        float edgeF = min(min(max(ef.x, ef.y), max(ef.y, ef.z)), max(ef.x, ef.z));
        float edgeB = min(min(max(eb.x, eb.y), max(eb.y, eb.z)), max(eb.x, eb.z));
        vec3 nf = step(vec3(max(max(af.x, af.y), af.z)), af) * sign(pf);
        vec3 nb = step(vec3(max(max(ab.x, ab.y), ab.z)), ab) * sign(pb);
        vec3 nfW = silkUnturn(nf, ang), nbW = silkUnturn(nb, ang);
        vec3 dn = normalize(d);
        float thick = clamp((tF - tN) / (2.0 * hs.z), 0.0, 1.5);
        float th = min(thick, 1.0);

        // What lies behind, seen through the block: bent by the front face and
        // again by the back face, as a slab of glass would.
        vec2 off = -(nfW.xy * 0.11 + nbW.xy * 0.07) * (0.6 + 0.4 * th);
        vec4 behind = silkScene(p + off / 1.25, rd.xy + off, travel);
        vec3 bc = behind.w < tN ? col : behind.rgb;      // satin nearer than the block stays as it was
        // Smoky glass: what's behind darkens fast with thickness, under a faint
        // teal haze, so the body reads deep and the edges carry the light.
        vec3 g = bc * mix(vec3(0.36, 0.62, 0.68), vec3(0.05, 0.15, 0.2), th) + vec3(0.0, 0.03, 0.04) * (0.5 + th);

        vec3 L = normalize(vec3(0.4, 0.8, -0.4));
        L.xz = rot(ang.x) * L.xz; L.xy = rot(ang.y) * L.xy;
        float lit = max(dot(nf, L), 0.0);
        float fres = pow(1.0 - abs(dot(nf, dn)), 3.0);
        // Inner reflection: one face of each block catches a soft cyan sheen.
        float tone = hash11(dot(nf, vec3(1.0, 2.0, 3.0)) + n * 1.3 + 0.5);
        float sheet = step(0.38, tone) * smoothstep(-1.2, 1.0, dot(pf, vec3(0.6, -0.5, 0.4)) + 0.8 * (tone - 0.7));
        // Inner diagonals (reflections of the edges inside), front and back.
        float diag = abs(abs(ab.x * nf.y + ab.y * nf.z + ab.z * nf.x) - abs(ab.y * nf.y + ab.z * nf.z + ab.x * nf.x));
        float diagF = abs(abs(af.x * nf.y + af.y * nf.z + af.z * nf.x) - abs(af.y * nf.y + af.z * nf.z + af.x * nf.x));
        float lineD = (1.0 - smoothstep(0.012, 0.012 + px, diag)) * 0.55 + (1.0 - smoothstep(0.01, 0.01 + px, diagF)) * 0.4;
        // Hard reflection bands across the front faces.
        float st = abs(fract(dot(pf, vec3(0.55, 0.4, 0.5)) * 0.9 + hash11(n * 4.7)) - 0.5);
        float refl = 1.0 - smoothstep(0.05, 0.05 + px, st);
        float glint = pow(max(dot(reflect(dn, nf), L), 0.0), 80.0);

        g += silkCyan * (0.08 * lit + 0.5 * fres + 0.8 * sheet * sheet + 0.15 * refl) * (0.75 + 0.1 * gSilkSwell);
        g += vec3(0.7, 1.0, 1.0) * (0.25 * fres * fres + 0.12 * refl);
        // Bevelled edges: a bright core, a wider bevel fringed pink on one side
        // and cyan on the other, and a dark line where the bevel turns away.
        float e1 = 1.0 - smoothstep(0.03, 0.03 + px, edgeF);
        float e2 = 1.0 - smoothstep(0.12, 0.12 + 1.5 * px, edgeF);
        float e3 = 1.0 - smoothstep(0.145, 0.145 + 1.5 * px, edgeF);
        float b1 = 1.0 - smoothstep(0.018, 0.018 + px, edgeB);
        float fr = smoothstep(-0.4, 0.4, dot(nfW.xy, vec2(0.6, 0.8)));
        float lift = 0.9 + 0.25 * gSilkSwell;
        g *= 1.0 - 0.6 * (e3 - e2);
        float bev = (e2 - e1) * (0.3 + 0.7 * smoothstep(0.12, 0.03, edgeF));   // the bevel brightens toward the edge
        g += mix(vec3(1.0, 0.4, 0.85), vec3(0.3, 1.0, 1.0), fr) * bev * 1.15 * lift;
        g += vec3(0.45, 1.0, 0.98) * (e1 * 1.7 + b1 * 0.65 + lineD * 0.65) * lift;
        g += vec3(1.0) * glint * (1.8 + 2.0 * gSilkHi);
        return mix(col, g, fade);
    }

    float silkNoise(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
                   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
    }

    // Space and satin seen along rd (p is the matching screen point for the
    // space layers). Returns the colour and the depth of the nearest satin.
    vec4 silkScene(vec2 p, vec2 rd, float travel) {
        // Deep sky: a dim teal nebula that billows and drifts on the eased clock
        // (so it is still in silence), breathes brighter and swells outward with
        // the smoothed loudness and bass and the soft beat swell, and leans a
        // little violet with the mids and brighter with the highs. All eased;
        // nothing here steps on a beat.
        float f = gSilkFlow;
        float lv = gSilkLv, bs = gSilkBs;
        float swell = 1.0 + 0.18 * lv + 0.14 * bs + 0.05 * gSilkSwell;   // the cloud grows with the music
        vec2 wq = p * 1.4 + vec2(travel * 0.012, 0.0);
        vec2 warp = vec2(silkNoise(wq * 1.3 + vec2(f * 0.07, 1.7)), silkNoise(wq * 1.3 + vec2(5.2, 0.6 - f * 0.06))) - 0.5;
        warp *= 0.9 + 0.7 * bs;                          // billows harder with the bass
        vec2 nq = wq + warp;
        float neb = silkNoise(nq * 1.6 + vec2(0.0, f * 0.03)) * 0.62 + silkNoise(nq * 3.3 + vec2(3.0 - f * 0.05, 1.0)) * 0.38;
        vec3 col = vec3(0.0, 0.05, 0.025) + vec3(0.0, 0.05, 0.07) * smoothstep(0.7 * swell, 0.0, length(p * vec2(0.7, 1.4)));
        vec2 pg = p * vec2(1.1, 1.8) / swell;
        float glow = smoothstep(0.3, 0.95, neb) * exp(-dot(pg, pg));
        vec3 nebC = mix(vec3(0.04, 0.19, 0.23), vec3(0.17, 0.12, 0.34), 0.07 * gSilkMid + 0.3 * smoothstep(0.45, 0.9, neb));
        col += nebC * glow * (0.05 + 0.32 * lv + 0.25 * gSilkSwell * (0.4 + bs) + 0.03 * gSilkHi) * (0.35 + 0.65 * uActive);
        // Its bright heart: a drifting cloud of dust in the middle, carried on
        // the same billows.
        vec2 pc = (p - vec2(0.05, 0.03) - warp * 0.1) * vec2(1.8, 3.2) / swell;
        float core = exp(-dot(pc, pc));
        float dust = 0.0;
        if (core > 0.02) {                               // the cloud is nothing out at the corners
            vec2 dq = p * 2.2 + vec2(travel * 0.02, 0.0) + warp * 0.5;
            float dn = silkNoise(dq * 1.6) * 0.45 + silkNoise(dq * 3.4 + 7.0) * 0.27 + silkNoise(dq * 7.5 - 3.0) * 0.17 + silkNoise(dq * 16.0 + 1.0) * 0.11;
            dust = smoothstep(0.25, 0.85, dn) * core * 1.5;
        }
        col += silkDust * dust * 1.25 * (0.5 + 0.55 * lv + 0.25 * gSilkSwell + 0.04 * gSilkHi) * (0.6 + 0.4 * uActive);
        // Fine specks streaming outward as we fly.
        for (int l = 0; l < 3; l++) {
            float fl = float(l);
            float ph = fract(travel * 0.08 + fl / 3.0);
            vec2 sp = p * mix(14.0, 2.5, ph) * 30.0 + fl * 37.0;
            vec2 cell = floor(sp);
            float h = hash21(cell);
            float sd = length(fract(sp) - 0.5 - 0.3 * (vec2(hash21(cell + 3.1), hash21(cell + 5.7)) - 0.5));
            float pxc = mix(14.0, 2.5, ph) * 30.0 / uResolution.y;   // one pixel, in cells: soft enough not to shimmer
            float star = step(0.93, h) * (1.0 - smoothstep(0.05, 0.25 + 1.2 * pxc, sd)) / (1.0 + 6.0 * pxc * pxc) * smoothstep(0.0, 0.3, ph) * smoothstep(1.0, 0.8, ph);
            col += mix(vec3(0.75, 0.35, 0.9), vec3(0.8, 0.9, 1.0), hash21(cell + 9.0)) * star * (0.45 + 0.12 * gSilkSwell + 0.4 * gSilkHi * step(0.6, hash21(cell + 11.0))) * (0.4 + 0.6 * dust + 0.3 * uActive);
        }

        // The ribbon: two branches, each a round tube. Along the ray (exponential
        // depth steps, front to back) the first step where the ray enters a
        // tube's cross-section is solved exactly.
        vec2 iwh = vec2(1.0 / gSilkW, 1.0 / gSilkH);
        float aak = 1.5 * 1.25 / (uResolution.y * gSilkH);  // a pixel, in cross-section units per unit of depth
        vec4 hitA = vec4(1e5, 0.0, 0.0, 0.0), hitB = vec4(1e5, 0.0, 0.0, 0.0);   // z, entry point, coverage
        vec2 prevA = vec2(0.0), prevB = vec2(0.0);
        float zPrev = 0.0;
        for (int i = 0; i < kSilkSteps; i++) {
            float z = 0.45 * pow(1.13, float(i));
            float s = travel + z;
            vec4 dk = silkDepth(z);
            vec3 ca = silkBranch(s, 0.0, dk), cb = silkBranch(s, 1.0, dk);
            float jn = silkJoin(z);
            vec2 fa = silkTube(rd, z, silkJoined(ca, cb, jn), iwh);
            vec2 fb = silkTube(rd, z, silkJoined(cb, ca, jn), iwh);
            if (i > 0) {
                float aa = aak * z / silkTaper(z);
                if (hitA.x > 1e4) hitA = silkCross(prevA, fa, zPrev, z, aa);
                if (hitB.x > 1e4) hitB = silkCross(prevB, fb, zPrev, z, aa);
                if (hitA.x < 1e4 && hitB.x < 1e4) break;
            }
            prevA = fa; prevB = fb; zPrev = z;
        }
        float zr = 1e5;
        // Composite far branch first, then near.
        for (int j = 0; j < 2; j++) {
            vec4 h = (j == 0) == (hitA.x > hitB.x) ? hitA : hitB;
            float b = (j == 0) == (hitA.x > hitB.x) ? 0.0 : 1.0;
            if (h.x > 1e4) continue;
            float alpha = h.w * smoothstep(17.0, 9.0, h.x);
            if (h.w > 0.5) zr = min(zr, h.x);
            col = mix(col, silkShade(rd, h.x, travel + h.x, h.yz, b), alpha);
        }

        return vec4(col, zr);
    }

    void main() {
        vec2 p = screenP();
        gSilkSwell = silkSwell();
        gSilkFlow = silkFlow();
        // The other parts of the music, each an average over many bands so it is
        // smooth across the spectrum, and shaped so a hat or a clap reads clearly.
        float bm = 0.0, bh = 0.0;
        for (int i = 0; i < 28; i++) bm += uBands[44 + i];    // ~0.8-3.5 kHz
        for (int i = 0; i < 16; i++) bh += uBands[80 + i];    // ~6-16 kHz
        gSilkMid = smoothstep(0.065, 0.11, sqrt(bm / 28.0)) * uActive;
        gSilkHi = smoothstep(0.03, 0.09, sqrt(bh / 16.0)) * uActive;
        gSilkSway = vec4(0.45 * sin(gSilkFlow * 0.23), 0.7 * sin(gSilkFlow * 0.31 + 1.0),
                         0.5 * sin(gSilkFlow * 0.19 + 2.0), 0.55 * sin(gSilkFlow * 0.27 + 3.0));
        gSilkW = 0.47 * (1.0 + 0.06 * gSilkSwell);
        gSilkH = 0.34 * (1.0 + 0.06 * gSilkSwell);
        gSilkLv = smoothstep(0.0, 0.18, uLevelSmooth);
        gSilkBs = smoothstep(0.0, 0.4, uBassSmooth);
        p = rot(0.06 * sin(uTime * 0.05)) * p;
        float travel = silkTravel();
        vec2 rd = p * 1.25 + vec2(0.04 * sin(uTime * 0.11), 0.03 * sin(uTime * 0.083 + 1.0));

        vec4 sc0 = silkScene(p, rd, travel);
        vec3 col = sc0.rgb;

        // Glass blocks: the nearest one in front of the satin on this ray.
        int gi = -1;
        float gt = sc0.w;
        vec3 gc = vec3(0.0), ghs = vec3(1.0);
        vec2 gang = vec2(0.0);
        float gfade = 0.0;
        for (int i = 0; i < kSilkGlass; i++) {
            vec3 c, hs; vec2 ang; float fade;
            silkBlock(i, travel, c, hs, ang, fade);
            if (fade <= 0.0) continue;
            vec3 ro, d;
            vec2 tt = silkSlab(vec3(rd, 1.0), c, hs, ang, ro, d);
            if (tt.x > tt.y || tt.y < 0.0 || tt.x > gt) continue;
            gi = i; gt = tt.x; gc = c; ghs = hs; gang = ang; gfade = fade;
        }
        if (gi >= 0) col = silkGlassShade(col, p, vec3(rd, 1.0), travel, gi, gc, ghs, gang, gfade);

        // Beat sparks: pink and cyan glitter drifting outward from each beat,
        // fading in over the swell's rise and out over about a second. The last
        // two beats' bursts overlap so nothing pops at the beat.
        float ang = atan(p.y, p.x) * 7.0;
        float pr = length(p);
        for (int j = 0; j < 2; j++) {
            float fj = float(j);
            float cellA = floor(ang + fj * 0.5) + fj * 50.0;
            float a2 = (floor(ang + fj * 0.5) + 0.5 - fj * 0.5 + 0.6 * (hash11(cellA * 2.1) - 0.5)) / 7.0;
            vec2 dir = vec2(cos(a2), sin(a2));
            vec3 sc = mix(silkPink, silkCyan, hash11(cellA * 1.3));
            for (int k = 0; k < 2; k++) {
                float bk = floor(uBeats) - float(k);
                float x = uBeats - bk;                      // time since that beat, in beats
                float hs = hash11(cellA + bk * 1.37);
                float rr = 0.07 + (1.0 - exp(-x * 1.1)) * (0.12 + 0.3 * hs);   // eased outward drift, like glitter in slow air
                if (hs < 0.5 || abs(pr - rr) > 0.02) continue;
                float spark = 1.0 - smoothstep(0.002, 0.006 + 0.004 * hs + 1.5 / uResolution.y, length(p - dir * rr));
                col += sc * spark * silkSwellAt(x) * uActive * 1.4;
            }
        }

        col *= 1.0 - 0.25 * dot(p, p);                  // vignette
        col = mix(col * 0.5, col, smoothstep(0.0, 1.0, uActive));   // dims and settles in silence, easing
        fragColor = vec4(col, 1.0);
    }
    """
}

extension FunShaders {
    // MARK: - Flux

    /// An abstract long-exposure light sweep, after the climax of the AudioVane
    /// brand film (0:38 to 0:40). Huge fanned sheets of fine light strands,
    /// hot pink and molten gold, sweep in from the edges of the frame and
    /// pinch and swirl into a vanishing point that drifts round the middle
    /// while the view rolls, like light trails seen while flying. Everything
    /// is drawn in log-polar space round the vanishing point, so equal steps
    /// fly past at equal speed: each sheet is an angular band that swirls
    /// harder near the centre, its strands are hairlines across the band
    /// (softened where they crowd together so they never shimmer), smeared
    /// outward by 1D noise, with chunky glitter and brighter, ragged edges.
    /// Gold sheets sit under the pink ones. Gold flakes, soft bokeh discs and
    /// a few tumbling cyan glass shards streak out past the camera in four
    /// depth layers. No raymarching; every loop is bounded by a constant.
    /// Smooth by design: flight runs on uTime (the eased activity clock) with
    /// a small extra share of uScroll when it's loud; the streak stretch and
    /// lean-in follow the eased uActive; the vanishing point circles and the
    /// view rolls one way, so nothing reverses; and the beat is a soft cosine
    /// swell on uBeats that only touches brightness, never the motion (the
    /// beat counter is nudged on detected beats, so moving by it would step).
    /// Louder music means a little faster flight and more light; the treble
    /// sparkles the glitter. The colours are picked to land as hot pink and gold through
    /// the NEON grade, and the background carries a touch of green so the
    /// grade's purple lift reads as black. In silence (uPresence, the
    /// renderer's slow music presence, ~2.3 s each way) it rests: the same
    /// sheets, dimmer, softer and a little cooler, breathing every 8 s, the
    /// sheets swaying and the flakes drifting while the view turns once every
    /// 10 min (every uClock period divides its one-hour wrap), so it never
    /// freezes. When music starts it brightens and speeds up into the flight.
    static let flux = """
    // Flux: an abstract long-exposure light sweep. Huge fanned sheets of fine
    // light strands, hot pink and molten gold, sweep in from the edges of the
    // frame and swirl into a drifting vanishing point, like light trails seen
    // while flying. Gold flakes and bokeh and a few cyan glass shards streak out
    // past the camera through black space. It flies faster, streaks longer and
    // burns brighter when the music is loud, and every motion glides.
    // In silence it rests: dim, soft and slowly drifting.

    const vec3 fluxPink = vec3(1.0, 0.12, 0.42);
    const vec3 fluxGold = vec3(1.0, 0.52, 0.06);
    const vec3 fluxCyan = vec3(0.0, 1.0, 0.80);

    float fluxSq(float x) { return x * x; }

    // Cheap 1D value noise for things that only vary along a strand.
    float fluxNoise1(float x) {
        float i = floor(x), f = fract(x);
        return mix(hash21(vec2(i, 0.37)), hash21(vec2(i + 1.0, 0.37)), f * f * (3.0 - 2.0 * f));
    }

    // A cheap atan2 (error under 0.01 rad), good enough for drawing.
    float fluxAtan(float y, float x) {
        float ax = abs(x), ay = abs(y);
        float a = min(ax, ay) / max(max(ax, ay), 1e-6);
        float s = a * a;
        float r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
        if (ay > ax) r = 1.57079637 - r;
        if (x < 0.0) r = PI - r;
        return y < 0.0 ? -r : r;
    }

    // A soft swell that peaks on each beat and eases away; never a kick.
    float fluxSwell() { return (0.5 + 0.5 * cos(2.0 * PI * uBeats)) * uActive; }

    // How much the music is playing: 0 in silence, 1 with sound. uPresence is
    // the renderer's slow music presence (a critically damped ease, ~2.3 s each
    // way, from the eased loudness, so it never snaps or chatters); the ends are
    // trimmed so it lands on exactly 0 and 1.
    float fluxPlay() { return smoothstep(0.02, 0.98, uPresence); }
    float gPlay;      // fluxPlay(), once per pixel
    float gIdle;      // 1 - gPlay

    // One sheet of light strands. `th` is the swirled angle round the vanishing
    // point, `r` the distance from it and `lr` its log, so equal steps of `lr`
    // fly past at equal speed. a0: the sheet's centre angle, w: its half-width
    // in angle, n: how many strands across it. Returns the colour in rgb and how
    // much it covers what's behind in a.
    vec4 fluxSheet(float th, float r, float lr, float travel, float sm, float px,
                   float a0, float w, float n, float seed, vec3 tint, float lit) {
        // in silence each sheet sways slowly open and shut (45 s, divides uClock's hour)
        a0 += gIdle * 0.16 * sin(uClock * (2.0 * PI / 45.0) + seed * 1.7);
        float d = th - a0;
        d -= 2.0 * PI * floor((d + PI) / (2.0 * PI));            // wrap to -PI..PI
        // the sheet ripples as it flies
        d += 0.14 * (fluxNoise1(lr * 1.6 - travel * 0.5 + seed * 11.0) - 0.5);
        // pinched towards the vanishing point, fanning out wide at the edges
        w *= 0.3 + 0.7 * smoothstep(0.0, 0.55, r);
        float x = d / w;                                          // -1..1 across
        float ax = abs(x);
        if (ax > 1.25) return vec4(0.0);
        // ragged, flickering edges, brighter than the middle
        float rag = fluxNoise1(lr * 2.5 - travel * 0.8 + seed * 5.0);
        float env = smoothstep(1.0 + 0.2 * rag, 0.7 - 0.2 * rag, ax);
        float rim = smoothstep(0.45, 0.9, ax) * env;
        // the strands: hairlines across the sheet, softened where they crowd
        // together towards the vanishing point so they never shimmer
        float c = (x * 0.5 + 0.5) * n + seed * 13.0;
        float fi = floor(c);
        float fh = hash21(vec2(fi, seed));
        float pxs = r * 2.0 * w / n * px;                        // pixels per strand
        float line = smoothstep(0.2 + 0.3 * fh, 0.0, abs(fract(c) - 0.5));
        line = mix(0.5, line, smoothstep(1.5, 4.0, pxs) * 0.6);
        // light streaks flying outward along each strand, stretched by the rush
        float st = fluxNoise1((lr * 10.0 / sm - travel * (2.0 + fh)) + fi * 7.31);
        st = smoothstep(0.2, 0.85, st);
        // chunky glitter caught in the sheet, smeared along the flight
        float gc = floor(c * 0.34);
        float gq = lr * 40.0 / sm - travel * 9.0 + hash21(vec2(gc, seed)) * 5.0;
        float gh = hash21(vec2(gc + seed * 17.0, floor(gq)));
        float grain = step(0.74, gh) * (0.4 + 2.2 * fluxSq(fract(gh * 7.3)))
                    * smoothstep(0.5, 0.1, abs(fract(gq) - 0.5)) * smoothstep(1.2 + 1.2 * fract(gh * 3.1), 0.2, abs(fract(c * 0.34) - 0.5) * 3.4);
        // the light gathers and thins in broad smeared patches
        float patch = fluxNoise1(lr * 3.0 / sm - travel * 0.9 + floor(c * 0.1) * 3.7 + seed);
        float s = env * (0.1 + 0.35 * patch + line * (0.2 + 0.8 * st) * (0.35 + 0.7 * fh) * (0.4 + 0.9 * patch)) + rim * (0.25 + 0.6 * st);
        vec3 hot = mix(tint, vec3(1.0, 0.88, 0.72), 0.55);
        vec3 col = tint * s + hot * (grain * env * (0.6 + 1.6 * uTreble) + rim * line * st * 0.5 + fluxSq(st * patch) * env * 0.35);
        // the strands thin out into the vanishing point
        float depth = smoothstep(0.012, 0.2, r);
        return vec4(col * lit * depth, env * 0.55 * depth);
    }

    void main() {
        vec2 p = screenP();
        // Clocks: uTime runs at the eased activity, so it glides; uScroll adds a
        // little extra speed when it's loud. Both stop in silence and never run
        // backwards. The beat swell only touches brightness, never the motion.
        float clk = uTime * 0.5 + uScroll * 0.4;
        float swl = fluxSwell();
        float travel = uTime * 3.6 + uScroll * 2.6;               // forward flight
        // streaks stretch with the (eased) flight speed, so motion blur hides
        // the step from frame to frame
        // it wakes and settles with the music presence (~2.3 s each way)
        gPlay = fluxPlay();
        gIdle = 1.0 - gPlay;
        float sm = 1.0 + 2.0 * uActive * gPlay;
        float lit = (0.35 + 0.65 * gPlay) * (1.05 + (0.8 * uLevel + 0.15 * uBass + 0.1 * swl) * gPlay);
        float breath = 0.5 + 0.5 * sin(uClock * (2.0 * PI / 8.0));   // 8 s, divides uClock's hour
        float px = uResolution.y;

        // the vanishing point drifts slowly round the middle; the view rolls
        // the vanishing point circles slowly round the middle (a circle never
        // reverses), and the camera leans in as the flight eases up
        vec2 v = vec2(-0.05, 0.03) + vec2(0.09 * cos(clk * 0.12), 0.055 * sin(clk * 0.12));
        vec2 q = (p - v) / (1.0 + 0.06 * uActive * gPlay);
        float r = max(length(q), 1e-4);
        float lr = log(r);
        float th = fluxAtan(q.y, q.x) + 0.22 * clk + uClock * (2.0 * PI / 600.0);   // a slow, steady roll that never quite stops
        // the sheets swirl harder the nearer they get to the vanishing point
        float sw = 1.0 / (r * 5.0 + 0.45) * mix(0.6, 1.0, gPlay);   // relaxes into long curves in silence

        vec3 col = vec3(0.004, 0.03, 0.0);                        // lands near-neutral black after the grade
        // gold sheets underneath, pink over them
        vec4 s;
        // a broad molten-gold sheet sweeping up from the bottom right, a thin
        // gold one tucked under the pink, a huge pink sheet wrapping in from the
        // top left and a smaller pink one from the bottom left
        s = fluxSheet(th + 1.4 * sw, r, lr, travel, sm, px, -0.95 + 0.3 * sin(clk * 0.05), 1.05, 170.0, 1.0, fluxGold, lit * 1.35);
        col = col * (1.0 - s.a) + s.rgb;
        s = fluxSheet(th + 1.1 * sw, r, lr, travel * 1.1, sm, px, 1.75 + 0.15 * sin(clk * 0.04 + 1.0), 0.3, 60.0, 2.0, fluxGold, lit * 1.2);
        col = col * (1.0 - s.a) + s.rgb;
        s = fluxSheet(th + 1.7 * sw, r, lr, travel * 0.95, sm, px, 2.45 + 0.3 * sin(clk * 0.045 + 2.0), 1.0, 170.0, 3.0, fluxPink, lit * 1.35);
        col = col * (1.0 - s.a) + s.rgb;
        s = fluxSheet(th + 1.2 * sw, r, lr, travel * 1.05, sm, px, -2.35 + 0.3 * sin(clk * 0.05 + 3.0), 0.42, 90.0, 4.0, fluxPink, lit * 1.2);
        col = col * (1.0 - s.a) + s.rgb;

        // a hot swirl of light right in the vanishing point
        col += mix(fluxPink, fluxGold, 0.55) * exp(-r * 14.0) * (0.3 + 0.25 * swl) * lit;

        // gold flakes, bokeh and cyan glass rushing out past the camera: far
        // layers are fine specks, near ones big soft discs, each smeared along
        // its flight line
        vec2 rdir = q / r;
        float busy = 0.35 + 0.9 * exp(-r * 3.0);
        for (int k = 0; k < 4; k++) {
            float fk = float(k);
            float z = fract(fk * 0.25 + travel * 0.1 + uClock / 40.0);   // 0 far, 1 right past us; drifts on in silence
            float scale = mix(28.0, 1.6, z * z);
            vec2 bq = q * scale + vec2(fk * 17.3, fk * 9.1);
            vec2 bc = floor(bq);
            float bh = hash21(bc + fk * 3.1);
            if (bh > 0.06 + 0.4 * busy) continue;                // an empty patch of space
            float h1 = hash21(bc + 1.3), h2 = fract(h1 * 37.1), h3 = fract(h1 * 91.7), h4 = fract(h1 * 13.3);
            vec2 lo = fract(bq) - 0.5 - (vec2(h1, h2) - 0.5) * 0.3;
            float along = dot(lo, rdir), across = dot(lo, vec2(-rdir.y, rdir.x));
            float fade = smoothstep(0.0, 0.25, z) * smoothstep(1.0, 0.93, z);
            float size = (0.04 + 0.16 * h3 * h3) * (0.6 + 0.9 * z);
            // motion streak along the flight line, kept inside the cell
            float blur = min(1.0 + (0.8 + 5.0 * z * z) * uActive * gPlay, 0.44 / size);
            float spin = bh * 300.0 + clk * (1.0 + 3.0 * h4) + travel * 0.6 + uClock * (2.0 * PI / 60.0);
            vec2 cp = rot(spin) * vec2(along / blur, across);
            if (bh < 0.012 && z > 0.4) {
                // a cyan glass shard: a skewed slab with a corner sheared off,
                // flipping end over end
                cp.x /= max(abs(cos(spin * 0.7 + h2 * 9.0)), 0.25);
                vec2 kp = vec2(cp.x + (h2 - 0.5) * cp.y, cp.y);
                vec2 cut = normalize(vec2(h3 - 0.5, h4 - 0.5) + 0.01);
                float sd = max(sdBox(kp, size * vec2(0.9 + 0.6 * h4, 0.5 + 0.4 * h2)), dot(cp, cut) - size * (0.2 + 0.3 * h1));
                float edge = 0.012 + 0.1 * z * z;
                float shard = smoothstep(edge, -edge, sd);
                float rimg = smoothstep(edge + 0.03, 0.0, abs(sd));
                float face = smoothstep(-0.1, 0.1, cp.x - cp.y);
                vec3 glass = fluxCyan * (0.3 + 0.4 * face + 0.7 * rimg) * (1.0 + 0.8 * uTreble + 0.4 * swl) * (0.35 + 0.65 * uActive);
                col = mix(col, glass + col * 0.4, shard * fade * 0.75);
            } else {
                // a gold speck far off, a big soft bokeh disc up close
                float soft = mix(0.03, 0.8, z * z) * size + 0.008;
                float dd = length(cp * vec2(1.0, 1.0 + 0.5 * h2)) - size;
                float flake = smoothstep(soft, -soft, dd);
                vec3 fc = mix(vec3(1.0, 0.45, 0.1), vec3(1.0, 0.82, 0.55), h4);
                float glint = fluxSq(fluxSq(max(cos(spin * 1.3), 0.0)));
                float fb = (0.4 + 1.0 * h2) * mix(1.5, 0.85, z) * lit * fade / sqrt(blur);
                col += fc * flake * fb * (0.6 + 0.5 * glint + 0.8 * uTreble * (1.0 - z));
            }
        }

        col = 1.0 - exp(-col * 1.5);                      // soft highlight roll-off
        // in silence: a soft, slightly cooler glow that breathes every 8 s
        vec3 rest = pow(col, vec3(0.8)) * (0.5 + 0.08 * breath);
        rest = mix(rest, rest * vec3(0.8, 0.95, 1.3), 0.7);
        rest += mix(fluxPink, fluxGold, 0.4) * exp(-r * 3.0) * (0.035 + 0.02 * breath);
        col = mix(rest, col, gPlay);
        fragColor = vec4(col, 1.0);
    }
    """
}
