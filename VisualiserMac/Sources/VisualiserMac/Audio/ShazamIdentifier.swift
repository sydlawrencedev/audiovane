import AVFoundation
import Foundation
import ShazamKit

/// Identifies the song that is playing by listening to it.
///
/// ShazamKit turns a few seconds of sound into a signature and asks Shazam's
/// catalogue what that signature is. It works with anything that makes a
/// sound — a music app, a browser, a film — rather than only with the
/// players that post notifications, which is why it is worth having
/// alongside the lookup by name.
///
/// Two things make it different from the lookup by name, and both are why
/// this is behind a flag:
///
/// - Matching against Shazam's catalogue needs the ShazamKit capability
///   enabled on the app's identifier, and the entitlement that comes with it.
///   Apple has not always issued that entitlement for apps signed with a
///   Developer ID certificate rather than a provisioning profile, which is
///   how this app is signed. The failure is `SHErrorCodeMatchAttemptFailed`,
///   error 202, and it means "not allowed" rather than "not found".
/// - The signature is sent to Apple. It is not the audio — it is a
///   fingerprint of it, one way, and it cannot be turned back into sound —
///   but it does say what was playing.
///
/// `--shazam-spike` runs one match and says what happened, which is how the
/// first of those two gets settled.
actor ShazamIdentifier {
    /// A song Shazam recognised.
    struct Match: Equatable {
        let title: String
        let artist: String
        /// The genres the catalogue has for it, which is what the band's
        /// stage is chosen from.
        let genres: [String]
    }

    /// What a match attempt came back with.
    enum Outcome: Equatable {
        case matched(Match)
        case noMatch
        /// The catalogue was asked and said no.
        case failed(String)
    }

    /// How much audio a signature is made from.
    ///
    /// ShazamKit needs a few seconds to say anything useful: less and the
    /// signature is too thin to match, and the app's ring buffer holds about
    /// five and a half seconds.
    static let seconds: Double = 4.0

    /// Matches a stretch of audio against the catalogue.
    func match(_ buffer: AVAudioPCMBuffer) async -> Outcome {
        do {
            let generator = SHSignatureGenerator()
            try generator.append(buffer, at: nil)
            let signature = generator.signature()

            let session = SHSession()
            switch await session.result(from: signature) {
            case .match(let match):
                guard let item = match.mediaItems.first else { return .noMatch }
                return .matched(Match(
                    title: item.title ?? "",
                    artist: item.artist ?? "",
                    genres: item.genres))
            case .noMatch:
                return .noMatch
            case .error(let error, _):
                // 202 is the one that means the app wasn't allowed to ask.
                let code = (error as NSError).code
                return .failed("error \(code): \(error.localizedDescription)")
            }
        } catch {
            return .failed("could not sign the audio: \(error.localizedDescription)")
        }
    }
}
