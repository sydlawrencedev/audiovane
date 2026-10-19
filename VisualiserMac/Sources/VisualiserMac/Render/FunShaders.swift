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
        (.wormhole, wormhole),
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

    /// Two ribbons of fine glowing strands, one magenta and one cyan, twist
    /// through floating glass polyhedra above a glossy floor. The glass is
    /// ray-traced exactly (each shape is a set of paired face planes, so there
    /// is no raymarching loop): it reflects the room, refracts the ribbons
    /// behind it and lights up along its edges. The whole scene slides right
    /// to left past the camera, so near glass and near stretches of ribbon
    /// cross faster than far ones (parallax), and each shape comes back in
    /// from the right once it has left. The slide speeds up with uScroll. The
    /// bass bends the ribbons and widens them, every beat turns the glass and
    /// reshapes the ribbons a step, the spectrum shapes each ribbon along its
    /// length, and the treble makes the edges and the dust sparkle.
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
    const int kStrands = 11;

    const vec3 ribbonMagenta = vec3(1.0, 0.16, 0.72);
    const vec3 ribbonViolet = vec3(0.52, 0.26, 1.0);
    const vec3 ribbonCyan = vec3(0.0, 0.85, 1.0);

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

    vec3 ribbonHue(float t) {
        t = fract(t);
        vec3 c = mix(ribbonMagenta, ribbonViolet, smoothstep(0.0, 0.33, t));
        c = mix(c, ribbonCyan, smoothstep(0.33, 0.66, t));
        return mix(c, ribbonMagenta, smoothstep(0.66, 1.0, t));
    }

    // Light from the two ribbon bundles at point q on their plane (z = 0).
    // soft > 0 blurs them, for reflections in the floor.
    vec3 ribbonLight(vec2 q, float soft) {
        vec3 acc = vec3(0.0);
        float turn = beatTurn();
        float X = q.x + sceneShift();                        // position along the ribbon, sliding left
        float hueDrift = 0.08 * sin(uBeats * PI / 32.0);     // colours sway a little over 64 beats
        float x01 = clamp(q.x / 6.0 + 0.5, 0.0, 1.0);
        float edge = smoothstep(-3.8, -2.6, q.x) * smoothstep(3.8, 2.6, q.x);
        for (int b = 0; b < 2; b++) {
            float fb = float(b);
            float sx = fb > 0.5 ? 0.3 + x01 * 0.5 : 0.05 + x01 * 0.35;
            float base = fb > 0.5 ? 0.5 : 0.15;
            float spec = 0.55 * (ribbonSpec(base - 0.1) + ribbonSpec(base) + ribbonSpec(base + 0.1)) / 3.0
                       + 0.45 * (ribbonSpec(sx - 0.08) + ribbonSpec(sx) + ribbonSpec(sx + 0.08)) / 3.0;
            // Bass bends the bundle harder; each beat reshapes it a little.
            float amp = (0.17 + 0.18 * spec + 0.26 * uBass) * mix(0.6, 1.0, uActive);
            float ph = fb * 2.1 + turn * 0.55;
            float k = 0.8 + fb * 0.25;
            float s = uScroll * (0.35 - fb * 0.12);              // a gentle ripple along the ribbon on top of the slide
            float a1 = X * k + s + ph;
            float a2 = X * k * 2.1 - s * 0.6 + ph * 1.7 + fb;
            float yc = (fb > 0.5 ? -0.34 : 0.02) + amp * sin(a1) + amp * 0.4 * sin(a2);
            float lo = kFloorY + 0.13;                       // skim the floor rather than sink into it
            yc = 0.5 * (yc + lo + sqrt((yc - lo) * (yc - lo) + 0.004));
            float slope = amp * k * (cos(a1) + 0.84 * cos(a2));
            // Each bundle is a flat ribbon of fine parallel strands that twists
            // as it travels: wide where it faces you, a bright pinch where it turns.
            float width = (0.10 + 0.09 * uBass + 0.06 * uBeatStrength) * (0.8 + 0.2 * sin(X * 0.7 + fb * 3.0));
            float twist = X * (0.75 + 0.2 * fb) - uScroll * 0.3 + fb * 1.7 + turn * 0.25;
            float face = cos(twist);
            float radius = width * abs(face);
            float norm = inversesqrt(1.0 + slope * slope);
            float dc = abs(q.y - yc) * norm;
            vec3 bundle = vec3(0.0);
            // Only pixels near the bundle pay for its strands.
            if (dc < radius + 0.12 + soft * 12.0) {
                float pinch = 1.0 / (0.35 + 0.65 * abs(face));     // strands crowd together and glow hotter at the turn
                for (int i = 0; i < kStrands; i++) {
                    float u = float(i) / float(kStrands - 1) * 2.0 - 1.0;
                    float d = abs(q.y - yc - u * width * face) * norm;
                    float w = 0.0022 + 0.0022 * (1.0 - abs(u)) + soft;
                    float core = 1.0 - smoothstep(0.0, w, d);
                    float halo = exp(-d / (0.014 + soft * 3.0));
                    vec3 c = ribbonHue(abs(u) * 0.22 + fb * 0.55 + X * 0.02 + hueDrift);
                    bundle += c * (core * 2.4 + halo * 0.4) * (0.55 + 0.45 * (1.0 - abs(u))) * min(pinch, 1.8);
                }
            }
            // the ribbon's translucent body, and its glow on the air around it
            vec3 bodyC = ribbonHue(0.05 + fb * 0.55 + X * 0.02 + hueDrift);
            bundle += bodyC * exp(-pow(dc / (radius + 0.015 + soft * 2.0), 2.0)) * 0.28;
            bundle += bodyC * exp(-dc / (0.16 + soft * 4.0)) * 0.12;
            acc += bundle;
        }
        float glow = (0.4 + 0.6 * uActive) * (0.85 + 0.5 * uLevel + 0.6 * uBeatStrength);
        return acc * edge * glow / (1.0 + soft * 25.0);
    }

    // The ribbons live on a curved sheet that slides left with the scene, so
    // stretches of ribbon swing towards the camera (and move faster) and back
    // away again. Where a ray meets it (a few fixed-point steps), or -1.
    float ribbonDepth(float x) { return 1.0 * sin((x + sceneShift()) * 0.45 + 0.9) - 0.1; }
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

    // Night sky behind everything: indigo falling to deep navy, a soft glow behind
    // the ribbons, and a little dust that sparkles with the treble.
    vec3 skyColour(vec3 rd) {
        vec3 col = mix(vec3(0.006, 0.014, 0.050), vec3(0.016, 0.026, 0.095), smoothstep(-0.1, 0.6, rd.y));
        col += vec3(0.16, 0.04, 0.22) * exp(-length(rd.xy - vec2(0.15, 0.02)) * 3.0) * (0.25 + 0.35 * uActive);
        col += vec3(0.01, 0.12, 0.22) * exp(-length(rd.xy - vec2(-0.45, -0.1)) * 3.0) * (0.25 + 0.35 * uActive);
        vec2 sp = rd.xy / max(rd.z, 0.2) * 90.0 + vec2(sceneShift() * 5.0, 0.0);   // far dust drifts slowest
        vec2 cell = floor(sp);
        float h = hash21(cell);
        vec2 off = vec2(hash21(cell + 7.1), hash21(cell + 3.3)) - 0.5;
        float star = smoothstep(0.12, 0.0, length(fract(sp) - 0.5 - off * 0.6)) * step(0.93, h);
        float tw = 0.4 + 0.6 * sin(h * 50.0 + uTime * 2.0);
        col += vec3(0.7, 0.8, 1.0) * star * tw * (0.25 + 1.5 * uTreble) * (0.3 + 0.7 * uActive);
        return col;
    }

    // Soft studio lights for the glass to reflect.
    vec3 envColour(vec3 rd) {
        vec3 col = skyColour(rd);
        col += ribbonMagenta * 0.9 * pow(max(dot(rd, normalize(vec3(0.7, 0.3, -0.6))), 0.0), 6.0);
        col += ribbonCyan * 0.8 * pow(max(dot(rd, normalize(vec3(-0.7, 0.2, -0.6))), 0.0), 6.0);
        col += vec3(0.85, 0.9, 1.0) * 0.9 * pow(max(dot(rd, normalize(vec3(0.1, 1.0, -0.3))), 0.0), 16.0);
        col += vec3(0.30, 0.15, 0.45) * (0.5 + 0.5 * rd.y) * 0.25;
        return col;
    }

    // Where each glass shape is, how it's turned, and how big it is. Each one
    // sits at its own depth and slides left with the scene; once it's off the
    // left edge it comes back in from the right (a little higher or lower, a bit
    // bigger or smaller, turned differently), so the stream never runs dry. The
    // starting points are staggered so the shapes don't travel as one clump.
    void gemPose(int j, out vec3 c, out vec2 ang, out float r, out int faces) {
        float fj = float(j);
        if (j == 0)      { c = vec3(0.0, -0.05, 0.25);  r = 0.58; faces = 10; }
        else if (j == 1) { c = vec3(0.0, 0.22, 0.55);   r = 0.42; faces = 10; }
        else if (j == 2) { c = vec3(0.0, 0.55, 1.40);   r = 0.30; faces = 4; }
        else if (j == 3) { c = vec3(0.0, -0.30, -1.95); r = 0.17; faces = 4; }
        else if (j == 4) { c = vec3(0.0, -0.26, 2.40);  r = 0.34; faces = 10; }
        else if (j == 5) { c = vec3(0.0, 0.40, -0.70);  r = 0.26; faces = 4; }
        else if (j == 6) { c = vec3(0.0, 0.45, 2.00);   r = 0.38; faces = 10; }
        else             { c = vec3(0.0, -0.22, -1.20); r = 0.20; faces = 10; }
        // Wrap span: wide enough that the jump happens off screen at this depth.
        float depth = c.z + 3.4;
        float span = 2.0 * (depth * 1.1 + r) + 0.6;
        float x = fract(fj * 0.375 + 0.2) * span - sceneShift();
        float lap = floor(x / span);
        c.x = x - lap * span - 0.5 * span;
        float lh = hash11(lap * 3.7 + fj * 11.3);
        c.y = clamp(c.y + (lh - 0.5) * 0.4, kFloorY + r + 0.05, 0.75);
        r *= 0.85 + 0.3 * hash11(lap * 5.1 + fj * 2.9);
        c.y += 0.06 * sin(uTime * 0.45 + fj * 1.9);
        ang = vec2(uTime * (0.10 + 0.03 * fj) + uClock * 0.02 + fj * 1.3 + lh * 6.28,
                   beatTurn() * 0.32 + fj * 2.1);
        r *= 1.0 + 0.06 * uBeatStrength + 0.04 * uBass;
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

    // How close a surface point is to an edge: 1 on an edge, 0 mid-face.
    float gemEdge(vec3 p, int faces, float h, float w) {
        float a = -1e5, b = -1e5;
        for (int i = 0; i < 10; i++) {
            if (i >= faces) break;
            float d = abs(dot(p, kFaceAxes[i])) - h;
            if (d > a) { b = a; a = d; } else if (d > b) { b = d; }
        }
        return 1.0 - smoothstep(0.0, w, a - b);
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

    // Glow around each shape's silhouette, so the glass seems to give off light.
    vec3 gemHalo(vec3 ro, vec3 rd, float tMax) {
        vec3 acc = vec3(0.0);
        for (int j = 0; j < kGems; j++) {
            vec3 c; vec2 ang; float r; int faces;
            gemPose(j, c, ang, r, faces);
            float t = max(dot(c - ro, rd), 0.0);
            if (t > tMax) continue;
            float d = max(length(ro + rd * t - c) - r * 0.85, 0.0);
            acc += mix(ribbonCyan, ribbonMagenta, step(1.5, float(j)) * 0.6) * exp(-d * 9.0) * 0.05 / (1.0 + t * 0.15);
        }
        return acc * (0.4 + 0.6 * uActive + 0.8 * uBeatStrength);
    }

    // One glass shape: reflection, refraction of the ribbons behind it, and its
    // bright edges, front and back.
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
        float edgeW = (px * tn * 1.1 + 0.003) / r * h;
        float edgeFront = gemEdge(pIn, faces, h, edgeW);

        float fres = 0.12 + 0.88 * pow(1.0 - clamp(-dot(rd, nW), 0.0, 1.0), 4.0);
        vec3 rr = reflect(rd, nW);
        vec3 col = envColour(rr) * fres * 1.6;
        col += vec3(0.6, 0.7, 1.0) * pow(max(dot(nW, normalize(vec3(-0.3, 0.8, -0.5))), 0.0), 3.0) * 0.10;
        float facet = hash11(dot(nn, vec3(12.9, 78.2, 37.7)));   // each face catches the light a little differently
        col += mix(ribbonViolet, ribbonCyan, facet) * (0.03 + 0.06 * facet) * (0.5 + 0.5 * uActive);
        vec3 edgeCol = mix(vec3(0.8, 0.95, 1.0), ribbonCyan, 0.55);

        if (full) {
            // Through the glass: bend in, cross to the far face, bend out.
            vec3 d1 = refract(ord, nn, 1.0 / 1.45);
            float tn2, tf2; vec3 nn2, nf2;
            gemHit(pIn + d1 * 0.002, d1, faces, h, tn2, tf2, nn2, nf2);
            vec3 pOut = pIn + d1 * (0.002 + tf2);
            vec3 d2 = refract(d1, -nf2, 1.45);
            vec3 wOut = fromGem(pOut, ang) + c;
            vec3 behind;
            if (dot(d2, d2) < 0.5) {
                // total internal reflection: the face lights up with the room instead
                behind = envColour(fromGem(reflect(d1, -nf2), ang)) * 1.2;
            } else {
                vec3 wd2 = fromGem(d2, ang);
                behind = skyColour(wd2) + ribbonsAlong(wOut, wd2, 0.002, 30.0) * 1.15;
            }
            col += behind * vec3(0.78, 0.88, 1.0) * (1.0 - fres) * (0.85 + 0.3 * facet);
            float edgeBack = gemEdge(pOut, faces, h, edgeW * 1.2);
            col += edgeCol * edgeBack * 0.35;
            // A ribbon passing through the middle of the glass glows inside it.
            float tz = ribbonT(ro, rd);
            if (tz > tHit && tz < tHit + (tf - tn)) col += ribbonLight((ro + rd * tz).xy, 0.0) * 0.6;
        }
        float sparkle = 0.9 + 0.8 * uTreble + 1.0 * uBeatStrength;
        float edgeGlow = gemEdge(pIn, faces, h, edgeW * 5.0);
        col += edgeCol * (edgeFront + edgeGlow * 0.25) * sparkle * (0.45 + 0.55 * uActive);
        col += vec3(0.025, 0.035, 0.07);                 // a faint body tint
        return col;
    }

    void main() {
        vec2 p = screenP();
        // Camera sways slowly (on the sound-gated clock) and leans in a little
        // on the bass. The scene itself slides left past it (sceneShift).
        float yaw = 0.22 * sin(uTime * 0.07);
        vec3 ro = vec3(0.0, 0.16, -3.3 + 0.10 * uBass);
        ro.xz = rot(yaw) * ro.xz;
        vec3 fw = normalize(vec3(0.0, -0.12, 0.0) - ro);
        vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
        vec3 up = cross(fw, rt);
        vec3 rd = normalize(p.x * rt + p.y * up + 1.05 * fw);

        float tFloor = rd.y < 0.0 ? (kFloorY - ro.y) / rd.y : 1e5;
        vec3 col = skyColour(rd);

        int j; float tGem;
        bool hitGem = nearestGem(ro, rd, tFloor, j, tGem);
        float tEnd = hitGem ? tGem : tFloor;
        if (hitGem) {
            col = shadeGem(j, ro, rd, tGem, true);
        } else if (tFloor < 1e4) {
            // Glossy black floor: a blurred mirror of the ribbons and the glass,
            // fading into the dark further away.
            vec3 fp = ro + rd * tFloor;
            vec3 rr = reflect(rd, vec3(0.0, 1.0, 0.0));
            float fres = 0.35 + 0.65 * pow(1.0 - clamp(-rd.y, 0.0, 1.0), 5.0);
            vec3 refl = skyColour(rr) * 0.6;
            int j2; float t2;
            if (nearestGem(fp, rr, 40.0, j2, t2)) refl = shadeGem(j2, fp, rr, t2, false);
            float tr = ribbonT(fp, rr);
            refl += ribbonsAlong(fp, rr, 0.008 + 0.03 * max(tr, 0.0), 40.0) + gemHalo(fp, rr, 40.0);
            col = vec3(0.012, 0.014, 0.035) + refl * fres * 0.32;
            col += vec3(0.10, 0.05, 0.22) * exp(-abs(fp.z - 2.5) * 0.25) * pow(1.0 - clamp(-rd.y, 0.0, 1.0), 6.0) * (0.4 + 0.6 * uActive);
            col = mix(col, skyColour(rd), smoothstep(5.0, 30.0, tFloor));
        }
        // Ribbons in front of whatever we hit.
        col += ribbonsAlong(ro, rd, 0.0, tEnd);
        col += gemHalo(ro, rd, tEnd);
        col += vec3(1.0, 0.6, 0.95) * uBeatStrength * 0.04 * uActive;

        col = 1.0 - exp(-col * 1.8);                   // soft highlight roll-off
        col *= 1.0 - 0.35 * dot(p, p);                  // vignette
        col = mix(col * 0.5, col, uActive);             // dims in silence, but keeps drifting
        fragColor = vec4(col, 1.0);
    }
    """
}

extension FunShaders {
    // MARK: - Silk Flight

    /// Flying forward through the music: two satin ribbons, pink shading to
    /// violet, spiral away into a smoky blue nebula while cyan glass cubes
    /// tumble past and dust streams by. Each ribbon is a chain of depth slices
    /// (at most 40), projected and hit-tested per pixel with an inverse
    /// bilinear map, front to back; a pixel stops as soon as it's covered or
    /// past the ribbons' reach, so most stop after a few slices. The cubes
    /// are exact ray/box slabs. The
    /// camera flies on uScroll, so it races when the music is loud. The bass
    /// widens the spiral and the ribbons, the spectrum shapes the ribbons out
    /// in the distance, every beat turns the cubes a step and throws a burst
    /// of sparks, and the treble makes the dust and the glass edges sparkle.
    /// In silence: dim, and still.
    static let silk = """
    // Silk Flight: flying forward through the music. Two satin ribbons spiral
    // away into a smoky nebula, glass cubes tumble past, and dust streams by.

    const int kSilkSlices = 40;      // depth slices per ribbon
    const int kSilkCubes = 10;
    const int kSilkDust = 5;
    const float kSilkStep = 0.42;    // world depth between ribbon slices
    const float kSilkNear = 0.22;
    const float kSilkCubeGap = 1.35; // world depth between glass cubes

    const vec3 silkPink = vec3(1.0, 0.30, 0.70);
    const vec3 silkViolet = vec3(0.46, 0.20, 0.95);
    const vec3 silkCyan = vec3(0.30, 0.95, 1.0);
    const vec3 silkHaze = vec3(0.42, 0.55, 0.78);

    // How far the camera has flown. Forward-only, faster when louder.
    float silkTravel() { return uScroll * 2.6; }
    // One step per beat, eased in, so beat-driven changes never run backwards.
    float silkTurn() { return floor(uBeats) + smoothstep(0.0, 0.5, fract(uBeats)); }

    float silkSpec(float x01) {
        float f = clamp(x01, 0.0, 1.0) * 95.0;
        int i = int(floor(f));
        float t = fract(f);
        return mix(uBands[i], uBands[min(i + 1, 95)], t * t * (3.0 - 2.0 * t));
    }

    float silkNoise(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = hash21(i), b = hash21(i + vec2(1.0, 0.0));
        float c = hash21(i + vec2(0.0, 1.0)), d = hash21(i + vec2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }
    float silkFbm(vec2 p) {
        float s = 0.0, a = 0.5;
        for (int i = 0; i < 4; i++) {
            s += a * silkNoise(p);
            p = rot(0.6) * p * 2.03 + 11.7;
            a *= 0.5;
        }
        return s;
    }

    // Centre of ribbon b at world depth z (relative depth zr picks the spectrum
    // band: near is bass, far is treble), and the direction its width lies along.
    vec2 silkPath(float z, float zr, float b, out vec2 across) {
        float turn = silkTurn();
        float ang = z * 0.30 + b * PI + 0.7 * sin(z * 0.11 + b * 1.7);
        float spec = silkSpec(0.05 + 0.6 * clamp(zr / 12.0, 0.0, 1.0) + b * 0.12);
        // the music reshapes the ribbon out in the distance, not right in your face
        float react = smoothstep(0.4, 3.0, zr);
        float rad = (0.52 + 0.22 * sin(z * 0.19 + b * 2.0 + turn * 0.35) + 0.30 * spec * uActive * react) * (1.0 + 0.25 * uBass * react);
        float phi = ang + 1.57 + 0.95 * sin(z * 0.23 + b * 1.3 + turn * 0.45);
        across = vec2(cos(phi), sin(phi));
        return rad * vec2(cos(ang) * 1.35, sin(ang) * 0.85);
    }

    // Where world point (xy, depth zr in front of the camera) lands on screen.
    vec2 silkProject(vec2 xy, float zr, vec2 cam, float focal) { return (xy - cam) * focal / zr; }

    float silkCross(vec2 a, vec2 b) { return a.x * b.y - a.y * b.x; }

    // Inverse bilinear map: where p sits inside quad a b c d, as (across, along)
    // in 0..1, or negative when it's outside.
    vec2 silkInvQuad(vec2 p, vec2 a, vec2 b, vec2 c, vec2 d) {
        vec2 e = b - a, f = d - a, g = a - b + c - d, h = p - a;
        float k2 = silkCross(g, f);
        float k1 = silkCross(e, f) + silkCross(h, g);
        float k0 = silkCross(h, e);
        if (abs(k2) < 1e-6) {
            float v = -k0 / k1;
            vec2 den = e + g * v;
            float u = abs(den.x) > abs(den.y) ? (h.x - f.x * v) / den.x : (h.y - f.y * v) / den.y;
            return vec2(u, v);
        }
        float w = k1 * k1 - 4.0 * k0 * k2;
        if (w < 0.0) return vec2(-1.0);
        w = sqrt(w);
        float ik2 = 0.5 / k2;
        float v = (-k1 - w) * ik2;
        vec2 den = e + g * v;
        float u = abs(den.x) > abs(den.y) ? (h.x - f.x * v) / den.x : (h.y - f.y * v) / den.y;
        if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) {
            v = (-k1 + w) * ik2;
            den = e + g * v;
            u = abs(den.x) > abs(den.y) ? (h.x - f.x * v) / den.x : (h.y - f.y * v) / den.y;
        }
        return vec2(u, v);
    }

    // Satin: a soft body colour, a glossy streak that runs along the ribbon where
    // it turns to the light, and a bright sheen at grazing angles.
    vec3 silkShade(vec3 n, vec3 v, float s, float z, float b) {
        bool back = dot(n, v) < 0.0;
        if (back) n = -n;
        vec3 l1 = normalize(vec3(-0.5, 0.8, -0.35));
        vec3 l2 = normalize(vec3(0.75, -0.3, -0.45));
        float hue = 0.5 + 0.5 * sin(z * 0.17 + b * 2.4);
        float lit = max(dot(n, l1), 0.0);
        // shadowed satin goes deep violet, lit satin hot pink
        vec3 shadowC = mix(vec3(0.16, 0.04, 0.34), vec3(0.30, 0.06, 0.40), hue);
        vec3 litC = mix(silkPink, mix(silkPink, silkViolet, 0.55), clamp(0.6 * s * s + 0.4 * hue * b, 0.0, 1.0));
        vec3 col = mix(shadowC, litC, smoothstep(0.0, 0.9, lit));
        if (back) col *= vec3(0.75, 0.7, 1.0);
        col *= 0.55 + 0.25 * max(dot(n, l2), 0.0);
        float spec = pow(max(dot(n, normalize(l1 + v)), 0.0), 22.0);
        float spec2 = pow(max(dot(n, normalize(l2 + v)), 0.0), 18.0);
        float graze = pow(1.0 - abs(dot(n, v)), 3.0);
        col += vec3(1.0, 0.86, 0.97) * spec * (2.0 + 1.0 * uBeatStrength);
        col += mix(silkPink, silkCyan, 0.3) * spec2 * 0.4;
        col += mix(silkViolet, silkPink, 0.6) * graze * 0.45;
        // the long glossy streak satin always has, wandering across the ribbon
        float sheen = exp(-pow((s - 0.45 * sin(z * 0.8 + b * 2.0)) * 3.5, 2.0));
        col += mix(silkPink, vec3(1.0, 0.9, 1.0), 0.5) * sheen * (0.35 + 0.4 * lit) * (1.0 + 0.6 * uBeatStrength);
        return col;
    }

    // Nebula, dust and the beat sparks behind everything.
    vec3 silkBackground(vec2 p, float travel) {
        vec2 c = p - vec2(0.03, 0.02);
        float r = length(c);
        vec3 col = mix(vec3(0.004, 0.006, 0.016), vec3(0.012, 0.016, 0.034), exp(-r * 2.0));
        // Smoke we keep flying into: two layers that grow out of the centre and
        // cross-fade, so the zoom never ends.
        float smoke = 0.0;
        for (int i = 0; i < 2; i++) {
            float ph = fract(travel * 0.035 + float(i) * 0.5);
            vec2 q = rot(uTime * 0.015 + float(i) * 2.0) * c * (3.2 * exp2(-ph * 1.6));
            smoke += silkFbm(q + float(i) * 7.3) * sin(ph * PI);
        }
        smoke = smoothstep(0.30, 1.0, smoke);
        float core = exp(-r * 3.0);
        col += silkHaze * smoke * core * (0.85 + 0.45 * uMid) * (0.45 + 0.55 * uActive);
        col += vec3(0.24, 0.16, 0.40) * smoke * exp(-r * 1.8) * 0.18;
        col += vec3(0.22, 0.30, 0.48) * core * core * 0.30;
        // Dust streaming past in a few depth layers.
        float a = atan(c.y, c.x);
        for (int i = 0; i < kSilkDust; i++) {
            float fi = float(i);
            float zl = fract(fi / float(kSilkDust) - travel * 0.06);
            vec2 sp = c * mix(26.0, 2.5, zl) + vec2(fi * 13.1, fi * 7.7);
            vec2 cell = floor(sp);
            float h = hash21(cell);
            vec2 off = vec2(hash21(cell + 3.1), hash21(cell + 8.3)) - 0.5;
            float d = length(fract(sp) - 0.5 - off * 0.7);
            float size = 0.035 + 0.05 * zl;
            float star = smoothstep(size, 0.0, d) * step(0.88, h);
            float fade = smoothstep(0.0, 0.25, zl) * smoothstep(1.0, 0.75, zl);
            vec3 sc = mix(vec3(1.0, 0.55, 0.85), vec3(0.75, 0.9, 1.0), hash21(cell + 1.7));
            col += sc * star * fade * (0.5 + 1.2 * uTreble + 0.8 * uBeatStrength) * (0.35 + 0.65 * uActive);
        }
        // A burst of sparks on every beat, flying out from the middle.
        float ph = fract(uBeats);
        float cellA = floor(a / (2.0 * PI) * 48.0);
        float hs = hash11(cellA + floor(uBeats) * 1.37);
        float sr = (0.06 + 0.7 * hs) * (1.0 - pow(1.0 - ph, 3.0));
        float aMid = (cellA + 0.5) / 48.0 * 2.0 * PI;
        vec2 sparkP = vec2(cos(aMid), sin(aMid)) * sr;
        float spark = smoothstep(0.006, 0.0, length(c - sparkP) - 0.002) * step(0.55, hs);
        col += mix(silkPink, silkCyan, hash11(cellA * 1.3)) * spark * uBeatStrength * (1.0 - ph) * 2.5 * uActive;
        return col;
    }

    // Glass cube j: centre (relative to the camera), half size and turn.
    void silkCube(int j, float travel, out vec3 c, out float h, out vec2 ang) {
        float n = floor(travel / kSilkCubeGap) + float(j);
        float hz = hash11(n * 1.91 + 0.3);
        float ha = hash11(n * 7.13 + 1.1);
        float hr = hash11(n * 3.77 + 2.9);
        float a = ha * 2.0 * PI;
        float rad = 0.55 + 1.5 * hr;
        c = vec3(cos(a) * rad * 1.3, sin(a) * rad * 0.8, n * kSilkCubeGap + hz * kSilkCubeGap - travel);
        h = (0.06 + 0.12 * hash11(n * 5.31)) * (1.0 + 0.10 * uBeatStrength);
        ang = vec2(uTime * (0.25 + 0.3 * hz) + ha * 6.0 + silkTurn() * 0.4, uTime * (0.2 + 0.25 * hr) + hr * 6.0);
    }

    vec3 silkToCube(vec3 v, vec2 ang) { v.xz = rot(ang.x) * v.xz; v.xy = rot(ang.y) * v.xy; return v; }
    vec3 silkFromCube(vec3 v, vec2 ang) { v.xy = rot(-ang.y) * v.xy; v.xz = rot(-ang.x) * v.xz; return v; }

    void main() {
        vec2 p = screenP();
        float travel = silkTravel();
        // Camera: a slow roll and sway on the sound-gated clock.
        p = rot(0.12 * sin(uTime * 0.05)) * p;
        vec2 cam = vec2(0.10 * sin(uTime * 0.11), 0.07 * sin(uTime * 0.083 + 1.0));
        float focal = 1.2 - 0.06 * uBass;
        float px = 1.0 / uResolution.y;

        vec3 col = silkBackground(p, travel);

        // --- Ribbons: front to back through depth slices.
        vec3 ribC = vec3(0.0);
        float ribA = 0.0;
        float ribZ = 1e5;
        float zFar = kSilkNear + float(kSilkSlices) * kSilkStep;
        // Nothing on a ribbon reaches further from the axis than this, so once a
        // slice at this depth would project inside the pixel's radius, every
        // slice beyond it does too and the pixel can stop looking.
        float reach = (2.25 + length(cam)) * focal;
        float pr = length(p);
        for (int b = 0; b < 2; b++) {
            float fb = float(b);
            vec3 accC = vec3(0.0);
            float accA = 0.0;
            float firstZ = 1e5;
            float width = (0.17 + 0.07 * uBass + 0.05 * uBeatStrength) * (1.0 - 0.35 * fb);
            // first slice sits exactly on the near plane
            float zA = travel + kSilkNear;
            vec2 acrossA;
            vec2 cA = silkPath(zA, kSilkNear, fb, acrossA);
            vec2 pa = silkProject(cA - acrossA * width, kSilkNear, cam, focal);
            vec2 pb = silkProject(cA + acrossA * width, kSilkNear, cam, focal);
            float z0 = (floor(zA / kSilkStep) + 1.0) * kSilkStep;
            for (int k = 0; k < kSilkSlices; k++) {
                if (pr * (zA - travel) > reach) break;
                float zB = z0 + float(k) * kSilkStep;
                float zrB = zB - travel;
                vec2 acrossB;
                vec2 cB = silkPath(zB, zrB, fb, acrossB);
                vec2 pc = silkProject(cB + acrossB * width, zrB, cam, focal);
                vec2 pd = silkProject(cB - acrossB * width, zrB, cam, focal);
                // cheap reject: is p anywhere near this quad?
                vec2 lo = min(min(pa, pb), min(pc, pd)) - 2.0 * px;
                vec2 hi = max(max(pa, pb), max(pc, pd)) + 2.0 * px;
                if (all(greaterThan(p, lo)) && all(lessThan(p, hi))) {
                    vec2 uv = silkInvQuad(p, pa, pb, pc, pd);
                    if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
                        float zrA = zA - travel;
                        float zr = mix(zrA, zrB, uv.y);
                        float s = uv.x * 2.0 - 1.0;
                        // surface frame at this point
                        vec2 across = normalize(mix(acrossA, acrossB, uv.y));
                        vec3 tang = normalize(vec3(cB - cA, zB - zA));
                        vec3 wdir = vec3(across, 0.0);
                        vec3 n = normalize(cross(tang, wdir));
                        float zw = zA + (zB - zA) * uv.y;
                        n = normalize(n + wdir * s * 1.3 - tang * 0.55 + tang * 0.3 * sin(zw * 1.7 + s * 1.2 + fb) * (1.0 - smoothstep(2.0, 8.0, zr)));   // rounded across, with soft folds, like satin
                        vec2 wxy = mix(cA, cB, uv.y) + across * width * s;
                        vec3 v = normalize(-vec3(wxy - cam, zr));
                        vec3 sc = silkShade(n, v, s, zA + (zB - zA) * uv.y, fb);
                        // soft edges, a pixel wide on screen
                        float wpx = length(mix(pb - pa, pc - pd, uv.y)) / px;
                        float edge = clamp((1.0 - abs(s)) * 0.5 * wpx, 0.0, 1.0);
                        float fog = smoothstep(zFar * 0.35, zFar, zr);
                        sc = mix(sc, silkHaze * 0.25, fog);
                        float alpha = edge * 0.96 * (1.0 - fog * fog);
                        accC += (1.0 - accA) * sc * alpha;
                        if (accA < 0.5 && accA + (1.0 - accA) * alpha >= 0.5) firstZ = zr;
                        accA += (1.0 - accA) * alpha;
                    }
                }
                if (accA > 0.985) break;
                zA = zB; cA = cB; acrossA = acrossB; pa = pd; pb = pc;
            }
            // keep whichever ribbon is in front on top
            if (firstZ < ribZ) {
                ribC = accC + (1.0 - accA) * ribC;
                ribA = accA + (1.0 - accA) * ribA;
                ribZ = firstZ;
            } else {
                ribC = ribC + (1.0 - ribA) * accC;
                ribA = ribA + (1.0 - ribA) * accA;
            }
        }
        float glowR = (0.95 + 0.5 * uLevel + 0.5 * uBeatStrength);
        ribC *= glowR;

        // --- Glass cubes tumbling past.
        vec3 ro = vec3(cam, 0.0);
        vec3 rd = normalize(vec3(p, focal));
        float tHit = 1e5;
        vec3 cubeC = vec3(0.0);
        float cubeA = 0.0;
        vec3 halo = vec3(0.0);
        for (int j = 0; j < kSilkCubes; j++) {
            vec3 c; float h; vec2 ang;
            silkCube(j, travel, c, h, ang);
            if (c.z < 0.05) continue;
            vec3 oc = ro - c;
            float tc = max(dot(-oc, rd), 0.0);
            float dl = length(oc + rd * tc);
            halo += silkCyan * exp(-max(dl - h * 1.2, 0.0) * 18.0) * 0.06 / (1.0 + c.z * 0.25);
            if (dl > h * 1.75) continue;
            vec3 o = silkToCube(oc, ang), d = silkToCube(rd, ang);
            vec3 inv = 1.0 / d;
            vec3 t1 = (-h - o) * inv, t2 = (h - o) * inv;
            vec3 tmin = min(t1, t2), tmax = max(t1, t2);
            float tn = max(max(tmin.x, tmin.y), tmin.z);
            float tf = min(min(tmax.x, tmax.y), tmax.z);
            if (tn < tf && tn > 0.0 && tn < tHit) {
                tHit = tn;
                vec3 q = o + d * tn;
                vec3 nl = step(tmin.yzx, tmin) * step(tmin.zxy, tmin) * -sign(d);
                vec3 nW = silkFromCube(nl, ang);
                vec3 aq = abs(q) / h;
                // second-largest coordinate: near 1 along an edge
                float m1 = max(max(aq.x, aq.y), aq.z);
                float m2 = aq.x + aq.y + aq.z - m1 - min(min(aq.x, aq.y), aq.z);
                float ew = 0.05 + px * tn * 2.5 / h;
                float edge = smoothstep(1.0 - ew, 1.0, m2);
                vec3 qb = o + d * tf;
                vec3 ab = abs(qb) / h;
                float b1 = max(max(ab.x, ab.y), ab.z);
                float b2 = ab.x + ab.y + ab.z - b1 - min(min(ab.x, ab.y), ab.z);
                float edgeBack = smoothstep(1.0 - ew, 1.0, b2);
                float fres = 0.1 + 0.9 * pow(1.0 - abs(dot(rd, nW)), 4.0);
                vec3 rr = reflect(rd, nW);
                vec3 env = silkHaze * 0.25 + silkPink * 0.8 * pow(max(dot(rr, normalize(vec3(0.6, 0.4, -0.7))), 0.0), 8.0)
                         + vec3(0.8, 0.95, 1.0) * pow(max(dot(rr, normalize(vec3(-0.3, 0.9, -0.3))), 0.0), 16.0);
                float streak = smoothstep(0.12, 0.0, abs(fract((q.x + q.y) / h * 0.7 + 0.3) - 0.5) - 0.18);
                vec3 face = vec3(0.0, 0.50, 0.60) * (0.55 + 0.45 * hash11(dot(nl, vec3(3.0, 5.0, 7.0)) + float(j)));
                cubeC = face + env * fres * 1.4 + silkCyan * streak * 0.18;
                cubeC += mix(silkCyan, vec3(0.85, 1.0, 1.0), 0.3) * (edge * 2.0 + edgeBack * 0.6) * (0.8 + 0.6 * uTreble + 0.8 * uBeatStrength);
                float fogC = smoothstep(9.0, kSilkCubeGap * float(kSilkCubes), c.z);
                cubeC = mix(cubeC, silkHaze * 0.2, fogC);
                cubeA = (0.45 + 0.5 * max(edge, fres)) * (1.0 - fogC);
            }
        }
        float cubeZ = tHit * rd.z;

        // --- Put it together, nearest on top.
        if (cubeZ < ribZ) {
            col = ribC + (1.0 - ribA) * col;
            col = mix(col, cubeC, cubeA);
        } else {
            col = mix(col, cubeC, cubeA);
            col = ribC + (1.0 - ribA) * col;
        }
        col += halo * (0.5 + 0.5 * uActive + 0.6 * uBeatStrength);

        col = 1.0 - exp(-col * 1.7);                    // soft highlight roll-off
        col *= 1.0 - 0.45 * dot(p, p);                   // vignette
        col = mix(col * 0.45, col, uActive);             // dims and settles in silence
        fragColor = vec4(col, 1.0);
    }
    """
}

extension FunShaders {
    // MARK: - Wormhole

    /// Falling through a knot of light, after the climax of the AudioVane
    /// brand film (0:38 to 0:40): a few thick, glittering streams of hot pink
    /// and gold sweep in from the edges of the screen over black space and
    /// twist into an off-centre knot, a gold coil turning away into the
    /// distance. Gold glitter, warm bokeh and a few cyan glass cubes fly out
    /// past the camera in depth layers. Drawn in log-polar space round the
    /// knot (angle, and log of the distance for depth), so it's a handful of
    /// noise lookups per pixel and five particle layers, with no raymarching.
    /// The colours are picked to land as hot pink and gold through the NEON
    /// grade, and the background carries a touch of green so the grade's
    /// purple lift reads as black. The fall runs on uScroll, so it rushes when
    /// the music is loud. The bass tightens the curl and the coil, every beat
    /// turns the knot a step and lifts the light, and the treble adds glitter
    /// and makes the glass glint. In silence: dim, and still.
    static let wormhole = """
    // Wormhole: falling through a knot of light in black space. A few thick,
    // glittering streams of hot pink and gold sweep in from the edges of the
    // screen and twist into an off-centre knot, while gold glitter, soft bokeh
    // and cyan glass cubes fly out past the camera.

    const int kWormLayers = 5;
    const vec3 wormPink = vec3(1.0, 0.13, 0.24);
    const vec3 wormGold = vec3(1.0, 0.54, 0.02);
    const vec3 wormCyan = vec3(0.0, 1.0, 0.80);

    // How far we've fallen. Forward-only, faster when louder.
    float wormTravel() { return uScroll * 9.0; }
    // One step per beat, eased in, so beat-driven turns never run backwards.
    float wormTurn() { return floor(uBeats) + smoothstep(0.0, 0.5, fract(uBeats)); }

    // Value noise that repeats every `period` cells in x, so it wraps round the
    // circle without a seam.
    float wormNoise(vec2 p, float period) {
        vec2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float i0 = mod(i.x, period), i1 = mod(i.x + 1.0, period);
        float a = hash21(vec2(i0, i.y)), b = hash21(vec2(i1, i.y));
        float c = hash21(vec2(i0, i.y + 1.0)), d = hash21(vec2(i1, i.y + 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    // Signed angle from `a` to `c`, wrapped to -PI..PI.
    float wormAngle(float a, float c) { return mod(a - c + PI, 2.0 * PI) - PI; }

    // One stream: a soft, ragged band of angle around `c` with half-width `w`.
    // `rag` roughens its edges.
    float wormStream(float a, float u, float c, float w, float seed, float rag) {
        float wob = wormNoise(vec2(u * 0.55 + seed, seed), 64.0) - 0.5;
        float d = abs(wormAngle(a, c + wob * 0.9));
        return smoothstep(w * (0.85 + 0.4 * wob), w * 0.45, d + (rag - 0.5) * w * 0.7);
    }

    // Roughly how close angle `a` is to a stream centred on `c`.
    float wormLobe(float a, float c) { return pow(0.5 + 0.5 * cos(a - c), 5.0); }

    // Long streaks running along the streams, stretched by the speed of the fall.
    float wormStreaks(float a, float flow, float n, float seed) {
        float x = a / (2.0 * PI) * n;
        float f = wormNoise(vec2(x, flow * 0.6 + seed), n);
        f = 0.6 * f + 0.4 * wormNoise(vec2(x * 3.0, flow * 1.0 - seed), n * 3.0);
        return f * f * f;
    }

    void main() {
        vec2 p = screenP();
        float travel = wormTravel();
        float turn = wormTurn();
        float lit = 0.35 + 0.65 * uActive;
        // The knot sits low and a little left of centre, drifting slowly.
        vec2 eye = vec2(-0.03 + 0.03 * sin(uTime * 0.11), -0.07 + 0.025 * sin(uTime * 0.09 + 1.0));
        vec2 q = p - eye;
        float r = max(length(q), 1e-4);
        float a = atan(q.y, q.x);
        float u = -log(r);                                // depth into the knot
        float flow = u * 3.0 - travel;                    // streaks rush outward

        // The streams curl hard near the knot and straighten out at the edges.
        // Bass tightens the curl; each beat turns the whole knot a step.
        float curl = (0.14 + 0.06 * uBass) / (r + 0.05);
        float a2 = a + curl + uTime * 0.012 + turn * 0.04;

        // A few broad streams: a wide pink fan, a gold river, and pink accents.
        float rag = wormNoise(vec2(a2 / (2.0 * PI) * 24.0, u * 0.8), 24.0);
        float pinkA = wormStream(a2, u, 3.2, 1.15, 1.0, rag);
        float goldA = wormStream(a2, u, -0.8, 1.0, 5.0, rag);
        float pinkB = wormStream(a2, u, 0.4, 0.5, 9.0, 1.0 - rag);
        float pinkC = wormStream(a2, u, 1.4, 0.22, 13.0, 1.0 - rag);
        float pink = max(max(pinkA, pinkB), pinkC * 0.8);

        float sp = wormStreaks(a2, flow, 90.0, 0.0);
        float sg = wormStreaks(a2 + 0.4, flow * 1.15, 120.0, 7.0);
        float level = (0.8 + 0.6 * uLevel + 0.5 * uBass) * lit;

        // Light gathers in the knot and dies in its very throat.
        float throat = smoothstep(0.0, 0.018, r);
        float knotGlow = exp(-r * 22.0);
        // A touch of green so the grade's purple lift lands as a near-neutral black.
        vec3 col = vec3(0.004, 0.03, 0.0);
        // a medium grain so the streams read as made of particles, not paint
        float grain = wormNoise(vec2(a2 / (2.0 * PI) * 200.0, u * 4.0 - travel * 1.3), 200.0);
        float sheet = wormNoise(vec2(a2 / (2.0 * PI) * 6.0, u * 0.7 - travel * 0.25), 6.0);
        grain = (0.25 + 1.5 * grain * grain) * (0.4 + 1.4 * sheet * sheet);
        col += wormPink * pink * (1.0 + 3.6 * sp) * grain * level * throat;
        col += wormGold * goldA * (0.9 + 3.4 * sg) * grain * level * throat;
        // the knot itself: a bright gold loop of light
        if (r < 0.2) {
            // the knot: a gold coil of light twisting away into the distance
            float loop = exp(-pow((r - 0.03) / 0.028, 2.0)) * (0.4 + 1.2 * wormStreaks(a2 * 2.0, flow, 40.0, 3.0));
            float coil = fract(u * 2.2 + a2 / (2.0 * PI) - travel * 0.5);
            coil = smoothstep(0.0, 0.3, coil) * smoothstep(0.9, 0.35, coil) * smoothstep(0.17, 0.05, r) * smoothstep(0.01, 0.03, r);
            coil *= 0.3 + 1.4 * sg;
            col += mix(wormGold, vec3(1.0, 0.85, 0.55), 0.3) * (loop * 2.4 + coil * (0.7 + 0.6 * uBass)) * level * throat;
        }
        col += vec3(1.0, 0.78, 0.45) * goldA * sg * sg * 2.4 * level * throat;     // white-hot cores
        col += vec3(1.0, 0.7, 0.85) * pink * sp * sp * sheet * 2.5 * level * throat;
        col += wormGold * pink * sg * sg * (1.0 - sheet) * 2.5 * level * throat;     // gold threads woven through the pink
        col += mix(wormGold, wormPink, 0.4) * knotGlow * (0.5 + 0.9 * uBeatStrength) * lit * throat;

        // Fine glitter inside the streams.
        // (log-polar cells are square on screen, so the specks keep their shape)
        vec2 gg = vec2(a2 / (2.0 * PI) * 220.0, (u * 3.0 - travel) * 220.0 / (6.0 * PI));
        vec2 gc = floor(gg);
        gc.x = mod(gc.x, 220.0);
        float gh = hash21(gc);
        vec2 gj = fract(gg) - 0.5 - (vec2(hash21(gc + 2.9), hash21(gc + 6.1)) - 0.5) * 0.8;
        float gsz = 0.1 + 0.5 * pow(hash21(gc + 4.3), 2.0);
        float glit = smoothstep(gsz, gsz * 0.3, length(gj * vec2(1.0, 0.55))) * step(0.80 - 0.18 * max(pink, goldA) - 0.10 * uTreble, gh) * (0.3 + 0.7 * hash21(gc + 8.2));
        col += mix(vec3(1.0, 0.36, 0.0), vec3(1.0, 0.75, 0.35), gh * gh * gh * gh) * glit * (pink * 1.4 + goldA * 1.4 + 0.4 * exp(-r * 8.0)) * 1.7 * (1.0 + uTreble) * lit * throat;

        // Gold sparks spraying out of the knot, streaked by their speed.
        vec2 sg2 = vec2(a2 / (2.0 * PI) * 150.0, u * 5.0 - travel * 1.6);
        vec2 sc = floor(sg2);
        sc.x = mod(sc.x, 150.0);
        float sh = hash21(sc + 31.0);
        vec2 so = fract(sg2) - 0.5 - (vec2(hash21(sc + 3.7), hash21(sc + 9.1)) - 0.5) * vec2(0.6, 0.4);
        float spark = smoothstep(0.18, 0.0, length(so * vec2(1.0, 0.18))) * step(0.93 - 0.05 * uTreble, sh) * (goldA + 2.0 * knotGlow);
        col += mix(wormGold, vec3(1.0, 0.9, 0.7), sh) * spark * (0.5 + 1.0 * uTreble + 1.0 * uBeatStrength) * throat * lit;

        // Bokeh, glitter specks and cyan glass cubes flying past in depth layers.
        vec2 dir = q / r;
        // more debris near the streams than out in empty space
        float near = 0.4 + 0.6 * max(wormLobe(a2, 3.2), wormLobe(a2, -0.8));
        for (int i = 0; i < kWormLayers; i++) {
            float fi = float(i);
            float z = fract(fi / float(kWormLayers) + travel * 0.25);     // 0 far, 1 right past us
            float scale = mix(14.0, 1.3, z * z);
            vec2 bq = q * scale + vec2(fi * 17.3, fi * 9.1);
            vec2 cell = floor(bq);
            float h = hash21(cell + fi * 3.1);
            vec2 local = fract(bq) - 0.5 - (vec2(hash21(cell + 1.3), hash21(cell + 5.9)) - 0.5) * 0.3;
            float along = dot(local, dir), side = dot(local, vec2(-dir.y, dir.x));
            float blur = 1.0 + 0.8 * z * z;                                 // motion blur
            float fade = smoothstep(0.0, 0.25, z) * smoothstep(1.0, 0.85, z);
            float size = 0.03 + 0.14 * pow(hash21(cell + 2.2), 2.0);
            if (h < 0.02 && z > 0.4) {
                // a cyan glass cube, tumbling
                vec2 cp = rot(h * 300.0 + uTime * 1.5 + turn * 0.5) * vec2(along / blur, side);
                float d = max(abs(cp.x), abs(cp.y)) - (0.09 + size * 0.8);
                float edge = 0.01 + 0.025 * z;                               // softer when close
                float cube = smoothstep(edge, -edge, d);
                float rim = smoothstep(edge + 0.03, 0.0, abs(d + 0.02));    // bright glass edges
                float face = smoothstep(-0.12, 0.12, cp.y + 0.4 * cp.x);              // lit from one side
                vec3 glass = wormCyan * (0.35 + 0.6 * face + 1.0 * rim) * (1.1 + 0.8 * uTreble + 0.6 * uBeatStrength) * lit;
                col = mix(col, glass + col * 0.45, cube * fade * 0.75);
            } else if (h < 0.06 + 0.5 * z * z) {
                // a soft out-of-focus disc, or a sharp gold speck
                float soft = mix(0.01, 0.07, z) * (0.5 + hash21(cell + 4.4));
                float d = length(vec2(along / blur, side)) - size;
                float disc = smoothstep(soft, -soft, d);
                vec3 bc = mix(vec3(0.85, 0.62, 0.40), vec3(1.0, 0.72, 0.25), hash21(cell + 7.7));
                col += bc * (0.25 + 0.9 * hash21(cell + 8.8)) * lit * disc * fade * near * (0.4 + 0.6 * z);
            }
        }

        col *= 1.0 + 0.25 * uBeatStrength * uActive;      // a lift on the beat
        col = 1.0 - exp(-col * 1.4);                      // soft highlight roll-off
        col = mix(col * 0.4, col, uActive);               // dims and settles in silence
        fragColor = vec4(col, 1.0);
    }
    """
}
