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

    /// How the server is described, in a form every MCP client understands:
    /// a name, the program to run, and the arguments to run it with.
    ///
    /// Not a copy-and-paste command for one client in particular — there are
    /// too many of them, and each wants it spelled differently. The page at
    /// `pageURL` has the per-client versions.
    static var command: String {
        "vibresia -- \"\(serverPath)\" --mcp"
    }

    /// Where the setup instructions live — a page of their own, because
    /// there's more than one kind of agent to set up and the instructions
    /// differ for each.
    static let pageURL = "https://vibresia.com/agents"

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
