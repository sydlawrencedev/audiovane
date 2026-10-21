import Foundation

// MARK: - Vibescape identity

/// Identifies something the app can draw: either a vibescape built into the binary,
/// or a custom shader the user added.
///
/// `Vibescape` is a compile-time enum, so a custom vibescape can't be a case
/// of it. This is the dynamic identifier that stands in for both, and it is
/// what the UI, the renderer and the saved preference all speak.
enum VibescapeID: Hashable, Identifiable {
    case builtin(Vibescape)
    case custom(String)

    var id: String { rawValue }

    /// Stable string form, used for `UserDefaults` and the analytics
    /// `vibescape` property. The `custom:` prefix keeps a custom vibescape from ever
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
        } else if let m = Vibescape(rawValue: rawValue) {
            self = .builtin(m)
        } else {
            return nil
        }
    }

    private static let customPrefix = "custom:"

    /// The built-in this wraps, or nil for a custom vibescape.
    var builtin: Vibescape? {
        if case .builtin(let m) = self { return m }
        return nil
    }

    var isCustom: Bool { builtin == nil }

    /// True for Auto Scan, which is the one vibescape that isn't a scene.
    var isAutoScan: Bool { self == .builtin(.autoScan) }

    /// True for The Band, which behaves differently from the other scenes
    /// enough that several call sites ask about it by name.
    var isBand: Bool { self == .builtin(.band) }

    /// The id without its prefix — the built-in's raw value, or the custom
    /// vibescape's slug.
    var slug: String {
        switch self {
        case .builtin(let v): return v.rawValue
        case .custom(let s): return s
        }
    }
}

// MARK: - The vibescape itself

/// One user-written vibescape: a name and a fragment shader.
///
/// The shader is a *body*, not a whole shader — the app prepends
/// `FunShaders.prelude`, which declares the uniforms, the signed-distance
/// helpers and `main()`'s surroundings. The user's job is to write a
/// `vec3 render(vec2 p, float t)` and hand it back.
struct CustomVibescape: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    /// Who made it. Free text, because someone else's vibescape should be
    /// credited to them.
    var author: String
    /// Where to find more, if there's somewhere. Optional — most vibescapes
    /// won't have one.
    var url: String?
    var shader: String
    /// Whether it shows in the vibescape list and takes part in Auto Scan. Off
    /// means "kept, but out of the way" — the same relationship the View All
    /// panel gives the built-ins.
    var enabled: Bool
    var modified: Date

    var modeID: VibescapeID { .custom(id) }

    /// Plain-language summary for the View All panel.
    var subtitle: String {
        let lines = shader.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return "\(lines.count) lines"
    }

    /// Decoding has to tolerate vibescapes saved before the author and URL
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

// MARK: - The vibescape list

/// Who made the vibescapes that ship with the app.
enum VibescapeMetadata {
    static let author = "Minith Labs"
    static let url = "https://minithlabs.com"
}

/// One row in the vibescape list, whether it came with the app or the user wrote
/// it. The UI only ever works with this, so a custom vibescape is a first-class
/// citizen rather than a special case bolted on beside the built-ins.
struct VibescapeEntry: Identifiable, Hashable {
    var id: VibescapeID
    var title: String
    /// Who made it. Shown on hover in the View All panel.
    var author: String
    /// Where to find more about it, if there's a somewhere.
    var url: String?
    /// That address as a link, if it is one.
    var link: URL? {
        guard let url, !url.isEmpty else { return nil }
        // A vibescape's address might be written without the scheme, so
        // "minithlabs.com" still works.
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return URL(string: url)
        }
        return URL(string: "https://" + url)
    }
    /// The mark in the list: the keyboard shortcut that picks this vibescape.
    var glyph: String
    /// The key that picks this vibescape, if it has one. It follows the vibescape's
    /// place in the list, so rearranging the list rearranges the keys.
    var shortcut: Character?
    /// A short line under the title.
    var subtitle: String?
    var isCustom: Bool
    var isEnabled: Bool
    /// True for the "make your own" card at the end of the list.
    var isNewVibescapeCard: Bool = false

    init(builtin mode: Vibescape, shortcut: Character?) {
        self.id = .builtin(mode)
        // Names are shown in capitals throughout, but kept as they were
        // written, so editing a vibescape doesn't shout at whoever typed it.
        self.title = mode.displayName.uppercased()
        self.author = VibescapeMetadata.author
        self.url = VibescapeMetadata.url
        self.shortcut = shortcut
        self.glyph = shortcut.map(String.init) ?? ""
        self.subtitle = nil
        self.isCustom = false
        self.isEnabled = true
    }

    init(custom mode: CustomVibescape, shortcut: Character?) {
        self.id = .custom(mode.id)
        self.title = mode.name.uppercased()
        self.author = mode.author
        self.url = mode.url
        self.shortcut = shortcut
        self.glyph = shortcut.map(String.init) ?? ""
        self.subtitle = mode.subtitle
        self.isCustom = true
        self.isEnabled = mode.enabled
        self.isNewVibescapeCard = false
    }

    /// The card at the end of the list that opens the Custom Vibescape sheet.
    /// It isn't a vibescape, so most of its fields are blank — but it travels
    /// through the same list as everything else so the grid doesn't need a
    /// special case for it.
    init(newVibescapeCard: Bool) {
        self.id = .builtin(.tunnel)
        self.title = "MAKE YOUR OWN"
        self.author = ""
        self.url = nil
        self.shortcut = nil
        self.glyph = "+"
        self.subtitle = nil
        self.isCustom = false
        self.isEnabled = true
        self.isNewVibescapeCard = newVibescapeCard
    }
}

// MARK: - On-disk store

/// Custom vibescapes live as one JSON file each under
/// `~/Library/Application Support/Vibresia/Vibescapes/`.
///
/// A folder rather than one blob in `UserDefaults` because these are the one
/// thing a user is expected to hand to someone else: the files can be copied,
/// emailed, dropped into another Mac, and kept in version control. It also
/// matches the Hamsters folder, so "where do I put my own stuff" has one
/// answer in this app.
enum CustomVibescapeStore {
    static var folder: URL {
        // VIBRESIA_CUSTOM_DIR points somewhere else, for tests and for
        // demo runs that must never read a real person's vibescapes.
        if let dir = ProcessInfo.processInfo.environment["VIBRESIA_CUSTOM_DIR"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        // "Vibescapes", reached by SupportFolder's migration rather than by any
        // build pointing straight at it — CustomModes -> Vibscapes -> Vibescapes,
        // one step per release that renamed it. This folder holds people's own
        // work and is named on disk in every install that has ever made a
        // vibescape, so the move has to happen in a migration rather than by
        // changing this literal: a build that skipped a release would otherwise
        // point at an empty folder and every existing vibescape would look
        // deleted.
        return SupportFolder.folder("Vibescapes")
    }

    static func ensureFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Every vibescape on disk, oldest first so a fresh install and a restored one
    /// list them the same way.
    static func loadAll() -> [CustomVibescape] {
        ensureFolder()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let modes: [CustomVibescape] = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(CustomVibescape.self, from: $0) }
        // A file whose slug doesn't match its filename would let two files
        // claim one id, and the second would silently never load.
        var seen = Set<String>()
        return modes.filter { seen.insert($0.id).inserted }
    }

    static func url(for id: String) -> URL {
        folder.appendingPathComponent("\(id).json")
    }

    static func save(_ mode: CustomVibescape) throws {
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

/// The words and starter code shown in the Custom Vibescape sheet.
///
/// Kept here rather than in the view so the AI prompt, the template and the
/// validator all quote the same uniform names. If a uniform is ever renamed in
/// the prelude, this is the one place that has to change with it.
enum CustomVibescapeGuide {
    /// Uniforms and helpers the prelude hands a custom vibescape.
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

    Anything that looks like a cloud, a flame or smoke is `fbm`:

    vec3 render(vec2 p, float t)
    {
        float n = fbm(p * 7.0 + vec2(0.0, -t * 0.5));
        n = fbm(p * 7.0 + vec2(n * 1.6, n * 1.6));
        float glow = 1.0 - smoothstep(0.0, 0.2, length(p));
        return mix(vec3(0.05, 0.1, 0.3), vec3(0.6, 0.8, 1.0), n * glow) * uActive;
    }

    Scale is what catches people out. `fbm(p)` sampled at the screen's scale is
    too smooth to see — across a shape a few tenths wide you'd be looking at a
    single slow ramp, and it reads as "the noise isn't working" rather than "the
    frequency is wrong". Multiply by something around 7.0 so several cells land
    inside the shape. Feeding one `fbm` into the next, as above, is what turns
    grain into structure.

    These helpers are already defined for you:

      screenP()        centred coordinates, x scaled to the window shape
      hash21(p)        random number from a position, always 0..1
      vnoise(p)        smooth noise at a position, 0..1
      fbm(p)           four octaves of vnoise, 0..1
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

    ## Look at it before you believe it

    This server can draw what you write and hand you the picture. Don't describe
    a shader you haven't seen. The loop is two calls: draw it, change one thing,
    draw it again. A frame takes about 40ms.

      preview_vibescape({ code })                   one frame, as a PNG
      preview_vibescape_animation({ code })         several frames in one picture

    Ask for several frames when the movement is the point — a single frame of a
    scrolling tunnel and a still tunnel look identical, and one of them is
    wrong. `preview_vibescape_animation` defaults to 8 frames over 4 seconds.

    You can also point the audio uniforms anywhere you like, which is how you
    find out how it behaves when the music isn't playing:

      preview_vibescape({
        code: myShader,
        options: { uniforms: { uBass: 0.9, uLevel: 0.7, uActive: 1.0 } }
      })

    `uActive` defaults to 1, so a preview is never a black rectangle in a quiet
    room. Draw the same shader at uBass 0.1 and uBass 0.9 and look at both
    before you decide how much it should react.

    Code that doesn't compile comes back as the driver's own error, in words,
    with the line number — not a blank picture. If a vibescape compiles but looks
    wrong, the problem is usually one of the lints: not reading the music at all,
    or a uniform that keeps running in silence when you wanted it to stop.

    ## Tune to the real numbers

    `get_uniform_snapshot` returns what the app is drawing with right now, with
    the ranges these values actually run in. Read it rather than picking a
    coefficient out of the air. `beat * 0.5` sounds reasonable and does nothing
    on a quiet track; the snapshot shows you that uBeatStrength peaks around 0.6
    on one and 0.2 on another, and that's the difference between a flash and a
    flicker.

    `what_i_hear` says what the music is — genre, instruments, tempo, spectrum —
    so you can write something that suits it rather than something generic.

    ## Colours are graded, and you can see it

    Every vibescape is drawn and then graded through the palette you pick in the
    header — the same as the built-ins. That's why a colour can look muted on
    screen when it was bright in your code: the app maps brightness between two
    palette colours and pushes saturation. It is not a bug, and the built-ins
    are treated identically.

      get_palette()          every palette, with its two colours and tint
      get_palette("NEON")    the details of one

    Two ways to work with it rather than against it. Use `uPalette` in your
    shader — it's a `vec3[3]` you get for free, holding shadow, highlight and
    their midpoint — and you get the palette exactly right. Or pick colours from
    the palette rather than bringing your own; anything between its shadow and
    highlight arrives as a version of those two. If you want to see a colour as
    you wrote it, pass `grade: false` in the preview options.
    """

    /// Ready-to-paste prompt for someone using an AI coding assistant.
    static let agentPrompt = """
    Write a vibescape for Vibresia, a macOS app for visual worlds that move \
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
      helpers:  screenP() hash21(p) vnoise(p) fbm(p) bandAt(x) rot(a)
                sdCircle(p,r) sdBox(p,b) sdRoundBox(p,b,r) sdSeg(p,a,b)
                fill(d,w) aaw(s)
      GLSL:     mix clamp sin cos fract length dot

    Fade gently in silence by scaling the final colour by uActive.

    Briefly describe the visual in one sentence AFTER the code block, so the \
    user knows what they are about to add.
    """

    /// The blank starting point for someone writing it by hand.
    static let starterTemplate = """
    // Your vibescape. Edit the colour, press Test.
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
