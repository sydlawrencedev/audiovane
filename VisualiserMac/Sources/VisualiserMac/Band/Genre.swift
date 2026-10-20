import Foundation
import simd

/// One of ten music genres the band vibscape can present. The integer raw value is
/// the `uGenre` uniform the band fragment shader switches on, so re-ordering or
/// renumbering these breaks the shader — add new genres at the end.
enum Genre: Int, CaseIterable, Identifiable {
    case classical = 0
    case electronic = 1
    case rock = 2
    case pop = 3
    case hiphop = 4
    case jazz = 5
    case blues = 6
    case country = 7
    case rnb = 8
    case ambient = 9

    var id: Int { rawValue }
    var name: String {
        switch self {
        case .classical: return "Classical"
        case .electronic: return "Electronic"
        case .rock: return "Rock"
        case .pop: return "Pop"
        case .hiphop: return "Hip-Hop"
        case .jazz: return "Jazz"
        case .blues: return "Blues"
        case .country: return "Country"
        case .rnb: return "R&B"
        case .ambient: return "Ambient"
        }
    }
    /// Tiny emoji-ish icon used in the picker; the band shader has no
    /// use for it but the UI uses it for quick scanning.
    var glyph: String {
        switch self {
        case .classical: return "♪"
        case .electronic: return "◉"
        case .rock: return "✦"
        case .pop: return "♡"
        case .hiphop: return "▰"
        case .jazz: return "♭"
        case .blues: return "♮"
        case .country: return "✿"
        case .rnb: return "❀"
        case .ambient: return "∿"
        }
    }
}

/// The six walker slots in the band. Indexed the same way as the GL uniform
/// `uMX[]` / `uPlay[]` so changes here must travel with the shader.
enum WalkerSlot: Int, CaseIterable {
    case drums = 0, bass, guitar, keys, femaleSinger, maleSinger

    /// Readable name, for logs and crash reports. The raw values are integers
    /// and "3" on stage tells nobody which instrument walked off.
    var shortName: String {
        switch self {
        case .drums: return "drums"
        case .bass: return "bass"
        case .guitar: return "guitar"
        case .keys: return "keys"
        case .femaleSinger: return "female_singer"
        case .maleSinger: return "male_singer"
        }
    }
}
