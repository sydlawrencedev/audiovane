import Foundation

// MARK: - Vibscape identity

/// Identifies something the app can draw: either a vibscape built into the binary,
/// or a custom shader the user added.
///
/// `Vibscape` is a compile-time enum, so a custom vibscape can't be a case
/// of it. This is the dynamic identifier that stands in for both, and it is
/// what the UI, the renderer and the saved preference all speak.
enum VibscapeID: Hashable, Identifiable {
    case builtin(Vibscape)
    case custom(String)

    var id: String { rawValue }

    /// Stable string form, used for `UserDefaults` and the analytics
    /// `vibscape` property. The `custom:` prefix keeps a custom vibscape from ever
    /// colliding with a built-in that happens to share its slug.
    var rawValue: String {
        switch self {
        case .builtin(let m): return m.rawValue
        case .custom(let slug): return "custom:" + slug
        }
    }

    init?(rawValue: String) {
        if rawValue.hasPrefix(Self.customPrefix) {
            self = .custom(String(rawValue.dropFirst(Self.customPrefix.count)))
        } else if let m = Vibscape(rawValue: rawValue) {
            self = .builtin(m)
        } else {
            return nil
        }
    }

    private static let customPrefix = "custom:"

    /// The built-in this wraps, or nil for a custom vibscape.
    var builtin: Vibscape? {
        if case .builtin(let m) = self { return m }
        return nil
    }

    var isCustom: Bool { builtin == nil }

    /// True for Auto Scan, which is the one vibscape that isn't a scene.
    var isAutoScan: Bool { self == .builtin(.autoScan) }

    /// True for The Band, which behaves differently from the other scenes
    /// enough that several call sites ask about it by name.
    var isBand: Bool { self == .builtin(.band) }

    /// The id without its prefix — the built-in's raw value, or the custom
    /// vibscape's slug.
    var slug: String {
        switch self {
        case .builtin(let v): return v.rawValue
        case .custom(let s): return s
        }
    }
}

// MARK: - The vibscape itself

/// One user-written vibscape: a name and a fragment shader.
///
/// The shader is a *body*, not a whole shader — the app prepends
/// `FunShaders.prelude`, which declares the uniforms, the signed-distance
/// helpers and `main()`'s surroundings. The user's job is to write a
/// `vec3 render(vec2 p, float t)` and hand it back.
struct CustomVibscape: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    /// Who made it. Free text, because someone else's vibscape should be
    /// credited to them.
    var author: String
    /// Where to find more, if there's somewhere. Optional — most vibscapes
    /// won't have one.
    var url: String?
    var shader: String
    /// Whether it shows in the vibscape list and takes part in Auto Scan. Off
    /// means "kept, but out of the way" — the same relationship the View All
    /// panel gives the built-ins.
    var enabled: Bool
    var modified: Date

    var modeID: VibscapeID { .custom(id) }

    /// Plain-language summary for the View All panel.
    var subtitle: String {
        let lines = shader.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return "\(lines.count) lines"
    }

    /// Decoding has to tolerate vibscapes saved before the author and URL
    /// existed, and before the fields were renamed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shader = try c.decode(String.self, forKey: .shader)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url)
    }

    init(id: String, name: String, author: String, url: String?, shader: String,
         enabled: Bool, modified: Date) {
        self.id = id
        self.name = name
        self.author = author
        self.url = url
        self.shader = shader
        self.enabled = enabled
        self.modified = modified
    }
}

// MARK: - The vibscape list

/// Who made the vibscapes that ship with the app.
enum VibscapeMetadata {
    static let author = "Minith Labs"
    static let url = "https://minithlabs.com"
}

/// One row in the vibscape list, whether it came with the app or the user wrote
/// it. The UI only ever works with this, so a custom vibscape is a first-class
/// citizen rather than a special case bolted on beside the built-ins.
struct VibscapeEntry: Identifiable, Hashable {
    var id: VibscapeID
    var title: String
    /// Who made it. Shown on hover in the View All panel.
    var author: String
    /// Where to find more about it, if there's a somewhere.
    var url: String?
    /// That address as a link, if it is one.
    var link: URL? {
        guard let url, !url.isEmpty else { return nil }
        // A vibscape's address might be written without the scheme, so
        // "minithlabs.com" still works.
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return URL(string: url)
        }
        return URL(string: "https://" + url)
    }
    /// The mark in the list: the keyboard shortcut that picks this vibscape.
    var glyph: String
    /// The key that picks this vibscape, if it has one. It follows the vibscape's
    /// place in the list, so rearranging the list rearranges the keys.
    var shortcut: Character?
    /// A short line under the title.
    var subtitle: String?
    var isCustom: Bool
    var isEnabled: Bool
    /// True for the "make your own" card at the end of the list.
    var isNewVibscapeCard: Bool = false

    init(builtin mode: Vibscape, shortcut: Character?) {
        self.id = .builtin(mode)
        // Names are shown in capitals throughout, but kept as they were
        // written, so editing a vibscape doesn't shout at whoever typed it.
        self.title = mode.displayName.uppercased()
        self.author = VibscapeMetadata.author
        self.url = VibscapeMetadata.url
        self.shortcut = shortcut
        self.glyph = shortcut.map(String.init) ?? ""
        self.subtitle = nil
        self.isCustom = false
        self.isEnabled = true
    }

    init(custom mode: CustomVibscape, shortcut: Character?) {
        self.id = .custom(mode.id)
        self.title = mode.name.uppercased()
        self.author = mode.author
        self.url = mode.url
        self.shortcut = shortcut
        self.glyph = shortcut.map(String.init) ?? ""
        self.subtitle = mode.subtitle
        self.isCustom = true
        self.isEnabled = mode.enabled
        self.isNewVibscapeCard = false
    }

    /// The card at the end of the list that opens the Custom Vibscape sheet.
    /// It isn't a vibscape, so most of its fields are blank — but it travels
    /// through the same list as everything else so the grid doesn't need a
    /// special case for it.
    init(newVibscapeCard: Bool) {
        self.id = .builtin(.tunnel)
        self.title = "MAKE YOUR OWN"
        self.author = ""
        self.url = nil
        self.shortcut = nil
        self.glyph = "+"
        self.subtitle = nil
        self.isCustom = false
        self.isEnabled = true
        self.isNewVibscapeCard = newVibscapeCard
    }
}

// MARK: - On-disk store

/// Custom vibscapes live as one JSON file each under
/// `~/Library/Application Support/Vibresia/Vibscapes/`.
///
/// A folder rather than one blob in `UserDefaults` because these are the one
/// thing a user is expected to hand to someone else: the files can be copied,
/// emailed, dropped into another Mac, and kept in version control. It also
/// matches the Hamsters folder, so "where do I put my own stuff" has one
/// answer in this app.
enum CustomVibscapeStore {
    static var folder: URL {
        // VIBRESIA_CUSTOM_DIR points somewhere else, for tests and for
        // demo runs that must never read a real person's vibscapes.
        if let dir = ProcessInfo.processInfo.environment["VIBRESIA_CUSTOM_DIR"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return SupportFolder.folder("Vibscapes")
    }

    static func ensureFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Every vibscape on disk, oldest first so a fresh install and a restored one
    /// list them the same way.
    static func loadAll() -> [CustomVibscape] {
        ensureFolder()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let modes: [CustomVibscape] = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(CustomVibscape.self, from: $0) }
        // A file whose slug doesn't match its filename would let two files
        // claim one id, and the second would silently never load.
        var seen = Set<String>()
        return modes.filter { seen.insert($0.id).inserted }
    }

    static func url(for id: String) -> URL {
        folder.appendingPathComponent("\(id).json")
    }

    static func save(_ mode: CustomVibscape) throws {
        ensureFolder()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(mode).write(to: url(for: mode.id), options: .atomic)
    }

    @discardableResult
    static func delete(id: String) -> Bool {
        (try? FileManager.default.removeItem(at: url(for: id))) != nil
    }

    /// Filesystem-safe slug from a display name. Falls back to a timestamp if
    /// the name is nothing but punctuation or emoji.
    static func slug(from name: String) -> String {
        let folded = name.folding(options: .diacriticInsensitive, locale: .current)
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        var slug = String(folded.lowercased().unicodeScalars.map { allowed.contains(Character($0)) ? Character($0) : "-" })
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !slug.isEmpty else {
            return "mode-" + String(Int(Date().timeIntervalSince1970))
        }
        return String(slug.prefix(48))
    }

    /// A slug that no file is using yet.
    static func uniqueSlug(from name: String) -> String {
        let base = slug(from: name)
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: url(for: candidate).path) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }
}

// MARK: - Helping content

/// The words and starter code shown in the Custom Vibscape sheet.
///
/// Kept here rather than in the view so the AI prompt, the template and the
/// validator all quote the same uniform names. If a uniform is ever renamed in
/// the prelude, this is the one place that has to change with it.
enum CustomVibscapeGuide {
    /// Uniforms and helpers the prelude hands a custom vibscape.
    static let reference = """
    Every mode is a small program written in GLSL, a language for drawing \
    pixels. You write one function:

        vec3 render(vec2 p, float t)

    `p` is the position on screen. It is centred on 0,0, and runs from about \
    -0.5 to 0.5 vertically — 0 is the middle of the screen. `t` is time in \
    seconds. What you return is the colour: three numbers from 0 to 1, for \
    red, green and blue. So `vec3(1.0, 0.0, 0.0)` is pure red.

    These are ready to use, and change with the music:

      uBass        0..1   low-end loudness, the thump
      uMid         0..1   midrange
      uTreble      0..1   highs and sparkle
      uLevel       0..1   overall loudness
      uLevelSmooth 0..1   overall loudness, eased so it doesn't flicker
      uBassSmooth  0..1   the same, for bass
      uBeatStrength 0..1  how hard the current beat hits
      uBeats             a beat counter at the detected tempo; it climbs
                         smoothly, it never jumps or runs backwards
      uBands[96]         96 numbers, low to high frequency, each 0..1
      uActive      0..1   0 in silence, eases to 1 when there is sound
      uClock             seconds since launch, keeps running in silence

    These helpers are already defined for you:

      screenP()        centred coordinates, x scaled to the window shape
      hash21(p)        random number from a position, always 0..1
      bandAt(x)        loudness at a point across the spectrum, 0..1
      rot(a)           a 2x2 rotation matrix
      sdCircle(p, r)   distance to a circle — negative inside
      sdBox(p, b)      distance to a box
      sdRoundBox(p, b, r)   a box with rounded corners
      sdSeg(p, a, b)   distance to a line between two points
      fill(d, w)       turns a distance into a filled shape, 1 inside
      aaw(s)           the right edge softness so shapes aren't jaggy
      mix, clamp, sin, cos, fract, length, dot — the usual

    To fade out in silence, multiply by `uActive` near the end.

    If you want to know what the music is actually doing right now — the
    suspected genre and instruments, the tempo, the levels — ask with
    `what_i_hear`, and write something that suits it.

    One more thing: the app tints every mode with the colour palette you pick
    in the header, so your colours come out shifted a little. That's the same
    as the built-in modes — pick a different palette in the header if you want
    to see your colours more truly.
    """

    /// Ready-to-paste prompt for someone using an AI coding assistant.
    static let agentPrompt = """
    Write a vibscape for Vibresia, a macOS app for visual worlds that move \
    with music. The output is one GLSL function, pasted into the app and \
    compiled as a fragment shader.

    Your entire answer must be a single GLSL code block containing exactly:

        vec3 render(vec2 p, float t)
        {
            // your code
        }

    Rules:
    - Write ONLY that function. No #version, no uniforms, no main(), no \
      includes, no text outside the code block.
    - Do not redeclare anything the app already declares.
    - Return a colour: vec3 with three numbers from 0 to 1.
    - `p` is centred on the screen and runs about -0.5 to 0.5 vertically.
    - `t` is seconds since launch.
    - React to the music so it visibly moves with the track.

    Already available, do not redefine:
      uniforms: uBass uMid uTreble uLevel uLevelSmooth uBassSmooth
                uBeat uBeatStrength uBands[96] uActive uBeats uClock
      helpers:  screenP() hash21(p) bandAt(x) rot(a)
                sdCircle(p,r) sdBox(p,b) sdRoundBox(p,b,r) sdSeg(p,a,b)
                fill(d,w) aaw(s)
      GLSL:     mix clamp sin cos fract length dot

    Fade gently in silence by scaling the final colour by uActive.

    Briefly describe the visual in one sentence AFTER the code block, so the \
    user knows what they are about to add.
    """

    /// The blank starting point for someone writing it by hand.
    static let starterTemplate = """
    // Your vibscape. Edit the colour, press Test.
    // Full list of uniforms and helpers: press "What's available?" below.
    vec3 render(vec2 p, float t)
    {
        // A colour that brightens with the bass.
        float pulse = 0.5 + 0.5 * sin(t * 2.0);
        float amount = uBass * 0.6 + pulse * 0.2;

        vec3 colour = vec3(1.0, 0.2, 0.8) * amount;   // pink
        colour += vec3(0.2, 0.9, 1.0) * uTreble;      // cyan on the highs

        // Fade out when there's no music.
        return colour * uActive;
    }
    """
}
