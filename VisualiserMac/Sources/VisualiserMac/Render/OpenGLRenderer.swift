import Foundation
import AppKit
import OpenGL.GL3
import simd

/// OpenGL 3.3 Core renderer. Drives NSOpenGLView's draw loop.
/// Uses CVDisplayLink for vsync-paced redraws.
final class OpenGLRenderer: NSObject {
    let audio: AudioEngine
    private(set) var glContext: NSOpenGLContext?
    private(set) var pixelFormat: NSOpenGLPixelFormat?
    private(set) var isReady: Bool = false
    private var offscreenContext: NSOpenGLContext?
    private var offscreenPixelFormat: NSOpenGLPixelFormat?

    // Programs
    private var tunnelProgram: GLuint = 0
    private var particleProgram: GLuint = 0
    private var liquidProgram: GLuint = 0
    /// MACHINE mode: instanced drums / pads / bouncing balls.
    private let machine = MachineRenderer()
    /// Where the machine camera is in its 48-second loop.
    private var machineCameraPhase: Float = 0

    // --- Palette post-process -------------------------------------------
    // The scene is rendered into an offscreen texture, then a full-screen
    // grade pass maps it through the active palette and writes to the
    // drawable. One shader themes every mode at once.
    private var gradeProgram: GLuint = 0
    private var gradeVAO: GLuint = 0
    private var gradeVBO: GLuint = 0
    private var sceneFBO: GLuint = 0
    private var sceneTex: GLuint = 0
    private var fboWidth = 0
    private var fboHeight = 0
    private var uGradeTex: GLint = -1
    private var uGradeShadow: GLint = -1
    private var uGradeHighlight: GLint = -1
    private var uGradeSaturation: GLint = -1
    private var uGradeDuotone: GLint = -1
    private var uGradeLift: GLint = -1

    /// Index into `Palette.all`. Set by AppState.
    var paletteIndex: Int = 0

    // VAOs / VBOs
    private var tunnelVAO: GLuint = 0
    private var tunnelVBO: GLuint = 0
    private var tunnelIBO: GLuint = 0

    private var particleVAO: GLuint = 0
    private var particleVBO: GLuint = 0

    private var liquidVAO: GLuint = 0
    private var liquidVBO: GLuint = 0

    // Uniform locations
    private var uTunnelMVP: GLint = -1
    private var uTunnelTime: GLint = -1
    private var uTunnelBass: GLint = -1
    private var uTunnelBeat: GLint = -1
    private var uTunnelBeatStrength: GLint = -1

    private var uParticleMVP: GLint = -1
    private var uParticleTime: GLint = -1
    private var uParticleBass: GLint = -1
    private var uParticleMid: GLint = -1
    private var uParticleTreble: GLint = -1
    private var uParticleBeat: GLint = -1
    private var uParticleBeatStrength: GLint = -1
    private var uParticleLevel: GLint = -1
    private var uParticleResolution: GLint = -1
    private var uParticleActive: GLint = -1
    private var uParticleBands: GLint = -1
    private var uLiquidActive: GLint = -1

    private var uLiquidTime: GLint = -1
    private var uLiquidBass: GLint = -1
    private var uLiquidMid: GLint = -1
    private var uLiquidTreble: GLint = -1
    private var uLiquidBeat: GLint = -1
    private var uLiquidBeatStrength: GLint = -1
    private var uLiquidLevel: GLint = -1
    private var uLiquidResolution: GLint = -1
    private var uLiquidIdle: GLint = -1
    private var uLiquidBands: GLint = -1

    /// Full-screen fragment-shader modes (see FunShaders) share one uniform layout.
    private struct ShaderMode {
        let program: GLuint
        let time, bass, mid, treble, beat, beatStrength, level, resolution, idle, bands: GLint
        let eventKind, eventAge: GLint
        let active, beats, peaks, scroll, clock: GLint
    }
    private var shaderModes: [VisualizerMode: ShaderMode] = [:]

    /// Badger mode overlays: a big beat (well above the recent beat average)
    /// pops up the mushroom; every third one brings the snake instead.
    private var bigBeatAverage: Float = 0.3
    private var overlayKind: Float = 0          // 0 none, 1 mushroom, 2 snake
    private var overlayStart: CFTimeInterval = 0
    private var overlayCount = 0
    private let overlayDuration: CFTimeInterval = 1.6

    /// Hamster Dance sprites from the user's folder, as a GL texture array.
    private var spriteTexture: GLuint = 0
    private var sprites: [SpriteAtlas.Sprite] = []
    private var spriteStamp: String?
    private var lastSpriteCheck: CFTimeInterval = 0
    private var spriteCellSize = SIMD2<Float>(1, 1)
    /// GIF playback clock in "native seconds": runs at the GIF's own speed when
    /// the music is at `spriteNativeBPM`, faster or slower to follow the detected
    /// tempo. 137 is roughly the original Hamster Dance song, so the GIF looks
    /// as designed at that tempo.
    private var spriteClock: Double = 0
    private var spriteClockLast: CFTimeInterval = CACurrentMediaTime()
    private let spriteNativeBPM = 137.0
    private var uSpriteClock: GLint = -1
    private var uSprites: GLint = -1, uSpriteKinds: GLint = -1, uSpriteCell: GLint = -1
    private var uSpriteFirst: GLint = -1, uSpriteFrames: GLint = -1, uSpriteDelay: GLint = -1

    /// Re-reads the sprite folder when its contents change (checked every 2s).
    /// Must run with the GL context current.
    private func refreshSpritesIfNeeded() {
        let now = CACurrentMediaTime()
        guard now - lastSpriteCheck > 2 else { return }
        lastSpriteCheck = now
        let stamp = SpriteAtlas.folderStamp()
        guard stamp != spriteStamp else { return }
        spriteStamp = stamp

        let atlas = SpriteAtlas.load()
        sprites = atlas.sprites
        guard atlas.layerCount > 0 else { return }
        spriteCellSize = SIMD2(Float(atlas.cellWidth), Float(atlas.cellHeight))
        if spriteTexture == 0 { glGenTextures(1, &spriteTexture) }
        glBindTexture(GLenum(GL_TEXTURE_2D_ARRAY), spriteTexture)
        atlas.pixels.withUnsafeBytes { buf in
            glTexImage3D(GLenum(GL_TEXTURE_2D_ARRAY), 0, GL_RGBA8,
                         GLsizei(atlas.cellWidth), GLsizei(atlas.cellHeight), GLsizei(atlas.layerCount),
                         0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), buf.baseAddress)
        }
        glTexParameteri(GLenum(GL_TEXTURE_2D_ARRAY), GLenum(GL_TEXTURE_MIN_FILTER), GL_NEAREST)
        glTexParameteri(GLenum(GL_TEXTURE_2D_ARRAY), GLenum(GL_TEXTURE_MAG_FILTER), GL_NEAREST)
        glTexParameteri(GLenum(GL_TEXTURE_2D_ARRAY), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D_ARRAY), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    }

    private func bindSprites(_ snap: AudioSnapshot) {
        refreshSpritesIfNeeded()
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - spriteClockLast)
        spriteClockLast = now
        if snap.sourceIsIdle < 0.5 {
            let rate = snap.bpm > 0 ? min(1.5, max(0.5, snap.bpm / spriteNativeBPM)) : 1
            spriteClock += dt * rate * danceActivity
        }
        glUniform1f(uSpriteClock, Float(spriteClock.truncatingRemainder(dividingBy: 3600)))
        var first = [Float](repeating: 0, count: SpriteAtlas.maxSprites)
        var frames = [Float](repeating: 1, count: SpriteAtlas.maxSprites)
        var delay = [Float](repeating: 0.1, count: SpriteAtlas.maxSprites)
        for (i, s) in sprites.enumerated() {
            first[i] = Float(s.firstLayer); frames[i] = Float(s.frameCount); delay[i] = Float(s.frameDelay)
        }
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D_ARRAY), spriteTexture)
        glUniform1i(uSprites, 0)
        glUniform2f(uSpriteCell, spriteCellSize.x, spriteCellSize.y)
        glUniform1i(uSpriteKinds, GLint(spriteTexture == 0 ? 0 : sprites.count))
        glUniform1fv(uSpriteFirst, GLsizei(SpriteAtlas.maxSprites), first)
        glUniform1fv(uSpriteFrames, GLsizei(SpriteAtlas.maxSprites), frames)
        glUniform1fv(uSpriteDelay, GLsizei(SpriteAtlas.maxSprites), delay)
    }

    // MARK: Band mode cues

    /// Who is playing comes from the sound classifier (slow, ~0.75s updates);
    /// the playing motion itself is driven by the beat clock in the shader.
    /// Spectrum onsets only add accents. Everything here is smoothed so
    /// nothing snaps: parts fade in/out, accents have a soft attack.
    private var bandPrev = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
    private var bandFluxAvg = [Float](repeating: 0.01, count: 4)   // snare, hat, strum, pluck
    private var bandPulse = [Float](repeating: 0, count: 5)        // raw accent triggers
    private var bandEnv = [Float](repeating: 0, count: 5)          // kick, snare, hat, strum, pluck (smoothed)
    private var bandParts = [Float](repeating: 0, count: 5)        // drums, bass, guitar, keys, vocals
    private var bandKeys = [Float](repeating: 0, count: 9)
    private var bandVocal: Float = 0
    private var bandLowAverage: Float = 0
    private var bandForceAll = false                               // snapshots: everyone plays
    /// Once a part is heard, keep it playing at least this long after it was
    /// last heard, to bridge gaps between strums, phrases and fills.
    private static let bandHoldSeconds: CFTimeInterval = 1.5
    private var bandHeldLevel = [Float](repeating: 0, count: 5)
    private var bandLastHeard = [CFTimeInterval](repeating: 0, count: 5)
    private var uBandParts: GLint = -1, uBandHits: GLint = -1, uBandPluck: GLint = -1
    private var uBandVocal: GLint = -1, uBandKeys: GLint = -1
    private var uBandX: GLint = -1, uBandWalk: GLint = -1, uBandFace: GLint = -1, uBandPlay: GLint = -1
    private var uBandHome: GLint = -1
    private var uBandLineupMask: GLint = -1, uBandPresent: GLint = -1
    private var uBandGenre: GLint = -1
    private var uBandGenrePrev: GLint = -1
    private var uBandGenreMix: GLint = -1
    private var uBandPrimary: GLint = -1
    private var uBandSecondary: GLint = -1
    private var uBandAccent: GLint = -1
    private var uBandBassReact: GLint = -1
    private var uBandTrebleReact: GLint = -1
    private var uBandBeatSharp: GLint = -1
    private var uBandStrobe: GLint = -1

    // Walk-on / walk-off. Musicians: 0 drums, 1 bass, 2 guitar, 3 keys,
    // 4 female singer, 5 male singer.
    //
    // Two rules govern leaving, both from the user:
    //   1. On a song change in the same genre: nobody leaves. They get a 10s
    //      grace to be re-confirmed by the new song; if their instrument
    //      hasn't been heard by then, they walk off.
    //   2. On a genre change: a walker whose slot isn't in the new genre's
    //      lineup walks off immediately (e.g. Rock → Ambient clears the stage
    //      because Ambient has no musicians). Slots in the new lineup also
    //      get the 10s grace.
    private struct Walker {
        var x: Float              // current stage position (art pixels)
        var on = false            // performing in this song
        var heardFor: Float = 0   // seconds continuously heard
        var phase: Float = 0      // walk cycle
        var face: Float = 0       // -1 / +1 while walking, 0 standing
        var mustExit = false      // walk all the way off before returning
        /// Set on every song change to "now + 10s". While set, the walker
        /// stays on stage until the deadline. Resets to 0 once partHeardInSong
        /// becomes true (they're locked in for the song).
        var candidateDepartureAt: CFTimeInterval = 0
        /// Set true the first time the instrument detector hears this walker
        /// in the current song. Once true, they stay for the rest of the song
        /// (the song-change grace is "you've been re-confirmed").
        var partHeardInSong = false
    }
    private var walkers: [Walker] = []
    private static let walkOnAfter: Float = 0.25
    private static let walkSpeed: Float = 160          // art pixels per second
    private static let drumRiseSpeed: Float = 80       // drummer rising/sinking behind the kit
    private static let songBreakSilence: Double = 1.0  // seconds of near-silence
    private static let songMinLength: Double = 10      // music needed before a break counts
    private static let reConfirmGrace: Double = 10.0   // walker grace period on a song change
    private var musicFor: Double = 0
    private var silenceFor: Double = 0
    private var seenTrackChanges = 0
    /// Set from the Lead Singer menu.
    var singerVoice: SingerVoice = .auto
    /// This song's singers, once worked out from the vocal pitch (nil until then).
    private var songLineup: InstrumentDetector.Lineup?
    /// With both singers on stage, how much each is singing right now (faded).
    private var leadHigh: Float = 1, leadLow: Float = 1

    /// Active genre — set by AppState. Default Rock because that's what the
    /// existing theatre stage looks like.
    var genre: Genre = .rock {
        didSet { if genre != oldValue { startGenreTransition(to: genre, from: oldValue) } }
    }
    /// The genre as of the previous frame. When it changes, we re-arm the
    /// walker logic so the new lineup filters them in/out.
    private var lastRenderedGenre: Genre = .rock

    // --- Genre cross-fade -------------------------------------------------
    // Switching genre shouldn't hard-cut from one room to another. We hold
    // the outgoing genre's room/palette for a moment and blend into the
    // incoming one. `genreFade` goes 0 → 1 over `genreFadeDuration`.
    private static let genreFadeDuration: CFTimeInterval = 0.65
    private var genreFadeStart: CFTimeInterval = 0
    private var genreFadingFrom: Genre = .rock
    private var genreFadeActive = false
    private var genreFade: Float = 1

    private func startGenreTransition(to new: Genre, from old: Genre) {
        genreFadingFrom = old
        genreFadeStart = CACurrentMediaTime()
        genreFadeActive = true
        genreFade = 0
    }

    /// Advances the fade. Called every frame from bindBand before the
    /// uniforms are pushed.
    private func advanceGenreFade(now: CFTimeInterval) {
        // Snapshots render each genre in isolation: no cross-fade from the last.
        if bandForceAll { genreFadeActive = false }
        guard genreFadeActive else { genreFade = 1; return }
        let t = Float((now - genreFadeStart) / Self.genreFadeDuration)
        // ease-in-out so the dip isn't abrupt
        genreFade = min(1, max(0, t))
        genreFade = genreFade * genreFade * (3 - 2 * genreFade)  // smoothstep
        if t >= 1 {
            genreFade = 1
            genreFadeActive = false
        }
    }

    /// Onset bands (indices into the 96 log bands, 40Hz-16kHz):
    /// snare 1-4kHz, hi-hat 6-16kHz, guitar strum 400Hz-2kHz, bass pluck 60-250Hz.
    private static let bandOnsetRanges = [52..<76, 80..<96, 35..<64, 8..<29]

    private func bindBand(_ snap: AudioSnapshot) {
        let dt = Float(lastFrameDT)
        let b = snap.bands

        // Accents: a clear onset sets a pulse; the envelope follows it with a
        // ~30ms attack and a ~170ms release instead of jumping.
        for e in 0..<bandPulse.count { bandPulse[e] *= expf(-dt * 6) }
        if snap.beat { bandPulse[0] = max(bandPulse[0], snap.beatStrength) }
        for (k, range) in Self.bandOnsetRanges.enumerated() {
            var flux: Float = 0
            for i in range { flux += max(0, b[i] - bandPrev[i]) }
            flux /= Float(range.count)
            if flux > bandFluxAvg[k] * 2.2 + 0.02 { bandPulse[k + 1] = 1 }
            bandFluxAvg[k] += (flux - bandFluxAvg[k]) * 0.05
        }
        bandPrev = b
        for e in 0..<bandEnv.count { bandEnv[e] += (bandPulse[e] - bandEnv[e]) * min(1, dt * 30) }

        // Who's playing: hold for a while after last heard, then fade (~1s).
        let detected = audio.instruments.presence()
        let now = CACurrentMediaTime()
        // Fast evidence from the spectrum alongside the (slow, sometimes
        // deaf) classifier: a locked-on tempo means drums; sustained energy
        // under ~250Hz means bass.
        var low: Float = 0
        for i in 6..<26 { low += b[i] / 20 }
        bandLowAverage += (low - bandLowAverage) * min(1, dt * 1.5)
        let spectral: [Float] = [snap.bpm > 0 ? 0.8 : 0, min(1, max(0, (bandLowAverage - 0.3) / 0.3)), 0, 0, 0]
        for i in 0..<bandParts.count {
            // Snapshots "hear" exactly the genre's usual line-up.
            let lineupSlots = GenreVisual.visual(for: genre).lineup
            let forced: Float = (i < 4 ? lineupSlots.contains(WalkerSlot(rawValue: i)!)
                                       : (lineupSlots.contains(.femaleSinger) || lineupSlots.contains(.maleSinger))) ? 1 : 0
            let c = bandForceAll ? forced : detected[i]
            var heard = max(min(1, max(0, (c - 0.05) / 0.3)), bandForceAll ? 0 : spectral[i])
            if heard > 0.4 {
                bandHeldLevel[i] = heard
                bandLastHeard[i] = now
            } else if !bandForceAll && now - bandLastHeard[i] < Self.bandHoldSeconds {
                heard = max(heard, bandHeldLevel[i])
            }
            let target = heard * Float(danceActivity)
            let rate: Float = target > bandParts[i] ? 4.0 : 1.5
            bandParts[i] += (target - bandParts[i]) * min(1, dt * rate)
        }

        var vocal: Float = 0
        for i in 45..<68 { vocal += b[i] }
        bandVocal += (vocal / 23 - bandVocal) * min(1, dt * 12)
        for k in 0..<9 {
            var e: Float = 0
            for i in (30 + k * 5)..<(35 + k * 5) { e += b[i] / 5 }
            bandKeys[k] += (e - bandKeys[k]) * min(1, dt * 10)
        }
        glUniform1fv(uBandParts, GLsizei(bandParts.count), bandParts)
        glUniform4f(uBandHits, bandEnv[0], bandEnv[1], bandEnv[2], bandEnv[3])
        glUniform1f(uBandPluck, bandEnv[4])
        glUniform1f(uBandVocal, bandVocal)
        glUniform1fv(uBandKeys, GLsizei(bandKeys.count), bandKeys)
        // Genre palette + motion — read once per frame from the GenreVisual
        // for the active genre. Changing genre in the middle of a song
        // updates uniforms on the next frame, so the shader can branch on
        // uGenre and the room/musicians will match. During a switch we also
        // send the outgoing genre + a 0→1 blend so the room cross-fades
        // instead of cutting.
        advanceGenreFade(now: CACurrentMediaTime())
        let gv = GenreVisual.visual(for: genre)
        glUniform1i(uBandGenre, GLint(genre.rawValue))
        if genreFadeActive {
            glUniform1i(uBandGenrePrev, GLint(genreFadingFrom.rawValue))
            glUniform1f(uBandGenreMix, genreFade)
        } else {
            glUniform1i(uBandGenrePrev, GLint(genre.rawValue))
            glUniform1f(uBandGenreMix, 1.0)
        }
        glUniform3f(uBandPrimary, gv.primary.x, gv.primary.y, gv.primary.z)
        glUniform3f(uBandSecondary, gv.secondary.x, gv.secondary.y, gv.secondary.z)
        glUniform3f(uBandAccent, gv.accent.x, gv.accent.y, gv.accent.z)
        glUniform1f(uBandBassReact, gv.bassReactivity)
        glUniform1f(uBandTrebleReact, gv.trebleReactivity)
        glUniform1f(uBandBeatSharp, gv.beatSharpness)
        glUniform1f(uBandStrobe, gv.strobeIntensity)

        let vocals = audio.instruments.vocals()
        if let detected = vocals.lineup { songLineup = detected }
        let lineup: InstrumentDetector.Lineup?
        switch singerVoice {
        case .auto: lineup = bandForceAll ? (songLineup ?? .female) : songLineup
        case .female: lineup = .female
        case .male: lineup = .male
        case .duet: lineup = .duet
        }
        updateWalkers(snap, lineup: lineup, currentHigh: vocals.currentHigh, dt: dt, now: now)
    }

    private func updateWalkers(_ snap: AudioSnapshot, lineup: InstrumentDetector.Lineup?,
                               currentHigh: Bool?, dt: Float, now: CFTimeInterval) {
        // Off-stage wings just past the visible edge. The drummer doesn't walk:
        // they rise up from behind the kit and sink back down (x = how far down).
        let scale = max(1, floor(min(viewHeight / 200, viewWidth / 440)))
        let wing = viewWidth / scale / 2 + 25
        let wingSide: [Float] = [0, -1, -1, 1, -1, 1]
        let drumHidden: Float = 56
        func offStage(_ i: Int) -> Float { i == 0 ? drumHidden : wingSide[i] * wing }
        if walkers.isEmpty {
            walkers = (0..<6).map { Walker(x: offStage($0)) }
        }

        // Song change: a short near-silence after a decent stretch of music,
        // or Music / Spotify telling us the track changed (catches skips).
        let quiet = snap.rms < 0.003 || snap.sourceIsIdle > 0.5
        if quiet { silenceFor += Double(dt) } else { silenceFor = 0; musicFor += Double(dt) }
        let skipped = audio.tracks.changeCount != seenTrackChanges
        let trackChanged = skipped
        seenTrackChanges = audio.tracks.changeCount

        // Genre change handling: when the user (or auto-detect) switches
        // genres, walkers whose slot isn't in the new lineup walk off
        // immediately. Slots IN the new lineup get the 10s grace.
        let genreChanged = (genre != lastRenderedGenre)
        if genreChanged {
            let visual = GenreVisual.visual(for: genre)
            for i in walkers.indices {
                let slot = WalkerSlot(rawValue: i)!
                if !visual.lineup.contains(slot) {
                    walkers[i].mustExit = true
                } else {
                    walkers[i].candidateDepartureAt = now + Self.reConfirmGrace
                    walkers[i].partHeardInSong = false
                }
            }
            lastRenderedGenre = genre
            let genreVisual = GenreVisual.visual(for: genre)
            if genreVisual.noMusicians {
                NSLog("[BAND] genre \(genre.name): no musicians, stage clears")
            } else {
                NSLog("[BAND] genre \(genre.name): lineup \(visual.lineup.map(\.rawValue).sorted())")
            }
            // The lineup is what a band-mode crash report needs: a stage with
            // two drummers on it is a different bug from an empty one.
            CrashReporter.shared.log("band lineup for \(genre.name): \(genreVisual.noMusicians ? "(none)" : visual.lineup.map(\.shortName).sorted().joined(separator: "+"))")
        }

        if trackChanged || (silenceFor >= Self.songBreakSilence && musicFor >= Self.songMinLength) {
            NSLog("[BAND] song change (\(trackChanged ? "track changed" : "silence")): band stays on stage, 10s grace")
            // No mustExit. The whole band stays put. Each walker has until
            // (now + reConfirmGrace) to be re-confirmed by the new song; if
            // their instrument isn't heard in that window, they walk off.
            let deadline = now + Self.reConfirmGrace
            for i in walkers.indices {
                walkers[i].candidateDepartureAt = deadline
                walkers[i].partHeardInSong = false
            }
            musicFor = 0
            songLineup = nil
            audio.instruments.resetVocals()
        }
        if silenceFor >= Self.songBreakSilence { musicFor = 0 }

        // Who is being heard right now. Singers wait until this song's voice
        // has been identified, then join by the line-up; once on stage anyone
        // stays for the rest of the song.
        let femaleIn = lineup == .female || lineup == .duet
        let maleIn = lineup == .male || lineup == .duet
        let vocalsHeard = bandParts[4] > 0.4
        let heard: [Bool] = [bandParts[0] > 0.4, bandParts[1] > 0.4, bandParts[2] > 0.4, bandParts[3] > 0.4,
                             vocalsHeard && femaleIn, vocalsHeard && maleIn]

        // Singers stand side by side when both are on stage, otherwise centre.
        let bothSingers = walkers[4].on && walkers[5].on
        let home: [Float] = [0, -175, -90, 150, bothSingers ? -27 : 0, bothSingers ? 27 : 0]

        // With both singers out, whoever's voice is heard just now sings; if
        // unclear, both do.
        var highTarget: Float = 1, lowTarget: Float = 1
        if bothSingers, let high = currentHigh {
            highTarget = high ? 1 : 0
            lowTarget = high ? 0 : 1
        }
        leadHigh += (highTarget - leadHigh) * min(1, dt * 8)
        leadLow += (lowTarget - leadLow) * min(1, dt * 8)
        let singerWeight: [Float] = [leadHigh, leadLow]

        var play = [Float](repeating: 0, count: 6)
        for i in walkers.indices {
            var w = walkers[i]
            if bandForceAll {
                // Use the active genre's lineup rather than the vocalist
                // lineup, so the snapshot frames show the same band that
                // real usage would have on stage.
                let visual = GenreVisual.visual(for: genre)
                let slot = WalkerSlot(rawValue: i)
                let inLineup = slot.map { visual.lineup.contains($0) } ?? false
                w.on = inLineup
                w.x = inLineup ? home[i] : offStage(i)
            }
            if w.mustExit {
                w.on = false
                w.heardFor = 0
            } else if heard[i] {
                w.heardFor += dt
                if w.heardFor >= Self.walkOnAfter { w.on = true }
                // Once the detector hears this walker in the current song,
                // they're locked in for the song — clear the departure deadline.
                if w.on {
                    w.candidateDepartureAt = 0
                    w.partHeardInSong = true
                }
            } else {
                w.heardFor = 0
            }

            // 10s grace expired without their instrument showing up: they walk off.
            if w.candidateDepartureAt > 0
               && now >= w.candidateDepartureAt
               && !w.partHeardInSong
               && !w.mustExit {
                w.mustExit = true
                w.on = false
                w.heardFor = 0
                NSLog("[BAND] slot \(i) not re-confirmed in 10s, leaving")
            }

            let target = w.on ? home[i] : offStage(i)
            let dx = target - w.x
            let speed = i == 0 ? Self.drumRiseSpeed : Self.walkSpeed
            let step = speed * dt
            if abs(dx) > 0.5 {
                w.x += max(-step, min(step, dx))
                if i != 0 { w.phase += dt * 9; w.face = dx > 0 ? 1 : -1 }
            } else {
                w.x = target
                w.face = 0
                if !w.on { w.mustExit = false }   // fully off
            }
            // Singers and guitarists play as they walk; drums and keys only
            // once they're at their instrument.
            let atMark = max(0, 1 - abs(w.x - home[i]) / 6)
            let needsMark = i == 0 || i == 3
            let part = i >= 4 ? bandParts[4] * (bothSingers ? singerWeight[i - 4] : 1) : bandParts[i]
            play[i] = (w.on ? 1 : 0) * (needsMark ? atMark : 1) * part
            walkers[i] = w
        }
        glUniform1fv(uBandX, 6, walkers.map(\.x))
        glUniform1fv(uBandWalk, 6, walkers.map { $0.face == 0 ? -1 : $0.phase })
        glUniform1fv(uBandFace, 6, walkers.map(\.face))
        glUniform1fv(uBandPlay, 6, play)
        glUniform1fv(uBandHome, 6, home)
        let mask = GenreVisual.visual(for: genre).lineup.reduce(0) { $0 | (1 << $1.rawValue) }
        glUniform1i(uBandLineupMask, GLint(mask))
        glUniform1fv(uBandPresent, 6, walkers.indices.map { walkers[$0].on || abs(walkers[$0].x - offStage($0)) > 1 ? 1 : 0 })
    }

    /// The band's current read of the music, for the evaluation log.
    func bandEvalState() -> [String: Any] {
        let names = ["drums", "bass", "guitar", "keys", "female_singer", "male_singer"]
        var onStage: [String] = []
        for (i, w) in walkers.enumerated() where w.on { onStage.append(names[i]) }
        let classifier = audio.instruments.presence()
        let partNames = ["drums", "bass", "guitar", "keys", "vocals"]
        return [
            "on_stage": onStage,
            "parts": Dictionary(uniqueKeysWithValues: zip(partNames, bandParts.map { Double($0) })),
            "classifier": Dictionary(uniqueKeysWithValues: zip(partNames, classifier.map { Double($0) })),
            "singers": songLineup?.rawValue ?? "",
        ]
    }

    private func updateBadgerOverlay(_ snap: AudioSnapshot) -> (kind: Float, age: Float) {
        let now = CACurrentMediaTime()
        if snap.beat {
            let isBig = snap.beatStrength > max(0.35, bigBeatAverage * 1.3)
            bigBeatAverage += (snap.beatStrength - bigBeatAverage) * 0.1
            if isBig && (overlayKind == 0 || now - overlayStart > overlayDuration) {
                overlayCount += 1
                overlayKind = overlayCount % 3 == 0 ? 2 : 1
                overlayStart = now
            }
        }
        if overlayKind != 0 && now - overlayStart > overlayDuration { overlayKind = 0 }
        return (overlayKind, Float(now - overlayStart))
    }

    // State
    private var currentMode: VisualizerMode = .tunnel
    private var viewWidth: GLfloat = 1.0
    private var viewHeight: GLfloat = 1.0

    // Tunnel CPU buffer
    private var tunnelVerts: [TunnelVertex]
    private let tunnelRings = 64
    private let tunnelBars = 96
    private let tunnelIndexCount: Int

    init(audio: AudioEngine) {
        self.audio = audio
        self.tunnelVerts = [TunnelVertex](
            repeating: TunnelVertex(position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0, 0, 0)),
            count: 64 * 96 * 2
        )
        self.tunnelIndexCount = 64 * 96 * 6
        super.init()
    }

    func attach(to view: NSOpenGLView) {
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 0,
            0
        ]
        guard let format = NSOpenGLPixelFormat(attributes: attrs) else {
            NSLog("[VIZ] failed to create pixel format")
            return
        }
        guard let ctx = NSOpenGLContext(format: format, share: nil) else {
            NSLog("[VIZ] failed to create GL context")
            return
        }
        var swap: GLint = 1
        ctx.setValues(&swap, for: .swapInterval)

        view.pixelFormat = format
        view.openGLContext = ctx
        view.wantsBestResolutionOpenGLSurface = false

        ctx.makeCurrentContext()
        self.glContext = ctx
        self.pixelFormat = format
        setupGL()
        buildPrograms()
        buildGeometry()
        self.isReady = true
    }

    /// Creates a separate offscreen GL context for FBO rendering (PNG snapshots).
    /// Shares state (programs, buffers, VAOs) with the screen context so we
    /// don't need to duplicate GL setup.
    private func ensureOffscreenContext() -> NSOpenGLContext? {
        if let c = offscreenContext { return c }
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 0,
            0
        ]
        guard let format = NSOpenGLPixelFormat(attributes: attrs) else { return nil }
        let ctx = NSOpenGLContext(format: format, share: glContext)!
        ctx.makeCurrentContext()
        // re-bind any shared VAOs/programs since current context changed
        if let tunnel = tunnelProgram as GLuint?, tunnel > 0 {
            // ensure we have a valid current context
        }
        self.offscreenPixelFormat = format
        self.offscreenContext = ctx
        return ctx
    }

    func setMode(_ mode: VisualizerMode) {
        if mode == .autoScan {
            // Start the cycle on whatever is already showing, so switching to
            // auto-scan doesn't visibly jump — the mode you're in gets its
            // full 20 seconds before the scanner moves on.
            if currentMode != .autoScan, Self.scanCycle.contains(currentMode) {
                autoScanTarget = currentMode
            } else if !Self.scanCycle.contains(autoScanTarget) {
                autoScanTarget = Self.scanCycle.first ?? .tunnel
            }
            autoScanStart = CACurrentMediaTime()
        }
        if mode == .machine, currentMode != .machine {
            // Start the camera at the beginning of its path.
            machineCameraPhase = 0
        }
        currentMode = mode
    }

    // --- Auto-scan ------------------------------------------------------
    /// True while the auto-scanner is running. The view uses this to keep
    /// rendering even in silence — the scanner has to keep cycling whether
    /// or not music is playing.
    var isAutoScanning: Bool { currentMode == .autoScan }

    /// The mode actually being drawn. In auto-scan this is the mode the
    /// scanner is currently sitting on, not `.autoScan` itself.
    private(set) var effectiveMode: VisualizerMode = .tunnel
    /// The modes auto-scan cycles through — everything except itself.
    private static var scanCycle: [VisualizerMode] {
        VisualizerMode.allCases.filter { $0 != .autoScan }
    }
    /// How long each mode gets before the scanner moves on.
    private static let autoScanDuration: CFTimeInterval = 20.0
    /// Overridable for testing only — `--scan-seconds 2` makes the cycle
    /// quick. The shipped default is 20 seconds per mode.
    private var autoScanDuration: CFTimeInterval = {
        if let i = CommandLine.arguments.firstIndex(of: "--scan-seconds"),
           i + 1 < CommandLine.arguments.count,
           let v = Double(CommandLine.arguments[i + 1]) {
            return v
        }
        return 20.0
    }()
    private var autoScanTarget: VisualizerMode = .tunnel
    /// Wall-clock time the current mode started. Using a timestamp rather
    /// than accumulated frame deltas means each mode gets exactly 20 real
    /// seconds whether the renderer is running at 30fps or 120fps, and it
    /// doesn't drift or stall if frames are dropped.
    private var autoScanStart: CFTimeInterval = 0
    /// Set when the mode changes so the UI can flash a "now showing" hint.
    private(set) var autoScanJustChanged = false

    /// Advances the auto-scan clock. Uses wall-clock time, not the
    /// sound-gated clock — the scanner should keep moving even in silence
    /// so you're not stuck on one mode when the music starts.
    private func advanceAutoScan(now: CFTimeInterval) {
        guard currentMode == .autoScan else { return }
        if now - autoScanStart >= autoScanDuration {
            // Carry the overshoot forward so a late frame doesn't shorten the
            // next mode's slot.
            autoScanStart += autoScanDuration
            let cycle = Self.scanCycle
            if let i = cycle.firstIndex(of: autoScanTarget) {
                autoScanTarget = cycle[(i + 1) % cycle.count]
            } else if let first = cycle.first {
                autoScanTarget = first
            }
            autoScanJustChanged = true
            NSLog("[SCAN] now showing \(autoScanTarget.rawValue)")
            CrashReporter.shared.log("auto-scan now showing \(autoScanTarget.rawValue)")
        }
    }

    func setSize(width: CGFloat, height: CGFloat) {
        viewWidth = GLfloat(width)
        viewHeight = GLfloat(height)
    }

    /// One-shot offscreen render to PNG. Used for verification / debug snapshots.
    func renderToPNG(width: Int, height: Int, mode: VisualizerMode, frames: Int = 60, path: String) {
        guard let ctx = ensureOffscreenContext() else {
            NSLog("[VIZ] renderToPNG: failed to create offscreen context")
            return
        }
        ctx.makeCurrentContext()

        let saveMode = currentMode
        currentMode = mode
        viewWidth = GLfloat(width)
        viewHeight = GLfloat(height)

        // create FBO
        var fbo: GLuint = 0
        glGenFramebuffers(1, &fbo)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)

        var colorTex: GLuint = 0
        glGenTextures(1, &colorTex)
        glBindTexture(GLenum(GL_TEXTURE_2D), colorTex)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, GLsizei(width), GLsizei(height), 0,
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), colorTex, 0)
        guard glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GL_FRAMEBUFFER_COMPLETE else {
            NSLog("[VIZ] FBO incomplete")
            return
        }

        glViewport(0, 0, GLsizei(width), GLsizei(height))

        // Run frames. Snapshot mode pre-set the analyzer state, so we just need
        // to copy the snapshot for the renderer to consume it.
        // Snapshots have no live audio: render as if music is playing at 120bpm.
        let savedActivity = danceActivity
        danceActivity = 1
        bandForceAll = true
        defer { danceActivity = savedActivity; bandForceAll = false }

        // Draw the scene into a target owned by this context (framebuffers
        // aren't shared between contexts), then grade it into the snapshot's
        // own FBO so the PNG shows the active palette.
        var snapTarget = makeSceneTarget(w: width, h: height)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), snapTarget.fbo)
        for k in 0..<frames {
            audio.refreshSnapshot()
            beatClock = Double(k) / 60.0 * 2.0
            glClearColor(0.02, 0.004, 0.03, 1.0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            glEnable(GLbitfield(GL_BLEND))
            let snap = audio.snapshot
            let t = Float(k) / 60.0
            switch currentMode {
            case .tunnel: drawTunnel(time: t, snap: snap)
            case .particles: drawParticles(time: t, snap: snap)
            case .liquid: drawLiquid(time: t, snap: snap)
            case .autoScan:
                // Snapshot the mode the scanner is actually sitting on.
                let m = autoScanTarget
                switch m {
                case .tunnel: drawTunnel(time: t, snap: snap)
                case .particles: drawParticles(time: t, snap: snap)
                case .liquid: drawLiquid(time: t, snap: snap)
                case .machine: drawMachine(time: t, snap: snap, now: Double(k) / 60.0, cameraT: 0.30)
                default: drawShaderMode(m, time: t, snap: snap)
                }
            case .machine:
                drawMachine(time: t, snap: snap, now: Double(k) / 60.0)
            default: drawShaderMode(currentMode, time: t, snap: snap)
            }
        }

        // Grade the scene through the palette into the snapshot's FBO.
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glDisable(GLbitfield(GL_BLEND))
        drawGrade(sampling: snapTarget.tex, mode: currentMode)

        // read pixels
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glDeleteFramebuffers(1, &fbo)
        glDeleteTextures(1, &colorTex)
        glDeleteFramebuffers(1, &snapTarget.fbo)
        glDeleteTextures(1, &snapTarget.tex)

        // flip vertically (GL is bottom-up, PNG is top-down)
        var flipped = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let src = (height - 1 - y) * rowBytes
            let dst = y * rowBytes
            for x in 0..<rowBytes {
                flipped[dst + x] = pixels[src + x]
            }
        }

        // write PNG via Core Graphics
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(flipped) as CFData) else { return }
        guard let cgImg = CGImage(width: width, height: height, bitsPerComponent: 8,
                                 bitsPerPixel: 32, bytesPerRow: rowBytes,
                                 space: cs, bitmapInfo: info,
                                 provider: provider, decode: nil, shouldInterpolate: false,
                                 intent: .defaultIntent) else { return }
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cgImg, nil)
        CGImageDestinationFinalize(dest)

        // restore
        currentMode = saveMode
        NSLog("[VIZ] saved \(path)")
    }

    /// Capture the current screen backbuffer to a PNG. Reads from the front
    /// buffer so it captures whatever the user is actually seeing, including
    /// any SwiftUI overlays (we composite them via the AppKit view tree, the
    /// back buffer is the final composited result).
    func captureScreen(to path: String) {
        guard let ctx = glContext else { NSLog("[CAP] no ctx"); return }
        ctx.makeCurrentContext()
        NSLog("[CAP] ctx current, viewSize=\(viewWidth)x\(viewHeight)")

        let w = Int(viewWidth)
        let h = Int(viewHeight)
        guard w > 0, h > 0 else { NSLog("[CAP] zero size"); return }

        let rowBytes = w * 4
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        glReadPixels(0, 0, GLsizei(w), GLsizei(h), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
        NSLog("[CAP] readPixels done, first 4 bytes=\(pixels[0]),\(pixels[1]),\(pixels[2]),\(pixels[3])")

        // flip vertically
        var flipped = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let src = (h - 1 - y) * rowBytes
            let dst = y * rowBytes
            for x in 0..<rowBytes {
                flipped[dst + x] = pixels[src + x]
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(flipped) as CFData) else { return }
        guard let cgImg = CGImage(width: w, height: h, bitsPerComponent: 8,
                                 bitsPerPixel: 32, bytesPerRow: rowBytes,
                                 space: cs, bitmapInfo: info,
                                 provider: provider, decode: nil, shouldInterpolate: false,
                                 intent: .defaultIntent) else { return }
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cgImg, nil)
        CGImageDestinationFinalize(dest)
    }

    // Called per draw cycle from the view
    func render() {
        guard let ctx = glContext else { return }
        ctx.makeCurrentContext()

        audio.tick()
        // The instrument classifier is only worth running when the band is
        // on screen — which, during auto-scan, means whenever the scanner
        // is sitting on the band mode.
        let isBandOnScreen = currentMode == .band || (currentMode == .autoScan && autoScanTarget == .band)
        audio.instruments.isEnabled = isBandOnScreen

        // Every mode runs on the sound-gated clock: it stops (easing out) when
        // there's no source or the music goes quiet, so nothing moves in silence.
        advanceDanceClock(audio.snapshot)
        let time = Float(danceClock.truncatingRemainder(dividingBy: 3600))

        // Draw the scene into the offscreen target so the palette grade can
        // be applied to the finished frame.
        ensureSceneTarget()
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), sceneFBO)
        glViewport(0, 0, GLsizei(viewWidth), GLsizei(viewHeight))
        glClearColor(0.02, 0.004, 0.03, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        glEnable(GLbitfield(GL_BLEND))
        glDisable(GLbitfield(GL_DEPTH_TEST))

        let snap = audio.snapshot
        advanceAutoScan(now: CACurrentMediaTime())
        let mode = currentMode == .autoScan ? autoScanTarget : currentMode
        effectiveMode = mode
        switch mode {
        case .tunnel:
            drawTunnel(time: time, snap: snap)
        case .particles:
            drawParticles(time: time, snap: snap)
        case .liquid:
            drawLiquid(time: time, snap: snap)
        case .machine:
            drawMachine(time: time, snap: snap, now: CACurrentMediaTime())
        default:
            drawShaderMode(mode, time: time, snap: snap)
        }

        // Grade the finished frame through the active palette and present it.
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glViewport(0, 0, GLsizei(viewWidth), GLsizei(viewHeight))
        glDisable(GLbitfield(GL_BLEND))
        drawGrade(sampling: sceneTex, mode: mode)
        // Note: flushBuffer is called by the view after this returns.
    }

    // MARK: - Palette grade

    /// Creates an FBO + colour texture of the given size. Framebuffer objects
    /// are not part of the OpenGL share list, so the snapshot path (which runs
    /// in a different context) needs its own rather than reusing the live one.
    private func makeSceneTarget(w: Int, h: Int) -> (fbo: GLuint, tex: GLuint) {
        var fbo: GLuint = 0
        glGenFramebuffers(1, &fbo)
        var tex: GLuint = 0
        glGenTextures(1, &tex)
        glBindTexture(GLenum(GL_TEXTURE_2D), tex)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, GLsizei(w), GLsizei(h), 0,
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), tex, 0)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        return (fbo, tex)
    }

    /// Creates (or resizes) the offscreen target the scene is drawn into.
    private func ensureSceneTarget() {
        let w = max(1, Int(viewWidth))
        let h = max(1, Int(viewHeight))
        guard w != fboWidth || h != fboHeight || sceneFBO == 0 else { return }
        fboWidth = w
        fboHeight = h
        if sceneFBO != 0 { glDeleteFramebuffers(1, &sceneFBO) }
        if sceneTex != 0 { glDeleteTextures(1, &sceneTex) }
        let pair = makeSceneTarget(w: w, h: h)
        sceneFBO = pair.fbo
        sceneTex = pair.tex
    }

    /// Modes drawn in their own fixed colours, which the palette would spoil.
    private static let ungradedModes: Set<VisualizerMode> = [.badger, .llama, .nyan]

    /// Full-screen quad that grades the offscreen scene through the palette
    /// (or passes it straight through for `ungradedModes`).
    private func drawGrade(sampling texture: GLuint, mode: VisualizerMode) {
        guard gradeProgram != 0 else { return }
        let ungraded = Self.ungradedModes.contains(mode)
        let pal = Palette.palette(at: paletteIndex)

        glUseProgram(gradeProgram)
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glUniform1i(uGradeTex, 0)
        glUniform3f(uGradeShadow, pal.shadow.x, pal.shadow.y, pal.shadow.z)
        glUniform3f(uGradeHighlight, pal.highlight.x, pal.highlight.y, pal.highlight.z)
        glUniform1f(uGradeSaturation, ungraded ? 1 : pal.saturation)
        glUniform1f(uGradeDuotone, ungraded ? 0 : pal.duotone)
        glUniform1f(uGradeLift, ungraded ? 0 : pal.lift)

        glBindVertexArray(gradeVAO)
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        glBindVertexArray(0)
    }

    // MARK: - Tunnel

    private func drawTunnel(time: Float, snap: AudioSnapshot) {
        updateTunnel(snap: snap)
        glUseProgram(tunnelProgram)

        // Upload uniforms
        glUniform1f(uTunnelTime, time)
        glUniform1f(uTunnelBass, snap.bass)
        glUniform1f(uTunnelBeat, snap.beat ? 1.0 : 0.0)
        glUniform1f(uTunnelBeatStrength, snap.beatStrength)

        // Aspect-corrected ortho projection (tunnel is rendered via vertex shader logic)
        let aspect = viewWidth / viewHeight
        let proj = ortho(left: -aspect, right: aspect, bottom: -1, top: 1, near: -1, far: 1)
        glUniformMatrix4fv(uTunnelMVP, 1, GLboolean(GL_FALSE), proj)

        glBindVertexArray(tunnelVAO)
        // upload updated vertices
        let count = tunnelVerts.count
        let size = count * MemoryLayout<TunnelVertex>.stride
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), tunnelVBO)
        var localVerts = tunnelVerts
        localVerts.withUnsafeBufferPointer { ptr in
            glBufferSubData(GLenum(GL_ARRAY_BUFFER), 0, size, ptr.baseAddress)
        }

        glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE))
        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(tunnelIndexCount), GLenum(GL_UNSIGNED_INT), nil)
        glBindVertexArray(0)
    }

    private func updateTunnel(snap: AudioSnapshot) {
        let bands = snap.bands
        let bass = snap.bass
        let beatS = snap.beatStrength
        let isBeat = snap.beat
        let ringSpacing: Float = 0.95

        for r in 0..<tunnelRings {
            let bin = min(bands.count - 1, Int(Float(r) / Float(tunnelRings) * Float(bands.count) * 0.85))
            let intensity = bands[bin]
            let ringPulse = intensity * (1.4 + bass * 2.5) + bass * 0.4

            let mix1 = Float(r) / Float(tunnelRings)
            let hot = SIMD3<Float>(1.0, 0.17, 0.84)
            let mid = SIMD3<Float>(0.54, 0.30, 1.0)
            let cold = SIMD3<Float>(0.17, 0.95, 1.0)
            var c: SIMD3<Float>
            if mix1 < 0.5 { c = mix(hot, mid, mix1 * 2) }
            else { c = mix(mid, cold, (mix1 - 0.5) * 2) }
            if isBeat {
                c.x = min(1, c.x + beatS * 0.35)
                c.y = min(1, c.y + beatS * 0.15)
            }

            for b in 0..<tunnelBars {
                let angle = Float(b) / Float(tunnelBars) * 2 * .pi
                let cosA = cosf(angle)
                let sinA = sinf(angle)

                let barBin = min(bands.count - 1, Int(Float(b) / Float(tunnelBars) * Float(bands.count)))
                let barIntensity = bands[barBin]
                let barLen = barIntensity * 3.2 + bass * 0.6 + ringPulse * 0.18

                let inner: Float = 2.2 + barLen
                let outer: Float = inner + 0.18 + ringPulse * 0.04
                let z = Float(r) * ringSpacing

                let brightness = min(1.0, 0.45 + barLen * 0.55 + ringPulse * 0.4 + beatS * 0.4)
                let baseIdx = (r * tunnelBars + b) * 2
                tunnelVerts[baseIdx + 0].position = SIMD3<Float>(cosA * inner, sinA * inner, z)
                tunnelVerts[baseIdx + 0].color = c * brightness
                tunnelVerts[baseIdx + 1].position = SIMD3<Float>(cosA * outer, sinA * outer, z)
                tunnelVerts[baseIdx + 1].color = c * brightness * 1.2
            }
        }
    }

    // MARK: - Particles

    private func drawParticles(time: Float, snap: AudioSnapshot) {
        glUseProgram(particleProgram)

        let aspect = viewWidth / viewHeight
        let proj = perspective(fovY: 65, aspect: aspect, near: 0.1, far: 100)
        glUniformMatrix4fv(uParticleMVP, 1, GLboolean(GL_FALSE), proj)
        glUniform1f(uParticleTime, time)
        glUniform1f(uParticleBass, snap.bass)
        glUniform1f(uParticleMid, snap.mid)
        glUniform1f(uParticleTreble, snap.treble)
        glUniform1f(uParticleBeat, snap.beat ? 1.0 : 0.0)
        glUniform1f(uParticleBeatStrength, snap.beatStrength)
        glUniform1f(uParticleLevel, snap.level)
        glUniform2f(uParticleResolution, viewWidth, viewHeight)
        glUniform1f(uParticleActive, Float(danceActivity))
        snap.bands.withUnsafeBufferPointer { ptr in
            glUniform1fv(uParticleBands, GLsizei(AudioAnalyzer.bandCount), ptr.baseAddress)
        }

        glBindVertexArray(particleVAO)
        glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE))
        glDrawArrays(GLenum(GL_POINTS), 0, GLsizei(particleCount))
    }

    // MARK: - Liquid

    /// MACHINE mode — a port of the MIDEM Music Hack Day piece. Drums in a
    /// corridor plus a ring of pads; note events launch bouncing balls that
    /// arc over the drums, which recoil and flash.
    ///
    /// `now` is the clock note ages are measured against — wall-clock in live
    /// playback, a synthetic clock in snapshot mode.
    /// MACHINE mode — a port of the MIDEM Music Hack Day piece. Drums in a
    /// corridor plus a ring of pads; note events launch bouncing balls that
    /// arc over the drums, which recoil and flash.
    ///
    /// `now` is the clock note ages are measured against — wall-clock in live
    /// playback, a synthetic clock in snapshot mode.
    private func drawMachine(time: Float, snap: AudioSnapshot, now: CFTimeInterval, cameraT: Float? = nil) {
        let dt = Float(lastFrameDT)
        machine.update(bands: snap.bands, rms: snap.rms, now: now)
        if bandForceAll && machine.mode.notes.isEmpty {
            // Snapshots have no live flux, so seed notes to show the balls.
            machine.mode.seedNotes(count: 24, now: now)
        }

        // The original flies its camera path once over the length of the
        // track. Music / Spotify tell us the track length; otherwise glide
        // back and forth along the path every four minutes.
        var t: Float
        if let k = ProcessInfo.processInfo.environment["MACHINE_T"].flatMap(Float.init) {
            t = k   // debug: pin the camera's place along its path
        } else if let k = cameraT {
            t = k
        } else if let length = audio.tracks.duration, length > 0, let start = audio.tracks.startedAt {
            t = Float(min(1, (CACurrentMediaTime() - start) / length))
        } else {
            machineCameraPhase += dt / 240
            if machineCameraPhase >= 1 { machineCameraPhase -= 1 }
            t = 1 - abs(1 - 2 * machineCameraPhase)
        }
        var cam = MachineMode.camera(progress: t)
        // Debug override: MACHINE_CAM="ex,ey,ez,tx,ty,tz" pins the camera.
        if let s = ProcessInfo.processInfo.environment["MACHINE_CAM"] {
            let n = s.split(separator: ",").compactMap { Float($0) }
            if n.count == 6 {
                cam = (SIMD3<Float>(n[0], n[1], n[2]), SIMD3<Float>(n[3], n[4], n[5]))
            }
        }
        let aspect = viewWidth / max(1, viewHeight)
        let viewProj = makeViewProj(eye: cam.pos, target: cam.target,
                                    up: SIMD3<Float>(0, 1, 0),
                                    aspect: aspect, fovY: 45,
                                    near: 1, far: 1000)
        machine.render(viewProj: viewProj, cameraPos: cam.pos, width: Int(viewWidth), height: Int(viewHeight))
    }

    private func drawLiquid(time: Float, snap: AudioSnapshot) {
        glUseProgram(liquidProgram)
        glUniform1f(uLiquidTime, time)
        glUniform1f(uLiquidBass, snap.bass)
        glUniform1f(uLiquidMid, snap.mid)
        glUniform1f(uLiquidTreble, snap.treble)
        glUniform1f(uLiquidBeat, snap.beat ? 1.0 : 0.0)
        glUniform1f(uLiquidBeatStrength, snap.beatStrength)
        glUniform1f(uLiquidLevel, snap.level)
        glUniform2f(uLiquidResolution, viewWidth, viewHeight)
        glUniform1f(uLiquidIdle, snap.sourceIsIdle)
        glUniform1f(uLiquidActive, Float(danceActivity))

        // upload bands as float[] uniform
        var bandsCopy = snap.bands
        bandsCopy.withUnsafeBufferPointer { ptr in
            glUniform1fv(uLiquidBands, GLsizei(AudioAnalyzer.bandCount), ptr.baseAddress)
        }

        glBindVertexArray(liquidVAO)
        glBlendFunc(GLenum(GL_ONE), GLenum(GL_ZERO)) // opaque
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
    }

    // MARK: - Shader modes

    /// Animation clock for all modes: only advances while there's sound, so
    /// everything freezes in place when the music stops (and eases in/out of it).
    private var danceClock: Double = 0
    private var danceActivity: Double = 0
    private var danceClockLast: CFTimeInterval = CACurrentMediaTime()
    /// Counts beats at the detected tempo (120 until one is detected), nudged
    /// toward a whole number on each detected beat so moves land on the beat.
    /// Like danceClock it only runs while there's sound.
    private var beatClock: Double = 0
    /// Spectrum peak caps: jump to the bar's level, then fall slowly.
    private var spectrumPeaks = [Float](repeating: 0, count: 48)
    private var lastFrameDT: Double = 1.0 / 60
    /// Distance travelled, for things that should move faster when louder.
    /// Accumulated (never time × speed) so a drop in speed can't run it backwards.
    private var scrollClock: Double = 0
    /// Plain wall-clock seconds that keep running in silence. Only for modes
    /// that should never stop completely (Ribbons keeps a slow, dim drift);
    /// everything else should stay on the sound-gated clocks above.
    private var wallClock: Double = 0

    private func advanceDanceClock(_ snap: AudioSnapshot) {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - danceClockLast)
        danceClockLast = now
        // Same thresholds as the analyzer's noise gate (~-54 to -40 dBFS RMS).
        let target = snap.sourceIsIdle > 0.5 ? 0 : min(1, max(0, Double(snap.rms - 0.002) / 0.008))
        danceActivity += (target - danceActivity) * min(1, dt * 6)
        danceClock += dt * danceActivity
        scrollClock += dt * danceActivity * (0.4 + Double(snap.level) * 0.6)
        wallClock += dt
        let bpm = snap.bpm > 0 ? snap.bpm : 120
        beatClock += dt * danceActivity * bpm / 60
        if snap.beat { beatClock += (beatClock.rounded() - beatClock) * 0.35 }
        lastFrameDT = dt
    }

    private func drawShaderMode(_ mode: VisualizerMode, time: Float, snap: AudioSnapshot) {
        guard let m = shaderModes[mode] else { return }
        glUseProgram(m.program)
        glUniform1f(m.time, time)
        glUniform1f(m.bass, snap.bass)
        glUniform1f(m.mid, snap.mid)
        glUniform1f(m.treble, snap.treble)
        glUniform1f(m.beat, snap.beat ? 1.0 : 0.0)
        glUniform1f(m.beatStrength, snap.beatStrength)
        glUniform1f(m.level, snap.level)
        glUniform2f(m.resolution, viewWidth, viewHeight)
        glUniform1f(m.idle, snap.sourceIsIdle)
        glUniform1f(m.active, Float(danceActivity))
        glUniform1f(m.beats, Float(beatClock.truncatingRemainder(dividingBy: 1024)))
        glUniform1f(m.scroll, Float(scrollClock.truncatingRemainder(dividingBy: 4096)))
        glUniform1f(m.clock, Float(wallClock.truncatingRemainder(dividingBy: 3600)))
        if mode == .spectrum {
            for i in 0..<spectrumPeaks.count {
                let v = max(snap.bands[i * 2], snap.bands[i * 2 + 1])
                spectrumPeaks[i] = max(v, spectrumPeaks[i] - Float(lastFrameDT) * 0.35)
            }
            glUniform1fv(m.peaks, GLsizei(spectrumPeaks.count), spectrumPeaks)
        }
        if mode == .badger {
            let overlay = updateBadgerOverlay(snap)
            glUniform1f(m.eventKind, overlay.kind)
            glUniform1f(m.eventAge, overlay.age)
        }
        if mode == .hamster { bindSprites(snap) }
        if mode == .band { bindBand(snap) }
        snap.bands.withUnsafeBufferPointer { ptr in
            glUniform1fv(m.bands, GLsizei(AudioAnalyzer.bandCount), ptr.baseAddress)
        }
        glBindVertexArray(liquidVAO)
        glBlendFunc(GLenum(GL_ONE), GLenum(GL_ZERO)) // opaque
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
    }

    // MARK: - Setup

    private func setupGL() {
        glEnable(GLenum(GL_PROGRAM_POINT_SIZE))
        glEnable(GLenum(GL_BLEND))
    }

    /// Builds the palette grade program and its full-screen quad.
    private func buildGradePass() {
        gradeProgram = makeGLProgram(vs: Shaders.gradeVS, fs: Shaders.gradeFS, "grade")
        uGradeTex = glGetUniformLocation(gradeProgram, "uTex")
        uGradeShadow = glGetUniformLocation(gradeProgram, "uShadow")
        uGradeHighlight = glGetUniformLocation(gradeProgram, "uHighlight")
        uGradeSaturation = glGetUniformLocation(gradeProgram, "uSaturation")
        uGradeDuotone = glGetUniformLocation(gradeProgram, "uDuotone")
        uGradeLift = glGetUniformLocation(gradeProgram, "uLift")

        // A full-screen triangle strip: two triangles in clip space.
        var vao: GLuint = 0
        glGenVertexArrays(1, &vao)
        gradeVAO = vao
        glBindVertexArray(gradeVAO)

        var vbo: GLuint = 0
        glGenBuffers(1, &vbo)
        gradeVBO = vbo
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), gradeVBO)
        let quad: [Float] = [-1, -1,  1, -1,  -1, 1,  1, 1]
        quad.withUnsafeBufferPointer { ptr in
            glBufferData(GLenum(GL_ARRAY_BUFFER), quad.count * 4, ptr.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(2 * 4), nil)
        glBindVertexArray(0)
    }

    private func buildGeometry() {
        // tunnel VBO + IBO
        var vao: GLuint = 0
        glGenVertexArrays(1, &vao); tunnelVAO = vao
        glBindVertexArray(tunnelVAO)

        var vbo: GLuint = 0
        glGenBuffers(1, &vbo); tunnelVBO = vbo
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), tunnelVBO)
        let vSize = tunnelVerts.count * MemoryLayout<TunnelVertex>.stride
        var scratch = tunnelVerts
        scratch.withUnsafeBufferPointer { ptr in
            glBufferData(GLenum(GL_ARRAY_BUFFER), vSize, ptr.baseAddress, GLenum(GL_DYNAMIC_DRAW))
        }
        let stride = GLsizei(MemoryLayout<TunnelVertex>.stride)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride, nil)
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride,
                              UnsafeRawPointer(bitPattern: MemoryLayout<SIMD3<Float>>.stride))

        var ibo: GLuint = 0
        glGenBuffers(1, &ibo); tunnelIBO = ibo
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), tunnelIBO)
        var indices = [UInt32](repeating: 0, count: tunnelIndexCount)
        var idx = 0
        for r in 0..<tunnelRings {
            for b in 0..<tunnelBars {
                let base = UInt32((r * tunnelBars + b) * 2)
                let next = UInt32((r * tunnelBars + ((b + 1) % tunnelBars)) * 2)
                indices[idx] = base; idx += 1
                indices[idx] = base + 1; idx += 1
                indices[idx] = next; idx += 1
                indices[idx] = base + 1; idx += 1
                indices[idx] = next + 1; idx += 1
                indices[idx] = next; idx += 1
            }
        }
        indices.withUnsafeBufferPointer { ptr in
            glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), indices.count * 4, ptr.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        glBindVertexArray(0)

        // particles
        glGenVertexArrays(1, &vao); particleVAO = vao
        glBindVertexArray(particleVAO)
        glGenBuffers(1, &vbo); particleVBO = vbo
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), particleVBO)
        let pSize = particleCount * MemoryLayout<ParticleVertex>.stride
        var particles = [ParticleVertex]()
        particles.reserveCapacity(particleCount)
        for _ in 0..<particleCount {
            particles.append(ParticleVertex.makeRandom())
        }
        particles.withUnsafeBufferPointer { ptr in
            glBufferData(GLenum(GL_ARRAY_BUFFER), pSize, ptr.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        let pStride = GLsizei(MemoryLayout<ParticleVertex>.stride)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), pStride, nil)
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), pStride,
                              UnsafeRawPointer(bitPattern: MemoryLayout<SIMD3<Float>>.stride))
        glEnableVertexAttribArray(2)
        glVertexAttribPointer(2, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), pStride,
                              UnsafeRawPointer(bitPattern: MemoryLayout<SIMD3<Float>>.stride * 2))
        glEnableVertexAttribArray(3)
        glVertexAttribPointer(3, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), pStride,
                              UnsafeRawPointer(bitPattern: MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<Float>.stride))
        glEnableVertexAttribArray(4)
        glVertexAttribPointer(4, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), pStride,
                              UnsafeRawPointer(bitPattern: MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<Float>.stride * 2))
        glEnableVertexAttribArray(5)
        glVertexAttribPointer(5, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), pStride,
                              UnsafeRawPointer(bitPattern: MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<Float>.stride * 3))
        glBindVertexArray(0)

        // liquid quad
        glGenVertexArrays(1, &vao); liquidVAO = vao
        glBindVertexArray(liquidVAO)
        glGenBuffers(1, &vbo); liquidVBO = vbo
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), liquidVBO)
        let quad: [Float] = [-1, -1,  1, -1,  -1, 1,  1, 1]
        quad.withUnsafeBufferPointer { ptr in
            glBufferData(GLenum(GL_ARRAY_BUFFER), quad.count * 4, ptr.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(8), nil)
        glBindVertexArray(0)
    }

    // MARK: - Programs

    private func buildPrograms() {
        tunnelProgram = makeProgram(vs: Shaders.tunnelVS, fs: Shaders.tunnelFS, "tunnel")
        uTunnelMVP = glGetUniformLocation(tunnelProgram, "uMVP")
        uTunnelTime = glGetUniformLocation(tunnelProgram, "uTime")
        uTunnelBass = glGetUniformLocation(tunnelProgram, "uBass")
        uTunnelBeat = glGetUniformLocation(tunnelProgram, "uBeat")
        uTunnelBeatStrength = glGetUniformLocation(tunnelProgram, "uBeatStrength")

        particleProgram = makeProgram(vs: Shaders.particleVS, fs: Shaders.particleFS, "particle")
        uParticleMVP = glGetUniformLocation(particleProgram, "uMVP")
        uParticleTime = glGetUniformLocation(particleProgram, "uTime")
        uParticleBass = glGetUniformLocation(particleProgram, "uBass")
        uParticleMid = glGetUniformLocation(particleProgram, "uMid")
        uParticleTreble = glGetUniformLocation(particleProgram, "uTreble")
        uParticleBeat = glGetUniformLocation(particleProgram, "uBeat")
        uParticleBeatStrength = glGetUniformLocation(particleProgram, "uBeatStrength")
        uParticleLevel = glGetUniformLocation(particleProgram, "uLevel")
        uParticleResolution = glGetUniformLocation(particleProgram, "uResolution")
        uParticleActive = glGetUniformLocation(particleProgram, "uActive")
        uParticleBands = glGetUniformLocation(particleProgram, "uBands[0]")

        liquidProgram = makeProgram(vs: Shaders.liquidVS, fs: Shaders.liquidFS, "liquid")
        uLiquidTime = glGetUniformLocation(liquidProgram, "uTime")
        uLiquidBass = glGetUniformLocation(liquidProgram, "uBass")
        uLiquidMid = glGetUniformLocation(liquidProgram, "uMid")
        uLiquidTreble = glGetUniformLocation(liquidProgram, "uTreble")
        uLiquidBeat = glGetUniformLocation(liquidProgram, "uBeat")
        uLiquidBeatStrength = glGetUniformLocation(liquidProgram, "uBeatStrength")
        uLiquidLevel = glGetUniformLocation(liquidProgram, "uLevel")
        uLiquidResolution = glGetUniformLocation(liquidProgram, "uResolution")
        uLiquidIdle = glGetUniformLocation(liquidProgram, "uIdle")
        uLiquidActive = glGetUniformLocation(liquidProgram, "uActive")
        uLiquidBands = glGetUniformLocation(liquidProgram, "uBands[0]")

        // MACHINE mode
        machine.buildProgram()

        // Palette grade pass
        buildGradePass()

        for (mode, body) in FunShaders.modes {
            let p = makeProgram(vs: Shaders.liquidVS, fs: FunShaders.prelude + body, mode.rawValue)
            func loc(_ name: String) -> GLint { glGetUniformLocation(p, name) }
            shaderModes[mode] = ShaderMode(
                program: p, time: loc("uTime"), bass: loc("uBass"), mid: loc("uMid"),
                treble: loc("uTreble"), beat: loc("uBeat"), beatStrength: loc("uBeatStrength"),
                level: loc("uLevel"), resolution: loc("uResolution"), idle: loc("uIdle"),
                bands: loc("uBands[0]"), eventKind: loc("uEventKind"), eventAge: loc("uEventAge"),
                active: loc("uActive"), beats: loc("uBeats"), peaks: loc("uPeaks[0]"),
                scroll: loc("uScroll"), clock: loc("uClock"))
            if mode == .band {
                uBandParts = loc("uParts[0]"); uBandHits = loc("uHits"); uBandPluck = loc("uPluck")
                uBandVocal = loc("uVocal"); uBandKeys = loc("uKeys[0]")
                uBandX = loc("uMX[0]"); uBandWalk = loc("uWalk[0]"); uBandFace = loc("uFace[0]")
                uBandPlay = loc("uPlay[0]"); uBandHome = loc("uHome[0]")
                uBandLineupMask = loc("uLineupMask"); uBandPresent = loc("uPresent[0]")
                uBandGenre = loc("uGenre")
                uBandGenrePrev = loc("uGenrePrev")
                uBandGenreMix = loc("uGenreMix")
                uBandPrimary = loc("uPrimary"); uBandSecondary = loc("uSecondary"); uBandAccent = loc("uAccent")
                uBandBassReact = loc("uBassReactivity"); uBandTrebleReact = loc("uTrebleReactivity")
                uBandBeatSharp = loc("uBeatSharpness"); uBandStrobe = loc("uStrobeIntensity")
            }
            if mode == .hamster {
                uSprites = loc("uSprites"); uSpriteKinds = loc("uSpriteKinds"); uSpriteCell = loc("uSpriteCell")
                uSpriteClock = loc("uSpriteClock")
                uSpriteFirst = loc("uSpriteFirst[0]"); uSpriteFrames = loc("uSpriteFrames[0]")
                uSpriteDelay = loc("uSpriteDelay[0]")
            }
        }
    }

    func makeProgram(vs: String, fs: String, _ label: String) -> GLuint {
        makeGLProgram(vs: vs, fs: fs, label)
    }

    private func compileShader(type: GLenum, source: String, _ label: String) -> GLuint {
        let s = glCreateShader(type)
        var src = (source as NSString).utf8String
        var srcs: [UnsafePointer<GLchar>?] = [src]
        glShaderSource(s, 1, &srcs, nil)
        glCompileShader(s)
        var status: GLint = 0
        glGetShaderiv(s, GLenum(GL_COMPILE_STATUS), &status)
        if status == 0 {
            var logLen: GLint = 0
            glGetShaderiv(s, GLenum(GL_INFO_LOG_LENGTH), &logLen)
            var log = [GLchar](repeating: 0, count: Int(max(logLen, 1)))
            glGetShaderInfoLog(s, logLen, nil, &log)
            let msg = String(cString: log)
            NSLog("Compile error (\(label)): \(msg)")
        }
        return s
    }

    deinit {
        // GL cleanup is unsafe after context dies; skip.
    }
}

// MARK: - Geometry types

struct TunnelVertex {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
}

struct ParticleVertex {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
    var size: Float
    var seed: Float
    var radius: Float
    var bandIdx: Float

    static func makeRandom() -> ParticleVertex {
        let u = Float.random(in: 0..<1)
        let v = Float.random(in: 0..<1)
        let theta = u * 2 * .pi
        let phi = acos(2 * v - 1)
        let baseR: Float = 1.4 + powf(Float.random(in: 0..<1), 1.4) * 4.6
        let sx = sinf(phi) * cosf(theta)
        let sy = cosf(phi)
        let sz = sinf(phi) * sinf(theta)

        let t = min(1.0, baseR / 6.0)
        let hot = SIMD3<Float>(1.0, 0.17, 0.84)
        let mid = SIMD3<Float>(0.54, 0.30, 1.0)
        let cold = SIMD3<Float>(0.17, 0.95, 1.0)
        let col: SIMD3<Float> = (t < 0.5)
            ? hot + (mid - hot) * (t * 2)
            : mid + (cold - mid) * ((t - 0.5) * 2)
        let size: Float = (0.6 + Float.random(in: 0..<1.8)) * (1.2 - t * 0.6)
        let seed = Float.random(in: 0..<1)
        let bandIdx = Float.random(in: 0..<1)
        // spherical distribution — no axis squash so the galaxy fills the sphere
        return ParticleVertex(
            position: SIMD3<Float>(sx * baseR, sy * baseR, sz * baseR),
            color: col,
            size: size,
            seed: seed,
            radius: baseR,
            bandIdx: bandIdx
        )
    }
}

let particleCount = 4000

// MARK: - Matrix helpers

private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    return a + (b - a) * t
}

/// Compiles and links a shader program. Shared by the renderer and the
/// machine mode.
func makeGLProgram(vs: String, fs: String, _ label: String) -> GLuint {
    let v = compileGLShader(type: GLenum(GL_VERTEX_SHADER), source: vs, "\(label).vs")
    let f = compileGLShader(type: GLenum(GL_FRAGMENT_SHADER), source: fs, "\(label).fs")
    let p = glCreateProgram()
    glAttachShader(p, v)
    glAttachShader(p, f)
    glLinkProgram(p)
    var status: GLint = 0
    glGetProgramiv(p, GLenum(GL_LINK_STATUS), &status)
    if status == 0 {
        var logLen: GLint = 0
        glGetProgramiv(p, GLenum(GL_INFO_LOG_LENGTH), &logLen)
        var log = [GLchar](repeating: 0, count: Int(max(logLen, 1)))
        glGetProgramInfoLog(p, logLen, nil, &log)
        NSLog("Link error (\(label)): \(String(cString: log))")
    }
    glDeleteShader(v)
    glDeleteShader(f)
    return p
}

func compileGLShader(type: GLenum, source: String, _ label: String) -> GLuint {
    let s = glCreateShader(type)
    var src = (source as NSString).utf8String
    var srcs: [UnsafePointer<GLchar>?] = [src]
    glShaderSource(s, 1, &srcs, nil)
    glCompileShader(s)
    var status: GLint = 0
    glGetShaderiv(s, GLenum(GL_COMPILE_STATUS), &status)
    if status == 0 {
        var logLen: GLint = 0
        glGetShaderiv(s, GLenum(GL_INFO_LOG_LENGTH), &logLen)
        var log = [GLchar](repeating: 0, count: Int(max(logLen, 1)))
        glGetShaderInfoLog(s, logLen, nil, &log)
        NSLog("Compile error (\(label)): \(String(cString: log))")
    }
    return s
}

func ortho(left: GLfloat, right: GLfloat, bottom: GLfloat, top: GLfloat, near: GLfloat, far: GLfloat) -> [GLfloat] {    let rl = right - left
    let tb = top - bottom
    let fn = far - near
    return [
        2 / rl, 0, 0, 0,
        0, 2 / tb, 0, 0,
        0, 0, -2 / fn, 0,
        -(right + left) / rl, -(top + bottom) / tb, -(far + near) / fn, 1
    ]
}

func perspective(fovY: GLfloat, aspect: GLfloat, near: GLfloat, far: GLfloat) -> [GLfloat] {
    let f = 1 / tanf(fovY * .pi / 180 / 2)
    return [
        f / aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (far + near) / (near - far), -1,
        0, 0, (2 * far * near) / (near - far), 0
    ]
}