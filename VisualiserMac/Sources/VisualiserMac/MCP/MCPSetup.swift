import Foundation

/// How to point an AI agent at Vibresia's MCP server.
///
/// The command has to name the app where it actually is, which is wherever
/// the user put it — so this is worked out at the time it's asked for rather
/// than written down in a README that goes stale the first time somebody
/// moves the app.
enum MCPSetup {
    /// The path to the app's binary, which is what the agent launches.
    static var serverPath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/Vibresia"
    }

    /// The command to add the server to an agent.
    static var command: String {
        "claude mcp add vibresia -- \"\(serverPath)\" --mcp"
    }

    /// The same thing for clients that read a JSON file rather than a
    /// command line.
    static var jsonEntry: String {
        """
        {
          "mcpServers": {
            "vibresia": {
              "command": "\(serverPath)",
              "args": ["--mcp"]
            }
          }
        }
        """
    }
}
