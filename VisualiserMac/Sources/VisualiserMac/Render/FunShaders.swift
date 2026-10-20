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
        (.waveform, waveform),
        (.ribbons, ribbons),
        (.silk, silk),
        (.knot, knot),
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
    uniform float uClock;       // wall-clock seconds; keeps running in silence (use sparingly)
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
}

extension FunShaders {
    // MARK: - Ribbons

    /// Two sheaves of glowing silk strands, one hot pink and one cyan, weave
    /// through clear glass polyhedra in a dark navy room above a glossy floor,
    /// the look of the screens in the AudioVane film. The strands are round
    /// tubes, hot in the middle and deep at the rim, with a soft bloom; the
    /// glass is ray-traced exactly (each shape is a set of paired face planes,
    /// so there is no raymarching loop): it reflects the ribbon lights,
    /// refracts the ribbons behind it and burns cyan along its edges, and
    /// shapes far from the lens's focus go soft. The floor mirrors it all and
    /// pools pink and cyan light. Colours are chosen to land as pink and cyan
    /// after the NEON grade. The whole scene slides right to left past the
    /// camera, so near glass and near stretches of ribbon cross faster than
    /// far ones (parallax), and each shape comes back in from the right once
    /// it has left. The slide speeds up with uScroll. The bass bends the
    /// ribbons and widens them, every beat turns the glass and reshapes the
    /// ribbons a step, the spectrum shapes each ribbon along its length, and
    /// the treble makes the edges and the dust sparkle.
    /// In silence it dims but keeps a slow drift (on uClock), by design.
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
    const int kStrands = 8;

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

    // The world turns a step on every beat: a whole number per beat that eases in
    // over the first part of the beat. Forward-only, so it never runs backwards.
    float beatTurn() { return floor(uBeats) + smoothstep(0.0, 0.45, fract(uBeats)); }

    // Light from the two ribbon bundles at point q on their plane.
    // soft > 0 blurs them, for reflections in the floor.
    vec3 ribbonLight(vec2 q, float soft) {
        vec3 acc = vec3(0.0);
        float turn = beatTurn();
        float X = q.x + sceneShift();                        // position along the ribbon, sliding left
        float x01 = clamp(q.x / 7.0 + 0.5, 0.0, 1.0);
        float edge = smoothstep(-4.8, -3.6, q.x) * smoothstep(4.8, 3.6, q.x);
        for (int b = 0; b < 2; b++) {
            float fb = float(b);
            float sx = fb > 0.5 ? 0.3 + x01 * 0.5 : 0.05 + x01 * 0.35;
            float base = fb > 0.5 ? 0.5 : 0.15;
            float spec = 0.55 * (ribbonSpec(base - 0.1) + ribbonSpec(base) + ribbonSpec(base + 0.1)) / 3.0
                       + 0.45 * (ribbonSpec(sx - 0.08) + ribbonSpec(sx) + ribbonSpec(sx + 0.08)) / 3.0;
            // Broad waves; bass bends the bundle harder and each beat reshapes it a little.
            float amp = (0.36 + 0.14 * spec + 0.24 * uBass) * mix(0.75, 1.0, uActive);
            float ph = fb * 3.0 + turn * 0.45;
            float k = 1.2 - fb * 0.3;
            float s = uScroll * (0.3 - fb * 0.1);              // a gentle ripple along the ribbon on top of the slide
            float a1 = X * k + s + ph;
            float a2 = X * k * 1.9 - s * 0.6 + ph * 1.7 + fb;
            float yc = (fb > 0.5 ? 0.02 : 0.36) + amp * sin(a1) + amp * 0.35 * sin(a2);   // close enough that they braid
            float lo = kFloorY + 0.16;                       // skim the floor rather than sink into it
            yc = 0.5 * (yc + lo + sqrt((yc - lo) * (yc - lo) + 0.004));
            float slope = amp * k * (cos(a1) + 0.665 * cos(a2));
            float norm = inversesqrt(1.0 + slope * slope);
            float dc = abs(q.y - yc) * norm;
            // Each bundle is a sheaf of glowing silk strands that twists as it
            // travels: fanned wide where it faces you, gathered where it turns,
            // and each strand weaves a little on its own so they cross.
            float width = (fb > 0.5 ? 0.21 : 0.24) * (1.0 + 0.35 * uBass + 0.2 * uBeatStrength)
                        * (0.75 + 0.25 * sin(X * 0.6 + fb * 3.0));
            float twist = X * (0.55 + 0.15 * fb) - uScroll * 0.25 + fb * 1.7 + turn * 0.2;
            float face = cos(twist);
            float sw = fb > 0.5 ? 0.048 : 0.09;            // strand radius
            vec3 hot = fb > 0.5 ? ribbonCyan : ribbonPink;
            vec3 deep = fb > 0.5 ? ribbonTeal : ribbonDeep;
            vec3 bundle = vec3(0.0);
            // Only pixels near the bundle pay for its strands.
            if (dc < width * 1.6 + 0.12 + soft * 12.0) {
                vec3 strands = vec3(0.0);
                float halo = 0.0;
                for (int i = 0; i < kStrands; i++) {
                    float fi = float(i);
                    float u = fi / float(kStrands - 1) * 2.0 - 1.0;
                    float off = width * (u * (0.5 + 0.5 * abs(face)) + 0.45 * sin(X * (1.1 + 0.25 * hash11(fi * 3.1 + fb)) + fi * 2.4 + fb * 2.0 + turn * 0.3));
                    float d = abs(q.y - yc - off) * norm;
                    float w = sw * (0.45 + 0.9 * hash11(fi + fb * 9.0)) * (0.75 + 0.25 * sin(X * 0.8 + fi * 1.3));
                    float aa = max(soft, 0.0025);
                    float cov = 1.0 - smoothstep(w - aa, w + aa, d);     // the strand's outline, anti-aliased
                    float x = min(d / (w + aa), 1.0);
                    float tube = sqrt(1.0 - x * x);                       // round strand: hot in the middle, deep at the rim
                    float shimmer = 0.75 + 0.25 * sin(X * 0.9 + fi * 2.3 - uScroll * 0.4);
                    vec3 c = mix(deep, hot, tube) * (0.35 + 1.35 * tube) * (1.0 + 0.9 * fb)
                           + vec3(1.0, 0.85, 0.95) * pow(tube, 40.0) * (0.8 - 0.8 * fb);
                    strands = mix(strands, c * shimmer, cov * 0.8);      // later strands lie over earlier ones
                    halo += exp(-max(d - w, 0.0) / (0.06 + soft * 3.0));
                }
                bundle = strands + hot * halo * (0.13 - 0.08 * fb);
            }
            // the glow the bundle throws on the air around it
            bundle += hot * exp(-dc / (0.18 + soft * 4.0)) * (0.13 - 0.07 * fb);
            acc += bundle * (fb > 0.5 ? 0.95 : 1.0);
        }
        float glow = (0.45 + 0.55 * uActive) * (0.9 + 0.35 * uLevel + 0.45 * uBeatStrength);
        return acc * edge * glow / (1.0 + soft * 20.0);
    }

    // The ribbons live on a curved sheet that slides left with the scene, so
    // stretches of ribbon swing towards the camera (and move faster) and back
    // away again. Where a ray meets it (a few fixed-point steps), or -1.
    float ribbonDepth(float x) { return 0.65 * sin((x + sceneShift()) * 0.45 + 0.9) + 0.1; }
    float ribbonT(vec3 ro, vec3 rd) {
        if (abs(rd.z) < 1e-3) return -1.0;
        float t = (ribbonDepth(ro.x) - ro.z) / rd.z;
        for (int i = 0; i < 4; i++) t = (ribbonDepth(ro.x + rd.x * max(t, 0.0)) - ro.z) / rd.z;
        return t;
    }

    // The ribbons as seen along a ray, or nothing if the ray doesn't reach them.
    vec3 ribbonsAlong(vec3 ro, vec3 rd, float soft, float tMax) {
        float t = ribbonT(ro, rd);
        if (t <= 0.0 || t > tMax) return vec3(0.0);
        vec3 p = ro + rd * t;
        if (p.y < kFloorY) return vec3(0.0);
        return ribbonLight(p.xy, soft + t * 0.7 / uResolution.y);   // never thinner than a pixel
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
        col += vec3(0.5, 0.85, 1.0) * star * tw * (0.15 + 1.2 * uTreble) * (0.3 + 0.7 * uActive);
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
    // sits at its own depth and slides left with the scene; once it's off the
    // left edge it comes back in from the right (a little higher or lower, a bit
    // bigger or smaller, turned differently), so the stream never runs dry. The
    // starting points are staggered so the shapes don't travel as one clump.
    void gemPose(int j, out vec3 c, out vec2 ang, out float r, out int faces) {
        float fj = float(j);
        if (j == 0)      { c = vec3(0.0, -0.50, -0.95); r = 0.62; faces = 10; }
        else if (j == 1) { c = vec3(0.0, 0.55, 3.00);   r = 0.55; faces = 10; }
        else if (j == 2) { c = vec3(0.0, 1.05, 0.90);   r = 0.42; faces = 10; }
        else if (j == 3) { c = vec3(0.0, -0.50, -1.30); r = 0.24; faces = 10; }
        else if (j == 4) { c = vec3(0.0, -0.50, 1.60);  r = 0.48; faces = 4; }
        else if (j == 5) { c = vec3(0.0, 0.85, -0.70);  r = 0.20; faces = 10; }
        else if (j == 6) { c = vec3(0.0, 0.20, 0.95);   r = 0.80; faces = 10; }
        else             { c = vec3(0.0, -0.50, 2.30);  r = 0.62; faces = 10; }
        // Wrap span: wide enough that the jump happens off screen at this depth.
        float depth = c.z + 3.4;
        float span = 2.0 * (depth * 0.85 + r) + 0.4;
        float x = fract(fj * 0.375 + 0.62) * span - sceneShift();
        float lap = floor(x / span);
        c.x = x - lap * span - 0.5 * span;
        float lh = hash11(lap * 3.7 + fj * 11.3);
        c.y = clamp(c.y + (lh - 0.5) * 0.4, kFloorY + r * 0.8, 2.0);
        r *= 0.85 + 0.3 * hash11(lap * 5.1 + fj * 2.9);
        c.y += 0.05 * sin(uTime * 0.45 + fj * 1.9);
        ang = vec2(uTime * (0.10 + 0.03 * fj) + uClock * 0.02 + fj * 1.3 + lh * 6.28,
                   beatTurn() * 0.32 + fj * 2.1);
        r *= 1.0 + 0.05 * uBeatStrength + 0.03 * uBass;
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
        return acc * (0.4 + 0.6 * uActive + 0.8 * uBeatStrength);
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
        col += mix(ribbonPink, ribbonCyan, step(0.6, facet)) * 0.12 * facet * facet * (0.5 + 0.5 * uActive);
        float lit = (0.45 + 0.55 * uActive) * (0.9 + 0.6 * uTreble + 0.8 * uBeatStrength);

        if (full) {
            // Through the glass: bend in, cross to the far face, bend out.
            vec3 d1 = refract(ord, nn, 1.0 / 1.15);
            float tn2, tf2; vec3 nn2, nf2;
            gemHit(pIn + d1 * 0.002, d1, faces, h, tn2, tf2, nn2, nf2);
            vec3 pOut = pIn + d1 * (0.002 + tf2);
            vec3 d2 = refract(d1, -nf2, 1.15);
            vec3 wOut = fromGem(pOut, ang) + c;
            vec3 behind;
            if (dot(d2, d2) < 0.5) {
                // total internal reflection: the face lights up with the room instead
                behind = skyColour(fromGem(reflect(d1, -nf2), ang)) * 1.3;
            } else {
                vec3 wd2 = fromGem(d2, ang);
                behind = skyColour(wd2) + ribbonsAlong(wOut, wd2, 0.002, 30.0) * 0.45;
            }
            col += behind * vec3(0.85, 0.96, 1.0) * (1.0 - fres) * (0.9 + 0.2 * facet);
            vec2 edgeBack = gemEdge(pOut, faces, h, edgeW * 1.2);
            // A ribbon passing through the glass lights it from inside.
            float tz = ribbonT(ro, rd);
            if (tz > tHit && tz < tHit + (tf - tn)) col += ribbonLight((ro + rd * tz).xy, 0.0) * 0.6;
            col += glassCyan * (edgeBack.x * 0.12 + edgeBack.y * 0.15) * lit * (1.0 - 0.7 * blur);
        }
        vec2 edgeGlow = gemEdge(pIn, faces, h, min(edgeW * 3.0, h * 0.08));
        vec3 edgeHot = mix(glassCyan, vec3(0.75, 1.0, 1.0), 0.1);   // edges burn a little whiter than their glow
        col += edgeHot * (edgeFront.x * 1.7 + edgeFront.y * 1.6) * (1.0 - 0.6 * blur) * lit;
        col += glassCyan * edgeGlow.x * 0.9 * (1.0 - 0.6 * blur) * lit;
        return col;
    }

    void main() {
        vec2 p = screenP();
        // Camera sits low by the glossy floor and sways slowly (on the
        // sound-gated clock); it leans in a little on the bass.
        // The scene itself slides left past it (sceneShift).
        float yaw = 0.12 * sin(uTime * 0.07);
        // The lens is shifted up rather than tilted, so the horizon sits low and
        // the glass stays upright.
        vec3 ro = vec3(0.0, -0.40, -3.3 + 0.10 * uBass);
        ro.xz = rot(yaw) * ro.xz;
        vec3 fw = vec3(-sin(yaw), 0.0, cos(yaw));
        vec3 rt = vec3(cos(yaw), 0.0, sin(yaw));
        vec3 rd = normalize(p.x * rt + vec3(0.0, p.y + 0.24, 0.0) + 1.3 * fw);

        float tFloor = rd.y < 0.0 ? (kFloorY - ro.y) / rd.y : 1e5;
        vec3 col = skyColour(rd);

        int j; float tGem;
        bool hitGem = nearestGem(ro, rd, tFloor, j, tGem);
        float tEnd = hitGem ? tGem : tFloor;
        if (hitGem) {
            col = shadeGem(j, ro, rd, tGem, true);
        } else if (tFloor < 1e4) {
            // Glossy black floor: a near-mirror of the ribbons and the glass,
            // softening with distance and fading into the hot horizon line.
            vec3 fp = ro + rd * tFloor;
            vec3 rr = reflect(rd, vec3(0.0, 1.0, 0.0));
            float fres = 0.30 + 0.70 * pow(1.0 - clamp(-rd.y, 0.0, 1.0), 5.0);
            vec3 refl = skyColour(rr) * 0.8;
            int j2; float t2;
            if (nearestGem(fp, rr, 40.0, j2, t2)) refl = shadeGem(j2, fp, rr, t2, false);
            float tr = ribbonT(fp, rr);
            vec3 glassPool;
            refl += ribbonsAlong(fp, rr, 0.01 + 0.035 * max(tr, 0.0), 40.0) + gemHalo(fp, rr, 40.0, glassPool) * 2.0;
            col = vec3(0.002, 0.006, 0.014) + refl * fres * 0.75;
            // the ribbons' light pooling on the floor beneath them
            float pool = exp(-abs(fp.z - ribbonDepth(fp.x)) * 0.8) * smoothstep(-4.8, -2.5, fp.x) * smoothstep(4.8, 2.5, fp.x);
            col += mix(ribbonCyan * 0.35, ribbonPink * 0.7, smoothstep(-2.0, 1.0, fp.x)) * pool * (0.4 + 0.6 * uActive) * (0.8 + 0.4 * uLevel);
            col += glassPool * 0.8 * (0.4 + 0.6 * uActive);
            col = mix(col, skyColour(rd), smoothstep(8.0, 30.0, tFloor));
        }
        // Ribbons in front of whatever we hit.
        col += ribbonsAlong(ro, rd, 0.0, tEnd);
        vec3 unused;
        col += gemHalo(ro, rd, tEnd, unused);
        col += ribbonPink * uBeatStrength * 0.025 * uActive;

        col = 1.0 - exp(-col * 1.8);                   // soft highlight roll-off
        col *= 1.0 - 0.3 * dot(p, p);                   // vignette
        col = mix(col * 0.5, col, uActive);             // dims in silence, but keeps drifting
        fragColor = vec4(col, 1.0);
    }
    """
}

extension FunShaders {
    // MARK: - Silk Flight

    /// Flying forward through the music, after the fly-through in the AudioVane
    /// brand film (0:11 to 0:13): a wide satin ribbon, hot pink with deep
    /// folds, sweeps in from both frame edges and twists away into a teal dust
    /// cloud, turning electric violet in the distance, while chunky cyan glass
    /// blocks tumble past on near-black space. The ribbon is found per pixel by
    /// a sign change of its side function along the ray (at most 36 depth
    /// steps for both ends together, stopping once both are found); the glass
    /// blocks are exact ray/box slabs. The camera flies on uScroll, so it races
    /// when the music is loud. The bass widens the ribbon, the spectrum lights
    /// its far reaches, the mids thicken the dust, every beat turns the glass a
    /// step and throws a burst of glitter, and the treble makes the specks and
    /// the glass edges sparkle. In silence: dim, and still.
    static let silk = """
    // Silk Flight: flying forward through the music. A wide satin ribbon, hot
    // pink with deep folds, sweeps in from both frame edges and twists away
    // into a teal dust cloud, turning electric violet in the distance, while
    // chunky cyan glass blocks tumble past on near-black space.
    const int kSilkSteps = 36;       // depth samples per ribbon branch
    const int kSilkGlass = 6;        // glass blocks

    const vec3 silkPink   = vec3(1.00, 0.36, 0.62);
    const vec3 silkPinkHi = vec3(1.00, 0.66, 0.84);
    const vec3 silkFold   = vec3(0.72, 0.14, 0.46);
    const vec3 silkLilac  = vec3(0.90, 0.49, 0.99);
    const vec3 silkViolet = vec3(0.31, 0.22, 0.86);
    const vec3 silkCyan   = vec3(0.00, 1.00, 0.89);
    const vec3 silkDust   = vec3(0.20, 0.43, 0.47);

    float silkTravel() { return uScroll * 3.0; }
    float silkTurn() { return floor(uBeats) + smoothstep(0.0, 0.5, fract(uBeats)); }

    // Ribbon centre (xy) and twist (z) at world depth s, for branch b (0 or 1).
    // Near the camera each branch is pushed out to its own side, so it sweeps
    // in from the frame edge and never closes over the lens.
    vec3 silkPath(float s, float z, float b) {
        float side = b < 0.5 ? -1.0 : 1.0;
        float push = 1.8 * exp(-0.5 * z);
        float cross = side * (0.75 + push - 1.5 * smoothstep(1.5, 7.0, z));
        return vec3(cross + 1.1 * sin(s * 0.7 + b * 2.4) + 0.4 * exp(-0.12 * z) * sin(s * 1.13 + b * 5.1),
                    side * (-0.25 - 0.55 * push) + 0.05 + 0.45 * sin(s * 0.47 + b * 1.7 + 2.0),
                    0.5 + 0.75 * exp(-0.06 * z) * sin(s * 0.41 + b * 3.0 + 1.0));
    }

    // Signed offset of the ray point from the ribbon's plane line at depth z,
    // and the across-ribbon coordinate.
    vec2 silkSide(vec2 rd, float z, float s, float b, float w) {
        vec3 c = silkPath(s, z, b);
        vec2 q = rd * z - c.xy;
        vec2 t = vec2(cos(c.z), sin(c.z));
        return vec2(dot(q, vec2(-t.y, t.x)), dot(q, t) / w);
    }

    vec3 silkShade(vec2 rd, float z, float s, float u, float b, float w) {
        vec3 c = silkPath(s, z, b);
        vec3 c2 = silkPath(s + 0.15, z + 0.15, b);
        vec3 T = vec3(cos(c.z), sin(c.z), 0.0);
        vec3 D = vec3((c2.xy - c.xy) / 0.15, 1.0);
        vec3 N = normalize(cross(D, T));
        vec3 V = normalize(vec3(rd, 1.0));
        float side = dot(N, V) < 0.0 ? 1.0 : -1.0;     // which face we see
        N *= side;
        // Lengthwise pleats tilt the normal across the ribbon.
        float ph = u * 5.5 + 1.4 * sin(s * 0.35 + u * 2.0 + b * 3.0);
        float pleat = sin(ph);
        vec3 Np = normalize(N + T * 1.1 * cos(ph) + normalize(D) * 0.45 * sin(s * 1.1 + u * 1.5 + b * 2.0));
        vec3 L = normalize(vec3(0.35, 0.75, -0.55));
        float dif = max(dot(Np, L), 0.0);
        vec3 H = normalize(L - V);
        float spec = pow(max(dot(Np, H), 0.0), 22.0) * 1.3 + 0.25 * pow(max(dot(Np, H), 0.0), 4.0);
        float sheen = pow(1.0 - abs(dot(Np, V)), 2.0);
        // Satin: a ramp from deep magenta folds through hot pink to a pale pink
        // sheen, cooling to lilac on the underside and at grazing angles.
        float k = clamp(0.15 + 0.5 * dif + 0.4 * smoothstep(0.3, 1.0, pleat) - 0.45 * smoothstep(0.1, 0.9, -pleat), 0.0, 1.0);
        vec3 col = k < 0.5 ? mix(silkFold * 0.75, silkPink, k * 2.0) : mix(silkPink, silkPinkHi, k * 2.0 - 1.0);
        col = mix(col, mix(silkViolet, silkLilac, k) * (0.6 + 0.6 * k), step(N.y, 0.0) * 0.4);
        col = mix(col, silkPinkHi, sheen * 0.15);
        col += vec3(1.0, 0.82, 0.95) * spec * (1.2 + 0.6 * uBeatStrength);
        col *= 1.0 - 0.45 * smoothstep(0.75, 1.0, abs(u));   // rolled edges
        // Far away the ribbon cools to electric violet-blue and sinks into the dust.
        float far = smoothstep(1.8, 7.0, z);
        float band = 0.8 + 0.7 * bandAt(clamp(z / 18.0, 0.0, 1.0));     // the spectrum lights the far ribbon
        col = mix(col, (mix(silkViolet, silkLilac, 0.35 * dif + spec) * (0.75 + 0.55 * dif) + spec * 0.4) * band, far * 0.9);
        col = mix(col, silkDust * 0.6, smoothstep(12.0, 30.0, z));
        return col;
    }

    // Glass block: exact ray/box slabs in the block's own frame.
    void silkGlass(inout vec3 col, vec3 rd, float zMax, int i, float travel) {
        float n = float(i);
        float span = 10.0;
        float z = 0.9 + mod((n + 0.6 * hash11(n * 3.7 + 0.31)) / float(kSilkGlass) * span - travel * (0.9 + 0.2 * hash11(n * 1.9)), span);
        float fade = smoothstep(span, span - 5.0, z) * smoothstep(1.5, 2.5, z);
        if (fade <= 0.0) return;
        float a = n * 2.39996 + 0.7 * hash11(n * 7.13 + 0.17);
        float rr = (0.6 + 0.8 * hash11(n * 2.3 + 0.53)) * (0.35 + 0.28 * z);
        vec3 c = vec3(cos(a) * rr * 1.3, sin(a) * rr * 0.8, z);
        vec3 hs = vec3(0.28 + 0.24 * hash11(n * 5.3 + 0.7), 0.24 + 0.2 * hash11(n * 6.7 + 0.3), 0.28 + 0.26 * hash11(n * 8.9 + 0.9));
        vec2 ang = vec2(uTime * (0.15 + 0.2 * hash11(n * 9.1)) + silkTurn() * 0.35 + n,
                        uTime * (0.12 + 0.15 * hash11(n * 1.3)) + n * 2.0);
        mat2 r1 = rot(ang.x), r2 = rot(ang.y);
        vec3 ro = -c;
        ro.xz = r1 * ro.xz; ro.xy = r2 * ro.xy;
        vec3 d = rd;
        d.xz = r1 * d.xz; d.xy = r2 * d.xy;
        vec3 m = 1.0 / d;
        vec3 k = abs(m) * hs;
        vec3 t1 = -m * ro - k, t2 = -m * ro + k;
        float tN = max(max(t1.x, t1.y), t1.z);
        float tF = min(min(t2.x, t2.y), t2.z);
        if (tN > tF || tF < 0.0 || tN > zMax) return;
        // Front and back hit points in box space, scaled to -1..1.
        vec3 pf = (ro + d * tN) / hs, pb = (ro + d * tF) / hs;
        vec3 af = abs(pf), ab = abs(pb);
        // Edge lines: a face point near two face boundaries.
        float px = 1.5 * tN / uResolution.y * 1.6 / min(min(hs.x, hs.y), hs.z);
        vec3 ef = 1.0 - af, eb = 1.0 - ab;
        float edgeF = min(min(max(ef.x, ef.y), max(ef.y, ef.z)), max(ef.x, ef.z));
        float edgeB = min(min(max(eb.x, eb.y), max(eb.y, eb.z)), max(eb.x, eb.z));
        float lineF = 1.0 - smoothstep(0.0, 0.045 + px, edgeF);
        float lineB = 1.0 - smoothstep(0.0, 0.03 + px, edgeB);
        // Face normal of the front hit, and an inner diagonal on the back face.
        vec3 nf = step(vec3(max(max(af.x, af.y), af.z)), af) * sign(pf);
        vec3 bq = ab;
        float diag = abs(abs(bq.x * nf.y + bq.y * nf.z + bq.z * nf.x) - abs(bq.y * nf.y + bq.z * nf.z + bq.x * nf.x));
        float lineD = (1.0 - smoothstep(0.0, 0.035 + px, diag)) * 0.7;
        vec3 L = normalize(vec3(0.4, 0.8, -0.4));
        L.xz = r1 * L.xz; L.xy = r2 * L.xy;
        float lit = max(dot(nf, L), 0.0);
        vec3 nb = step(vec3(max(max(ab.x, ab.y), ab.z)), ab) * sign(pb);
        float litB = max(dot(-nb, L), 0.0);
        float refl = smoothstep(0.6, 1.0, sin(dot(pf, vec3(3.1, 2.3, 3.7)) + n * 1.7)) + 0.5 * smoothstep(0.7, 1.0, sin(dot(pb, vec3(-2.7, 3.3, 1.9)) + n));
        float tone = hash11(dot(nf, vec3(1.0, 2.0, 3.0)) + n * 1.3 + 0.5);   // each face its own shade
        float fres = pow(1.0 - abs(dot(nf, normalize(d))), 3.0);
        float thick = clamp((tF - tN) / (2.0 * hs.z), 0.0, 1.5);
        vec3 g = col * mix(0.5, 0.2, min(thick, 1.0)) + vec3(0.0, 0.035, 0.04) * min(thick, 1.0);            // tinted glass body
        g += silkCyan * (0.03 + 1.0 * smoothstep(0.35, 0.95, lit) + 0.8 * smoothstep(0.45, 0.85, tone) + 0.15 * fres + 0.45 * refl + 0.25 * litB) * (0.7 + 0.5 * uTreble);
        g += vec3(0.15, 1.0, 0.92) * (lineF * 1.3 + lineB * 0.6 + lineD * 0.8) * (0.85 + 0.5 * uTreble + 0.5 * uBeatStrength);
        col = mix(col, g, fade);
    }

    float silkNoise(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
                   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
    }

    void main() {
        vec2 p = screenP();
        p = rot(0.06 * sin(uTime * 0.05)) * p;
        float travel = silkTravel();
        vec2 rd = p * 1.25 + vec2(0.04 * sin(uTime * 0.11), 0.03 * sin(uTime * 0.083 + 1.0));

        // Space: near-black teal with a drifting cloud of dust in the middle.
        vec3 col = vec3(0.0, 0.05, 0.025) + vec3(0.0, 0.05, 0.07) * smoothstep(0.7, 0.0, length(p * vec2(0.7, 1.4)));
        vec2 dq = p * 2.2 + vec2(travel * 0.02, 0.0);
        float dn = silkNoise(dq * 1.6) * 0.45 + silkNoise(dq * 3.4 + 7.0) * 0.27 + silkNoise(dq * 7.5 - 3.0) * 0.17 + silkNoise(dq * 16.0 + 1.0) * 0.11;
        vec2 pc = (p - vec2(0.05, 0.03)) * vec2(1.8, 3.2);
        float core = exp(-dot(pc, pc));
        float dust = smoothstep(0.25, 0.85, dn) * core * 1.5;
        col += silkDust * dust * 1.25 * (1.0 + 0.4 * uMid) * (0.6 + 0.4 * uActive);
        // Fine specks streaming outward as we fly.
        for (int l = 0; l < 3; l++) {
            float fl = float(l);
            float ph = fract(travel * 0.08 + fl / 3.0);
            vec2 sp = p * mix(14.0, 2.5, ph) * 30.0 + fl * 37.0;
            vec2 cell = floor(sp);
            float h = hash21(cell);
            float sd = length(fract(sp) - 0.5 - 0.3 * (vec2(hash21(cell + 3.1), hash21(cell + 5.7)) - 0.5));
            float star = step(0.93, h) * (1.0 - smoothstep(0.05, 0.25, sd)) * smoothstep(0.0, 0.3, ph) * smoothstep(1.0, 0.8, ph);
            col += mix(vec3(0.75, 0.35, 0.9), vec3(0.8, 0.9, 1.0), hash21(cell + 9.0)) * star * (0.35 + 0.6 * uTreble + 0.4 * uBeatStrength) * (0.4 + 0.6 * dust + 0.3 * uActive);
        }

        // The ribbon: two branches, each found by a sign change of its side
        // function along the ray (exponential depth steps, front to back).
        float w = 0.62 * (1.0 + 0.15 * uBass);
        vec4 hitA = vec4(1e5, 0.0, 0.0, 0.0), hitB = vec4(1e5, 0.0, 0.0, 0.0);   // z, u, s, alpha
        vec2 prevA = vec2(0.0), prevB = vec2(0.0);
        float zPrev = 0.0;
        for (int i = 0; i < kSilkSteps; i++) {
            float z = 0.45 * pow(1.13, float(i));
            float s = travel + z;
            vec2 fa = silkSide(rd, z, s, 0.0, w);
            vec2 fb = silkSide(rd, z, s, 1.0, w);
            if (i > 0) {
                if (hitA.x > 1e4 && fa.x * prevA.x <= 0.0) {
                    float k = prevA.x / (prevA.x - fa.x);
                    float u = mix(prevA.y, fa.y, k);
                    if (abs(u) < 1.05) { float zz = mix(zPrev, z, k); hitA = vec4(zz, u, travel + zz, 1.0); }
                }
                if (hitB.x > 1e4 && fb.x * prevB.x <= 0.0) {
                    float k = prevB.x / (prevB.x - fb.x);
                    float u = mix(prevB.y, fb.y, k);
                    if (abs(u) < 1.05) { float zz = mix(zPrev, z, k); hitB = vec4(zz, u, travel + zz, 1.0); }
                }
                if (hitA.x < 1e4 && hitB.x < 1e4) break;
            }
            prevA = fa; prevB = fb; zPrev = z;
        }
        float zr = min(hitA.x, hitB.x);
        // Composite far branch first, then near.
        for (int j = 0; j < 2; j++) {
            vec4 h = (j == 0) == (hitA.x > hitB.x) ? hitA : hitB;
            float b = (j == 0) == (hitA.x > hitB.x) ? 0.0 : 1.0;
            if (h.x > 1e4) continue;
            float aa = 2.0 * h.x / (uResolution.y * 1.25 * w);
            float alpha = (1.0 - smoothstep(1.0 - aa, 1.0, abs(h.y))) * smoothstep(17.0, 9.0, h.x);
            col = mix(col, silkShade(rd, h.x, h.z, h.y, b, w), alpha);
        }

        // Glass blocks in front of the ribbon.
        for (int i = 0; i < kSilkGlass; i++) silkGlass(col, vec3(rd, 1.0), zr, i, travel);

        // Beat sparks: a burst of pink and cyan glitter thrown outward.
        float ph = fract(uBeats);
        float ang = atan(p.y, p.x) * 7.0;
        for (int j = 0; j < 2; j++) {
            float fj = float(j);
            float cellA = floor(ang + fj * 0.5) + fj * 50.0;
            float hs = hash11(cellA + floor(uBeats) * 1.37);
            float a2 = (floor(ang + fj * 0.5) + 0.5 - fj * 0.5 + 0.6 * (hash11(cellA * 2.1) - 0.5)) / 7.0;
            float rr = 0.06 + ph * (0.25 + 0.6 * hs);
            vec2 sp = vec2(cos(a2), sin(a2)) * rr;
            float spark = (1.0 - smoothstep(0.002, 0.006 + 0.004 * hs, length(p - sp))) * step(0.5, hs);
            col += mix(silkPink, silkCyan, hash11(cellA * 1.3)) * spark * uBeatStrength * (1.0 - ph) * 3.0 * uActive;
        }

        col *= 1.0 - 0.25 * dot(p, p);                  // vignette
        col = mix(col * 0.45, col, uActive);             // dims and settles in silence
        fragColor = vec4(col, 1.0);
    }
    """
}

extension FunShaders {
    // MARK: - Knot

    /// A tangle of glowing paint threads, after the climax of the AudioVane
    /// brand film (0:38 to 0:40). Two broad streams of fibres, hot pink
    /// sweeping in from the top left and gold from the bottom right, pinch
    /// through one tight twisted neck like a wrung-out rope and flare out
    /// again, with a couple of loose threads tangled round the neck. Each
    /// stream is drawn as a projected twisted cylinder: the angle round it at
    /// each pixel comes straight from acos, so every single fibre can be read,
    /// splits into finer threads where the stream fans out, and frays at the
    /// edges, with no raymarching. The loose threads are polar loops that
    /// cross themselves like a trefoil. Gold glitter, chunky soft flakes and
    /// cyan glass shards stream out past the camera in four depth layers.
    /// The colours are picked to land as hot pink and gold through the NEON
    /// grade, and the background carries a touch of green so the grade's
    /// purple lift reads as black. Streaks run along the fibres on uScroll, so
    /// it moves more when the music is loud. The bass wrings the neck tighter
    /// and swells the fans, every beat twists the neck another notch and
    /// re-ties one of the loose threads, and the treble sparkles the fibres.
    /// In silence: dim, and still.
    static let knot = """
    // Knot: two broad streams of glowing paint threads, hot pink sweeping in
    // from the top left and gold from the bottom right, pinch through one tight
    // twisted neck like a wrung-out rope and flare out again, with loose threads
    // tangled round the neck. Each stream is a bundle of single fibres that fray,
    // split and rejoin. Gold glitter, chunky flakes and cyan glass shards stream
    // out past the camera through black space.

    const vec3 knotPink = vec3(1.0, 0.12, 0.42);
    const vec3 knotGold = vec3(1.0, 0.52, 0.06);
    const vec3 knotCyan = vec3(0.0, 1.0, 0.80);

    float knotSq(float x) { return x * x; }

    // Cheap 1D value noise for things that only vary along a strand.
    float knotNoise1(float x) {
        float i = floor(x), f = fract(x);
        return mix(hash21(vec2(i, 0.37)), hash21(vec2(i + 1.0, 0.37)), f * f * (3.0 - 2.0 * f));
    }

    // A cheap atan2 (error under 0.01 rad), good enough for drawing curves.
    float knotAtan(float y, float x) {
        float ax = abs(x), ay = abs(y);
        float a = min(ax, ay) / max(max(ax, ay), 1e-6);
        float s = a * a;
        float r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
        if (ay > ax) r = 1.57079637 - r;
        if (x < 0.0) r = PI - r;
        return y < 0.0 ? -r : r;
    }

    // How thick a strand is along its length: a cheap smooth wobble.
    float knotThick(float t, float seed) {
        float x = fract(t * 0.21 + seed * 0.37);
        return 0.6 + 0.4 * (8.0 * x * (1.0 - x) - 1.0);
    }

    // Slow motion clock: runs faster when louder, stops in silence.
    float knotClock() { return uTime * 0.3 + uScroll * 1.4; }
    // One re-tie per beat, eased in, so the twist never snaps backwards.
    float knotRetie() { return floor(uBeats) + smoothstep(0.0, 0.35, fract(uBeats)); }

    // Paint one pass of a strand. `u` runs -1..1 across it, `t` along it.
    // Returns the colour to add in rgb and how much it covers what's behind in a.
    vec4 knotShade(float u, float t, float R, float seed, float nf, float gold,
                   float ends, float depth, float level) {
        float au = abs(u);
        float arc = t * R * 6.0;
        vec3 tint = mix(knotPink, knotGold, gold);
        // single fibres: they weave across the strand, split and rejoin
        float weave = knotNoise1(arc * 1.5 + seed * 17.0);
        float fr = (u * 0.5 + 0.5) * nf + (weave - 0.5) * 3.0;
        float fi = floor(fr);
        float fh = hash21(vec2(fi, seed));
        float fl = abs(fract(fr) - 0.5);
        float thread = smoothstep(0.14 + 0.24 * fh, 0.02, fl);
        float streak = knotNoise1(arc * (5.0 + 5.0 * fh) + fi * 13.7 + seed * 5.0);
        thread *= smoothstep(0.3, 0.6, streak);
        // ragged edges with loose fibres straying out
        float env = smoothstep(1.0 + 0.8 * fract(weave * 3.7), 0.45, au) * ends;
        // brushy paint body, streaked along the strand and full of flecks
        float fa = arc * 40.0 + fh * 7.0;
        float fleck = step(0.82, hash21(vec2(floor(fa), fi + seed * 41.0)));
        fleck *= smoothstep(0.5, 0.15, length(vec2(fract(fa) - 0.5, fract(fr) - 0.5)));
        float body = knotSq(max(1.0 - 0.45 * u * u, 0.0)) * (0.35 + 0.9 * streak * streak) * (0.8 + 0.7 * fleck);
        float s = env * (body * mix(1.0, 0.75, gold) + thread * (0.35 + 0.9 * fh) * mix(0.7, 1.1, gold));
        // treble sparkles along the fibres
        float gl = step(0.985 - 0.04 * uTreble, hash21(vec2(fi + seed * 31.0, floor(arc * 30.0))));
        vec3 hot = mix(tint, mix(vec3(1.0, 0.7, 0.85), vec3(1.0, 0.88, 0.55), gold), mix(0.4, 0.6, gold));
        vec3 c = tint * s + hot * env * (thread * fh * fh * fh * fh * 1.2 + (fleck * 0.35 + gl * (0.9 + 2.0 * uTreble)) * step(0.5, fh));
        // a soft glow round the strand
        c += tint * ends * 0.08 / (1.0 + 3.0 * au * au);
        return vec4(c * level * depth * (1.0 + 0.25 * gold), 0.5 * env);
    }

    // One strand: a looping polar curve round the knot whose ends open out and fly
    // off the screen. A: centre offset, tilt, squash. B: loop radius, lobes, lobe
    // depth, phase. C: knot section start and end angle, how far each end flies
    // out. D: width, fibre count, gold (0 pink, 1 gold), seed.
    // A cheaper paint for the far pass where a strand crosses behind itself.
    vec4 knotShadeFar(float u, float t, float R, float seed, float gold, float ends, float level) {
        float au = abs(u);
        vec3 tint = mix(knotPink, knotGold, gold);
        float streak = knotNoise1(t * R * 50.0 + floor(u * 6.0) * 7.3 + seed * 5.0);
        float env = smoothstep(1.2, 0.5, au) * ends;
        float s = env * knotSq(max(1.0 - 0.45 * u * u, 0.0)) * (0.3 + 0.8 * streak);
        return vec4(tint * s * level, 0.5 * env);
    }

    void knotStrand(inout vec3 col, inout float near, vec2 p, vec2 knot, float clk, float retie,
                    float tight, float swell, float level, vec4 A, vec4 B, vec4 C, vec4 D) {
        float seed = D.w;
        float flip = mod(seed, 2.0) * 2.0 - 1.0;
        // every third beat this strand re-ties: its loops slide round and flip
        // (the strands take turns, so something re-ties on every beat)
        float bt3 = (retie - mod(seed, 3.0)) / 3.0;
        float tie = floor(bt3) + smoothstep(0.0, 0.35, fract(bt3));
        float ph = B.w + clk * (0.35 + 0.06 * seed) * flip + tie * 1.7 * flip;
        // the knot twists slowly: a small sway on top of each strand's fixed tilt
        float sway = sin(clk * 0.23 + seed * 2.1);
        float da = 0.3 * sway;
        vec2 q = rot(A.z + 0.35 * tie * flip) * (mat2(1.0 - 0.5 * da * da, -da, da, 1.0 - 0.5 * da * da) * (p - knot - A.xy));
        float sq = A.w * (0.85 + 0.15 * sway);
        q.y /= sq;
        float r = length(q);
        float th = knotAtan(q.y, q.x);
        float R = B.x * 0.6 * tight;
        float t0 = C.x - C.z, t1 = C.y + C.w;
        float k0 = ceil((t0 - th) / (2.0 * PI));
        // lobes that don't divide a turn evenly (1.5 = a trefoil) so the passes
        // cross over each other like a real knot; each pass is the last one turned
        // on by a fixed angle
        float la = B.y * (th + 2.0 * PI * k0) + ph;
        float lobe = sin(la), dlobe = cos(la);
        float sa = sin(2.0 * PI * B.y), ca = cos(2.0 * PI * B.y);
        float bdl = dlobe, cdl = dlobe;
        // the two nearest passes of this strand (it winds round up to 3 times)
        float bu = 1e3, bt = t0, bd = 0.0, bw = 1.0;
        float cu = 1e3, ct = t0, cd = 0.0, cw = 1.0;
        for (int j = 0; j < 3; j++) {
            float t = th + 2.0 * PI * (k0 + float(j));
            // out on a tail the loop opens up and flies to the edge of the screen
            float o = max(C.x - t, 0.0) + max(t - C.y, 0.0);
            float tail = 1.0 + o * (0.9 + o * 0.45);
            float rho = R * (tail + B.z * lobe);
            float drho = R * (B.z * B.y * dlobe + (step(C.y, t) - step(t, C.x)) * (0.9 + 0.9 * o));
            float sl = drho / max(rho, 1e-3);
            float d = (r - rho) * inversesqrt(1.0 + sl * sl) * mix(1.0, sq, 0.5);
            float w = D.x * swell * mix(0.75, tail, 0.6);
            float u = abs(d) / w + step(t1, t) * 1e3;
            if (u < bu) { cu = bu; ct = bt; cd = bd; cw = bw; cdl = bdl; bu = u; bt = t; bd = d; bw = w; bdl = dlobe; }
            else if (u < cu) { cu = u; ct = t; cd = d; cw = w; cdl = dlobe; }
            float nl = lobe * ca + dlobe * sa;
            dlobe = dlobe * ca - lobe * sa;
            lobe = nl;
        }
        // the further pass first, then the nearer one over it
        if (cu < 2.0) {
            float e2 = smoothstep(t0, t0 + 1.2, ct) * smoothstep(t1, t1 - 1.2, ct);
            vec4 s2 = knotShadeFar(cd / (cw * knotThick(ct, seed)), ct, R, seed, D.z, e2, (0.56 + 0.24 * cdl) * level);
            col = col * (1.0 - s2.a) + s2.rgb;
        }
        near += 1.0 / (1.0 + bu * bu);
        if (bu > 2.2) return;              // this pixel is nowhere near the strand
        float e1 = smoothstep(t0, t0 + 1.2, bt) * smoothstep(t1, t1 - 1.2, bt);
        vec4 s1 = knotShade(bd / (bw * knotThick(bt, seed)), bt, R, seed, D.y, D.z, e1, 0.7 + 0.3 * bdl, level);
        col = col * (1.0 - s1.a) + s1.rgb;
    }

    // One layer (front or back half) of a twisted bundle of fibres.
    // `ph` is the angle round the bundle, `s` the distance along it.
    // Returns the colour in rgb and how much it covers what's behind in a.
    vec4 knotFibres(float ph, float s, float x, float flow, float nf, float seed,
                    vec3 tint, float fan, float lit) {
        float ax = abs(x);
        // fibres: count them round the bundle; where it fans out wide, each one
        // splits into finer threads
        float c = ph * nf / (2.0 * PI) + seed * 13.0;
        float fi = floor(c);
        float fh = hash21(vec2(fi, seed));
        float fl = abs(fract(c) - 0.5);
        float thread = smoothstep(0.12 + 0.25 * fh, 0.02, fl);
        float c2 = c * 3.0;
        float fine = smoothstep(0.3, 0.05, abs(fract(c2) - 0.5)) * hash21(vec2(floor(c2), seed + 3.0));
        thread = mix(thread, max(thread * 0.6, fine), fan);
        // long streaks flowing in along the fibres: they split, thin out and rejoin
        float streak = knotNoise1((abs(s) * 14.0 - flow) * (1.0 + fh) + fi * 7.3);
        thread *= smoothstep(0.25, 0.6, streak);
        // ragged edges: some fibres stray outside the bundle, some stop short
        float rag = knotNoise1(abs(s) * 6.0 + fi * 3.1);
        float env = smoothstep(1.0, 0.75 - 0.3 * rag * fan, ax);
        // the paint body: a soft round bundle, streaked along its length
        float body = sqrt(max(1.0 - x * x, 0.0)) * (0.3 + 0.9 * streak * streak);
        // glittering flecks caught in the paint, and treble sparkle on the fibres
        float fa = (abs(s) * 90.0 - flow * 2.0) + fh * 7.0;
        float fleck = step(0.8, hash21(vec2(floor(fa), floor(c2) + seed * 41.0)));
        fleck *= smoothstep(0.35, 0.05, length(vec2(fract(fa) - 0.5, fract(c2) - 0.5)));
        float gl = step(0.985 - 0.04 * uTreble, hash21(vec2(fi + seed * 31.0, floor(fa * 0.5))));
        // fine bright filaments running through the gold
        float c3 = c * 2.0 + 0.37;
        float fil = smoothstep(0.08, 0.0, abs(fract(c3) - 0.5)) * step(0.65, hash21(vec2(floor(c3), seed + 9.0)));
        fil *= smoothstep(0.4, 0.8, knotNoise1(abs(s) * 5.0 - flow * 0.5 + floor(c3) * 5.1)) * step(0.3, tint.g);
        float s1 = env * (body * 0.75 + thread * (0.35 + 0.9 * fh));
        vec3 hot = mix(tint, vec3(1.0, 0.85, 0.7), 0.5);
        vec3 col = tint * s1 + hot * env * (fil * 1.6 + thread * fh * fh * fh * fh + (fleck * 0.6 + gl * thread * (0.9 + 2.0 * uTreble)) * step(0.4, fh));
        return vec4(col * lit, 0.55 * env);
    }

    // A stream: a bundle of fibres along a gently bent axis through the neck at
    // `n`, `ang` pointing back up the stream to where it comes in. It is narrow
    // at the neck and fans out either side (`flareIn` where it enters, `flareOut`
    // past the neck), and twists hardest right at the neck.
    void knotStream(inout vec3 col, inout float near, vec2 p, vec2 n, float ang, float bend,
                    float flareIn, float flareOut, float twist, float spin, float flow,
                    float nf, float seed, vec3 tint, float fadeOut, float lit) {
        vec2 dir = vec2(cos(ang), sin(ang));
        vec2 q = p - n;
        float s = dot(q, dir);                                // > 0: coming in
        float v = dot(q, vec2(-dir.y, dir.x)) - bend * s * s;
        float neck = 0.018 * (1.0 - 0.3 * uBass);            // bass wrings the neck tighter
        float W = neck + s * s * (s > 0.0 ? flareIn : flareOut);
        float x = v / W;
        float ax = abs(x);
        float side = s > 0.0 ? 1.0 : fadeOut;
        float reach = smoothstep(0.0, 0.08, s + 0.9);
        float fan = smoothstep(0.03, 0.3, W);
        near += side * reach / (1.0 + ax * ax);
        // a soft glow round the stream
        col += tint * side * reach * 0.06 * lit / (1.0 + 2.0 * ax * ax);
        if (ax > 1.05) return;
        // a projected twisted cylinder: each fibre sits at angle ph round it
        float a = acos(clamp(x, -1.0, 1.0));
        float T = twist * s / (0.05 + abs(s)) + spin;         // twists hardest at the neck
        float depth = 0.65 + 0.35 * sqrt(max(1.0 - x * x, 0.0));
        vec4 back = knotFibres(-a - T, s, x, flow, nf, seed, tint, fan, lit * side * reach * 0.55);
        col = col * (1.0 - back.a * 0.6) + back.rgb;
        vec4 front = knotFibres(a - T, s, x, flow, nf, seed, tint, fan, lit * side * reach * depth);
        col = col * (1.0 - front.a) + front.rgb;
    }

    void main() {
        vec2 p = screenP();
        float clk = knotClock();
        float retie = knotRetie();
        float lit = (0.35 + 0.65 * uActive) * (1.1 + 0.5 * uLevel + 0.4 * uBass);
        // the neck sits a little left of centre, wandering slowly
        vec2 n = vec2(-0.08 + 0.03 * sin(clk * 0.13), 0.0 + 0.02 * sin(clk * 0.11 + 1.0));
        float flow = uScroll * 6.0 + uTime * 0.6;             // streaks run in along the streams
        float swell = 1.0 + 0.4 * uBass;                       // bass swells the fans
        float wring = 2.6 + 0.6 * uBass;                       // and twists it harder
        float tie = retie * 0.9;                                // every beat twists it another notch

        vec3 col = vec3(0.004, 0.03, 0.0);                     // lands near-neutral black after the grade
        float near = 0.0;
        // gold comes in from the bottom right, pink from the top left
        knotStream(col, near, p, n, -0.9 + 0.08 * sin(clk * 0.2), 0.5, 3.0 * swell, 0.8 * swell,
                   wring, clk * 0.5 + tie, flow, 40.0, 2.0, knotGold, 0.4, lit);
        knotStream(col, near, p, n, 2.6 + 0.08 * sin(clk * 0.17 + 2.0), -0.4, 2.4 * swell, 0.7 * swell,
                   -wring, -clk * 0.6 - tie, flow * 1.1, 46.0, 1.0, knotPink, 0.35, lit);
        // loose threads tangled round the neck
        knotStrand(col, near, p, n, clk, retie, 1.0 - 0.16 * uBass, swell, lit,
                   vec4(0.01, 0.0, 0.4, 0.6), vec4(0.07, 1.5, 0.5, 0.0), vec4(0.0, 9.0, 1.6, 1.4), vec4(0.022, 8.0, 1.0, 4.0));
        knotStrand(col, near, p, n, clk, retie, 1.0 - 0.16 * uBass, swell, lit,
                   vec4(-0.01, 0.01, 2.0, 0.5), vec4(0.06, 2.5, 0.45, 2.0), vec4(1.0, 8.0, 1.4, 1.6), vec4(0.018, 7.0, 0.0, 5.0));
        near = min(near, 2.0);
        // warm light gathered in the neck
        float kr = length(p - n);
        col += mix(knotPink, knotGold, 0.6) * exp(-kr * 10.0) * (0.25 + 0.5 * uBeatStrength) * lit;

        // gold glitter flecks, thicker round the streams
        vec2 gq = (p - n) * 60.0;
        vec2 gc = floor(gq);
        float gh = hash21(gc);
        vec2 go = fract(gq) - 0.5 - (vec2(hash21(gc + 3.1), hash21(gc + 7.7)) - 0.5) * 0.6;
        float gsz = 0.07 + 0.2 * knotSq(hash21(gc + 1.9));
        float speck = smoothstep(gsz, gsz * 0.3, length(go)) * step(0.99 - 0.25 * near - 0.04 * uTreble, gh);
        col += mix(knotGold, vec3(1.0, 0.85, 0.5), hash21(gc + 5.5)) * speck * (0.8 + 1.0 * uTreble) * lit;

        // a dense field of glitter, flakes and glass streaming out from the neck
        // towards the camera: far layers are fine specks, near ones big, soft,
        // chunky flakes streaked by their speed
        float travel = uScroll * 0.5 + uTime * 0.04;
        vec2 rq = p - n;
        float rr = max(length(rq), 1e-3);
        vec2 rdir = rq / rr;
        float busy = min(near, 1.0) * 0.7 + exp(-rr * 5.0);
        for (int k = 0; k < 4; k++) {
            float fk = float(k);
            float z = fract(fk * 0.25 + travel);                    // 0 far, 1 right past us
            float scale = mix(26.0, 2.2, z * z);
            vec2 bq = rq * scale + vec2(fk * 17.3, fk * 9.1);
            vec2 bc = floor(bq);
            float bh = hash21(bc + fk * 3.1);
            vec2 lo = fract(bq) - 0.5 - (vec2(hash21(bc + 1.3), hash21(bc + 5.9)) - 0.5) * 0.4;
            float along = dot(lo, rdir), across = dot(lo, vec2(-rdir.y, rdir.x));
            float blur = 1.0 + 2.5 * z * z * (0.4 + 0.6 * uLevel);   // motion streaks
            float fade = smoothstep(0.0, 0.2, z) * smoothstep(1.0, 0.8, z);
            float size = (0.05 + 0.18 * knotSq(hash21(bc + 2.2))) * (0.8 + 0.6 * z);
            if (bh < 0.02 && z > 0.55) {
                // a cyan glass shard, tumbling
                vec2 cp = rot(bh * 300.0 + clk * 1.5 + retie * 0.5) * vec2(along / blur, across);
                vec2 kp = vec2(cp.x + 0.5 * cp.y, cp.y);
                float sd = max(sdBox(kp, vec2(size * 1.6 + 0.08, size * 0.8 + 0.05)), dot(cp, vec2(0.6, 0.8)) - size * 0.6 - 0.03);
                float edge = 0.015 + 0.03 * z;
                float shard = smoothstep(edge, -edge, sd);
                float rim = smoothstep(edge + 0.03, 0.0, abs(sd));
                float face = smoothstep(-0.1, 0.1, cp.x - cp.y);
                vec3 glass = knotCyan * (0.3 + 0.4 * face + 0.7 * rim) * (1.0 + 0.8 * uTreble + 0.6 * uBeatStrength) * (0.35 + 0.65 * uActive);
                col = mix(col, glass + col * 0.4, shard * fade * 0.75);
            } else if (bh < 0.08 + 0.55 * busy) {
                // a gold speck far off, a soft chunky flake up close
                float soft = mix(0.04, 0.35, z) * size + 0.01;
                float d = length(vec2(along / blur, across) * vec2(1.0, 1.0 + 0.4 * hash21(bc + 8.1))) - size;
                float flake = smoothstep(soft, -soft, d);
                vec3 fc = mix(vec3(1.0, 0.45, 0.1), vec3(1.0, 0.75, 0.4), hash21(bc + 6.6));
                float fb = (0.3 + 1.0 * hash21(bc + 3.3)) * mix(1.4, 0.7, z) * lit * fade;
                col += fc * flake * fb * (0.6 + 0.6 * uTreble * (1.0 - z));
            }
        }

        col = 1.0 - exp(-col * 1.5);                      // soft highlight roll-off
        col = mix(col * 0.4, col, uActive);               // dims and settles in silence
        fragColor = vec4(col, 1.0);
    }
    """
}
