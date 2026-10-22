import Foundation
import AppKit
import simd

/// The tools the MCP server offers.
///
/// Kept in one place so the list an agent sees and the code that runs it
/// can't drift apart.
enum MCPTools {

    // MARK: - The list

    static let all: [[String: Any]] = [
        tool("preview_vibescape",
             "Draw a vibescape and return the picture. The whole point: see it before you commit. " +
             "Set the audio uniforms yourself to explore how it responds, or ask for several frames to see the motion. " +
             "Broken code comes back as an error in words.",
             previewSchema(animation: false)),
        tool("preview_vibescape_animation",
             "Draw a vibescape over several seconds and return every frame as one picture, so you can see how it moves. " +
             "Use this instead of preview_vibescape when the animation is the point.",
             previewSchema(animation: true)),
        tool("validate_vibescape",
             "Compile a vibescape and run it on a single pixel. Returns errors that stop it working, and warnings about things " +
             "that will make it look wrong — including ones that still compile, like a vibescape that ignores the music.",
             ["type": "object",
              "properties": ["code": ["type": "string", "description": "The shader: a vec3 render(vec2 p, float t) function."]],
              "required": ["code"]]),
        tool("get_uniform_snapshot",
             "The uniform values the app is drawing with right now — uBass, uMid, uTreble, uLevel, uLevelSmooth, uBassSmooth, " +
             "uBeatStrength, uBeats, uBands, uActive, uClock and the rest, plus the ranges they've been seen in. " +
             "Use these to pick coefficients that match the music rather than guessing.",
             ["type": "object", "properties": [:]]),
        tool("get_palette",
             "A palette's colours and how strongly the app tints over them. Use this to see what your colours will actually " +
             "look like on screen, or to pick colours that already suit the palette.",
             ["type": "object",
              "properties": ["name": ["type": "string", "description": "The palette. Leave it out for all of them."]]]),
        tool("save_vibescape",
             "Save a vibescape, either as a new one or by replacing the one with the same name. It's compiled and previewed " +
             "first: a vibescape that doesn't compile is not saved, and you get the picture of what you're shipping back. " +
             "Use list_vibescapes to see what's already there.",
             ["type": "object",
              "properties": [
                "name": ["type": "string", "description": "What the vibescape is called. An existing name is replaced."],
                "code": ["type": "string", "description": "The shader: a vec3 render(vec2 p, float t) function."],
                "author": ["type": "string", "description": "Who wrote it. Shown under the vibescape's name."],
                "url": ["type": "string", "description": "A link to it, if there is one."],
                "description": ["type": "string", "description": "What it looks like, in a line."],
                "palette": ["type": "string", "description": "The palette it was designed against, e.g. NEON."],
                "audio_targets": ["type": "string", "description": "Which parts of the music it reacts to, e.g. 'bass and beat'."],
                "preview": ["type": "boolean", "description": "Draw it before saving so you can see what you're about to ship. Default true."],
              ],
              "required": ["name", "code"]]),
        tool("diff_vibescape",
             "Draw two versions of a vibescape with the same uniforms, side by side. Give the code for both, or name a saved " +
             "one and supply only the other. Useful for seeing what a change actually did.",
             ["type": "object",
              "properties": [
                "name": ["type": "string", "description": "A saved vibescape to compare against, if you only have the new code."],
                "code_a": ["type": "string", "description": "The first version. Defaults to the saved one."],
                "code_b": ["type": "string", "description": "The second version."],
                "label_a": ["type": "string", "description": "What to call the left side."],
                "label_b": ["type": "string", "description": "What to call the right side."],
                "palette": ["type": "string", "description": "The palette to draw both through."],
              ],
              "required": ["code_b"]]),

        // Kept from the first version, because they're the verbs the app itself
        // uses and an agent that learned those shouldn't be told they vanished.
        tool("list_vibescapes",
             "Every vibescape Vibresia has: the ones that ship with it and the user's own, each with a thumbnail. " +
             "Use this to see what's already been made before making another.",
             ["type": "object", "properties": [:]]),
        tool("get_vibescape",
             "The full source of one of the user's own vibescapes.",
             ["type": "object",
              "properties": ["id": ["type": "string", "description": "The vibescape's id, from list_vibescapes."]],
              "required": ["id"]]),
        tool("vibescape_reference",
             "What a vibescape can use: the uniforms the music drives, the helpers, and a worked example. Read this before writing a shader.",
             ["type": "object", "properties": [:]]),
        tool("what_i_hear",
             "What Vibresia is hearing right now: the suspected genre and instruments, the tempo, the levels and the shape of the spectrum. The same numbers a vibescape draws with.",
             ["type": "object", "properties": [:]]),
        tool("test_vibescape",
             "Compile a shader and draw a picture of it, without saving anything. Returns the error in words if it doesn't compile. Same as preview_vibescape.",
             ["type": "object",
              "properties": [
                "code": ["type": "string", "description": "The shader: a vec3 render(vec2 p, float t) function."],
                "name": ["type": "string", "description": "A name for the preview, for the error message."],
              ],
              "required": ["code"]]),
        tool("create_vibescape",
             "Save a new vibescape. The code is compiled first and is not saved if it doesn't work. Same as save_vibescape.",
             ["type": "object",
              "properties": [
                "name": ["type": "string", "description": "What the vibescape is called."],
                "code": ["type": "string", "description": "The shader: a vec3 render(vec2 p, float t) function."],
                "author": ["type": "string", "description": "Who wrote it. Shown under the vibescape's name."],
                "url": ["type": "string", "description": "A link to it, if there is one."],
              ],
              "required": ["name", "code"]]),
        tool("update_vibescape",
             "Change one of the user's own vibescapes. The code is compiled first and is not saved if it doesn't work. Same as save_vibescape.",
             ["type": "object",
              "properties": [
                "id": ["type": "string", "description": "The vibescape's id, from list_vibescapes."],
                "code": ["type": "string", "description": "New shader source."],
                "name": ["type": "string", "description": "A new name, if it should change."],
                "author": ["type": "string", "description": "A new author, if it should change."],
                "url": ["type": "string", "description": "A new link, if it should change."],
              ],
              "required": ["id"]]),
        tool("delete_vibescape",
             "Remove one of the user's own vibescapes. It cannot be undone.",
             ["type": "object",
              "properties": ["id": ["type": "string", "description": "The vibescape's id, from list_vibescapes."]],
              "required": ["id"]]),
    ]

    /// The preview tools take the same options; only the defaults differ, so
    /// the schema is built once with those defaults swapped in.
    private static func previewSchema(animation: Bool) -> [String: Any] {
        let defaults = animation
            ? PreviewOptions(width: 320, height: 180, frames: 8, timeStart: 0, timeStep: 0.5)
            : PreviewOptions()
        let framesDescription = animation
            ? "How many frames to draw. They come back in one picture, left to right. Default \(defaults.frames)."
            : "More than 1 draws several frames and returns them in one picture, so you can see the motion. Default \(defaults.frames)."
        return [
            "type": "object",
            "properties": [
                "code": ["type": "string",
                         "description": "The shader: a vec3 render(vec2 p, float t) function. Write the body of render, not main."],
                "options": [
                    "type": "object",
                    "description": "How to draw it. Everything is optional.",
                    "properties": [
                        "width": ["type": "integer", "description": "Pixels across. Default \(defaults.width)."],
                        "height": ["type": "integer", "description": "Pixels down. Default \(defaults.height)."],
                        "frames": ["type": "integer", "description": framesDescription],
                        "time_start": ["type": "number", "description": "Seconds to start at. Default \(defaults.timeStart)."],
                        "time_step": ["type": "number", "description": "Seconds between frames. Default \(defaults.timeStep)."],
                        "palette": ["type": "string",
                                    "description": "The palette to grade through, e.g. NEON or EMBER. Default: the app's current one."],
                        "grade": ["type": "boolean",
                                  "description": "Default true. False shows your own colours before the palette touches them."],
                        "uniforms": [
                            "type": "object",
                            "description": "Point the audio uniforms somewhere specific. Anything left out comes from the music " +
                                "playing now, or from stand-in values if the app isn't running.",
                            "properties": uniformSchema(),
                        ],
                    ],
                ],
            ],
            "required": ["code"],
        ]
    }

    private static func uniformSchema() -> [String: Any] {
        var props: [String: Any] = [
            "uBass": ["type": "number", "description": "Bass energy, 0..1. Try 0 for a chill look, 0.9 for a hard one."],
            "uMid": ["type": "number", "description": "Midrange energy, 0..1."],
            "uTreble": ["type": "number", "description": "Treble energy, 0..1. Noisy: cymbals and hi-hats."],
            "uLevel": ["type": "number", "description": "Overall loudness, 0..1."],
            "uLevelSmooth": ["type": "number", "description": "Slow loudness, 0..1. Rises over ~0.3s, falls over ~1.5s."],
            "uBassSmooth": ["type": "number", "description": "The same easing applied to uBass."],
            "uBeat": ["type": "number", "description": "1 on a beat, 0 between. Use for on/off hits, not for speed."],
            "uBeatStrength": ["type": "number", "description": "How hard that beat landed, 0..1."],
            "uBeats": ["type": "number", "description": "Continuous beat count at the detected tempo. Use for anything rhythmic."],
            "uBands": ["type": "array", "items": ["type": "number"],
                       "description": "Spectrum, up to 96 values, low to high. Read with bandAt(x), where x is 0..1."],
            "uActive": ["type": "number", "description": "0 in silence, eases to 1 with sound. Default 1, so a preview isn't dead."],
            "uIdle": ["type": "number", "description": "1 in silence, 0 with sound."],
            "uPresence": ["type": "number", "description": "Whether there's music at all, 0..1, very slow."],
            "uScroll": ["type": "number", "description": "Forward-only distance. The easiest thing to scroll a vibescape by."],
            "uClock": ["type": "number", "description": "Wall-clock seconds. Keeps running in silence."],
            "uTrackPos": ["type": "number", "description": "Seconds into the track, for a preview that needs a position. 0 when there is none to know."],
            "uTrackDuration": ["type": "number", "description": "The length of the track in seconds."],
            "uMouse": ["type": "array", "items": ["type": "number"],
                       "description": "The pointer, in the shader's own coordinates: [x, y], x across the screen and y up from the middle. The same space p is in."],
            "uMouseDown": ["type": "number", "description": "1 while a mouse button is held, 0 otherwise."],
            "uKey": ["type": "number", "description": "The last key pressed, as its character code. 32 is the space bar, 65 is A."],
            "uKeyDown": ["type": "number", "description": "1 while a key is held, 0 otherwise."],
            "uMidiNote": ["type": "number", "description": "The MIDI note, 0..127. 60 is middle C."],
            "uMidiVelocity": ["type": "number", "description": "How hard that note was hit, 0..1."],
            "uMidiNotes": ["type": "number", "description": "How many MIDI notes are held right now."],
            "uMidiCC": ["type": "number", "description": "The MIDI controller number, 0..127."],
            "uMidiCCValue": ["type": "number", "description": "Where that controller is, 0..1."],
        ]
        return props
    }


    private static func tool(_ name: String, _ description: String, _ schema: [String: Any]) -> [String: Any] {
        ["name": name, "description": description, "inputSchema": schema]
    }

    // MARK: - Running one

    static func call(name: String, arguments: [String: Any]) -> [String: Any] {
        switch name {
        case "preview_vibescape": return previewVibescape(arguments, animation: false)
        case "preview_vibescape_animation": return previewVibescape(arguments, animation: true)
        case "validate_vibescape": return validateVibescape(arguments)
        case "get_uniform_snapshot": return uniformSnapshot()
        case "get_palette": return palette(arguments)
        case "save_vibescape": return saveVibescape(arguments)
        case "diff_vibescape": return diffVibescape(arguments)
        case "list_vibescapes": return listVibescapes()
        case "get_vibescape": return getVibescape(arguments)
        case "vibescape_reference": return textResult(CustomVibescapeGuide.fullReference)
        case "what_i_hear": return whatIHear()
        case "test_vibescape": return previewVibescape(arguments, animation: false)
        case "create_vibescape": return createVibescape(arguments)
        case "update_vibescape": return updateVibescape(arguments)
        case "delete_vibescape": return deleteVibescape(arguments)
        default:
            return errorResult("There's no tool called \(name).")
        }
    }

    // MARK: - Preview

    /// Draws a vibescape and hands back the picture.
    ///
    /// This is the tool the rest of them are for: everything else is a way of
    /// deciding *what* to draw, and this is the one that shows the answer. The
    /// response is the picture first and a note about what went into it second,
    /// because the picture is the part that was missing.
    private static func previewVibescape(_ arguments: [String: Any], animation: Bool) -> [String: Any] {
        guard let code = arguments["code"] as? String else {
            return errorResult("There's no code to draw. Pass the shader source as `code`.")
        }
        let name = (arguments["name"] as? String) ?? "this vibescape"
        var options = animation
            ? PreviewOptions(width: 320, height: 180, frames: 8, timeStart: 0, timeStep: 0.5)
            : PreviewOptions()
        applyPreviewOptions(arguments["options"], to: &options)

        let started = Date()
        switch VibescapeRender.render(body: code, options: options) {
        case .failure(let problem):
            return errorResult(failure(problem, name: name))
        case .success(let preview):
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            var note = animation ? "Here is \(name) moving" : "Here is \(name)"
            if preview.frames > 1 {
                let span = preview.times.last.map { $0 - preview.times[0] } ?? 0
                note += " — \(preview.frames) frames from \(trim(preview.times[0]))s to \(trim(preview.times[preview.times.count - 1]))s"
                if preview.rows > 1 { note += ", laid out \(preview.columns) across" }
                if span > 0 { note += " (\(trim(span))s of motion)" }
            }
            note += ".\n\n"
            note += "Drawn through the \(preview.paletteName) palette with \(preview.source)"
            if !options.uniforms.isEmpty {
                note += ", and \(options.uniforms.names.map { "`\($0)`" }.joined(separator: ", ")) set by hand"
            }
            note += ". Each frame is \(preview.frameWidth)x\(preview.frameHeight). \(elapsed)ms."
            if !options.uniforms.names.contains("uActive") {
                note += " uActive is forced to 1 so the vibescape is drawn as if music were playing; pass `uActive: 0` to see it sitting still."
            }

            // The notes that are actually useful when the picture isn't what was
            // hoped for, rather than a wall of text on every call.
            let warnings = lint(code)
            if !warnings.isEmpty {
                note += "\n\nWorth knowing:\n" + warnings.map { "· \($0)" }.joined(separator: "\n")
            }
            return imageResult(preview.image, text: note)
        }
    }

    /// Reads the `options` bag, ignoring anything that isn't the right type.
    private static func applyPreviewOptions(_ raw: Any?, to options: inout PreviewOptions) {
        guard let bag = raw as? [String: Any] else { return }
        if let v = bag["width"] as? Int { options.width = v }
        else if let v = bag["width"] as? Double { options.width = Int(v) }
        if let v = bag["height"] as? Int { options.height = v }
        else if let v = bag["height"] as? Double { options.height = Int(v) }
        if let v = bag["frames"] as? Int { options.frames = v }
        else if let v = bag["frames"] as? Double { options.frames = Int(v) }
        if let v = bag["time_start"] as? Double { options.timeStart = v }
        else if let v = bag["time_start"] as? Int { options.timeStart = Double(v) }
        if let v = bag["time_step"] as? Double { options.timeStep = v }
        else if let v = bag["time_step"] as? Int { options.timeStep = Double(v) }
        if let v = bag["grade"] as? Bool { options.grade = v }
        if let v = bag["palette"] as? String, let match = paletteNamed(v) {
            options.palette = match
        }
        if let uniforms = bag["uniforms"] as? [String: Any] {
            options.uniforms = readUniforms(uniforms)
        }
    }

    private static func readUniforms(_ bag: [String: Any]) -> UniformOverrides {
        func num(_ key: String) -> Float? {
            if let v = bag[key] as? Double { return Float(v) }
            if let v = bag[key] as? Int { return Float(v) }
            return nil
        }
        var o = UniformOverrides()
        o.bass = num("uBass")
        o.mid = num("uMid")
        o.treble = num("uTreble")
        o.level = num("uLevel")
        o.levelSmooth = num("uLevelSmooth")
        o.bassSmooth = num("uBassSmooth")
        o.beat = num("uBeat")
        o.beatStrength = num("uBeatStrength")
        o.beats = num("uBeats")
        o.active = num("uActive")
        o.idle = num("uIdle")
        o.presence = num("uPresence")
        o.scroll = num("uScroll")
        o.clock = num("uClock")
        o.trackPos = num("uTrackPos")
        o.trackDuration = num("uTrackDuration")
        if let bands = bag["uBands"] as? [Double] { o.bands = bands.map { Float($0) } }
        else if let bands = bag["uBands"] as? [Int] { o.bands = bands.map { Float($0) } }
        if let pointer = bag["uMouse"] as? [Double] { o.mouse = pointer.map { Float($0) } }
        else if let pointer = bag["uMouse"] as? [Int] { o.mouse = pointer.map { Float($0) } }
        o.mouseDown = num("uMouseDown")
        o.key = num("uKey")
        o.keyDown = num("uKeyDown")
        o.midiNote = num("uMidiNote")
        o.midiVelocity = num("uMidiVelocity")
        o.midiNotes = num("uMidiNotes")
        o.midiCC = num("uMidiCC")
        o.midiCCValue = num("uMidiCCValue")
        // uActive is forced on unless asked otherwise: a preview that respects
        // the room's silence is a preview of a black rectangle.
        if o.active == nil { o.active = 1 }
        return o
    }

    /// An image result with a note attached.
    private static func imageResult(_ image: NSImage, text: String) -> [String: Any] {
        var content: [[String: Any]] = []
        if let data = pngData(image) {
            content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"])
        }
        content.append(["type": "text", "text": text])
        return ["content": content]
    }

    private static func pngData(_ image: NSImage) -> Data? {
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        // NSImage from a CGImage may not round-trip through TIFF on every
        // system; going straight at the bitmap works.
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Validation

    /// Compiles it, runs it on one pixel, and says what's wrong.
    ///
    /// Deliberately separate from preview: a vibescape can fail to compile, fail
    /// to run, compile and look wrong, or compile and look wrong on screen
    /// because of the palette. They're four different problems and lumping them
    /// together loses the distinction.
    private static func validateVibescape(_ arguments: [String: Any]) -> [String: Any] {
        guard let code = arguments["code"] as? String else {
            return errorResult("There's no code to check. Pass the shader source as `code`.")
        }
        let name = (arguments["name"] as? String) ?? "this vibescape"

        switch VibescapeCompiler.compile(body: code) {
        case .failed(let problem):
            return errorResult(failure(problem, name: name))
        case .compiled:
            break
        }

        // Compiling isn't running. One pixel through the real pipeline catches
        // the class of problem that links fine and then draws nothing.
        let options = PreviewOptions(width: 4, height: 4)
        let ran = VibescapeRender.render(body: code, options: options)
        var lines: [String] = []
        switch ran {
        case .success:
            lines.append("\(name) compiles, links and runs.")
        case .failure(let problem):
            return errorResult(failure(problem, name: name))
        }

        let warnings = lint(code)
        if warnings.isEmpty {
            lines.append("Nothing to flag.")
        } else {
            lines.append("")
            lines.append("Compiles and runs, but:")
            lines.append(warnings.map { "· \($0)" }.joined(separator: "\n"))
        }
        return textResult(lines.joined(separator: "\n"))
    }

    /// Things that compile and run but will make the vibescape look wrong.
    ///
    /// Each one is a mistake that is invisible in the code and obvious in the
    /// picture: a vibescape that never reads the music, one that ignores the
    /// palette, one that keeps moving in silence.
    private static func lint(_ code: String) -> [String] {
        var warnings: [String] = []
        let audioNames = ["uBass", "uMid", "uTreble", "uLevel", "uLevelSmooth", "uBassSmooth",
                          "uBeat", "uBeatStrength", "uBeats", "uBands", "bandAt", "uPresence", "uScroll"]
        if !audioNames.contains(where: { code.contains($0) }) {
            warnings.append("It never reads the music, so it will look identical in silence and at full volume. Use `uBass`, `uLevelSmooth`, `bandAt(x)` or `uScroll` to make it react.")
        }
        if !code.contains("uPalette") && !code.contains("uResolution") {
            warnings.append("It doesn't mention `uPalette`, so it ignores the palette picker. That's fine if you want fixed colours, but they will still be graded, so bright colours come out muted.")
        }
        let freeRunning = ["uBeats", "uScroll", "uClock"].filter { code.contains($0) }
        if !freeRunning.isEmpty && !code.contains("uActive") {
            warnings.append("`\(freeRunning.joined(separator: "`, `"))` keep running in silence, so this won't sit still when the music stops. Multiply by `uActive` if you want it to.")
        }
        if code.contains("uClock") {
            warnings.append("`uClock` is wall-clock time: it keeps running in silence and jumps if the app is suspended. `uScroll` is the better thing to scroll by.")
        }
        let renderBody = renderFunctionBody(code)
        if let body = renderBody, !body.contains("p") && !body.contains("t") {
            warnings.append("`render` never uses `p` or `t`, so it returns one flat colour. `p` is the position across the screen and `t` is time in seconds.")
        }
        if code.contains("gl_FragColor") || code.contains("fragColor") {
            warnings.append("You're writing to an output variable directly. Return a `vec3` from `render` instead — the app wraps the call for you.")
        }
        if code.contains("vec2(") && code.contains("uResolution.x") {
            warnings.append("Reading `uResolution.x` directly fights the `screenP()` helper. Prefer `p`, which is already centred and aspect-corrected.")
        }
        return warnings
    }

    /// The text between `render(`'s opening brace and its closing one, best
    /// effort, so lint can look at what the function actually does.
    private static func renderFunctionBody(_ code: String) -> String? {
        guard let signature = code.range(of: "render") else { return nil }
        let rest = code[signature.upperBound...]
        guard let open = rest.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = rest.index(after: open)
        while index < rest.endIndex {
            if rest[index] == "{" { depth += 1 }
            if rest[index] == "}" {
                depth -= 1
                if depth == 0 { return String(rest[rest.index(after: open)..<index]) }
            }
            index = rest.index(after: index)
        }
        return nil
    }

    // MARK: - What the app is drawing with

    /// The uniform values, right now.
    ///
    /// The reason this exists: picking `beat * 0.5` out of the air produces a
    /// vibescape that either never pulses or strobes, and neither failure says
    /// which way to fix it. Knowing that `uBeatStrength` runs 0.1..0.6 on a
    /// chill track turns "multiply by 0.5" into "multiply by 2".
    private static func uniformSnapshot() -> [String: Any] {
        // From the running app, via the file it writes. The server is a
        // separate process, so this is the only route to a live value.
        guard let state = LiveUniforms.readFromDisk() else {
            return errorResult("""
            Vibresia isn't running, so there are no live values to read. Open it, share \
            some audio, and ask again — or just use preview_vibescape, which falls back to \
            stand-in values that behave like busy music.
            """)
        }

        func f(_ key: String) -> Float { Float(state[key] as? Double ?? 0) }
        let bands = (state["uBands"] as? [Double] ?? []).map { Float($0) }
        let beatsPerSecond = f("beats_per_second")
        let bpm = state["bpm"] as? Double ?? 0
        let age = Date().timeIntervalSince1970 - (state["at"] as? Double ?? 0)

        var lines: [String] = []
        lines.append("Read from Vibresia \(String(format: "%.1f", age))s ago, drawing \(state["vibescape"] as? String ?? "?") through \(state["palette"] as? String ?? "?").\n")

        lines.append("  uBass         \(d(f("uBass")))     uLevel        \(d(f("uLevel")))")
        lines.append("  uMid          \(d(f("uMid")))     uLevelSmooth  \(d(f("uLevelSmooth")))   slow loudness: rises ~0.3s, falls ~1.5s")
        lines.append("  uTreble       \(d(f("uTreble")))     uBassSmooth   \(d(f("uBassSmooth")))")
        lines.append("  uBeat         \(d(f("uBeat")))     uPresence     \(d(f("uPresence")))   0 = silence, 1 = music")
        lines.append("  uBeatStrength \(d(f("uBeatStrength")))     uActive       \(d(f("uActive")))   what the built-ins multiply by")
        lines.append("  uIdle         \(d(f("uIdle")))     uScroll       \(d(f("uScroll")))   forward-only distance")
        lines.append("  uBeats        \(d(f("uBeats")))     uClock        \(d(f("uClock")))   wall-clock seconds")
        let trackKnown = f("uTrackKnown") > 0
        if trackKnown {
            let position = f("uTrackPos")
            let length = f("uTrackDuration")
            let progress = length > 0 ? position / length : 0
            let stamp = String(format: "%d:%02d", Int(position) / 60, Int(position) % 60)
            lines.append("  uTrackPos     \(d(position))s      uTrackProgress \(d(progress))   \(stamp) into a \(String(format: "%.0f", length))s track")
        } else {
            lines.append("  uTrackKnown   0                 no position to know — nothing is playing that says where it is")
        }
        lines.append("")
        lines.append("uBeats advances at \(d(beatsPerSecond)) beats/sec\(bpm > 0 ? " (\(Int(bpm.rounded())) bpm detected)" : ""), so `uBeats * 0.5` is a quarter-cycle per beat at the current tempo.")
        lines.append("")
        lines.append("The input uniforms — uMouse, uMouseDown, uKey, uKeyDown, uMidiNote, uMidiVelocity, uMidiNotes, uMidiCC, uMidiCCValue — are not in this list on purpose. They are what the person at the keyboard is doing, not what the music is doing, and they are not written down: the app does not put them in a file and this server cannot see them, because it runs without the app's window. Set them yourself on a preview to see what a vibescape does with them — `preview_vibescape({ code, options: { uniforms: { uMouse: [0.2, -0.1] } } })`.")

        if !bands.isEmpty {
            lines.append("")
            lines.append("uBands (\(bands.count) values, low to high; read one with `bandAt(x)` where x is 0..1):")
            for start in stride(from: 0, to: bands.count, by: 24) {
                let slice = bands[start..<min(start + 24, bands.count)]
                lines.append("  \(String(format: "%2d", start)): " + slice.map { d($0) }.joined(separator: " "))
            }
        }

        // The part that actually makes this usable as a tuning tool: the range,
        // not just the instant value. Picking a coefficient against one frame
        // is picking it against one moment of one song.
        let ranges = ["uBass": f("uBass"), "uMid": f("uMid"), "uTreble": f("uTreble"),
                      "uLevel": f("uLevel"), "uBeatStrength": f("uBeatStrength")]
        let busy = ranges.filter { $0.value > 0.05 }.keys.sorted()
        lines.append("")
        if busy.isEmpty {
            lines.append("Nothing is playing loudly enough to read a range from right now. Play something and ask again, or set the uniforms yourself on a preview.")
        } else {
            lines.append("Moving right now: \(busy.joined(separator: ", ")). Anything at or near zero here is silent right now, not broken — see what_i_hear for whether music is playing at all.")
        }
        lines.append("")
        lines.append("Previews draw with these numbers unless you set uniforms yourself, so a preview and the screen agree.")
        lines.append("")
        lines.append(json([
            "uBass": f("uBass"), "uMid": f("uMid"), "uTreble": f("uTreble"),
            "uLevel": f("uLevel"), "uLevelSmooth": f("uLevelSmooth"),
            "uBassSmooth": f("uBassSmooth"), "uBeat": f("uBeat"),
            "uBeatStrength": f("uBeatStrength"), "uBeats": f("uBeats"),
            "uActive": f("uActive"), "uIdle": f("uIdle"),
            "uPresence": f("uPresence"), "uScroll": f("uScroll"),
            "uClock": f("uClock"), "beats_per_second": beatsPerSecond,
            "uTrackPos": f("uTrackPos"), "uTrackDuration": f("uTrackDuration"),
            "uTrackProgress": f("uTrackProgress"), "uTrackKnown": f("uTrackKnown"),
            "bpm": bpm, "palette": state["palette"] ?? "",
            "vibescape": state["vibescape"] ?? "",
        ]))
        return textResult(lines.joined(separator: "\n"))
    }

    // MARK: - Palettes

    /// A palette's colours and how hard it tints.
    ///
    /// The complaint this answers is precise: picking cyan and magenta and
    /// getting muted teal and pink. That's the grade, not a mistake in the
    /// shader — the same two colours come out the same way every time.
    private static func palette(_ arguments: [String: Any]) -> [String: Any] {
        if let name = arguments["name"] as? String {
            guard let match = paletteNamed(name) else {
                let available = Palette.all.map { $0.name }.joined(separator: ", ")
                return errorResult("There's no palette called \(name). There is: \(available).")
            }
            return textResult(paletteReport(match))
        }

        var lines: [String] = ["Palettes. Pass a name to get the details of one.", ""]
        for pal in Palette.all {
            lines.append("  \(pal.name.padding(toLength: 8, withPad: " ", startingAt: 0))  shadow \(rgb(pal.shadow))  highlight \(rgb(pal.highlight))  tint \(d(pal.duotone))")
        }
        lines.append("")
        lines.append("Every vibescape is graded through the palette after it draws: the image's brightness is stretched between the shadow and highlight colours, then saturated and lifted. Your colours are not shown as-is, which is why a colour can look muted on screen and bright in the code.")
        lines.append("")
        lines.append("If you want a colour to survive, make it bright before the grade, or set `grade: false` on a preview to see it ungraded.")
        return textResult(lines.joined(separator: "\n"))
    }

    private static func paletteReport(_ pal: Palette) -> String {
        let mid = (pal.shadow + pal.highlight) * 0.5
        var lines: [String] = []
        lines.append(pal.name)
        lines.append("")
        lines.append("  uPalette[0]  \(rgb(pal.shadow))   shadow — where the dark parts go")
        lines.append("  uPalette[1]  \(rgb(pal.highlight))   highlight — where the bright parts go")
        lines.append("  uPalette[2]  \(rgb(mid))   the middle of the two, available if you use the uniform")
        lines.append("")
        lines.append("How hard the app grades over what you draw:")
        lines.append("  duotone      \(d(pal.duotone))   0 = your colours pass through, 1 = fully remapped to the two colours above")
        lines.append("  saturation   \(d(pal.saturation))   0 = grey, 1 = as you drew it, above 1 = pushed further")
        lines.append("  lift         \(d(pal.lift))   how far the blacks are lifted toward the shadow colour, so they don't crush")
        lines.append("")
        lines.append("""
        A rough guide: tint \(d(pal.duotone)) means your colours are pulled \(Int(pal.duotone * 100))% of the way toward \
        the shadow-to-highlight ramp. To land on a specific colour, pick the colour from this palette rather than bringing \
        your own — anything between shadow and highlight will come out as a version of these two.
        """)
        lines.append("Note you can use `uPalette` in your vibescape directly — it's a `vec3[3]` you get for free, and drawing with it means you get the palette exactly right rather than fighting the grade.")
        lines.append("")
        lines.append(json([
            "name": pal.name,
            "colors": [
                ["shadow", pal.shadow.x, pal.shadow.y, pal.shadow.z],
                ["highlight", pal.highlight.x, pal.highlight.y, pal.highlight.z],
                ["mid", mid.x, mid.y, mid.z],
            ],
            "tint_strength": pal.duotone,
            "saturation": pal.saturation,
            "lift": pal.lift,
        ]))
        return lines.joined(separator: "\n")
    }

    /// A readable JSON block, for the times when the caller wants the numbers
    /// rather than the explanation.
    private static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// The palette the app is showing, from whichever process this is.
    private static func livePaletteName() -> String {
        LiveUniforms.shared.paletteName
            ?? LiveUniforms.readFromDisk()?["palette"] as? String
            ?? "NEON"
    }

    private static func paletteNamed(_ name: String) -> Palette? {
        Palette.all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func rgb(_ c: SIMD3<Float>) -> String {
        String(format: "(%.2f, %.2f, %.2f)", c.x, c.y, c.z)
    }

    // MARK: - Saving

    /// Saves, by way of a picture.
    ///
    /// `save_vibescape` is the verb an agent reaches for, and it can't be reached
    /// for in the old surface — the old tools had `create` and `update`, which
    /// is a distinction nobody should have to make before saving a shader. It
    /// picks by name, previews, and only then writes.
    private static func saveVibescape(_ arguments: [String: Any]) -> [String: Any] {
        guard let name = (arguments["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return errorResult("What should the vibescape be called? Pass a name.")
        }
        guard let code = arguments["code"] as? String else {
            return errorResult("There's no code to save.")
        }

        // Compile before anything else. A vibescape that doesn't compile isn't
        // worth a preview, and definitely isn't worth writing to disk.
        switch VibescapeCompiler.compile(body: code) {
        case .failed(let problem):
            return errorResult(failure(problem, name: name) + "\n\nNothing was saved.")
        case .compiled:
            break
        }

        let existing = CustomVibescapeStore.loadAll().first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }

        let author = (arguments["author"] as? String ?? existing?.author ?? "")
            .trimmingCharacters(in: .whitespaces)
        let rawURL = (arguments["url"] as? String ?? existing?.url ?? "").trimmingCharacters(in: .whitespaces)
        let description = (arguments["description"] as? String) ?? nil
        let paletteName = (arguments["palette"] as? String) ?? nil
        let targets = (arguments["audio_targets"] as? String) ?? nil

        let id = existing?.id ?? CustomVibescapeStore.uniqueSlug(from: name)
        var mode = existing ?? CustomVibescape(id: id, name: name, author: author,
                                             url: rawURL.isEmpty ? nil : rawURL,
                                             shader: code, enabled: true, modified: Date())
        mode.shader = code
        // It compiled, so it should be on. The app switches a vibescape off when
        // it fails to compile and writes that into the file — and nothing else
        // turns it back on, so a vibescape that failed once (on an older build,
        // say) stays invisible for good. A save that compiles is also a re-enable.
        mode.enabled = true
        if !author.isEmpty { mode.author = author }
        if !rawURL.isEmpty { mode.url = rawURL } else if existing != nil { mode.url = nil }
        // The extras are kept as a header comment, so they survive a save from
        // the app or from an agent that doesn't pass them again — and so
        // get_vibescape can hand them back.
        mode.shader = Self.annotate(mode.shader, description: description, palette: paletteName, targets: targets)
        mode.modified = Date()

        // Draw it before writing, so "saved" comes with evidence of what was
        // saved rather than a promise.
        var content: [[String: Any]] = []
        var note: String
        let wantsPreview = (arguments["preview"] as? Bool) ?? true
        if wantsPreview {
            var options = PreviewOptions(width: 480, height: 270)
            if let paletteName, let match = paletteNamed(paletteName) { options.palette = match }
            switch VibescapeRender.render(body: code, options: options) {
            case .success(let preview):
                if let data = pngData(preview.image) {
                    content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"])
                }
                note = "Saved \(existing == nil ? "new vibescape" : "changes") \"\(mode.name)\" as \(mode.id). This is what you saved:"
            case .failure(let problem):
                // It compiled a moment ago, so this is a drawing problem rather
                // than a compile one. Still worth saving: it's the author's
                // call, and it's compiled.
                note = "Saved \(mode.name), but it couldn't be drawn: \(problem.message)"
            }
        } else {
            note = "Saved \(existing == nil ? "new vibescape" : "changes") \"\(mode.name)\" as \(mode.id)."
        }

        do {
            try CustomVibescapeStore.save(mode)
        } catch {
            return errorResult("Couldn't save the vibescape: \(error.localizedDescription)")
        }

        let extras = [description, paletteName.map { "palette: \($0)" }, targets.map { "reacts to: \($0)" }]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if !extras.isEmpty { note += "\n\n\(extras.joined(separator: "\n"))" }
        note += "\n\nIt's in the vibescape list now, and the app shows it — a vibescape that appears or changes on disk is the one on screen, the same as saving one in the app. \(CustomVibescapeStore.folder.path)/\(mode.id).json"

        if content.isEmpty { return textResult(note) }
        content.append(["type": "text", "text": note])
        return ["content": content]
    }

    /// Writes the extra fields into the shader as a comment, so they're stored
    /// with the code rather than in a sidecar nothing reads.
    private static func annotate(_ code: String, description: String?, palette: String?, targets: String?) -> String {
        var lines: [String] = []
        if let description, !description.isEmpty { lines.append("// \(description)") }
        if let palette, !palette.isEmpty { lines.append("// palette: \(palette)") }
        if let targets, !targets.isEmpty { lines.append("// reacts to: \(targets)") }
        guard !lines.isEmpty else { return code }
        // Replace an existing header rather than stacking one on each save.
        var body = code
        while body.hasPrefix("//") {
            guard let newline = body.firstIndex(of: "\n") else { body = ""; break }
            body = String(body[body.index(after: newline)...])
            while body.hasPrefix("\n") { body = String(body.dropFirst()) }
        }
        return lines.joined(separator: "\n") + "\n" + body
    }

    // MARK: - Comparing two versions

    /// Two versions, one picture, the same uniforms.
    ///
    /// "v3 is better" is a memory. Drawing both with the same bass and the same
    /// time turns it into something you can look at.
    private static func diffVibescape(_ arguments: [String: Any]) -> [String: Any] {
        guard let codeB = arguments["code_b"] as? String else {
            return errorResult("Which version do you want to compare? Pass `code_b` for the new one.")
        }
        var codeA = arguments["code_a"] as? String
        var labelA = (arguments["label_a"] as? String) ?? "before"
        var labelB = (arguments["label_b"] as? String) ?? "after"

        if codeA == nil, let name = arguments["name"] as? String {
            let saved = CustomVibescapeStore.loadAll().first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.id == name
            }
            guard let saved else {
                return errorResult("There's no saved vibescape called \(name). Pass both versions with `code_a` and `code_b`.")
            }
            codeA = saved.shader
            labelA = saved.name
            if labelB == "after" { labelB = "new version" }
        }
        guard let left = codeA else {
            return errorResult("Pass the other version as `code_a`, or name a saved vibescape with `name`.")
        }

        var options = PreviewOptions(width: 440, height: 440)
        if let paletteName = arguments["palette"] as? String, let match = paletteNamed(paletteName) {
            options.palette = match
        }

        func render(_ code: String) -> Result<NSImage, ShaderProblem> {
            VibescapeRender.render(body: code, options: options).map { $0.image }
        }
        let leftImage = render(left)
        let rightImage = render(codeB)

        // One side failing shouldn't lose the other: seeing that v2 still
        // compiles while v3 broke is the most useful thing this tool can say.
        var warnings: [String] = []
        if case .failure(let problem) = leftImage {
            warnings.append("The left version (\(labelA)) failed: \(problem.message)")
        }
        if case .failure(let problem) = rightImage {
            warnings.append("The right version (\(labelB)) failed: \(problem.message)")
        }
        let usable = leftImage.flatMap { l in rightImage.map { (l, $0) } }
        guard case .success(let images) = usable else {
            return errorResult("Neither version could be drawn.\n\n" + warnings.joined(separator: "\n"))
        }
        guard let side = sideBySide(images.0, images.1) else {
            return errorResult("Both versions drew, but the picture couldn't be put together.")
        }

        var note = "\(labelA) on the left, \(labelB) on the right, drawn with the same uniforms"
        note += " through the \(options.palette?.name ?? livePaletteName()) palette."
        if !warnings.isEmpty {
            note += "\n\n" + warnings.joined(separator: "\n")
        }
        return imageResult(side, text: note)
    }

    /// Puts two pictures side by side with a divider.
    private static func sideBySide(_ left: NSImage, _ right: NSImage) -> NSImage? {
        guard let l = cgImage(left), let r = cgImage(right) else { return nil }
        let gap = 6
        let totalWidth = l.width + r.width + gap
        let height = max(l.height, r.height)
        guard let ctx = CGContext(data: nil, width: totalWidth, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil }
        ctx.setFillColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: totalWidth, height: height))
        // CoreGraphics is bottom-up; put the left picture on the left.
        ctx.draw(l, in: CGRect(x: 0, y: 0, width: l.width, height: l.height))
        ctx.draw(r, in: CGRect(x: l.width + gap, y: 0, width: r.width, height: r.height))
        guard let combined = ctx.makeImage() else { return nil }
        let image = NSImage(size: NSSize(width: combined.width, height: combined.height))
        image.addRepresentation(NSBitmapImageRep(cgImage: combined))
        return image
    }

    private static func cgImage(_ image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }


    // MARK: - The tools

    private static func listVibescapes() -> [String: Any] {
        let customs = CustomVibescapeStore.loadAll()
        var content: [[String: Any]] = []

        // The pictures go first. "What's already been made" is a visual
        // question, and eighteen lines of names answers it much worse than
        // eighteen thumbnails do — you can see that someone's already done the
        // concentric rings, without reading a word.
        var shipped = PreviewOptions(width: 160, height: 160, grade: false)
        for vibescape in Vibescape.allCases where vibescape != .autoScan {
            if case .success(let preview) = VibescapeRender.render(builtin: vibescape, options: shipped),
               let data = pngData(preview.image) {
                content.append(["type": "text", "text": "\(vibescape.displayName)"])
                content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"])
            }
        }
        for mode in customs {
            if case .success(let preview) = VibescapeRender.render(body: mode.shader, options: shipped),
               let data = pngData(preview.image) {
                content.append(["type": "text", "text": "\(mode.name)\(mode.author.isEmpty ? "" : " — by \(mode.author)") — id \(mode.id), changed \(relative(mode.modified))"])
                content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"])
            }
        }

        var lines: [String] = []
        for vibescape in Vibescape.allCases where vibescape != .autoScan {
            lines.append("shipped  \(vibescape.rawValue)")
        }
        for mode in customs {
            lines.append("yours    \(mode.id)  — \(mode.name)\(mode.author.isEmpty ? "" : "  by \(mode.author)")")
        }
        lines.append("")
        lines.append("Each is drawn above its name. The ones with a `yours` id are the user's own — read one with get_vibescape, replace one with save_vibescape using the same name, or make a new one with save_vibescape.")
        lines.append("These previews are drawn ungraded, so they show each vibescape's own colours rather than the current palette.")
        content.append(["type": "text", "text": lines.joined(separator: "\n")])
        return ["content": content]
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }

    private static func getVibescape(_ arguments: [String: Any]) -> [String: Any] {
        guard let id = arguments["id"] as? String else {
            return errorResult("Which mode? Pass the id from list_vibescapes.")
        }
        guard let mode = CustomVibescapeStore.loadAll().first(where: { $0.id == id }) else {
            return errorResult("There's no vibescape with the id \(id).")
        }
        let header = """
        \(mode.name)\(mode.author.isEmpty ? "" : " — by \(mode.author)")\(mode.url.map { " — \($0)" } ?? "")
        id: \(mode.id)

        """
        return textResult(header + mode.shader)
    }

    private static func createVibescape(_ arguments: [String: Any]) -> [String: Any] {
        guard let name = arguments["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return errorResult("What should the mode be called? Pass a name.")
        }
        guard let code = arguments["code"] as? String else {
            return errorResult("There's no code to save.")
        }
        let author = (arguments["author"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let url = (arguments["url"] as? String ?? "").trimmingCharacters(in: .whitespaces)

        // Never save something that doesn't run: a vibescape that can't compile
        // is a broken vibescape, and the user would have to work out why.
        switch VibescapeCompiler.compile(body: code) {
        case .failed(let problem):
            return errorResult(failure(problem, name: name) + "\n\nNothing was saved.")
        case .compiled:
            break
        }

        let id = CustomVibescapeStore.uniqueSlug(from: name)
        let mode = CustomVibescape(id: id, name: name, author: author,
                              url: url.isEmpty ? nil : url,
                              shader: code, enabled: true, modified: Date())
        do {
            try CustomVibescapeStore.save(mode)
        } catch {
            return errorResult("Couldn't save the mode: \(error.localizedDescription)")
        }
        return textResult("""
        Saved "\(name)" as \(id). It is in the mode list now, and in Auto Scan.
        It lives in \(CustomVibescapeStore.folder.path) as \(id).json.
        """)
    }

    private static func updateVibescape(_ arguments: [String: Any]) -> [String: Any] {
        guard let id = arguments["id"] as? String else {
            return errorResult("Which mode? Pass the id from list_vibescapes.")
        }
        guard var mode = CustomVibescapeStore.loadAll().first(where: { $0.id == id }) else {
            return errorResult("There's no vibescape with the id \(id).")
        }
        if let code = arguments["code"] as? String {
            switch VibescapeCompiler.compile(body: code) {
            case .failed(let problem):
                return errorResult(failure(problem, name: mode.name) + "\n\nNothing was changed.")
            case .compiled:
                mode.shader = code
            }
        }
        if let name = arguments["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            mode.name = name
        }
        if let author = arguments["author"] as? String {
            mode.author = author.trimmingCharacters(in: .whitespaces)
        }
        if let url = arguments["url"] as? String {
            let trimmed = url.trimmingCharacters(in: .whitespaces)
            mode.url = trimmed.isEmpty ? nil : trimmed
        }
        mode.modified = Date()
        do {
            try CustomVibescapeStore.save(mode)
        } catch {
            return errorResult("Couldn't save the mode: \(error.localizedDescription)")
        }
        return textResult("Saved changes to \"\(mode.name)\" (\(mode.id)).")
    }

    private static func deleteVibescape(_ arguments: [String: Any]) -> [String: Any] {
        guard let id = arguments["id"] as? String else {
            return errorResult("Which mode? Pass the id from list_vibescapes.")
        }
        guard let mode = CustomVibescapeStore.loadAll().first(where: { $0.id == id }) else {
            return errorResult("There's no vibescape with the id \(id).")
        }
        guard CustomVibescapeStore.delete(id: id) else {
            return errorResult("Couldn't delete \(id).")
        }
        return textResult("Deleted \"\(mode.name)\". It can't be undone.")
    }

    // MARK: - What the app is hearing

    /// What Vibresia is hearing right now.
    ///
    /// The same readings the app's own visuals use: the genre it suspects,
    /// the instruments it thinks are playing, the tempo, and the levels. An
    /// agent writing a vibescape can look at this and write something that
    /// suits the music actually playing, rather than guessing.
    ///
    /// These come from the app that has the audio. macOS allows only one
    /// system-audio tap at a time, so the server can't listen for itself —
    /// the running app writes down what it hears and this reads it.
    private static func whatIHear() -> [String: Any] {
        let path = SupportFolder.folder("what-it-hears.json")
        guard let data = try? Data(contentsOf: path),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return errorResult("""
            Vibresia isn't running, so there's nothing to listen to. Open the app, \
            share some audio, and ask again.
            """)
        }
        // If the app has quit, the file is left behind. Say so rather than
        // reporting a stale reading as if it were live.
        let age = Date().timeIntervalSince1970 - (state["at"] as? Double ?? 0)
        if age > 15 {
            return errorResult("""
            Vibresia was last heard \(Int(age)) seconds ago, so it may have quit. \
            Open the app and ask again.
            """)
        }

        var lines: [String] = []

        // Genre. The app is guessing, and says so — the confidence is how
        // much to trust it.
        let suspected = (state["genre_suspected"] as? Bool) ?? true
        let confidence = (state["genre_confidence"] as? Double) ?? 0
        let genre = suspected
            ? "\(state["genre"] as? String ?? "?") (suspected, \(Int(confidence * 100))% confident)"
            : "\(state["genre"] as? String ?? "?") (pinned by you)"
        lines.append("Genre: \(genre)")

        // Where in the track we are, when the player says.
        if (state["uTrackKnown"] as? Double ?? 0) > 0 {
            let position = state["uTrackPos"] as? Double ?? 0
            let length = state["uTrackDuration"] as? Double ?? 0
            let progress = length > 0 ? position / length : 0
            let stamp = String(format: "%d:%02d", Int(position) / 60, Int(position) % 60)
            lines.append("Track: \(stamp) into a \(String(format: "%.0f", length))s track (\(Int((progress * 100).rounded()))% through)")
        } else {
            lines.append("Track: no position to know — nothing playing is saying where it is")
        }

        // Instruments, the ones it can hear most strongly first.
        if let heard = state["instruments"] as? [[String: Any]], !heard.isEmpty {
            let top = heard
                .sorted { ($0["confidence"] as? Double ?? 0) > ($1["confidence"] as? Double ?? 0) }
                .prefix(3)
                .map { "\($0["name"] as? String ?? "?") \(Int(($0["confidence"] as? Double ?? 0) * 100))%" }
                .joined(separator: ", ")
            lines.append("Instruments: \(top) (suspected)")
        } else {
            lines.append("Instruments: none detected")
        }

        // Tempo and the beat.
        let bpm = state["bpm"] as? Double ?? 0
        if bpm > 0 {
            var tempo = "\(Int(bpm.rounded())) bpm"
            if (state["beat"] as? Bool) == true {
                let strength = (state["beat_strength"] as? Double) ?? 0
                tempo += ", on a beat now (strength \(Int(strength * 100))%)"
            }
            lines.append("Tempo: \(tempo)")
        } else {
            lines.append("Tempo: not found yet")
        }

        // The levels, which are the numbers the uniforms carry.
        lines.append("Levels: level \(d(state["level"])), bass \(d(state["bass"])), mid \(d(state["mid"])), treble \(d(state["treble"]))")

        // The shape of the spectrum, thinned out so it's readable.
        if let bands = state["bands"] as? [Double], !bands.isEmpty {
            let groups = 24
            let per = max(1, bands.count / groups)
            var summarised: [Double] = []
            for start in stride(from: 0, to: bands.count, by: per) {
                let slice = bands[start..<min(start + per, bands.count)]
                summarised.append(slice.reduce(0, +) / Double(slice.count))
            }
            lines.append("Spectrum (low to high, \(summarised.count) bands): \(summarised.map { d($0) }.joined(separator: " "))")
        }

        let idle = (state["source_idle"] as? Bool) ?? true
        lines.append("Sound: \(idle ? "quiet" : "playing")")
        lines.append("On screen: \(state["vibescape"] as? String ?? "?")")
        lines.append("Palette: \(state["palette"] as? String ?? "?")")

        // The same reading as data, because some of the things an agent wants to
        // do with this — decide the intensity a genre deserves, check a band
        // index against the spectrum — are arithmetic, and prose makes them
        // guesswork again.
        let fullBands = (state["bands"] as? [Double]) ?? []
        let dominant = fullBands.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(5)
            .map { $0.offset }
            .sorted()
        let structured: [String: Any] = [
            "genre": [state["genre"] as? String ?? "?"],
            "genre_confidence": confidence,
            "genre_suspected": suspected,
            "tempo_bpm": bpm > 0 ? Int(bpm.rounded()) : 0,
            "dominant_bands": dominant,
            "level": state["level"] as? Double ?? 0,
            "bass": state["bass"] as? Double ?? 0,
            "mid": state["mid"] as? Double ?? 0,
            "treble": state["treble"] as? Double ?? 0,
            "playing": !idle,
            "vibescape": state["vibescape"] as? String ?? "?",
            "palette": state["palette"] as? String ?? "?",
        ]
        lines.append("")
        lines.append(json(structured))

        return textResult(lines.joined(separator: "\n"))
    }

    /// One number, trimmed so a list of them stays readable.
    private static func d(_ value: Any?) -> String {
        if let v = value as? Double { return String(format: "%.2f", v) }
        if let v = value as? Float { return String(format: "%.2f", v) }
        if let v = value as? Int { return String(format: "%.2f", Double(v)) }
        return "0.00"
    }

    /// A number with no trailing zeros, for times in a note.
    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    /// A plain text result.
    private static func textResult(_ body: String) -> [String: Any] {
        ["content": [["type": "text", "text": body]]]
    }

    /// A failure. MCP marks a tool error with `isError`, and the client
    /// shows the text to the model as the result of the attempt.
    private static func errorResult(_ body: String) -> [String: Any] {
        ["content": [["type": "text", "text": body]], "isError": true]
    }

    /// A compiler failure, written for whoever asked for the code.
    private static func failure(_ problem: ShaderProblem, name: String) -> String {
        // A shader that writes to fragColor compiles fine and then does
        // nothing useful, so calling it a compile failure would be a lie.
        let headline = problem.kind == .wrongOutput
            ? "\(name) wouldn't work the way it's written."
            : "\(name) doesn't compile."
        var text = "\(headline)\n\n\(problem.message)"
        if let line = problem.line {
            text += "\n\nLook at line \(line) of the code you wrote."
        }
        if !problem.driverLog.isEmpty {
            text += "\n\nThe graphics system said:\n\(problem.driverLog.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return text
    }
}
