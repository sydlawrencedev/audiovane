import Foundation

/// A local MCP server, so an AI agent can write vibscapes for Vibresia.
///
/// The server speaks JSON-RPC 2.0 over stdin and stdout, one message per
/// line, which is how MCP clients launch a stdio server. It is the same
/// binary as the app, run with `--mcp`.
///
/// Two things it deliberately doesn't do: it doesn't listen on a port, and
/// it doesn't need the app to be running. A stdio server has no socket to
/// secure, and it reads and writes the same files the app does — so an agent
/// can create a vibscape whether or not Vibresia is open.
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
        // The app's own stdout is a log; in MCP vibscape stdout is the protocol
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
    /// is for, and that a vibscape is a shader.
    private static let instructions = """
    This server writes vibscapes for Vibresia, a macOS app for visual worlds \
    that move with your music. A vibscape is a fragment shader: a single function

        vec3 render(vec2 p, float t)

    that returns a colour. `p` is the position on screen, centred on 0,0 and \
    about -0.5 to 0.5 vertically; `t` is time in seconds.

    ## See it, don't imagine it

    This server can draw a vibscape and hand you the picture. That is the whole \
    point of it — don't describe a shader you haven't looked at.

        preview_vibscape({ code })                      one frame
        preview_vibscape_animation({ code })            several frames, one picture

    Both return a PNG. Try a constant, change it, look again — that's the loop, \
    and it costs about 40ms a frame. If code doesn't compile you get the driver's \
    own error in words rather than a blank picture.

    The uniforms are yours to set, which is how you find out how a vibscape \
    behaves when the music isn't playing:

        preview_vibscape({ code, options: { uniforms: { uBass: 0.9 } } })

    `uActive` defaults to 1, so a preview is never a black rectangle.

    ## Tune to the real numbers

    `get_uniform_snapshot` returns the values the app is drawing with right now, \
    including the ranges they run in. Use it instead of guessing a coefficient. \
    `what_i_hear` says what the music currently is — genre, tempo, spectrum — so \
    you can write something that suits it.

    `get_palette` explains why your colours come out shifted: every vibscape is \
    graded through the current palette after it draws. Pick colours from the \
    palette, or draw with `uPalette` directly, rather than bringing your own and \
    watching them turn teal.

    ## Save

    `save_vibscape` replaces the one with the same name, so there is no \
    create/update to choose between. It compiles first — code that doesn't work \
    is never written to disk — and it returns a picture of what it saved.

    Also here: `list_vibscapes` (every vibscape with a thumbnail, so you can see \
    what's been made), `get_vibscape` (read one), `diff_vibscape` (two versions, \
    one picture), `validate_vibscape` (compile without drawing), \
    `delete_vibscape`, and `vibscape_reference` for the full list of uniforms \
    and helpers.
    """
}
