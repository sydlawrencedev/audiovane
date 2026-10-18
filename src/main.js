// main.js — renderer, post-processing, mode switching, UI wiring.
import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';

import { AudioEngine } from './audio.js';
import { TunnelVisualizer } from './visualizers/tunnel.js';
import { ParticleVisualizer } from './visualizers/particles.js';
import { ShaderVisualizer } from './visualizers/shader.js';

// ---------- DOM ----------
const $ = (sel) => document.querySelector(sel);
const canvas = $('#stage');
const meterCanvas = $('#meter-canvas');
const meterCtx = meterCanvas.getContext('2d');
const intro = $('#intro');
const sourcePill = $('#source-pill');
const sourceLabel = sourcePill.querySelector('.source-label');
const bpmEl = $('#bpm');
const bpmNum = bpmEl.querySelector('.bpm-num');
const modeButtons = [...document.querySelectorAll('.mode-btn')];
const footerCells = {
  mode: $('#f-mode'),
  rms: $('#f-rms'),
  bass: $('#f-bass'),
  mid: $('#f-mid'),
  treble: $('#f-treble'),
  beat: $('#f-beat'),
};

// ---------- Audio engine ----------
const audio = new AudioEngine();

// ---------- Three.js ----------
const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  powerPreference: 'high-performance',
  alpha: false,
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight, false);
renderer.setClearColor(0x05010a, 1);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;

const mainScene = new THREE.Scene();
const mainCamera = new THREE.PerspectiveCamera(
  65,
  window.innerWidth / window.innerHeight,
  0.1,
  100
);
mainCamera.position.set(0, 0, 8);

// bloom composer for 3D modes
const composer = new EffectComposer(renderer);
composer.setPixelRatio(renderer.getPixelRatio());
composer.setSize(window.innerWidth, window.innerHeight);
composer.addPass(new RenderPass(mainScene, mainCamera));
const bloomPass = new UnrealBloomPass(
  new THREE.Vector2(window.innerWidth, window.innerHeight),
  0.85, // strength
  0.55, // radius
  0.18 // threshold
);
composer.addPass(bloomPass);
composer.addPass(new OutputPass());

// ---------- Visualizers ----------
const visualizers = {
  tunnel: new TunnelVisualizer(mainScene, mainCamera),
  particles: new ParticleVisualizer(mainScene, mainCamera),
  shader: new ShaderVisualizer(),
};
let activeMode = 'tunnel';
visualizers.shader.setSize(window.innerWidth, window.innerHeight);
setActiveMode('tunnel', { skipIntro: true });

function setActiveMode(mode, opts = {}) {
  if (!visualizers[mode]) return;
  if (activeMode === mode && !opts.force) return;
  for (const k of Object.keys(visualizers)) {
    visualizers[k].setVisible(k === mode);
  }
  activeMode = mode;
  for (const btn of modeButtons) {
    btn.classList.toggle('active', btn.dataset.mode === mode);
  }
  footerCells.mode.textContent = mode.toUpperCase();
}

modeButtons.forEach((btn) => {
  btn.addEventListener('click', () => setActiveMode(btn.dataset.mode));
});

// ---------- UI bindings ----------
function setSourcePill(state, label) {
  sourcePill.dataset.state = state;
  sourceLabel.textContent = label;
}

async function startSystem() {
  try {
    setSourcePill('idle', 'requesting…');
    await audio.connectSystem();
    setSourcePill('live', 'system audio');
    intro.classList.add('hidden');
  } catch (err) {
    console.error(err);
    setSourcePill('idle', 'cancelled');
    alert(
      `Could not start system audio.\n\n${err.message}\n\nTip: pick "Share tab audio" / "Share tab" with sound in the picker.`
    );
  }
}

async function startMic() {
  try {
    setSourcePill('idle', 'requesting mic…');
    await audio.connectMic();
    setSourcePill('live', 'microphone');
    intro.classList.add('hidden');
  } catch (err) {
    console.error(err);
    setSourcePill('idle', 'mic denied');
    alert(`Could not access microphone.\n\n${err.message}`);
  }
}

async function startFile(file) {
  try {
    setSourcePill('idle', `loading ${file.name}`);
    await audio.connectFile(file);
    setSourcePill('live', file.name);
    intro.classList.add('hidden');
  } catch (err) {
    console.error(err);
    setSourcePill('idle', 'load failed');
    alert(`Could not load that file.\n\n${err.message}`);
  }
}

function startDemo() {
  audio.connectDemo();
  setSourcePill('demo', 'demo tone');
  intro.classList.add('hidden');
}

$('#btn-system').addEventListener('click', startSystem);
$('#btn-mic').addEventListener('click', startMic);
$('#btn-demo').addEventListener('click', startDemo);

const fileInput = $('#file-input');
fileInput.addEventListener('change', (e) => {
  const f = e.target.files?.[0];
  if (f) startFile(f);
});

// keyboard shortcuts
window.addEventListener('keydown', (e) => {
  if (e.key === '1') setActiveMode('tunnel');
  else if (e.key === '2') setActiveMode('particles');
  else if (e.key === '3') setActiveMode('shader');
  else if (e.key === ' ' || e.key === 'Escape') {
    intro.classList.toggle('hidden');
  }
});

// ---------- Resize ----------
function onResize() {
  const w = window.innerWidth;
  const h = window.innerHeight;
  renderer.setSize(w, h, false);
  composer.setSize(w, h);
  mainCamera.aspect = w / h;
  mainCamera.updateProjectionMatrix();
  visualizers.shader.setSize(w, h);
}
window.addEventListener('resize', onResize);

// ---------- Meter drawing ----------
const METER_BANDS = 64;
function drawMeter(state) {
  const w = meterCanvas.width;
  const h = meterCanvas.height;
  meterCtx.clearRect(0, 0, w, h);

  // bg subtle grid
  meterCtx.fillStyle = 'rgba(255,255,255,0.02)';
  meterCtx.fillRect(0, 0, w, h);

  const bands = state.bands;
  if (!bands) return;
  const binStep = Math.floor(bands.length / METER_BANDS);
  const barW = w / METER_BANDS;

  for (let i = 0; i < METER_BANDS; i++) {
    const v = bands[i * binStep] || 0;
    const v2 = bands[Math.floor(((i + 0.5) / METER_BANDS) * bands.length)] || 0;
    const peak = Math.max(v, v2);
    const bh = Math.min(h, peak * h * 1.1);
    const x = i * barW;

    const grad = meterCtx.createLinearGradient(0, h - bh, 0, h);
    if (i < METER_BANDS / 3) {
      grad.addColorStop(0, '#ff2bd6');
      grad.addColorStop(1, 'rgba(255, 43, 214, 0.2)');
    } else if (i < (METER_BANDS * 2) / 3) {
      grad.addColorStop(0, '#8a4dff');
      grad.addColorStop(1, 'rgba(138, 77, 255, 0.2)');
    } else {
      grad.addColorStop(0, '#2bf2ff');
      grad.addColorStop(1, 'rgba(43, 242, 255, 0.2)');
    }
    meterCtx.fillStyle = grad;
    meterCtx.fillRect(x + 1, h - bh, barW - 2, bh);
  }
}

// ---------- Loop ----------
let lastT = performance.now();
let beatFlashEl = null;
function ensureBeatFlash() {
  if (beatFlashEl) return;
  beatFlashEl = document.createElement('div');
  beatFlashEl.style.cssText = `
    position: absolute;
    inset: 0;
    pointer-events: none;
    z-index: 6;
    background: radial-gradient(ellipse at center, rgba(255,43,214,0.18) 0%, transparent 60%);
    opacity: 0;
    transition: opacity 180ms ease-out;
  `;
  document.getElementById('app').appendChild(beatFlashEl);
}

function fmt(n, d = 2) {
  return n.toFixed(d);
}

function tick() {
  const now = performance.now();
  const dt = Math.min(0.05, (now - lastT) / 1000);
  lastT = now;

  audio.update();

  // update active visualizer
  visualizers[activeMode].update(dt, audio.state);

  // render — shader mode is direct; 3D modes via bloom composer
  if (activeMode === 'shader') {
    visualizers.shader.render(renderer);
  } else {
    composer.render();
  }

  // HUD updates
  const s = audio.state;
  drawMeter(s);
  footerCells.rms.textContent = fmt(s.rms);
  footerCells.bass.textContent = fmt(s.bass);
  footerCells.mid.textContent = fmt(s.mid);
  footerCells.treble.textContent = fmt(s.treble);

  if (s.beat) {
    footerCells.beat.textContent = 'HIT';
    footerCells.beat.classList.add('beat');
    ensureBeatFlash();
    beatFlashEl.style.opacity = String(Math.min(1, s.beatStrength * 1.4));
  } else {
    footerCells.beat.classList.remove('beat');
    if (beatFlashEl) {
      beatFlashEl.style.opacity = '0';
    }
    if (s.beatStrength < 0.01) footerCells.beat.textContent = '—';
    else footerCells.beat.textContent = fmt(s.beatStrength, 2);
  }

  if (s.bpm > 30) {
    bpmEl.hidden = false;
    bpmNum.textContent = String(Math.round(s.bpm));
  } else {
    bpmEl.hidden = true;
  }

  requestAnimationFrame(tick);
}

requestAnimationFrame(tick);

// expose for debugging
window.__viz = { audio, visualizers, setActiveMode };