import Foundation

/// Works out what song is playing, and what genre it is.
///
/// Apple Music and Spotify both post a notification when the track changes,
/// with the title and the artist in it. That is enough to look the song up in
/// Apple's public catalogue, which knows what genre it is — so The Band can
/// be the right shape of room for the music rather than a guess made from
/// the waveform.
///
/// It is a courtesy, not a dependency. No music app posting notifications, no
/// network, no match: the app falls back to the audio heuristic it has
/// always used, and nothing about the visualiser stops working.
///
/// Only the title and the artist are looked up. Nothing about the audio
/// leaves the machine.
actor SongIdentifier {
    /// One identifier for the app: the song it last worked out.
    static let shared = SongIdentifier()

    /// A song the app recognised.
    struct Song: Equatable {
        /// The song, as the music app named it.
        let title: String
        /// Who made it.
        let artist: String
        /// The genre, as the catalogue has it.
        let catalogueGenre: String
        /// The same genre, as one of the ten The Band can show. Nil when the
        /// catalogue's name means nothing here — which is most of them, and
        /// is not a failure: the song is still known.
        let genre: Genre?
    }

    /// One result from the catalogue's search.
    ///
    /// Both names are optional because the search answers with every kind of
    /// thing — a song, an album, a video of a song — and only some of them
    /// have a track and an artist.
    private struct Result: Decodable {
        let trackName: String?
        let artistName: String?
        let primaryGenreName: String?
        let collectionName: String?
    }

    private struct Search: Decodable {
        let results: [Result]
    }

    /// Apple's public catalogue search. No key, no account: it is the same
    /// search the iTunes Store does, and it answers with JSON.
    ///
    /// It is asked about songs only, and it is asked about a name — never
    /// about the music itself.
    private static let searchURL = URL(string: "https://itunes.apple.com/search")!

    /// How long to wait before giving up. The genre is a nicety: a slow
    /// answer is not worth holding anything up for.
    private static let timeout: TimeInterval = 6

    /// The song the app last worked out.
    private(set) var current: Song?

    /// Looks a song up by name.
    ///
    /// Returns nil when the catalogue doesn't know it, when the answer is
    /// about a different song, or when the network isn't there. All three
    /// mean the same thing to the caller: no answer, carry on as before.
    func identify(title: String, artist: String) async -> Song? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        guard var components = URLComponents(url: Self.searchURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(cleanTitle) \(cleanArtist)"),
            // Songs only, and a handful of them. Setting the query items
            // replaces the lot, so everything the search needs has to be in
            // here: without the entity it answers with albums and videos
            // too, and without the limit it answers with thousands.
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return nil
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        guard let search = try? JSONDecoder().decode(Search.self, from: data) else {
            return nil
        }

        guard let best = search.results
            .map({ ($0, score($0, title: cleanTitle, artist: cleanArtist)) })
            .filter({ $0.1 > 0 })
            .max(by: { $0.1 < $1.1 })?.0 else {
            return nil
        }

        let catalogueGenre = best.primaryGenreName ?? ""
        let song = Song(
            title: best.trackName ?? cleanTitle,
            artist: best.artistName ?? cleanArtist,
            catalogueGenre: catalogueGenre,
            genre: GenreMapping.genre(for: catalogueGenre))
        current = song
        return song
    }

    /// How well a catalogue result matches the song we were told about.
    ///
    /// Zero means not this song, and zero means no answer at all: both the
    /// artist and the title have to be right. The catalogue will happily
    /// answer "Me and Your Mama" for "Redbone" — same artist, different
    /// song — and a wrong song means a wrong genre on the stage.
    private func score(_ result: Result, title: String, artist: String) -> Int {
        guard let foundTitleRaw = result.trackName,
              let foundArtistRaw = result.artistName else { return 0 }
        let foundTitle = foundTitleRaw.lowercased()
        let foundArtist = foundArtistRaw.lowercased()
        let wantedTitle = title.lowercased()
        let wantedArtist = artist.lowercased()
        guard !foundTitle.isEmpty, !foundArtist.isEmpty else { return 0 }

        var total = 0

        // The artist has to be right: the same song title is on a dozen
        // records by a dozen different people.
        if !wantedArtist.isEmpty {
            if foundArtist == wantedArtist { total += 4 }
            else if foundArtist.contains(wantedArtist) || wantedArtist.contains(foundArtist) {
                total += 2
            } else {
                return 0
            }
        }

        // And so does the title.
        if foundTitle == wantedTitle {
            total += 4
        } else if foundTitle.contains(wantedTitle) || wantedTitle.contains(foundTitle) {
            total += 2
        } else {
            // A live version, a remix or a different edit has a different
            // name and usually the same genre. Count the words they share —
            // and only the ones long enough to mean something, because "in"
            // is in a great many titles that have nothing to do with each
            // other.
            let words = wantedTitle.split(separator: " ").map(String.init)
                .filter { $0.count >= 3 }
            let shared = words.filter { foundTitle.contains($0) }.count
            guard shared >= 2 else { return 0 }
            total += 1
        }
        return total
    }
}
