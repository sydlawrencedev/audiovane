import Foundation
import simd

/// Everything that distinguishes one genre from another visually: the colour
/// palette the band shader uses, which of the six walker slots are typical for
/// the genre, and the motion profile that controls how sharp / smooth the
/// music drives the visuals.
struct GenreVisual {
    let genre: Genre

    /// Display name for the picker. Kept on the visual so the picker can show
    /// "Classical (orchestra)" later without touching the Genre enum.
    let displayName: String

    /// Hint string the band fragment shader can switch on to draw the right
    /// room (curtain vs neon vs brick wall vs nothing). The shader gets the raw
    /// Genre enum value and decides.
    let roomHint: String

    /// Triplet of (r, g, b) art-pipeline colours. The shader uses them for the
    /// curtain, instruments, lighting and clothing.
    let primary: SIMD3<Float>
    let secondary: SIMD3<Float>
    let accent: SIMD3<Float>

    /// Which walker slots are typical for this genre. Musicians whose slot
    /// isn't in the lineup walk off immediately on a genre change; musicians
    /// whose slot IS in the lineup get the 10s grace period to be re-confirmed
    /// by the new song.
    let lineup: Set<WalkerSlot>

    /// How reactive the visuals are to bass/mid/treble and beats. The shader
    /// reads these and scales the audio-driven deformation accordingly.
    let bassReactivity: Float      // 0 = ignores bass, 1 = full kick
    let trebleReactivity: Float    // 0 = ignores hats, 1 = full hi-hat sheen
    let beatSharpness: Float        // 0 = smooth pulse, 1 = hard hit

    /// Synth-pop: 0, orchestra: 0, jazz: 0, electronic: 1. Drives strobe overlays
    /// and similar beat-locked effects.
    let strobeIntensity: Float

    /// Convenience — true when the genre has no actual human musicians
    /// (electronic DJ booth, ambient soundscape). The walker list is unused
    /// in that case and the renderer just shows the room + spectrum.
    var noMusicians: Bool { lineup.isEmpty }
}

extension GenreVisual {
    /// One preset per genre. The palettes are designed to read well against the
    /// shared velvet-stage backdrop. Numbers are 0–1 floats; the shader scales
    /// to its art-pixel range.
    static let all: [GenreVisual] = [
        // 1. Classical — concert hall. Warm gold / cream / deep red. Strings +
        // keys + two singers. The most "symphony" of the lineups.
        GenreVisual(
            genre: .classical,
            displayName: "Classical",
            roomHint: "hall",
            primary:   SIMD3<Float>(0.95, 0.78, 0.32),  // gold valance
            secondary: SIMD3<Float>(0.55, 0.20, 0.18),  // velvet red
            accent:    SIMD3<Float>(0.98, 0.92, 0.78),  // warm skin / sheet music
            lineup: [.bass, .guitar, .keys, .femaleSinger, .maleSinger], // strings sit on guitar slot
            bassReactivity: 0.35,
            trebleReactivity: 0.7,  // strings shimmer
            beatSharpness: 0.2,     // smooth — no sharp kick
            strobeIntensity: 0
        ),

        // 2. Electronic — DJ booth. Cyan / magenta neon, mostly the DJ figure +
        // decks. No real "band"; the lineup is just the DJ (mapped to keys
        // since the DJ is at the keys position on stage).
        GenreVisual(
            genre: .electronic,
            displayName: "Electronic",
            roomHint: "booth",
            primary:   SIMD3<Float>(0.18, 0.95, 1.00),  // cyan
            secondary: SIMD3<Float>(1.00, 0.18, 0.85),  // magenta
            accent:    SIMD3<Float>(0.05, 0.05, 0.10),  // near-black
            lineup: [.keys],  // DJ on the keys position
            bassReactivity: 1.0,  // kick drives the room
            trebleReactivity: 0.6,
            beatSharpness: 1.0,   // hard punch on every kick
            strobeIntensity: 1.0  // strobe on every beat
        ),

        // 3. Rock — the existing theatre. Red / black / leather.
        GenreVisual(
            genre: .rock,
            displayName: "Rock",
            roomHint: "theatre",
            primary:   SIMD3<Float>(0.62, 0.10, 0.14),  // velvet red
            secondary: SIMD3<Float>(0.05, 0.05, 0.07),  // near-black
            accent:    SIMD3<Float>(0.95, 0.75, 0.25),  // gold valance
            lineup: [.drums, .bass, .guitar, .keys, .femaleSinger, .maleSinger],
            bassReactivity: 0.85,
            trebleReactivity: 0.55,
            beatSharpness: 0.85,
            strobeIntensity: 0.3
        ),

        // 4. Pop — clean studio. Pink / purple, full band.
        GenreVisual(
            genre: .pop,
            displayName: "Pop",
            roomHint: "studio",
            primary:   SIMD3<Float>(0.95, 0.55, 0.85),  // pink
            secondary: SIMD3<Float>(0.60, 0.40, 0.95),  // purple
            accent:    SIMD3<Float>(0.98, 0.98, 0.95),  // bright white
            lineup: [.drums, .bass, .guitar, .keys, .femaleSinger, .maleSinger],
            bassReactivity: 0.7,
            trebleReactivity: 0.7,
            beatSharpness: 0.5,
            strobeIntensity: 0.2
        ),

        // 5. Hip-Hop — urban. Gold chain backdrop, low rider. MC at the mic
        // and a DJ at the keys. Drums and bass are the spine.
        GenreVisual(
            genre: .hiphop,
            displayName: "Hip-Hop",
            roomHint: "urban",
            primary:   SIMD3<Float>(0.95, 0.78, 0.18),  // gold
            secondary: SIMD3<Float>(0.10, 0.07, 0.05),  // near-black
            accent:    SIMD3<Float>(0.80, 0.20, 0.15),  // rust red
            lineup: [.drums, .bass, .keys, .maleSinger],  // MC at front
            bassReactivity: 1.0,    // 808s drive everything
            trebleReactivity: 0.4,
            beatSharpness: 0.95,
            strobeIntensity: 0.0
        ),

        // 6. Jazz — smoky club. Amber / cream / brown. Sparse lineup, swinging
        // motion.
        GenreVisual(
            genre: .jazz,
            displayName: "Jazz",
            roomHint: "smoky",
            primary:   SIMD3<Float>(0.85, 0.65, 0.35),  // warm amber
            secondary: SIMD3<Float>(0.45, 0.25, 0.18),  // brown
            accent:    SIMD3<Float>(0.95, 0.85, 0.65),  // cream
            lineup: [.bass, .guitar, .keys, .femaleSinger],  // upright bass sits on bass slot, no keys
            bassReactivity: 0.5,
            trebleReactivity: 0.6,   // ride cymbal shimmer
            beatSharpness: 0.25,    // swing, not straight
            strobeIntensity: 0.0
        ),

        // 7. Blues — bar. Warm wood, neon BAR. Three people: guitar, singer,
        // and a harmonica player mapped to femaleSinger for variety.
        GenreVisual(
            genre: .blues,
            displayName: "Blues",
            roomHint: "bar",
            primary:   SIMD3<Float>(0.90, 0.50, 0.20),  // amber
            secondary: SIMD3<Float>(0.35, 0.15, 0.10),  // dark wood
            accent:    SIMD3<Float>(0.80, 0.10, 0.10),  // neon red
            lineup: [.guitar, .maleSinger, .femaleSinger],  // guitar, singer, harp
            bassReactivity: 0.55,
            trebleReactivity: 0.5,
            beatSharpness: 0.4,
            strobeIntensity: 0.0
        ),

        // 8. Country — porch. Wood, daylight. Acoustic guitar, fiddle, singer.
        GenreVisual(
            genre: .country,
            displayName: "Country",
            roomHint: "porch",
            primary:   SIMD3<Float>(0.78, 0.55, 0.30),  // earth brown
            secondary: SIMD3<Float>(0.45, 0.30, 0.18),  // darker wood
            accent:    SIMD3<Float>(0.95, 0.88, 0.55),  // warm cream
            lineup: [.guitar, .bass, .maleSinger, .femaleSinger],  // guitar, upright bass, singers
            bassReactivity: 0.5,
            trebleReactivity: 0.7,
            beatSharpness: 0.6,
            strobeIntensity: 0.0
        ),

        // 9. R&B — smooth velvet. Purple / gold / pink. Full band with two
        // backup singers.
        GenreVisual(
            genre: .rnb,
            displayName: "R&B",
            roomHint: "velvet",
            primary:   SIMD3<Float>(0.55, 0.20, 0.55),  // purple
            secondary: SIMD3<Float>(0.90, 0.70, 0.20),  // gold
            accent:    SIMD3<Float>(0.95, 0.65, 0.85),  // pink
            lineup: [.drums, .bass, .guitar, .keys, .femaleSinger, .maleSinger],
            bassReactivity: 0.8,
            trebleReactivity: 0.5,
            beatSharpness: 0.5,
            strobeIntensity: 0.15
        ),

        // 10. Ambient — no stage, no band. Just sound-as-scape.
        GenreVisual(
            genre: .ambient,
            displayName: "Ambient",
            roomHint: "void",
            primary:   SIMD3<Float>(0.70, 0.78, 0.95),  // pale blue
            secondary: SIMD3<Float>(0.95, 0.78, 0.90),  // pale pink
            accent:    SIMD3<Float>(0.95, 0.95, 0.95),  // white
            lineup: [],  // no musicians at all
            bassReactivity: 0.4,
            trebleReactivity: 0.5,
            beatSharpness: 0.0,     // no beats
            strobeIntensity: 0.0
        ),
    ]

    /// Lookup by enum case. Falls back to Rock if missing (shouldn't happen —
    /// `Genre.allCases` and `GenreVisual.all` are kept in lock-step).
    static func visual(for genre: Genre) -> GenreVisual {
        all.first { $0.genre == genre } ?? all[2]
    }
}
