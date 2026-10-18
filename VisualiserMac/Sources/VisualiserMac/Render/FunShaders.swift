import Foundation

/// Full-screen fragment shaders for the extra visualizer modes. Each body is
/// appended to `prelude` and drawn on the shared full-screen quad with
/// `Shaders.liquidVS`. Everything is drawn procedurally with 2D signed
/// distance fields: no textures or sprite assets.
enum FunShaders {
    static let modes: [(VisualizerMode, String)] = [
        (.badger, badger),
        (.llama, llama),
        (.hamster, hamster),
        (.nyan, nyan),
        (.spectrum, spectrum),
        (.kaleidoscope, kaleidoscope),
        (.warp, warp),
        (.band, band),
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
    uniform float uBeats;       // beat counter at the detected tempo
    uniform float uScroll;      // forward-only distance, faster when louder
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
        if (v.y > valY) col = vec3(0.55, 0.42, 0.10);
        if (abs(v.y - valY) < 1.5) col = GENRE_GOLD_C;
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
                grille *= 1.0 + uBeats * 0.35;
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
        // a single mic stand front-and-centre
        vec2 ms = v - vec2(0.0, 8.0);
        if (abs(ms.x) < 0.8 && ms.y > -8.0 && ms.y < 25.0) col = vec3(0.10);
        if (sdCircle(ms - vec2(0.0, 25.0), 3.5) < 0.0) {
            col = mix(col, vec3(0.20), 0.8);
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
        // gold chain curtain at the top — a row of interlocking circles
        float cy = 60.0;
        float cx = mod(v.x + 4.0, 8.0) - 4.0;
        float link = abs(sdCircle(v - vec2(cx, cy), 4.0));
        if (link < 0.8) col = GENRE_GOLD_C;
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
        return col;
    }

    // ========== Room 7: BLUES — bar ==========
    // Wood, neon "BAR" sign, a bottle, dim amber.
    vec3 roomBlues(vec2 v, vec3 col) {
        // wood wall
        col = vec3(0.30, 0.18, 0.10);
        if (mod(v.x, 16.0) < 0.8) col = vec3(0.18, 0.10, 0.06);
        if (mod(v.y, 24.0) < 0.8) col = vec3(0.18, 0.10, 0.06);
        // neon "BAR" sign in the upper-right
        if (v.y > 30.0 && v.y < 50.0) {
            float bx = v.x - 130.0;
            // B
            if (abs(bx + 30.0) < 1.5 && v.y > 32.0 && v.y < 48.0) col = mix(col, vec3(0.95, 0.20, 0.15), 0.9);
            // A
            if (abs(bx + 22.0) < 1.0 && v.y > 33.0 && v.y < 47.0) col = mix(col, vec3(0.95, 0.20, 0.15), 0.9);
            // R
            if (abs(bx + 12.0) < 1.5 && v.y > 32.0 && v.y < 48.0) col = mix(col, vec3(0.95, 0.20, 0.15), 0.9);
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
        // window pane at the back
        if (v.y > 20.0 && v.y < 60.0 && v.x > -180.0 && v.x < -150.0) {
            col = mix(vec3(0.85, 0.92, 0.98), vec3(0.95, 0.88, 0.65), 0.3);
            // crossbars
            if (abs(v.y - 40.0) < 1.0 || abs(v.x + 165.0) < 1.0) col = vec3(0.30, 0.18, 0.10);
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

        // Early exit for Ambient — no musicians, the colour field is the show.
        if (uGenre == 9) {
            fragColor = vec4(col, 1.0);
            return;
        }

        // -- drummers: rises up from behind the kit, sinks back down at the end.
        // For non-rock genres the kit and riser are styled by the palette.
        if (pDr > 0.0) {
            vec2 d = v - vec2(0.0, -26.0 - floor(uMX[0]));
            bool aboveRiser = v.y > -21.5;
            vec3 shirt = mix(uPrimary, vec3(1.0), 0.4);
            if (aboveRiser) person(col, d, SKIN_B, vec3(0.20, 0.12, 0.08), shirt, vec3(0.2), 1.0, 0.0, false, false, false, 0.0, -1.0, 0.0);

            // riser
            ink(col, sdBox(v - vec2(0.0, -30.0), vec2(52.0, 9.0)), uSecondary);
            if (abs(v.y + 21.5) < 1.0 && abs(v.x) < 51.0) col = uAccent;
            // cymbals + snare + kick, in palette colours
            vec2 k = v - vec2(0.0, -26.0);
            for (int s2 = -1; s2 <= 1; s2 += 2) {
                float sx = float(s2) * 30.0;
                if (abs(k.x - sx) < 0.6 && k.y > -4.0 && k.y < 38.0) col = vec3(0.70, 0.70, 0.75);
            }
            float rideTilt = 0.25 + uHits.z * pDr * 0.15;
            ink(col, sdEllipse(k - vec2(-30.0, 33.0), vec2(10.0, 2.0)), uAccent);
            ink(col, sdEllipse(rot(rideTilt) * (k - vec2(30.0, 38.0)), vec2(12.0, 2.0)), uAccent);
            ink(col, sdBox(k - vec2(-16.0, 19.0), vec2(8.0, 3.0)), vec3(0.62, 0.62, 0.68));
            ink(col, sdEllipse(k - vec2(-16.0, 22.0), vec2(8.0, 2.5)), vec3(0.92, 0.92, 0.95));
            ink(col, sdBox(k - vec2(-13.0, 25.0), vec2(7.0, 3.5)), uPrimary);
            ink(col, sdEllipse(k - vec2(-13.0, 28.5), vec2(7.0, 2.2)), uAccent);
            float br = 15.0 + floor(kick * pDr * 1.5);
            ink(col, sdCircle(k - vec2(0.0, 10.0), br), uPrimary);
            paint(col, sdCircle(k - vec2(0.0, 10.0), br - 2.5), uAccent);
            ink(col, sdCircle(k - vec2(0.0, 10.0), 4.0), uAccent);
            // arms
            float lUp = snareBeat ? swing(ph) : 1.0 - smoothstep(0.7, 1.0, ph);
            float rUp = swing(ph8);
            vec2 lh = mix(vec2(-12.0, 24.0), vec2(-15.0, 25.0 + lUp * 9.0), pDr);
            vec2 rh = mix(vec2(12.0, 24.0), vec2(24.0, 41.0 + rUp * 7.0), pDr);
            if (aboveRiser) {
                arm(col, d, vec2(-9.0, 34.0), lh, -1.0, shirt, SKIN_B);
                arm(col, d, vec2(9.0, 34.0), rh, 1.0, shirt, SKIN_B);
                ink(col, sdSeg(d, lh, lh + vec2(-5.0, -4.0 + lUp * 2.0)) - 0.6, vec3(0.90, 0.80, 0.55));
                ink(col, sdSeg(d, rh, rh + vec2(6.0, -3.0 + rUp * 2.0)) - 0.6, vec3(0.90, 0.80, 0.55));
            }
        }

        // -- bassist (stage left)
        if (pBa > 0.0) {
            vec2 b = v - vec2(uMX[1], 0.0);
            // upright bass sits where an electric bass would for classical/jazz
            vec3 shirt = mix(uPrimary, vec3(1.0), 0.3);
            person(col, b, SKIN_A, vec3(0.10, 0.05, 0.04), shirt, vec3(0.10, 0.08, 0.16),
                    0.0, uVocal * 0.4, true, false, false, 0.0, -1.0, 0.0);
            vec2 bp = b - vec2(0.0, -10.0);
            // bass body
            ink(col, sdRoundBox(bp, vec2(8.0, 16.0), 3.0), vec3(0.30, 0.16, 0.06));
            // neck + head
            ink(col, sdSeg(bp, vec2(0.0, 16.0), vec2(0.0, 36.0)) - 1.0, vec3(0.30, 0.16, 0.06));
            ink(col, sdBox(bp - vec2(0.0, 36.0), vec2(5.0, 3.0)), vec3(0.30, 0.16, 0.06));
            // pluck accent on each beat
            if (uHits.y > 0.0) {
                vec2 hp = vec2(uHits.y * 6.0 - 7.0, -16.0);
                ink(col, sdEllipse(bp - hp, vec2(3.0 + uHits.y * 1.5, 2.0)), uAccent);
            }
            // arm + bow (classical/jazz: long bow; otherwise: short plucking hand)
            if (uGenre == 0 || uGenre == 5) {
                arm(col, b, vec2(0.0, 20.0), b - vec2(-6.0, 18.0) + vec2(sin(ph * 6.0) * 3.0, 0.0), -1.0, shirt, SKIN_A);
                ink(col, sdSeg(b, b - vec2(-6.0, 18.0) + vec2(sin(ph * 6.0) * 3.0, 0.0), b - vec2(-6.0, 18.0) + vec2(sin(ph * 6.0) * 3.0 + 0.0, 28.0)) - 0.4, vec3(0.55, 0.40, 0.20));
            } else {
                arm(col, b, vec2(-2.0, 22.0), vec2(-9.0, 4.0) + vec2(sin(ph * 12.0) * 1.5, cos(ph * 12.0) * 1.5), -1.0, shirt, SKIN_A);
            }
        }

        // -- guitarist (left of centre)
        if (pGu > 0.0) {
            vec2 g = v - vec2(uMX[2], 0.0);
            vec3 shirt = mix(uPrimary, vec3(1.0), 0.3);
            float hairStyle = uGenre == 0 ? 1.0 : 0.0;  // strings have a side-part
            person(col, g, SKIN_A, vec3(0.18, 0.10, 0.06), shirt, vec3(0.16, 0.10, 0.20),
                    hairStyle, uVocal * 0.4, true, false, false, 0.0, -1.0, 0.0);
            // guitar body for electric (rock/pop/etc), violin body for classical
            if (uGenre == 0) {
                // violin — small body, long neck with bow
                ink(col, sdCircle(g - vec2(0.0, 8.0), 5.0), vec3(0.45, 0.27, 0.12));
                ink(col, sdBox(g - vec2(0.0, 24.0), vec2(3.0, 14.0)), vec3(0.45, 0.27, 0.12));
                ink(col, sdBox(g - vec2(0.0, 32.0), vec2(4.0, 2.0)), vec3(0.30, 0.17, 0.08));
                if (uHits.w > 0.0) ink(col, sdSeg(g, g - vec2(0.0, 8.0), g - vec2(uHits.w * 6.0 - 7.0, 4.0)) - 0.5, vec3(0.85, 0.85, 0.8));
            } else {
                // standard guitar (electric or acoustic)
                float ang = 0.35 + uHits.w * 0.05;
                vec2 dir = vec2(1.0, 0.0);
                vec2 gq = rot(-ang) * (g - vec2(0.0, 8.0));
                vec2 tip = vec2(dir.x * 28.0, 28.0 * 0.62);
                ink(col, sdSeg(gq, vec2(dir.x * 4.0, 3.0), tip) - 1.6, vec3(0.45, 0.27, 0.12));
                ink(col, sdBox(gq - tip - vec2(dir.x * 2.0, 1.0), vec2(2.5, 1.6)), vec3(0.30, 0.17, 0.08));
                float body = min(sdCircle(gq - vec2(-dir.x * 2.0, -2.0), 8.5), sdCircle(gq - vec2(dir.x * 3.0, 3.0), 6.5));
                float r = length(gq - vec2(-dir.x * 1.0, 0.0));
                vec3 burst = r < 4.0 ? mix(uPrimary, vec3(1.0), 0.4) : (r < 7.0 ? mix(uPrimary, uAccent, 0.5) : uSecondary);
                ink(col, body, burst);
                paint(col, sdCircle(gq - vec2(dir.x * 1.5, 1.0), 2.2), INK);
            }
        }

        // -- keyboardist (right of centre)
        if (pKe > 0.0) {
            vec2 k = v - vec2(uMX[3], 0.0);
            vec3 shirt = mix(uPrimary, vec3(1.0), 0.3);
            float hairStyle = uGenre == 5 ? 4.0 : 3.0;  // jazz has a beanie
            person(col, k, SKIN_B, vec3(0.20, 0.12, 0.08), shirt, vec3(0.18, 0.14, 0.20),
                    hairStyle, uVocal * 0.3, true, false, false, 0.0, -1.0, 0.0);
            // keys — 9 pitch bands, white keys with one highlighted at a time
            float kx = k.x;
            float ky = k.y;
            vec2 kp = vec2(kx, ky - 12.0);
            ink(col, sdBox(kp, vec2(40.0, 3.0)), vec3(0.10));
            for (int i = 0; i < 9; i++) {
                float wi = (float(i) - 4.0) * 4.4;
                vec2 whiteKey = vec2(kp.x - wi, kp.y + 1.5);
                float top = uKeys[i];
                float lit = step(0.55, top);
                vec3 col_ = lit > 0.5 ? uAccent : vec3(0.95);
                if (sdBox(whiteKey, vec2(1.8, 1.5)) < 0.0) col = col_;
                // a black key on every other position
                if (i != 0 && i != 4 && i != 8) {
                    vec2 bk = vec2(kp.x - wi + 1.2, kp.y + 2.6);
                    if (sdBox(bk, vec2(0.7, 1.0)) < 0.0) col = vec3(0.06);
                }
            }
        }

        // -- singers (front edge, both sing unless onStageCount says otherwise)
        for (int i = 0; i < 2; i++) {
            float onStage = step(0.5, uPlay[4 + i]);
            if (onStage > 0.5) {
                vec2 s = v - vec2(uMX[4 + i], 0.0);
                // 0 = female, 1 = male
                bool female = i == 0;
                vec3 shirt = mix(uPrimary, vec3(1.0), 0.4);
                // females wear dresses in the shirt colour; males wear trousers
                person(col, s, female ? SKIN_A : SKIN_B, female ? vec3(0.18, 0.10, 0.06) : vec3(0.10, 0.06, 0.04),
                        shirt, vec3(0.10, 0.08, 0.16), 0.0, uVocal * (female ? 1.0 : 0.85),
                        true, female, female, 0.0, -1.0, 0.0);
                // mic stand
                vec2 ms = s - vec2(0.0, 5.0);
                if (abs(ms.x) < 0.6 && ms.y > -5.0 && ms.y < 28.0) col = vec3(0.10);
                // mic head — pulses with vocal energy
                if (sdCircle(ms - vec2(0.0, 28.0 + uVocal * 0.5), 2.0 + uVocal * 0.6) < 0.0) col = vec3(0.20);
                // free arm holding the mic
                arm(col, s, vec2(female ? 3.0 : -3.0, 22.0),
                    vec2(female ? 4.0 : -4.0, 25.0 + uVocal * 1.5),
                    female ? -1.0 : 1.0, shirt, female ? SKIN_A : SKIN_B);
            }
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
        vec3 skin = vec3(0.98, 0.80, 0.64);
        if (female)
            person(col, s, skin, vec3(0.95, 0.85, 0.55), vec3(0.45, 0.15, 0.42), vec3(0.2), 3.0, voc, true, true, true, 0.0, walk, uFace[i] * side);
        else {
            person(col, s, skin, vec3(0.28, 0.16, 0.08), vec3(0.16, 0.16, 0.19), vec3(0.22, 0.28, 0.48), 2.0, voc, true, false, false, 0.0, walk, uFace[i] * side);
            paint(col, sdBox(s - vec2(0.0, 32.0), vec2(2.5, 7.0)), vec3(0.95, 0.95, 0.92));   // white tee under the jacket
        }
        vec3 sleeve = female ? vec3(0.45, 0.15, 0.42) : vec3(0.16, 0.16, 0.19);
        // mic hand up at the mouth; the free arm rises with the vocals
        vec2 hand = vec2(7.0, 40.0);
        arm(col, s, vec2(9.0, 36.0), hand, 1.0, sleeve, skin);
        ink(col, sdSeg(s, hand, hand + vec2(-2.0, 4.0)) - 1.2, vec3(0.18, 0.18, 0.20));
        ink(col, sdCircle(s - hand - vec2(-2.5, 5.5), 2.4), vec3(0.62, 0.62, 0.66));
        arm(col, s, vec2(-9.0, 36.0), mix(vec2(-12.0, 22.0), vec2(-19.0, 52.0), voc), -1.0, sleeve, skin);
    }

    """
}
