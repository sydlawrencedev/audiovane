import Foundation
import simd

/// The uniform values the app is drawing with, right now.
///
/// These are the numbers a vibscape actually gets: the levels straight off the
/// analyser, plus the clocks and smoothed values the renderer derives from them
/// (`uBeats`, `uScroll`, `uLevelSmooth`, `uPresence` and the rest). Without this
/// someone writing a vibscape has to guess the range of `uBeatStrength`, and
/// guess low — the visible effect of a wrong coefficient is "it doesn't pulse",
/// which looks identical to "it's not reacting to the music".
///
/// The renderer writes it once a frame; the MCP tools read it. It lives in its
/// own small type so the renderer doesn't have to know that anything else wants
/// it, and the tools don't have to reach into the renderer to get it.
final class LiveUniforms {

    static let shared = LiveUniforms()

    /// One reading of everything the uniforms carry.
    struct Reading {
        var bass: Float = 0
        var mid: Float = 0
        var treble: Float = 0
        var level: Float = 0
        var levelSmooth: Float = 0
        var bassSmooth: Float = 0
        var beat: Float = 0
        var beatStrength: Float = 0
        var beats: Float = 0
        var active: Float = 1
        var idle: Float = 0
        var presence: Float = 0
        var scroll: Float = 0
        var clock: Float = 0
        var bands = [Float](repeating: 0, count: 96)
        /// uBeats advances at the detected tempo, so the rate matters as much
        /// as the value: `uBeats * 0.5` looks very different at 90 bpm and 150.
        var beatsPerSecond: Float = 2
        var bpm: Double = 0
        var palette: String = "NEON"
        var vibscape: String = ""
        var rms: Float = 0
        var at: Date = Date()

        /// How long ago this reading was taken.
        var age: TimeInterval { Date().timeIntervalSince(at) }

        /// Old enough that the app has probably quit.
        var isStale: Bool { age > 15 }

        /// The zeros. Declared explicitly because the initializer below stops
        /// Swift generating the memberwise one.
        init() {}

        /// Rebuilds a reading from what the running app wrote to disk.
        ///
        /// The renderer holds one of these in memory, but the MCP server is a
        /// separate process and its copy of that box is always empty — so
        /// anything the tools want to know about the live music has to come
        /// back off the disk.
        init(fromDisk state: [String: Any]) {
            func f(_ key: String) -> Float { Float(state[key] as? Double ?? 0) }
            bass = f("uBass")
            mid = f("uMid")
            treble = f("uTreble")
            level = f("uLevel")
            levelSmooth = f("uLevelSmooth")
            bassSmooth = f("uBassSmooth")
            beat = f("uBeat")
            beatStrength = f("uBeatStrength")
            beats = f("uBeats")
            active = f("uActive")
            idle = f("uIdle")
            presence = f("uPresence")
            scroll = f("uScroll")
            clock = f("uClock")
            bands = (state["uBands"] as? [Double] ?? []).map { Float($0) }
            if bands.count != 96 { bands = Array(repeating: 0, count: 96) }
            beatsPerSecond = f("beats_per_second")
            if beatsPerSecond <= 0 { beatsPerSecond = 2 }
            bpm = state["bpm"] as? Double ?? 0
            rms = f("rms")
            palette = state["palette"] as? String ?? "NEON"
            vibscape = state["vibscape"] as? String ?? ""
            at = Date(timeIntervalSince1970: state["at"] as? Double ?? 0)
        }
    }

    private let lock = NSLock()
    private var reading: Reading?

    private init() {}

    /// The current reading, or nil if the app has never drawn a frame.
    var snapshot: Reading? {
        lock.lock()
        defer { lock.unlock() }
        guard let reading, !reading.isStale else { return nil }
        return reading
    }

    /// The palette the app is showing, for previews that want to match it.
    var paletteName: String? {
        lock.lock()
        defer { lock.unlock() }
        guard let reading, !reading.isStale else { return nil }
        return reading.palette
    }

    /// Records what was just drawn. Called once a frame by the renderer.
    func record(_ value: Reading) {
        lock.lock()
        reading = value
        lock.unlock()
    }

    // MARK: - Across processes

    /// How often the live values are written to disk.
    ///
    /// The MCP server is a second copy of this binary, in its own process, so a
    /// value set here is invisible there. Same reason `what_i_hear` reads a file
    /// rather than asking the app: an agent asking "what are the uniforms
    /// right now" gets a different process's answer, or none.
    private static let writeInterval: TimeInterval = 0.2

    private static var lastWrite = Date.distantPast

    /// Writes the values where another process can read them.
    ///
    /// Throttled, because this runs inside the draw loop and writing a file
    /// sixty times a second to say something that changes slowly is a good way
    /// to make a visualiser stutter.
    static func publishToDisk(_ value: Reading, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastWrite) > writeInterval else { return }
        lastWrite = now

        let state: [String: Any] = [
            "at": now.timeIntervalSince1970,
            "uBass": value.bass,
            "uMid": value.mid,
            "uTreble": value.treble,
            "uLevel": value.level,
            "uLevelSmooth": value.levelSmooth,
            "uBassSmooth": value.bassSmooth,
            "uBeat": value.beat,
            "uBeatStrength": value.beatStrength,
            "uBeats": value.beats,
            "uActive": value.active,
            "uIdle": value.idle,
            "uPresence": value.presence,
            "uScroll": value.scroll,
            "uClock": value.clock,
            "uBands": value.bands.map { Double($0) },
            "beats_per_second": value.beatsPerSecond,
            "bpm": value.bpm,
            "rms": value.rms,
            "palette": value.palette,
            "vibscape": value.vibscape,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        // Written to a temporary file and moved into place, so a reader never
        // catches it halfway through and parse half a spectrum.
        let destination = SupportFolder.folder("uniforms.json")
        let temporary = destination.appendingPathExtension("tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? data.write(to: destination, options: .atomic)
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    /// Reads the live values written by the running app, if there are any
    /// current ones.
    static func readFromDisk() -> [String: Any]? {
        let url = SupportFolder.folder("uniforms.json")
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let age = Date().timeIntervalSince1970 - (state["at"] as? Double ?? 0)
        // Older than this and the app has quit; reporting a frozen frame as
        // live is worse than saying nothing. The app also deletes the file when
        // it quits, so this only has to cover being killed.
        return age > 4 ? nil : state
    }

    /// Removes the published file, so nothing can read it as live after the app
    /// has gone.
    static func clearPublishedFile() {
        try? FileManager.default.removeItem(at: SupportFolder.folder("uniforms.json"))
    }
}
