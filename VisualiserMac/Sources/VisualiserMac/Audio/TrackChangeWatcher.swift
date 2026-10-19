import Foundation
import QuartzCore

/// Notices track changes, including skips with no gap, from the system-wide
/// notifications Apple Music and Spotify post whenever playback changes. No
/// permission needed. Other sources (browser tabs etc.) don't post these;
/// the band falls back to detecting the silence between songs.
final class TrackChangeWatcher: NSObject {
    /// Bumped on every change to a different track (main thread).
    private(set) var changeCount = 0
    private(set) var nowPlaying: String?
    /// Length of the current track, if the player reported it, and when it
    /// started (approximately: when we heard about it).
    private(set) var duration: TimeInterval?
    private(set) var startedAt: CFTimeInterval?
    private var lastTrackID: String?

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
        guard let info, info["Player State"] as? String == "Playing",
              let id = idKeys.lazy.compactMap({ info[$0].map { "\(app):\($0)" } }).first,
              id != lastTrackID else { return }
        lastTrackID = id
        let title = info["Name"] as? String ?? "?"
        let artist = info["Artist"] as? String ?? "?"
        nowPlaying = "\(title) – \(artist)"
        // Music: "Total Time"; Spotify: "Duration" — both milliseconds.
        let ms = (info["Total Time"] as? NSNumber) ?? (info["Duration"] as? NSNumber)
        duration = ms.map { $0.doubleValue / 1000 }
        startedAt = CACurrentMediaTime()
        NSLog("[TRACK] \(app) now playing: \(nowPlaying!)")
        // These only post on a change, so even the first one after launch is
        // usually a skip. (Resuming a paused track can count once; harmless.)
        changeCount += 1
    }
}
