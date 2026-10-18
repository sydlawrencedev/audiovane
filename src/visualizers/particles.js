// particles.js — bass-reactive particle galaxy
import * as THREE from 'three';

const COUNT = 50000;

export class ParticleVisualizer {
  constructor(scene, camera) {
    this.scene = scene;
    this.camera = camera;

    this.group = new THREE.Group();
    scene.add(this.group);

    this._buildParticles();
    this._buildBackdrop();

    this._t = 0;

    scene.fog = new THREE.FogExp2(0x05010a, 0.04);
  }

  _buildParticles() {
    const positions = new Float32Array(COUNT * 3);
    const colors = new Float32Array(COUNT * 3);
    const sizes = new Float32Array(COUNT);
    const seeds = new Float32Array(COUNT); // per-particle random offset
    const radii = new Float32Array(COUNT); // base radius from center
    const bandIdx = new Float32Array(COUNT); // which frequency band drives this particle

    const colorHot = new THREE.Color('#ff2bd6');
    const colorMid = new THREE.Color('#8a4dff');
    const colorCold = new THREE.Color('#2bf2ff');

    for (let i = 0; i < COUNT; i++) {
      // Spherical distribution — prefer a thick shell (galactic disk shape)
      const u = Math.random();
      const v = Math.random();
      const theta = 2 * Math.PI * u;
      const phi = Math.acos(2 * v - 1);
      const baseR = 1.4 + Math.pow(Math.random(), 1.4) * 4.6;
      const sx = Math.sin(phi) * Math.cos(theta);
      const sy = Math.cos(phi);
      const sz = Math.sin(phi) * Math.sin(theta);
      positions[i * 3] = sx * baseR;
      positions[i * 3 + 1] = sy * baseR * 0.55; // squashed disk
      positions[i * 3 + 2] = sz * baseR;
      radii[i] = baseR;
      seeds[i] = Math.random();
      bandIdx[i] = Math.random();

      // color mix: hot near core, cold at edges
      const t = Math.min(1, baseR / 6);
      const tmp = new THREE.Color();
      if (t < 0.5) {
        tmp.copy(colorHot).lerp(colorMid, t * 2);
      } else {
        tmp.copy(colorMid).lerp(colorCold, (t - 0.5) * 2);
      }
      colors[i * 3] = tmp.r;
      colors[i * 3 + 1] = tmp.g;
      colors[i * 3 + 2] = tmp.b;

      sizes[i] = (0.6 + Math.random() * 1.8) * (1.2 - t * 0.6);
    }

    const geom = new THREE.BufferGeometry();
    geom.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geom.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geom.setAttribute('size', new THREE.BufferAttribute(sizes, 1));
    geom.setAttribute('seed', new THREE.BufferAttribute(seeds, 1));
    geom.setAttribute('radius', new THREE.BufferAttribute(radii, 1));
    geom.setAttribute('bandIdx', new THREE.BufferAttribute(bandIdx, 1));

    const mat = new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 },
        uBass: { value: 0 },
        uMid: { value: 0 },
        uTreble: { value: 0 },
        uBeat: { value: 0 },
        uBeatStrength: { value: 0 },
        uBands: { value: new Float32Array(96) },
      },
      vertexColors: true,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      vertexShader: `
        attribute float size;
        attribute float seed;
        attribute float radius;
        attribute float bandIdx;

        uniform float uTime;
        uniform float uBass;
        uniform float uMid;
        uniform float uTreble;
        uniform float uBeat;
        uniform float uBeatStrength;
        uniform float uBands[96];

        varying vec3 vColor;
        varying float vBeat;

        // cheap 3D hash-based noise
        float hash11(float n) { return fract(sin(n) * 43758.5453123); }

        void main() {
          vColor = color;

          // band-driven push
          int bandI = int(bandIdx * 95.0);
          float band = uBands[bandI];

          // base orbital motion
          float speed = 0.18 + seed * 0.42;
          float angle = uTime * speed + seed * 6.2831;

          // direction = normalize(position.xz at base)
          float r = length(position.xz);
          vec2 dir;
          if (r > 0.0001) dir = position.xz / r; else dir = vec2(1.0, 0.0);
          // rotate
          float ca = cos(angle);
          float sa = sin(angle);
          vec2 rotated = vec2(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);

          // radius scales with bass + band intensity + beat blast
          float bassExpand = 1.0 + uBass * 0.85;
          float beatBlast = 1.0 + uBeatStrength * 1.4;
          float bandPush = 1.0 + band * 1.3;
          float newRadius = radius * bassExpand * bandPush * beatBlast;

          // turbulence from treble
          float turb = uTreble * 0.7;
          vec3 jitter = vec3(
            sin(uTime * 2.3 + seed * 9.7),
            cos(uTime * 1.8 + seed * 7.3),
            sin(uTime * 2.1 + seed * 11.1)
          ) * turb;

          // axial disk y position squashed by bass
          float axialSquash = mix(1.0, 0.4, uBass);

          vec3 p = vec3(
            rotated.x * newRadius + jitter.x,
            position.y * axialSquash + jitter.y,
            rotated.y * newRadius + jitter.z
          );

          // mid-frequency lifts the whole galaxy up
          p.y += uMid * 0.8 * sin(seed * 6.28);

          // beat flash: brightness pulse
          vBeat = uBeatStrength * (0.5 + band * 0.5);

          vec4 mv = modelViewMatrix * vec4(p, 1.0);
          gl_PointSize = size * (260.0 / -mv.z) * (1.0 + uBeatStrength * 1.2 + band * 0.4);
          gl_Position = projectionMatrix * mv;
        }
      `,
      fragmentShader: `
        varying vec3 vColor;
        varying float vBeat;
        void main() {
          vec2 c = gl_PointCoord - 0.5;
          float d = length(c);
          if (d > 0.5) discard;
          float core = smoothstep(0.5, 0.0, d);
          float glow = pow(core, 1.5);
          vec3 col = vColor + vec3(0.4, 0.2, 0.5) * vBeat;
          gl_FragColor = vec4(col, glow * (0.55 + vBeat * 0.5));
        }
      `,
    });

    this.material = mat;
    this.points = new THREE.Points(geom, mat);
    this.group.add(this.points);
  }

  _buildBackdrop() {
    // subtle radial gradient sphere for ambient depth
    const geom = new THREE.SphereGeometry(28, 32, 32);
    const mat = new THREE.ShaderMaterial({
      side: THREE.BackSide,
      depthWrite: false,
      uniforms: {
        uTime: { value: 0 },
        uBass: { value: 0 },
      },
      vertexShader: `
        varying vec3 vN;
        void main() {
          vN = normalize(position);
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: `
        varying vec3 vN;
        uniform float uTime;
        uniform float uBass;
        void main() {
          float f = vN.y * 0.5 + 0.5;
          vec3 top = vec3(0.04, 0.02, 0.10);
          vec3 mid = vec3(0.18, 0.04, 0.32);
          vec3 bot = vec3(0.02, 0.04, 0.12);
          vec3 col = mix(bot, mid, smoothstep(0.0, 0.5, f));
          col = mix(col, top, smoothstep(0.5, 1.0, f));
          // bass glow ring
          float ring = smoothstep(0.7, 0.95, abs(vN.y));
          col += vec3(0.6, 0.1, 0.7) * ring * uBass * 0.3;
          gl_FragColor = vec4(col, 1.0);
        }
      `,
    });
    this.backdrop = new THREE.Mesh(geom, mat);
    this.backdrop.frustumCulled = false;
    scene.add(this.backdrop); // outside group so we don't double-transform
  }

  update(dt, audio) {
    this._t += dt;
    this.material.uniforms.uTime.value = this._t;
    this.material.uniforms.uBass.value = audio.bass;
    this.material.uniforms.uMid.value = audio.mid;
    this.material.uniforms.uTreble.value = audio.treble;
    this.material.uniforms.uBeat.value = audio.beat ? 1 : 0;
    this.material.uniforms.uBeatStrength.value = audio.beatStrength;
    // upload latest bands snapshot
    const dest = this.material.uniforms.uBands.value;
    for (let i = 0; i < audio.bands.length && i < dest.length; i++) {
      dest[i] = audio.bands[i];
    }

    this.backdrop.material.uniforms.uTime.value = this._t;
    this.backdrop.material.uniforms.uBass.value = audio.bass;

    // gentle auto-rotation
    this.group.rotation.y += dt * 0.05;
    this.group.rotation.x = Math.sin(this._t * 0.13) * 0.18;

    // camera dolly tied to beat
    const dolly = 8 + audio.level * 1.5;
    this.camera.position.z += (dolly - this.camera.position.z) * 0.05;
    this.camera.position.x = Math.sin(this._t * 0.2) * 0.4;
    this.camera.position.y = Math.cos(this._t * 0.15) * 0.3;
    this.camera.lookAt(0, 0, 0);
  }

  setVisible(v) {
    this.group.visible = v;
    this.backdrop.visible = v;
  }

  dispose() {
    this.scene.remove(this.group);
    if (this.backdrop.parent) this.scene.remove(this.backdrop);
    this.scene.fog = null;
    this.points.geometry.dispose();
    this.material.dispose();
    this.backdrop.geometry.dispose();
    this.backdrop.material.dispose();
  }
}