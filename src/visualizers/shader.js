// shader.js — fullscreen psychedelic fluid (Milkdrop-inspired domain warping)
import * as THREE from 'three';

const VERT = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = vec4(position, 1.0);
  }
`;

const FRAG = /* glsl */ `
  precision highp float;

  varying vec2 vUv;

  uniform float uTime;
  uniform float uBass;
  uniform float uMid;
  uniform float uTreble;
  uniform float uLevel;
  uniform float uBeatStrength;
  uniform float uBands[96];
  uniform vec2  uResolution;
  uniform float uIdle; // 1.0 when no audio, ramps gently

  // hash + noise
  float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
  }
  float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
  }
  float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
      v += a * noise(p);
      p = p * 2.04 + vec2(1.7, 9.2);
      a *= 0.52;
    }
    return v;
  }

  // IQ palette
  vec3 palette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
    return a + b * cos(6.28318 * (c * t + d));
  }

  vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
  }

  void main() {
    vec2 uv = vUv;
    vec2 p  = (gl_FragCoord.xy * 2.0 - uResolution) / min(uResolution.x, uResolution.y);

    float t = uTime * 0.16;

    // domain warp — fluid feel
    vec2 q = vec2(
      fbm(p * 1.4 + vec2(0.0, t)),
      fbm(p * 1.4 + vec2(5.2, -t * 0.8))
    );

    vec2 r = vec2(
      fbm(p * 1.6 + 4.0 * q + vec2(1.7 + t * 1.5, 9.2)),
      fbm(p * 1.6 + 4.0 * q + vec2(8.3 - t * 1.2, 2.8))
    );

    float f = fbm(p * 1.8 + 4.0 * r + vec2(0.0, t * 2.0));

    // kaleidoscope symmetry — adjustable
    float kSegments = 6.0 + floor(uMid * 4.0);
    float ang = atan(p.y, p.x);
    float radius = length(p);
    float seg = 6.2831853 / kSegments;
    ang = mod(ang, seg);
    ang = abs(ang - seg / 2.0);
    vec2 kp = vec2(cos(ang), sin(ang)) * radius;

    float kField = fbm(kp * 2.2 + t * 0.6 + uBass * 1.3);

    // spectrum-driven intensity
    float distAmp = 0.4 + uBass * 0.9 + uTreble * 0.4 + uIdle * 0.25;
    float beatFlash = uBeatStrength * 0.8;

    // composite field
    float v = f * (1.0 - distAmp * 0.4) + kField * 0.55 * distAmp;
    v += beatFlash;

    // per-band drive: split screen into horizontal slices, each band modulates its slice
    float bandRow = floor(uv.y * 6.0) / 6.0;
    int bandI = int(mod(bandRow * 17.0, 95.0));
    float band = uBands[bandI];

    v += band * 0.55 * smoothstep(0.0, 1.0, sin(uv.y * 3.14159 + t * 4.0));

    // palette
    vec3 col = palette(
      v + t * 0.6,
      vec3(0.5, 0.45, 0.55),
      vec3(0.55, 0.5, 0.5),
      vec3(1.0, 1.0, 1.0),
      vec3(0.0, 0.33, 0.67)
    );

    // neon tinting
    vec3 neon = vec3(1.0, 0.17, 0.84); // magenta
    vec3 cyan = vec3(0.17, 0.95, 1.0);
    vec3 violet = vec3(0.54, 0.30, 1.0);

    vec3 tint = mix(neon, cyan, smoothstep(0.0, 1.0, v + 0.3));
    tint = mix(tint, violet, smoothstep(0.4, 1.0, v));
    col = mix(col, tint, 0.55);

    // beat: bright hot core
    col += neon * beatFlash * 0.6;

    // contrast / vignette
    float vig = smoothstep(1.4, 0.3, length(p));
    col *= 0.55 + vig * 0.7;

    // subtle film grain
    float grain = hash(gl_FragCoord.xy + uTime * 0.01) - 0.5;
    col += grain * 0.025;

    // bass floor — keep scene visible even when idle
    col += vec3(0.04, 0.02, 0.08) * uIdle;

    gl_FragColor = vec4(col, 1.0);
  }
`;

export class ShaderVisualizer {
  constructor(scene, camera) {
    this.scene = scene;
    this.camera = camera;
    // for fullscreen quad we don't need a perspective camera; use orthographic
    // we'll create a separate scene/camera pair to keep this contained.

    this.sceneFS = new THREE.Scene();
    this.cameraFS = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);

    const geom = new THREE.PlaneGeometry(2, 2);
    this.material = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      uniforms: {
        uTime: { value: 0 },
        uBass: { value: 0 },
        uMid: { value: 0 },
        uTreble: { value: 0 },
        uLevel: { value: 0 },
        uBeatStrength: { value: 0 },
        uBands: { value: new Float32Array(96) },
        uResolution: { value: new THREE.Vector2(1, 1) },
        uIdle: { value: 1 },
      },
      depthWrite: false,
    });
    this.quad = new THREE.Mesh(geom, this.material);
    this.sceneFS.add(this.quad);

    this._t = 0;
  }

  setSize(w, h) {
    this.material.uniforms.uResolution.value.set(w, h);
  }

  render(renderer) {
    renderer.setRenderTarget(null);
    renderer.render(this.sceneFS, this.cameraFS);
  }

  update(dt, audio) {
    this._t += dt;
    this.material.uniforms.uTime.value = this._t;
    this.material.uniforms.uBass.value = audio.bass;
    this.material.uniforms.uMid.value = audio.mid;
    this.material.uniforms.uTreble.value = audio.treble;
    this.material.uniforms.uLevel.value = audio.level;
    this.material.uniforms.uBeatStrength.value = audio.beatStrength;
    this.material.uniforms.uIdle.value = audio.sourceKind === 'idle' ? 1 : 0;

    const dest = this.material.uniforms.uBands.value;
    for (let i = 0; i < audio.bands.length && i < dest.length; i++) {
      dest[i] = audio.bands[i];
    }
  }

  setVisible(v) {
    this.sceneFS.visible = v;
  }

  dispose() {
    this.quad.geometry.dispose();
    this.material.dispose();
  }
}