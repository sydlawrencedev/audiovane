// Draws a shared vibescape in the browser, so a link someone was sent shows the
// vibescape rather than a wall of shader.
//
// Built-in vibescapes have a page each with a picture rendered at build time. A
// shared custom vibescape can't have that: it arrives as source in the URL and
// nothing stores it. So it is drawn here, from the same source, by the same
// contract the app uses — the same prelude, the same `render(vec2, float)`
// wrapper, the same palette grade. What you see is the vibescape someone made,
// not a picture of it.
//
// Nothing is playing on a web page, so the uniforms come from a synthetic beat
// clock: a kick on every beat, a spectrum that swells with it, a bar that
// drifts. It is the same shape of made-up music the homepage video and the MCP
// preview tools use, so a vibescape behaves the same in all three.
//
// The first frame is drawn synchronously and is the picture the page has even if
// it never animates — so with reduced motion, on a machine without WebGL, or in
// a screenshot, there's still an image. Animation is added on top, never
// instead.

(function () {
  "use strict";

  var PRELUDE = `#version 330 core
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
uniform int uGenre;         // the genre of the music: 0 classical, 1 electronic, 2 rock,
                             // 3 pop, 4 hiphop, 5 jazz, 6 blues, 7 country, 8 rnb, 9 ambient
uniform float uTrackPos;    // seconds into the track, 0 when there is no position to know
uniform float uTrackDuration; // the length of the track in seconds, 0 when unknown
uniform float uTrackProgress; // 0..1 through the track, 0 when unknown
uniform float uTrackKnown;  // 1 when the position is real, 0 when there is none to know
uniform vec2 uMouse;         // the pointer, in the same coordinates as p: x across, y up from the middle
uniform float uMouseDown;    // 1 while a mouse button is held
uniform float uMouseHere;    // 1 when there is a pointer to react to, 0 when there is not
uniform float uKey;          // the last key pressed, as its character code; 0 when nothing has been pressed
uniform float uKeyDown;      // 1 while a key is held
uniform float uMidiNote;     // the last MIDI note, 0..127
uniform float uMidiVelocity; // how hard it was hit, 0..1
uniform float uMidiNotes;    // how many MIDI notes are held right now
uniform float uMidiCC;       // the last MIDI controller that moved, 0..127
uniform float uMidiCCValue;  // where that controller is, 0..1
out vec4 fragColor;

const float PI = 3.14159265;

// Centered coords: y spans -0.5..0.5, x scales with aspect ratio.
vec2 screenP() { return (gl_FragCoord.xy - 0.5 * uResolution) / uResolution.y; }

// Where the pointer is, in the same coordinates as p: x across the
// screen, y up from the middle. It is eased on its way here, so it
// never teleports from one place to another.
vec2 pointerAt() { return uMouse; }

// Where the pointer is, in 0..1 screen coordinates, y up. For the
// vibescapes that draw in that space rather than in p.
vec2 pointerUV() {
    return vec2(0.5 + uMouse.x * uResolution.y / uResolution.x, 0.5 + uMouse.y);
}

// Anti-alias width for a shape drawn at scale \`s\`.
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
`;

  var WRAPPER = `uniform vec3 uPalette[3];

void main() {
    vec2 p = screenP();
    vec3 c = render(p, uTime);
    fragColor = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
}`;

  var LIQUID_VS = `#version 330 core
layout(location = 0) in vec2 aPos;
out vec2 vUV;
void main() {
    vUV = aPos * 0.5 + 0.5;
    gl_Position = vec4(aPos, 0.0, 1.0);
}`;

  var GRADE_FS = `#version 330 core
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
}`;

  // NEON, the first palette in the app's list and the one it opens on. The
  // payload can't say which palette the sender was using.
  var PALETTE = {
    shadow:     [0.07, 0.00, 0.11],
    highlight:  [1.00, 0.36, 0.95],
    saturation: 1.15,
    duotone:    0.25,
    lift:       0.22
  };

  var BPM = 124;
  // Where the still is taken, in seconds. Far enough in that anything driven by
  // time has reached its stride, rather than being caught at its first frame.
  var T0 = 6.0;
  // The scroll clock runs at 0.7x wall time, as it does in the app, so this
  // looks like the app's own view of the same shader at the same moment.
  var SCROLL_RATE = 0.7;
  // 30 is plenty for a preview, and this is a background element.
  var FRAME_MS = 1000 / 30;

  /* Retargets a shader from the app's GLSL to the browser's.
   *
   * The app draws with desktop GLSL 3.30. A browser's WebGL2 context will not
   * accept that — checked against ANGLE/Metal, where `#version 330 core` fails
   * with "'core' : invalid version directive" for both stages. WebGL2 speaks
   * GLSL ES 3.00, which has no default float precision in a fragment shader.
   *
   * Adapted here rather than kept as a second copy, so the app changing its
   * prelude changes this page too.
   */
  function toES(source, fragment) {
    var lines = source.replace(/^#version[ \t]+330[ \t]+core/, "#version 300 es").split("\n");
    if (fragment) lines.splice(1, 0, "precision highp float;", "precision highp int;");
    return lines.join("\n");
  }

  /* The music that isn't there. Returns the uniforms a vibescape would be
   * drawing with if a kick were landing on the beat.
   *
   * uActive stays 1 throughout: a preview that respects the room's silence is a
   * preview of a black rectangle, which is the one thing this page can't be.
   */
  function fakeAudio(t) {
    var beat = 60 / BPM;
    var phase = t % beat;
    var kick = Math.exp(-phase * 5.5);
    var half = (t % (beat / 2)) / (beat / 2);
    var barPhase = (t % (beat * 4)) / (beat * 4);
    return {
      time: t,
      beats: t * (BPM / 60),
      scroll: t * SCROLL_RATE,
      clock: t,
      barPhase: barPhase,
      bass: 0.34 + 0.34 * kick,
      mid: 0.40 + 0.14 * half,
      treble: 0.18 + 0.20 * barPhase,
      level: 0.42 + 0.22 * kick,
      levelSmooth: 0.42 + 0.18 * barPhase,
      bassSmooth: 0.34 + 0.26 * kick,
      beat: kick > 0.75 ? 1 : 0,
      beatStrength: 0.62 * Math.max(0.15, kick),
      idle: 0,
      active: 1,
      presence: 0.9
    };
  }

  // Bass-heavy with sparkle, the low end swelling on the kick and the shape
  // drifting across the bar — the same curve the app's synthetic state uses.
  function bands(a) {
    var out = [];
    for (var i = 0; i < 96; i++) {
      var x = i / 95;
      var base = (1 - x) * 0.7 + 0.3 * Math.sin(x * 18);
      var swell = 1 + a.bass * 0.30 * (1 - x);
      var drift = 0.12 * Math.sin(x * 18 + a.barPhase * 2 * Math.PI);
      out.push(Math.max(0, Math.min(1, base * swell + drift)));
    }
    return out;
  }

  function compile(gl, type, source) {
    var shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      var log = gl.getShaderInfoLog(shader);
      gl.deleteShader(shader);
      throw new Error(log || "compile failed");
    }
    return shader;
  }

  function link(gl, vsSource, fsSource) {
    var vs = compile(gl, gl.VERTEX_SHADER, vsSource);
    var fs;
    try {
      fs = compile(gl, gl.FRAGMENT_SHADER, fsSource);
    } catch (e) {
      gl.deleteShader(vs);
      throw e;
    }
    var program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      var log = gl.getProgramInfoLog(program);
      gl.deleteProgram(program);
      throw new Error(log || "link failed");
    }
    return program;
  }

  function uniforms(gl, program, names) {
    var map = {};
    for (var i = 0; i < names.length; i++) {
      map[names[i]] = gl.getUniformLocation(program, names[i]);
    }
    return map;
  }

  /* Everything one frame needs, made once and reused.
   *
   * Compiling on every frame would be the obvious way to write this and it
   * would jank horribly; the shader doesn't change between frames, only the
   * uniforms. */
  function setup(gl, canvas, body) {
    var vs = toES(LIQUID_VS, false);
    // The order matters: GLSL has no forward declarations, so the caller of
    // `render` has to come after the function it calls.
    var program = link(gl, vs, toES(PRELUDE + "\n" + body + "\n" + WRAPPER, true));
    var grade = link(gl, vs, toES(GRADE_FS, true));

    var vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    var vbo = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

    // The scene is drawn into a texture because the grade has to sample it.
    var tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, canvas.width, canvas.height, 0,
                   gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    var fbo = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
      return null;
    }

    var u = uniforms(gl, program, ["uTime", "uBass", "uMid", "uTreble", "uLevel",
      "uLevelSmooth", "uBassSmooth", "uBeat", "uBeatStrength", "uResolution",
      "uIdle", "uActive", "uBeats", "uScroll", "uClock", "uPresence", "uGenre",
      "uTrackPos", "uTrackDuration", "uTrackProgress", "uTrackKnown",
      "uMouse", "uMouseDown", "uMouseHere", "uKey", "uKeyDown",
      "uMidiNote", "uMidiVelocity", "uMidiNotes", "uMidiCC", "uMidiCCValue",
      "uBands[0]", "uPalette[0]"]);
    var g = uniforms(gl, grade, ["uTex", "uShadow", "uHighlight", "uSaturation",
      "uDuotone", "uLift"]);

    var mid = [
      (PALETTE.shadow[0] + PALETTE.highlight[0]) / 2,
      (PALETTE.shadow[1] + PALETTE.highlight[1]) / 2,
      (PALETTE.shadow[2] + PALETTE.highlight[2]) / 2
    ];

    return {
      program: program, grade: grade, u: u, g: g,
      fbo: fbo, tex: tex, vao: vao,
      palette: [].concat(PALETTE.shadow, PALETTE.highlight, mid)
    };
  }

  // The pointer, in the same coordinates the shader's p is in: x across the
  // screen, y up from the middle, both scaled by the height.
  //
  // Where the pointer really is, and where it has been eased to. A pointer
  // arrives in whole pixels and jumps when the hand moves quickly, so a
  // vibescape that drew from it directly would twitch. The eased value is
  // what the shader gets: it chases the pointer with a time constant of a
  // few tens of milliseconds, quick enough to feel attached to the hand and
  // slow enough not to judder. The app eases it the same way.
  var pointer = { x: 0, y: 0, down: false, here: 0 };
  var pointerTarget = { x: 0, y: 0 };
  var pointerLast = 0;

  function easePointer(now) {
    var dt = pointerLast ? Math.min(0.1, Math.max(0, now - pointerLast)) : 0;
    pointerLast = now;
    // A time constant of about 45 milliseconds.
    var k = dt > 0 ? 1 - Math.exp(-dt / 0.045) : 0;
    pointer.x += (pointerTarget.x - pointer.x) * k;
    pointer.y += (pointerTarget.y - pointer.y) * k;
  }

  function watchPointer(canvas) {
    if (!canvas || !canvas.addEventListener) return;
    function move(event) {
      var rect = canvas.getBoundingClientRect();
      if (!rect || !rect.height) return;
      pointerTarget.x = (event.clientX - rect.left - rect.width / 2) / rect.height;
      pointerTarget.y = (rect.top + rect.height / 2 - event.clientY) / rect.height;
      pointer.here = 1;
    }
    canvas.addEventListener("pointermove", move);
    canvas.addEventListener("pointerdown", function (event) {
      move(event);
      pointer.down = true;
    });
    canvas.addEventListener("pointerup", function () { pointer.down = false; });
    canvas.addEventListener("pointerleave", function () { pointer.down = false; });
  }

  function draw(gl, canvas, s, t) {
    easePointer(t);
    var a = fakeAudio(t);
    var w = canvas.width, h = canvas.height;

    gl.bindFramebuffer(gl.FRAMEBUFFER, s.fbo);
    gl.viewport(0, 0, w, h);
    gl.clearColor(0.02, 0.004, 0.03, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(s.program);
    var u = s.u;
    gl.uniform1f(u.uTime, a.time);
    gl.uniform1f(u.uBass, a.bass);
    gl.uniform1f(u.uMid, a.mid);
    gl.uniform1f(u.uTreble, a.treble);
    gl.uniform1f(u.uLevel, a.level);
    gl.uniform1f(u.uLevelSmooth, a.levelSmooth);
    gl.uniform1f(u.uBassSmooth, a.bassSmooth);
    gl.uniform1f(u.uBeat, a.beat);
    gl.uniform1f(u.uBeatStrength, a.beatStrength);
    gl.uniform2f(u.uResolution, w, h);
    gl.uniform1f(u.uIdle, a.idle);
    gl.uniform1f(u.uActive, a.active);
    gl.uniform1f(u.uBeats, a.beats);
    gl.uniform1f(u.uScroll, a.scroll);
    gl.uniform1f(u.uClock, a.clock);
    gl.uniform1f(u.uPresence, a.presence);
    // The browser has no idea what is playing, so there is no position to
    // know: the track is unknown, and the uniforms say so rather than
    // pretending a shader that wants a progress bar is at the start.
    gl.uniform1f(u.uTrackPos, 0);
    gl.uniform1f(u.uTrackDuration, 0);
    gl.uniform1f(u.uTrackProgress, 0);
    gl.uniform1f(u.uTrackKnown, 0);
    // The browser has no idea what is playing, so the preview says it is
    // rock. A shader that branches on the genre still draws.
    gl.uniform1i(u.uGenre, 2);
    // The pointer, if there is a person at the page. A browser has no MIDI
    // and no keyboard to spare, so those stay at their neutral values.
    gl.uniform2f(u.uMouse, pointer.x, pointer.y);
    gl.uniform1f(u.uMouseDown, pointer.down ? 1 : 0);
    gl.uniform1f(u.uMouseHere, pointer.here);
    gl.uniform1f(u.uKey, 0);
    gl.uniform1f(u.uKeyDown, 0);
    gl.uniform1f(u.uMidiNote, 0);
    gl.uniform1f(u.uMidiVelocity, 0);
    gl.uniform1f(u.uMidiNotes, 0);
    gl.uniform1f(u.uMidiCC, 0);
    gl.uniform1f(u.uMidiCCValue, 0);
    gl.uniform1fv(u["uBands[0]"], bands(a));
    gl.uniform3fv(u["uPalette[0]"], s.palette);
    gl.bindVertexArray(s.vao);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    // The palette grade, so this looks like the app rather than raw shader
    // output. A custom vibescape is graded in the app too.
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, w, h);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(s.grade);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, s.tex);
    gl.uniform1i(s.g.uTex, 0);
    gl.uniform3fv(s.g.uShadow, PALETTE.shadow);
    gl.uniform3fv(s.g.uHighlight, PALETTE.highlight);
    gl.uniform1f(s.g.uSaturation, PALETTE.saturation);
    gl.uniform1f(s.g.uDuotone, PALETTE.duotone);
    gl.uniform1f(s.g.uLift, PALETTE.lift);
    gl.bindVertexArray(s.vao);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    gl.bindVertexArray(null);
  }

  function context(canvas) {
    return canvas.getContext("webgl2", {
      antialias: false, preserveDrawingBuffer: true, alpha: false
    });
  }

  /* One still. Returns {ok} or {ok:false, error}. */
  function render(body, canvas) {
    var gl = context(canvas);
    if (!gl) return { ok: false, error: "no webgl2" };
    var s;
    try {
      s = setup(gl, canvas, body);
    } catch (e) {
      return { ok: false, error: String(e.message || e) };
    }
    if (!s) return { ok: false, error: "framebuffer incomplete" };
    draw(gl, canvas, s, T0);
    return { ok: true };
  }

  /* The still, then the animation on top of it.
   *
   * `stop` pauses the loop and leaves the last frame on the canvas. The loop
   * stops itself when the tab is hidden or the preview has scrolled out of
   * view: a background animation nobody is looking at is a laptop fan.
   */
  function animate(body, canvas, opts) {
    opts = opts || {};
    var gl = context(canvas);
    if (!gl) return { ok: false, error: "no webgl2" };
    var s;
    try {
      s = setup(gl, canvas, body);
    } catch (e) {
      return { ok: false, error: String(e.message || e) };
    }
    if (!s) return { ok: false, error: "framebuffer incomplete" };

    watchPointer(canvas);

    draw(gl, canvas, s, T0);   // the image, before anything moves

    var running = false, raf = null, last = 0, elapsed = T0;
    var loop = function (now) {
      if (!running) return;
      raf = requestAnimationFrame(loop);
      if (now - last < FRAME_MS) return;
      last = now;
      elapsed += FRAME_MS / 1000;
      draw(gl, canvas, s, elapsed);
    };
    var start = function () {
      if (running) return;
      running = true;
      last = 0;
      raf = requestAnimationFrame(loop);
    };
    var stop = function () {
      running = false;
      if (raf) cancelAnimationFrame(raf);
      raf = null;
    };

    if (opts.animate === false) {
      return { ok: true, stop: stop };
    }
    start();

    document.addEventListener("visibilitychange", function () {
      if (document.hidden) stop(); else start();
    });
    if (typeof IntersectionObserver === "function") {
      new IntersectionObserver(function (entries) {
        var visible = entries.some(function (e) { return e.isIntersecting; });
        if (visible && !document.hidden) start(); else stop();
      }, { threshold: 0.01 }).observe(canvas);
    }
    return { ok: true, stop: stop };
  }

  window.vibresiaPreview = {
    render: render, animate: animate, T0: T0,
    // Exposed so the shaders can be checked from a console, and so the
    // drift check in scripts/check-preview-glsl.py can compare them.
    sources: {
      vs: function () { return toES(LIQUID_VS, false); },
      scene: function (body) { return toES(PRELUDE + "\n" + body + "\n" + WRAPPER, true); },
      grade: function () { return toES(GRADE_FS, true); }
    }
  };
})();
