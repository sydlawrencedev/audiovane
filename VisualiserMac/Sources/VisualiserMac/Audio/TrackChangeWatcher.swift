import Foundation
import QuartzCore

/// Notices track changes, including skips with no gap, from the system-wide
/// notifications Apple Music and Spotify post whenever playback changes. No
/// permission needed. Other sources (browser tabs etc.) don't post these;
/// the band falls back to detecting the silence between songs.
///
/// It also knows where in the track we are, which is the part the
/// notifications are only half good at. Both players say what is playing and
/// how long it is; neither reliably says where the playhead is, so the
/// position is worked out from when the notification arrived — with pauses
/// held still, and a seek starting the count again.
final class TrackChangeWatcher: NSObject {
    /// Bumped on every change to a different track (main thread).
    private(set) var changeCount = 0
    private(set) var nowPlaying: String?
    /// The title on its own, and who made it.
    ///
    /// Separate because the song's name is what a catalogue is asked about:
    /// "Song – Artist" is a string for a label and two fields for a lookup.
    private(set) var nowPlayingTitle: String?
    private(set) var nowPlayingArtist: String?
    /// Length of the current track, if the player reported it, and when it
    /// started (approximately: when we heard about it).
    private(set) var duration: TimeInterval?
    private(set) var startedAt: CFTimeInterval?
    private var lastTrackID: String?

    /// Whether the player says it is playing.
    ///
    /// A pause has to be held still: a position that keeps counting through
    /// a pause is a position that is wrong for the rest of the track.
    private var isPlaying = false
    /// The position at the moment the track was paused, so it can be picked
    /// up again from there.
    private var pausedAt: TimeInterval?

    override init() {
        super.init()
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(musicChanged(_:)),
                           name: Notification.Name("com.apple.Music.playerInfo"),
                           object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(spotifyChanged(_:)),
                           name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                           object: nil, suspensionBehavior: .deliverImmediately)
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func musicChanged(_ note: Notification) {
        handle(note.userInfo, idKeys: ["PersistentID", "Name"], app: "Music")
    }

    @objc private func spotifyChanged(_ note: Notification) {
        handle(note.userInfo, idKeys: ["Track ID", "Name"], app: "Spotify")
    }

    private func handle(_ info: [AnyHashable: Any]?, idKeys: [String], app: String) {
        guard let info, let id = idKeys.lazy.compactMap({ info[$0].map { "\(app):\($0)" } }).first else { return }

        let state = info["Player State"] as? String ?? ""
        let playing = state == "Playing"

        if !playing {
            // A pause, or the end of the track. Hold the position still
            // rather than letting it run on.
            if state == "Paused" {
                pause()
            }
            return
        }

        let isNewTrack = id != lastTrackID
        lastTrackID = id

        if isNewTrack {
            let title = info["Name"] as? String ?? "?"
            let artist = info["Artist"] as? String ?? "?"
            nowPlaying = "\(title) – \(artist)"
            nowPlayingTitle = title
            nowPlayingArtist = artist
            // Music: "Total Time"; Spotify: "Duration" — both milliseconds.
            let ms = (info["Total Time"] as? NSNumber) ?? (info["Duration"] as? NSNumber)
            duration = ms.map { $0.doubleValue / 1000 }
            NSLog("[TRACK] \(app) now playing: \(nowPlaying!)")
            // These only post on a change, so even the first one after launch is
            // usually a skip. (Resuming a paused track can count once; harmless.)
            changeCount += 1
        }

        // The position. A notification for a track that is already playing
        // is a seek, and a seek cannot be located from the notifications
        // alone — so the count starts again from where it is now rather than
        // carrying on from a place the playhead has left.
        //
        // Some players do put the position in the notification, and when
        // they do it is exact, so it is used when it is there.
        let now = CACurrentMediaTime()
        if let reported = reportedPosition(info) {
            startedAt = now - reported
            pausedAt = nil
        } else if isNewTrack {
            startedAt = now
            pausedAt = nil
        } else if let paused = pausedAt {
            // Picking up again where it was paused.
            startedAt = now - paused
            pausedAt = nil
        } else {
            // A seek. The playhead has moved and the notifications do not
            // say where to.
            startedAt = now
        }
        isPlaying = true
    }

    /// The position the player reported, in seconds, if it reported one.
    ///
    /// The key names differ between the two players and have changed over
    /// the years, so a few are tried. None of them is guaranteed to be
    /// there — which is why the position is worked out from the clock when
    /// it is not.
    private func reportedPosition(_ info: [AnyHashable: Any]) -> TimeInterval? {
        for key in ["Position", "Elapsed Time", "Playback Position"] {
            guard let number = info[key] as? NSNumber else { continue }
            // Milliseconds, like the duration.
            let seconds = number.doubleValue / 1000
            if seconds > 0, seconds < 24 * 60 * 60 { return seconds }
        }
        return nil
    }

    /// Whether the player says it is playing right now.
    ///
    /// The title and the artist are kept when playback stops, so that the
    /// chrome can still say what was playing. That is right for the chrome
    /// and wrong for anything that claims a piece of audio is that track, so
    /// this is here for the rest of the app to ask.
    var playing: Bool { isPlaying }

    /// The playhead, in seconds from the start of the track.
    ///
    /// Zero when nothing is known: there is no position for a browser tab or
    /// a film, and a made-up one would be worse than none.
    var position: TimeInterval {
        if let pausedAt { return pausedAt }
        guard isPlaying, let startedAt else { return 0 }
        return max(0, CACurrentMediaTime() - startedAt)
    }

    /// Whether the position means anything.
    ///
    /// False for everything that is not Apple Music or Spotify: the position
    /// is zero because it is unknown, and a shader drawing a progress bar
    /// needs to know that zero means "no idea" rather than "the beginning".
    var positionIsKnown: Bool {
        if pausedAt != nil { return true }
        return isPlaying && startedAt != nil
    }

    /// Holds the position still, for a pause.
    private func pause() {
        guard isPlaying else { return }
        pausedAt = position
        isPlaying = false
    }
}
