import Foundation
import AppKit

/// The tools the MCP server offers.
///
/// Kept in one place so the list an agent sees and the code that runs it
/// can't drift apart.
enum MCPTools {

    // MARK: - The list

    static let all: [[String: Any]] = [
        tool("list_vibscapes",
             "Every vibscape Vibresia has: the ones that ship with it and the user's own.",
             ["type": "object", "properties": [:]]),
        tool("get_vibscape",
             "The full source of one of the user's own vibscapes.",
             ["type": "object",
              "properties": ["id": ["type": "string", "description": "The vibscape's id, from list_vibscapes."]],
              "required": ["id"]]),
        tool("vibscape_reference",
             "What a vibscape can use: the uniforms the music drives, the helpers, and a worked example. Read this before writing a shader.",
             ["type": "object", "properties": [:]]),
        tool("test_vibscape",
             "Compile a shader and draw a picture of it, without saving anything. Returns the error in words if it doesn't compile.",
             ["type": "object",
              "properties": [
                "code": ["type": "string", "description": "The shader: a vec3 render(vec2 p, float t) function."],
                "name": ["type": "string", "description": "A name for the preview, for the error message."],
              ],
              "required": ["code"]]),
        tool("create_vibscape",
             "Save a new vibscape. The code is compiled first and is not saved if it doesn't work.",
             ["type": "object",
              "properties": [
                "name": ["type": "string", "description": "What the vibscape is called."],
                "code": ["type": "string", "description": "The shader: a vec3 render(vec2 p, float t) function."],
                "author": ["type": "string", "description": "Who wrote it. Shown under the vibscape's name."],
                "url": ["type": "string", "description": "A link to it, if there is one."],
              ],
              "required": ["name", "code"]]),
        tool("update_vibscape",
             "Change one of the user's own vibscapes. The code is compiled first and is not saved if it doesn't work.",
             ["type": "object",
              "properties": [
                "id": ["type": "string", "description": "The vibscape's id, from list_vibscapes."],
                "code": ["type": "string", "description": "New shader source."],
                "name": ["type": "string", "description": "A new name, if it should change."],
                "author": ["type": "string", "description": "A new author, if it should change."],
                "url": ["type": "string", "description": "A new link, if it should change."],
              ],
              "required": ["id"]]),
        tool("delete_vibscape",
             "Remove one of the user's own vibscapes. It cannot be undone.",
             ["type": "object",
              "properties": ["id": ["type": "string", "description": "The vibscape's id, from list_vibscapes."]],
              "required": ["id"]]),
    ]

    private static func tool(_ name: String, _ description: String, _ schema: [String: Any]) -> [String: Any] {
        ["name": name, "description": description, "inputSchema": schema]
    }

    // MARK: - Running one

    static func call(name: String, arguments: [String: Any]) -> [String: Any] {
        switch name {
        case "list_vibscapes": return listVibscapes()
        case "get_vibscape": return getVibscape(arguments)
        case "vibscape_reference": return textResult(CustomVibscapeGuide.reference)
        case "test_vibscape": return testVibscape(arguments)
        case "create_vibscape": return createVibscape(arguments)
        case "update_vibscape": return updateVibscape(arguments)
        case "delete_vibscape": return deleteVibscape(arguments)
        default:
            return errorResult("There's no tool called \(name).")
        }
    }

    // MARK: - The tools

    private static func listVibscapes() -> [String: Any] {
        let customs = CustomVibscapeStore.loadAll()
        var lines: [String] = []
        for (index, mode) in Vibscape.allCases.enumerated() {
            guard mode != .autoScan else { continue }
            lines.append("shipped  \(mode.rawValue)  —  \(mode.displayName)")
        }
        for mode in customs {
            lines.append("yours  \(mode.id)  —  \(mode.name)\(mode.author.isEmpty ? "" : "  by \(mode.author)")")
        }
        let text = """
        \(lines.joined(separator: "\n"))

        The ones with a `yours` label are the user's own. Read one with \
        get_vibscape, change it with update_vibscape, and make a new one with \
        create_vibscape.
        """
        return textResult(text)
    }

    private static func getVibscape(_ arguments: [String: Any]) -> [String: Any] {
        guard let id = arguments["id"] as? String else {
            return errorResult("Which mode? Pass the id from list_vibscapes.")
        }
        guard let mode = CustomVibscapeStore.loadAll().first(where: { $0.id == id }) else {
            return errorResult("There's no vibscape with the id \(id).")
        }
        let header = """
        \(mode.name)\(mode.author.isEmpty ? "" : " — by \(mode.author)")\(mode.url.map { " — \($0)" } ?? "")
        id: \(mode.id)

        """
        return textResult(header + mode.shader)
    }

    private static func testVibscape(_ arguments: [String: Any]) -> [String: Any] {
        guard let code = arguments["code"] as? String else {
            return errorResult("There's no code to test.")
        }
        let name = arguments["name"] as? String ?? "your mode"

        switch VibscapeCompiler.compile(body: code) {
        case .failed(let problem):
            return errorResult(failure(problem, name: name))
        case .compiled:
            break
        }

        // It compiles, so draw it — an agent can look at the picture, which
        // says more about a visualiser than "it compiled".
        switch VibscapeCompiler.preview(body: code, width: 480, height: 270) {
        case .failure(let problem):
            return errorResult(failure(problem, name: name))
        case .success(let image):
            var content: [[String: Any]] = [
                ["type": "text", "text": "\(name) compiles and draws. Here is what it looks like:"]
            ]
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                content.append(["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"])
            }
            return ["content": content]
        }
    }

    private static func createVibscape(_ arguments: [String: Any]) -> [String: Any] {
        guard let name = arguments["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return errorResult("What should the mode be called? Pass a name.")
        }
        guard let code = arguments["code"] as? String else {
            return errorResult("There's no code to save.")
        }
        let author = (arguments["author"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let url = (arguments["url"] as? String ?? "").trimmingCharacters(in: .whitespaces)

        // Never save something that doesn't run: a vibscape that can't compile
        // is a broken vibscape, and the user would have to work out why.
        switch VibscapeCompiler.compile(body: code) {
        case .failed(let problem):
            return errorResult(failure(problem, name: name) + "\n\nNothing was saved.")
        case .compiled:
            break
        }

        let id = CustomVibscapeStore.uniqueSlug(from: name)
        let mode = CustomVibscape(id: id, name: name, author: author,
                              url: url.isEmpty ? nil : url,
                              shader: code, enabled: true, modified: Date())
        do {
            try CustomVibscapeStore.save(mode)
        } catch {
            return errorResult("Couldn't save the mode: \(error.localizedDescription)")
        }
        return textResult("""
        Saved "\(name)" as \(id). It is in the mode list now, and in Auto Scan.
        It lives in \(CustomVibscapeStore.folder.path) as \(id).json.
        """)
    }

    private static func updateVibscape(_ arguments: [String: Any]) -> [String: Any] {
        guard let id = arguments["id"] as? String else {
            return errorResult("Which mode? Pass the id from list_vibscapes.")
        }
        guard var mode = CustomVibscapeStore.loadAll().first(where: { $0.id == id }) else {
            return errorResult("There's no vibscape with the id \(id).")
        }
        if let code = arguments["code"] as? String {
            switch VibscapeCompiler.compile(body: code) {
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
            try CustomVibscapeStore.save(mode)
        } catch {
            return errorResult("Couldn't save the mode: \(error.localizedDescription)")
        }
        return textResult("Saved changes to \"\(mode.name)\" (\(mode.id)).")
    }

    private static func deleteVibscape(_ arguments: [String: Any]) -> [String: Any] {
        guard let id = arguments["id"] as? String else {
            return errorResult("Which mode? Pass the id from list_vibscapes.")
        }
        guard let mode = CustomVibscapeStore.loadAll().first(where: { $0.id == id }) else {
            return errorResult("There's no vibscape with the id \(id).")
        }
        guard CustomVibscapeStore.delete(id: id) else {
            return errorResult("Couldn't delete \(id).")
        }
        return textResult("Deleted \"\(mode.name)\". It can't be undone.")
    }

    // MARK: - Saying things

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
        var text = "\(name) doesn't compile.\n\n\(problem.message)"
        if let line = problem.line {
            text += "\n\nLook at line \(line) of the code you wrote."
        }
        if !problem.driverLog.isEmpty {
            text += "\n\nThe graphics system said:\n\(problem.driverLog.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return text
    }
}
