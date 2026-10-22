import Foundation

/// A local MCP server, so an AI agent can write vibescapes for Vibresia.
///
/// The server speaks JSON-RPC 2.0 over stdin and stdout, one message per
/// line, which is how MCP clients launch a stdio server. It is the same
/// binary as the app, run with `--mcp`.
///
/// Two things it deliberately doesn't do: it doesn't listen on a port, and
/// it doesn't need the app to be running. A stdio server has no socket to
/// secure, and it reads and writes the same files the app does — so an agent
/// can create a vibescape whether or not Vibresia is open.
final class MCPServer {
    private let output: FileHandle
    private let input: FileHandle
    /// The version of the protocol this server speaks. The client sends the
    /// version it wants; if it's one we know, we use theirs.
    private let protocolVersion = "2024-11-05"

    init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        self.input = input
        self.output = output
    }

    /// Reads messages until stdin closes.
    func run() {
        // The app's own stdout is a log; in MCP vibescape stdout is the protocol
        // channel, so nothing else may write to it.
        setvbuf(stdout, nil, _IONBF, 0)
        NSLog("[MCP] listening on stdio")

        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = request["method"] as? String else {
                continue
            }
            handle(method: method, request: request)
        }

        // stdin closed, so the client has gone. A stdio server that outlives
        // its client is a process nobody will ever reap, and the client that
        // launched it is already waiting for it to go away — so leave.
        // `fflush` first: the last response is still sitting in the buffer.
        fflush(stdout)
        exit(0)
    }

    private func handle(method: String, request: [String: Any]) {
        let id = request["id"]
        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "vibresia", "version": serverVersion],
                "instructions": Self.instructions,
            ])
        case "notifications/initialized", "notifications/cancelled":
            break // nothing to answer
        case "ping":
            respond(id: id, result: [:])
        case "tools/list":
            respond(id: id, result: ["tools": MCPTools.all])
        case "tools/call":
            guard let params = request["params"] as? [String: Any],
                  let name = params["name"] as? String else {
                respond(id: id, error: ["code": -32602, "message": "Bad tool call"])
                return
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = MCPTools.call(name: name, arguments: arguments)
            respond(id: id, result: result)
        default:
            // An unknown method is the client's problem, but saying so is
            // better than silence.
            guard id != nil else { return }
            respond(id: id, error: ["code": -32601, "message": "Unknown method: \(method)"])
        }
    }

    // MARK: - Speaking the protocol

    private func respond(id: Any?, result: [String: Any]) {
        var message: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { message["id"] = id }
        send(message)
    }

    private func respond(id: Any?, error: [String: Any]) {
        var message: [String: Any] = ["jsonrpc": "2.0", "error": error]
        if let id { message["id"] = id }
        send(message)
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        output.write(Data((text + "\n").utf8))
    }

    private var serverVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// What the client is told about this server the first time it connects.
    /// Clients show this to the user, so it says the useful thing: what this
    /// is for, and that a vibescape is a shader.
    private static var instructions: String { """
    This server writes vibescapes for Vibresia, a macOS app for visual worlds \
    that move with your music. A vibescape is a fragment shader: a single function

        vec3 render(vec2 p, float t)

    that returns a colour. `p` is the position on screen, centred on 0,0 and \
    about -0.5 to 0.5 vertically; `t` is time in seconds.

    ## See it, don't imagine it

    This server can draw a vibescape and hand you the picture. That is the whole \
    point of it — don't describe a shader you haven't looked at.

        preview_vibescape({ code })                      one frame
        preview_vibescape_animation({ code })            several frames, one picture

    Both return a PNG. Try a constant, change it, look again — that's the loop, \
    and it costs about 40ms a frame. If code doesn't compile you get the driver's \
    own error in words rather than a blank picture.

    The uniforms are yours to set, which is how you find out how a vibescape \
    behaves when the music isn't playing:

        preview_vibescape({ code, options: { uniforms: { uBass: 0.9 } } })

    `uActive` defaults to 1, so a preview is never a black rectangle.

    ## Tune to the real numbers

    `get_uniform_snapshot` returns the values the app is drawing with right now, \
    including the ranges they run in. Use it instead of guessing a coefficient. \
    `what_i_hear` says what the music currently is — genre, tempo, spectrum — so \
    you can write something that suits it.

    ## The person is there too

    A vibescape can react to the person, not only to the music: `uMouse` is \
    the pointer in the same coordinates as `p`, `uMouseDown` says whether a \
    button is held, `uKey` and `uKeyDown` are the keyboard, and `uMidiNote`, \
    `uMidiVelocity`, `uMidiNotes`, `uMidiCC` and `uMidiCCValue` are the MIDI \
    keyboard. Set them on a preview to see what a vibescape does with them. \
    The app's own shortcuts still work, so a vibescape that reacts to a \
    number key sees the vibescape change as well.

    ## The app knows more than the waveform

    The app has three things a shader cannot work out for itself, and they are all \
    worth using:

    - **The genre.** The app works out what is playing — from the song's own \
      catalogue entry when the music app says what it is playing, and from the \
      sound when it cannot. The band vibescape's stage is chosen from it, and \
      every vibescape can read it as `uGenre`: 0 classical, 1 electronic, 2 rock, \
      3 pop, 4 hip-hop, 5 jazz, 6 blues, 7 country, 8 r&b, 9 ambient. A shader \
      that branches on it changes with the music in a way the bass alone cannot \
      manage.
    - **The sound itself.** Bass, mids, treble, the level, the beat, and 96 \
      numbers across the spectrum — all of it live, all of it in `what_i_hear` and \
      in the snapshot.
    - **The palette.** The two colours everything is graded through, and why a \
      colour you wrote comes out shifted.

    Ask `what_i_hear` before you write, not after. A vibescape written for the \
    music actually playing is a different thing from one written in the abstract.

    `get_palette` explains why your colours come out shifted: every vibescape is \
    graded through the current palette after it draws. Pick colours from the \
    palette, or draw with `uPalette` directly, rather than bringing your own and \
    watching them turn teal.

    ## Save

    `save_vibescape` replaces the one with the same name, so there is no \
    create/update to choose between. It compiles first — code that doesn't work \
    is never written to disk — and it returns a picture of what it saved.

    Also here: `list_vibescapes` (every vibescape with a thumbnail, so you can see \
    what's been made), `get_vibescape` (read one), `diff_vibescape` (two versions, \
    one picture), `validate_vibescape` (compile without drawing), \
    `delete_vibescape`, and `vibescape_reference` for the full list of uniforms \
    and helpers.

    The style below is the same text the prompt a user copies into an AI \
    assistant carries, and the same text the website's MCP server hands out, \
    so an agent is told the same thing whichever way it arrives.
    """ + "\n\n" + CustomVibescapeGuide.style }
}
