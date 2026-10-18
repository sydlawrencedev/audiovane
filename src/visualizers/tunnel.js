// tunnel.js — flying through concentric rings of spectrum-reactive bars
import * as THREE from 'three';

const NUM_RINGS = 64;
const BARS_PER_RING = 96;
const RING_SPACING = 0.95;
const TUNNEL_LENGTH = NUM_RINGS * RING_SPACING;

export class TunnelVisualizer {
  constructor(scene, camera) {
    this.scene = scene;
    this.camera = camera;

    this.group = new THREE.Group();
    this.group.position.z = -TUNNEL_LENGTH / 2;
    scene.add(this.group);

    this._buildRings();
    this._buildStarfield();

    this._t = 0;
    this._colorHot = new THREE.Color('#ff2bd6');
    this._colorMid = new THREE.Color('#8a4dff');
    this._colorCold = new THREE.Color('#2bf2ff');

    // fog blends rings far away into the void
    scene.fog = new THREE.FogExp2(0x05010a, 0.045);
  }

  _buildRings() {
    const ringGeom = new THREE.BufferGeometry();
    const positions = new Float32Array(NUM_RINGS * BARS_PER_RING * 2 * 3);
    const colors = new Float32Array(NUM_RINGS * BARS_PER_RING * 2 * 3);
    const indices = new Uint32Array(NUM_RINGS * BARS_PER_RING * 6);

    let pIdx = 0,
      cIdx = 0,
      iIdx = 0;

    for (let r = 0; r < NUM_RINGS; r++) {
      const z = r * RING_SPACING;
      for (let b = 0; b < BARS_PER_RING; b++) {
        const angle = (b / BARS_PER_RING) * Math.PI * 2;
        const cosA = Math.cos(angle);
        const sinA = Math.sin(angle);
        const inner = 2.2;
        const outer = 2.4;

        const i0 = pIdx / 3;
        positions[pIdx++] = cosA * inner;
        positions[pIdx++] = sinA * inner;
        positions[pIdx++] = z;
        positions[pIdx++] = cosA * outer;
        positions[pIdx++] = sinA * outer;
        positions[pIdx++] = z;

        // initial color (will be updated in update())
        colors[cIdx++] = 1;
        colors[cIdx++] = 0.4;
        colors[cIdx++] = 0.8;
        colors[cIdx++] = 1;
        colors[cIdx++] = 0.4;
        colors[cIdx++] = 0.8;

        // quad indices
        const next = (b + 1) % BARS_PER_RING;
        const i1 = r * BARS_PER_RING * 2 + next * 2;
        const i2 = i0 + 1;
        const i3 = i1 + 1;

        indices[iIdx++] = i0;
        indices[iIdx++] = i2;
        indices[iIdx++] = i1;
        indices[iIdx++] = i2;
        indices[iIdx++] = i3;
        indices[iIdx++] = i1;
      }
    }

    ringGeom.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    ringGeom.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    ringGeom.setIndex(new THREE.BufferAttribute(indices, 1));

    this.ringGeometry = ringGeom;
    this.ringPositions = positions;
    this.ringColors = colors;

    const mat = new THREE.MeshBasicMaterial({
      vertexColors: true,
      side: THREE.DoubleSide,
      transparent: true,
      opacity: 0.92,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    this.ringMaterial = mat;
    this.rings = new THREE.Mesh(ringGeom, mat);
    this.group.add(this.rings);
  }

  _buildStarfield() {
    const count = 1500;
    const positions = new Float32Array(count * 3);
    const colors = new Float32Array(count * 3);
    const sizes = new Float32Array(count);

    for (let i = 0; i < count; i++) {
      // points along the tunnel length, randomly in radial slice
      const z = (i / count) * TUNNEL_LENGTH - TUNNEL_LENGTH / 2;
      const angle = Math.random() * Math.PI * 2;
      const radius = Math.random() * 1.8 + 0.4;
      positions[i * 3] = Math.cos(angle) * radius;
      positions[i * 3 + 1] = Math.sin(angle) * radius;
      positions[i * 3 + 2] = z;

      const t = Math.random();
      colors[i * 3] = 0.6 + t * 0.4;
      colors[i * 3 + 1] = 0.2 + (1 - t) * 0.4;
      colors[i * 3 + 2] = 0.8 + t * 0.2;
      sizes[i] = Math.random() * 1.6 + 0.4;
    }

    const geom = new THREE.BufferGeometry();
    geom.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geom.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geom.setAttribute('size', new THREE.BufferAttribute(sizes, 1));

    const mat = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 } },
      vertexColors: true,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      vertexShader: `
        attribute float size;
        varying vec3 vColor;
        uniform float uTime;
        void main() {
          vColor = color;
          vec3 p = position;
          // gentle drift
          p.x += sin(uTime * 0.7 + position.z * 0.05) * 0.04;
          p.y += cos(uTime * 0.5 + position.z * 0.04) * 0.04;
          vec4 mv = modelViewMatrix * vec4(p, 1.0);
          gl_PointSize = size * (180.0 / -mv.z);
          gl_Position = projectionMatrix * mv;
        }
      `,
      fragmentShader: `
        varying vec3 vColor;
        void main() {
          vec2 c = gl_PointCoord - 0.5;
          float d = length(c);
          if (d > 0.5) discard;
          float a = smoothstep(0.5, 0.0, d);
          gl_FragColor = vec4(vColor, a * 0.6);
        }
      `,
    });

    this.starfield = new THREE.Points(geom, mat);
    this.group.add(this.starfield);
  }

  update(dt, audio) {
    this._t += dt;
    this.ringMaterial.uniforms?.uTime; // noop guard
    if (this.starfield.material.uniforms) {
      this.starfield.material.uniforms.uTime.value = this._t;
    }

    // scroll tunnel toward camera
    const scrollSpeed = 5.5 + audio.level * 22 + (audio.beat ? 18 : 0);
    this.group.position.z += scrollSpeed * dt;
    if (this.group.position.z > TUNNEL_LENGTH / 2) {
      this.group.position.z -= TUNNEL_LENGTH;
    }

    // bass-driven camera shake (very subtle)
    const shake = audio.beat ? 0.06 * audio.beatStrength : 0;
    this.camera.position.x = Math.sin(this._t * 7.3) * shake;
    this.camera.position.y = Math.cos(this._t * 6.1) * shake;
    this.camera.lookAt(0, 0, this.group.position.z);

    // ring colors & extrusions
    const colors = this.ringColors;
    const positions = this.ringPositions;
    const bands = audio.bands;
    const bass = audio.bass;
    const mid = audio.mid;
    const treb = audio.treble;

    for (let r = 0; r < NUM_RINGS; r++) {
      // bins per ring
      const bin = Math.floor((r / NUM_RINGS) * bands.length * 0.85);
      const intensity = bands[bin] || 0;
      const ringPulse = intensity * (1.4 + bass * 2.5) + bass * 0.4;

      // color: hot low -> cold high
      const colorMix = r / NUM_RINGS;
      let cr, cg, cb;
      if (colorMix < 0.5) {
        const t = colorMix * 2;
        cr = this._colorHot.r + (this._colorMid.r - this._colorHot.r) * t;
        cg = this._colorHot.g + (this._colorMid.g - this._colorHot.g) * t;
        cb = this._colorHot.b + (this._colorMid.b - this._colorHot.b) * t;
      } else {
        const t = (colorMix - 0.5) * 2;
        cr = this._colorMid.r + (this._colorCold.r - this._colorMid.r) * t;
        cg = this._colorMid.g + (this._colorCold.g - this._colorMid.g) * t;
        cb = this._colorMid.b + (this._colorCold.b - this._colorMid.b) * t;
      }

      // hue shift on beat
      if (audio.beat) {
        cr = Math.min(1, cr + audio.beatStrength * 0.35);
        cg = Math.min(1, cg + audio.beatStrength * 0.15);
      }

      // ring radius offset (per-bar extrusion)
      for (let b = 0; b < BARS_PER_RING; b++) {
        const angle = (b / BARS_PER_RING) * Math.PI * 2;
        const cosA = Math.cos(angle);
        const sinA = Math.sin(angle);

        // per-bar spectrum variation
        const barBin = Math.floor((b / BARS_PER_RING) * bands.length);
        const barIntensity = bands[barBin] || 0;
        const barLen = barIntensity * 3.2 + bass * 0.6 + ringPulse * 0.18;

        const inner = 2.2 + barLen;
        const outer = inner + 0.18 + ringPulse * 0.04;

        const baseIdx = (r * BARS_PER_RING + b) * 2 * 3;
        positions[baseIdx] = cosA * inner;
        positions[baseIdx + 1] = sinA * inner;
        positions[baseIdx + 2] = r * RING_SPACING;
        positions[baseIdx + 3] = cosA * outer;
        positions[baseIdx + 4] = sinA * outer;
        positions[baseIdx + 5] = r * RING_SPACING;

        // brightness scales with barLen + ringPulse
        const brightness = Math.min(1, 0.45 + barLen * 0.55 + ringPulse * 0.4 + audio.beatStrength * 0.4);
        colors[baseIdx] = cr * brightness;
        colors[baseIdx + 1] = cg * brightness;
        colors[baseIdx + 2] = cb * brightness;
        colors[baseIdx + 3] = cr * brightness * 1.2;
        colors[baseIdx + 4] = cg * brightness * 1.2;
        colors[baseIdx + 5] = cb * brightness * 1.2;
      }
    }

    this.ringGeometry.attributes.position.needsUpdate = true;
    this.ringGeometry.attributes.color.needsUpdate = true;
  }

  setVisible(v) {
    this.group.visible = v;
  }

  dispose() {
    this.scene.remove(this.group);
    this.scene.fog = null;
    this.ringGeometry.dispose();
    this.ringMaterial.dispose();
    this.starfield.geometry.dispose();
    this.starfield.material.dispose();
  }
}