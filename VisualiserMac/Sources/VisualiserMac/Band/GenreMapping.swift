import Foundation

/// Maps a genre name from a music catalogue onto one of the ten genres The
/// Band knows how to show.
///
/// The catalogues disagree about names — Apple's "Hip-Hop/Rap" is Shazam's
/// "Hip-Hop" is the radio industry's "Rhythm & Blues" — so this is a list
/// of the names in the wild rather than an exact match, and the order
/// matters: the specific ones are looked for first, so "Pop/Rock" is pop and
/// not rock, and "Rhythm & Blues" is rhythm and blues and not the blues.
enum GenreMapping {
    /// The genre a catalogue name means, or nil if it means nothing here.
    ///
    /// The judgements in the list are worth knowing about:
    ///
    /// - "Alternative" and the indie rock family go to rock. It is the
    ///   biggest gap in the catalogue — Apple's most common genre is one
    ///   this app has no room for — and rock is the nearest of the ten.
    /// - Singer-songwriters and folk go to pop. They are not really pop, but
    ///   the alternative is country, and a quiet acoustic song in a country
    ///   room is a worse guess than one in a pop room.
    /// - Musical theatre goes to classical, because the alternative is pop
    ///   and a stage full of people singing is closer to an orchestra than
    ///   to a chorus.
    static func genre(for catalogueName: String) -> Genre? {
        let name = catalogueName.lowercased()
        guard !name.isEmpty else { return nil }
        for rule in rules where rule.needles.contains(where: { name.contains($0) }) {
            return rule.genre
        }
        return nil
    }

    private static let rules: [(needles: [String], genre: Genre)] = [
        (["hip-hop", "hip hop", "rap", "trap", "grime"], .hiphop),
        (["r&b", "rnb", "soul", "funk", "motown", "disco", "reggae",
          "dancehall", "rhythm"], .rnb),
        (["ambient", "new age", "drone", "experimental", "downtempo", "post-rock"], .ambient),
        (["electronic", "dance", "house", "techno", "trance", "dubstep",
          "drum & bass", "drum and bass", "trip-hop", "electro", "idm",
          "breakbeat", "synthwave"], .electronic),
        (["classical", "opera", "chamber", "orchestra", "symphony", "baroque",
          "musical theatre", "soundtrack"], .classical),
        (["jazz", "bebop", "big band", "swing"], .jazz),
        (["blues"], .blues),
        (["country", "honky tonk", "americana", "bluegrass"], .country),
        (["folk", "singer/songwriter", "singer-songwriter", "acoustic"], .pop),
        (["pop"], .pop),
        (["rock", "alternative", "indie", "metal", "punk", "grunge"], .rock),
    ]
}
