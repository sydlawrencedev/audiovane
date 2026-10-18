// audio.js — Web Audio engine + FFT + beat detection
// Sources: system audio (display media), microphone, file, demo oscillator.
// Exposes live spectrum / band / RMS / beat / BPM for visualizers.

const FFT_SIZE = 2048;
const NUM_BANDS = 96; // post-log-binning spectrum length

export class AudioEngine extends EventTarget {
  constructor() {
    super();
    this.ctx = null;
    this.analyser = null;
    this.sourceNode = null;
    this.gainNode = null;

    this.fftBins = null; // Uint8Array(fft_size/2)
    this.timeBins = null; // Uint8Array(fft_size)
    this.bandBins = null; // Uint8Array(NUM_BANDS)

    this.sourceKind = 'idle'; // idle | system | mic | file | demo
    this.stream = null;
    this.fileElement = null;

    // smoothed state for visualizers
    this.state = {
      rms: 0,
      bass: 0,
      mid: 0,
      treble: 0,
      level: 0, // combined 0..1
      bands: null, // Float32Array(NUM_BANDS) 0..1
      peakBands: null, // Float32Array(NUM_BANDS) — instant FFT
      beat: false, // pulsed true for one frame on detected beat
      beatStrength: 0,
      bpm: 0,
    };

    // beat detection
    this._beatHistory = new Float32Array(43); // ~1s of frames @ ~60fps
    this._beatHistoryIdx = 0;
    this._beatCounter = 0; // frames since last beat
    this._bassEnergy = 0;
    this._lastBeatTime = 0;

    // onset detection for BPM
    this._onsetTimes = []; // seconds
    this._maxOnsets = 64;

    // log-banding edges (computed lazily once ctx exists)
    this._bandEdges = null;
  }

  _ensureCtx() {
    if (!this.ctx) {
      const Ctor = window.AudioContext || window.webkitAudioContext;
      this.ctx = new Ctor({ latencyHint: 'interactive' });
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = FFT_SIZE;
      this.analyser.smoothingTimeConstant = 0.78;
      this.analyser.minDecibels = -90;
      this.analyser.maxDecibels = -10;
      this.gainNode = this.ctx.createGain();
      this.gainNode.gain.value = 1.0;

      this.fftBins = new Uint8Array(this.analyser.frequencyBinCount);
      this.timeBins = new Uint8Array(this.analyser.fftSize);
      this.bandBins = new Uint8Array(NUM_BANDS);
      this.state.bands = new Float32Array(NUM_BANDS);
      this.state.peakBands = new Float32Array(NUM_BANDS);
      this._buildBandEdges();
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
  }

  // Logarithmic band edges, perceptually flat.
  _buildBandEdges() {
    const sampleRate = this.ctx.sampleRate;
    const nyquist = sampleRate / 2;
    const binCount = this.analyser.frequencyBinCount;
    const binHz = nyquist / binCount;
    const fMin = 40;
    const fMax = Math.min(16000, nyquist);
    const edges = new Float32Array(NUM_BANDS + 1);
    for (let i = 0; i <= NUM_BANDS; i++) {
      const t = i / NUM_BANDS;
      const f = fMin * Math.pow(fMax / fMin, t);
      edges[i] = Math.max(1, Math.min(binCount - 1, Math.round(f / binHz)));
    }
    this._bandEdges = edges;
  }

  async connectSystem() {
    this._ensureCtx();
    this._teardownSource();
    if (!navigator.mediaDevices.getDisplayMedia) {
      throw new Error('Screen capture not supported in this browser.');
    }
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: true,
      audio: true,
    });
    const audioTrack = stream.getAudioTracks()[0];
    if (!audioTrack) {
      stream.getTracks().forEach((t) => t.stop());
      throw new Error('No audio track in selection. Re-share and tick "Share tab audio".');
    }
    // drop video track — we don't need it, just the audio
    stream.getVideoTracks().forEach((t) => t.stop());
    this.stream = new MediaStream([audioTrack]);
    const node = this.ctx.createMediaStreamSource(this.stream);
    this._wire(node);
    this.sourceKind = 'system';
    audioTrack.addEventListener('ended', () => this._handleStreamEnded());
    this._emit('source', { kind: this.sourceKind });
    return this.sourceKind;
  }

  async connectMic() {
    this._ensureCtx();
    this._teardownSource();
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
      video: false,
    });
    this.stream = stream;
    const node = this.ctx.createMediaStreamSource(stream);
    this._wire(node);
    this.sourceKind = 'mic';
    this._emit('source', { kind: this.sourceKind });
    return this.sourceKind;
  }

  async connectFile(file) {
    this._ensureCtx();
    this._teardownSource();
    if (!this.fileElement) {
      this.fileElement = document.getElementById('file-audio');
    }
    const url = URL.createObjectURL(file);
    this.fileElement.src = url;
    await new Promise((res, rej) => {
      const ok = () => {
        this.fileElement.removeEventListener('error', err);
        res();
      };
      const err = () => {
        this.fileElement.removeEventListener('canplaythrough', ok);
        rej(new Error('Could not decode audio file.'));
      };
      this.fileElement.addEventListener('canplaythrough', ok, { once: true });
      this.fileElement.addEventListener('error', err, { once: true });
    });
    await this.fileElement.play();
    const node = this.ctx.createMediaElementSource(this.fileElement);
    this._wire(node);
    this.sourceKind = 'file';
    this._emit('source', { kind: this.sourceKind });
    return this.sourceKind;
  }

  connectDemo() {
    this._ensureCtx();
    this._teardownSource();
    // Build a multi-oscillator demo: bass kick + sweeping pad + occasional ping.
    const now = this.ctx.currentTime;
    const master = this.ctx.createGain();
    master.gain.value = 0.0;

    const pad = this.ctx.createOscillator();
    pad.type = 'sawtooth';
    pad.frequency.value = 110;
    const padGain = this.ctx.createGain();
    padGain.gain.value = 0.18;
    pad.connect(padGain).connect(master);

    const sub = this.ctx.createOscillator();
    sub.type = 'sine';
    sub.frequency.value = 55;
    const subGain = this.ctx.createGain();
    subGain.gain.value = 0.0;
    sub.connect(subGain).connect(master);

    // LFO for sweep
    const lfo = this.ctx.createOscillator();
    lfo.type = 'sine';
    lfo.frequency.value = 0.18;
    const lfoGain = this.ctx.createGain();
    lfoGain.gain.value = 220;
    lfo.connect(lfoGain).connect(pad.frequency);

    // kick scheduler
    const kickBPM = 124;
    const kickInterval = 60 / kickBPM;
    let nextKick = now + 0.1;
    const scheduleKick = () => {
      while (nextKick < this.ctx.currentTime + 0.5) {
        const t = nextKick;
        subGain.gain.setValueAtTime(0.0, t);
        subGain.gain.linearRampToValueAtTime(0.9, t + 0.005);
        subGain.gain.exponentialRampToValueAtTime(0.001, t + 0.32);
        sub.frequency.setValueAtTime(110, t);
        sub.frequency.exponentialRampToValueAtTime(40, t + 0.18);
        nextKick += kickInterval;
      }
    };
    const kickTimer = setInterval(scheduleKick, 200);
    scheduleKick();

    pad.start();
    sub.start();
    lfo.start();

    // ramp master in
    master.gain.setValueAtTime(0, now);
    master.gain.linearRampToValueAtTime(0.55, now + 0.3);

    this._demoHandles = { master, pad, sub, lfo, kickTimer };
    this._wire(master);
    this.sourceKind = 'demo';
    this._emit('source', { kind: this.sourceKind });
    return this.sourceKind;
  }

  disconnect() {
    this._teardownSource();
    this._emit('source', { kind: 'idle' });
  }

  _wire(node) {
    this.sourceNode = node;
    node.connect(this.analyser);
    this.analyser.connect(this.gainNode);
    this.gainNode.connect(this.ctx.destination);
  }

  _teardownSource() {
    if (this.sourceNode) {
      try {
        this.sourceNode.disconnect();
      } catch {}
      this.sourceNode = null;
    }
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop());
      this.stream = null;
    }
    if (this.fileElement) {
      this.fileElement.pause();
      this.fileElement.removeAttribute('src');
      try {
        URL.revokeObjectURL(this.fileElement.src);
      } catch {}
    }
    if (this._demoHandles) {
      const { master, pad, sub, lfo, kickTimer } = this._demoHandles;
      clearInterval(kickTimer);
      try {
        pad.stop();
        sub.stop();
        lfo.stop();
      } catch {}
      this._demoHandles = null;
    }
    // reset smoothed state
    this.state.rms = 0;
    this.state.bass = 0;
    this.state.mid = 0;
    this.state.treble = 0;
    this.state.level = 0;
    this.state.beatStrength = 0;
    if (this.state.bands) this.state.bands.fill(0);
    this._onsetTimes.length = 0;
    this.sourceKind = 'idle';
  }

  _handleStreamEnded() {
    if (this.sourceKind === 'system') {
      this._teardownSource();
      this._emit('source', { kind: 'idle', reason: 'stream-ended' });
    }
  }

  // Call once per animation frame.
  update() {
    if (!this.analyser) return;
    this.analyser.getByteFrequencyData(this.fftBins);
    this.analyser.getByteTimeDomainData(this.timeBins);

    // RMS from time domain
    let sumSq = 0;
    for (let i = 0; i < this.timeBins.length; i++) {
      const v = (this.timeBins[i] - 128) / 128;
      sumSq += v * v;
    }
    const rms = Math.sqrt(sumSq / this.timeBins.length);

    // bands (log-averaged)
    const edges = this._bandEdges;
    const bands = this.state.peakBands;
    for (let b = 0; b < NUM_BANDS; b++) {
      const lo = edges[b];
      const hi = edges[b + 1];
      let sum = 0;
      let n = 0;
      for (let i = lo; i <= hi; i++) {
        sum += this.fftBins[i];
        n++;
      }
      const v = n ? sum / n / 255 : 0;
      bands[b] = v;
    }

    // band averages (low / mid / high)
    const third = Math.floor(NUM_BANDS / 3);
    let bSum = 0,
      mSum = 0,
      tSum = 0;
    for (let i = 0; i < third; i++) bSum += bands[i];
    for (let i = third; i < third * 2; i++) mSum += bands[i];
    for (let i = third * 2; i < NUM_BANDS; i++) tSum += bands[i];
    const bassRaw = bSum / third;
    const midRaw = mSum / third;
    const trebRaw = tSum / (NUM_BANDS - third * 2);

    // smooth
    const a = 0.32; // smoothing for visualizers
    this.state.rms = this.state.rms + (rms - this.state.rms) * a;
    this.state.bass = this.state.bass + (bassRaw - this.state.bass) * a;
    this.state.mid = this.state.mid + (midRaw - this.state.mid) * a;
    this.state.treble = this.state.treble + (trebRaw - this.state.treble) * a;
    this.state.level = (this.state.bass + this.state.mid + this.state.treble) / 3;
    for (let i = 0; i < NUM_BANDS; i++) {
      this.state.bands[i] = this.state.bands[i] + (bands[i] - this.state.bands[i]) * a;
    }

    // beat detection on bass energy — simple adaptive threshold.
    const bassEnergy = bassRaw;
    const hist = this._beatHistory;
    let avg = 0;
    for (let i = 0; i < hist.length; i++) avg += hist[i];
    avg /= hist.length;
    const variance = 0;
    let varSum = 0;
    for (let i = 0; i < hist.length; i++) {
      const d = hist[i] - avg;
      varSum += d * d;
    }
    const std = Math.sqrt(varSum / hist.length);
    const dynamicThreshold = avg * 1.32 + std * 0.6 + 0.04;

    let beat = false;
    if (bassEnergy > dynamicThreshold && bassEnergy > 0.18) {
      if (this._beatCounter > 12) {
        // ~ minimum 200ms between beats at 60fps
        beat = true;
        this._beatCounter = 0;
        const t = this.ctx.currentTime;
        this._onsetTimes.push(t);
        if (this._onsetTimes.length > this._maxOnsets) this._onsetTimes.shift();
      }
    }
    hist[this._beatHistoryIdx] = bassEnergy;
    this._beatHistoryIdx = (this._beatHistoryIdx + 1) % hist.length;
    this._beatCounter++;
    this.state.beat = beat;
    this.state.beatStrength = beat ? Math.min(1, bassEnergy) : this.state.beatStrength * 0.86;

    // BPM: estimate from inter-onset intervals if we have enough onsets.
    if (this._onsetTimes.length >= 8) {
      const first = this._onsetTimes[0];
      const last = this._onsetTimes[this._onsetTimes.length - 1];
      const intervals = [];
      for (let i = 1; i < this._onsetTimes.length; i++) {
        const d = this._onsetTimes[i] - this._onsetTimes[i - 1];
        if (d > 0.25 && d < 1.2) intervals.push(d);
      }
      if (intervals.length >= 4) {
        intervals.sort((a, b) => a - b);
        // median interval
        const med = intervals[Math.floor(intervals.length / 2)];
        let bpm = 60 / med;
        // snap to plausible musical range
        while (bpm < 70) bpm *= 2;
        while (bpm > 180) bpm /= 2;
        // smooth toward target
        const target = Math.round(bpm);
        this.state.bpm =
          this.state.bpm === 0 ? target : this.state.bpm + (target - this.state.bpm) * 0.05;
        if (last - first > 8 && this._onsetTimes.length > 32) this._onsetTimes.shift();
      }
    }
  }

  _emit(name, detail) {
    this.dispatchEvent(new CustomEvent(name, { detail }));
  }
}