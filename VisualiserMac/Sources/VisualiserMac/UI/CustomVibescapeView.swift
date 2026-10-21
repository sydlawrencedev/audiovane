import SwiftUI
import AppKit

/// The Custom Vibescape sheet: the way a person adds a vibescape of their own.
///
/// It opens on a choice of three routes, because "write some code" is a
/// dead end for most people and the app shouldn't pretend otherwise:
/// paste in code they already have, ask an AI assistant to write it, or open
/// a file somebody sent them. Whichever route they take, they end in the
/// same place — a box of code, a name, and a Test button that tells them
/// honestly whether it works.
struct CustomVibescapeView: View {
    /// Where in the flow they are.
    enum Step {
        case choose
        case write
        case ai
        /// Setting an agent up to talk to Vibresia.
        case mcp
    }

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// False for the headless UI shots, which render the panel without a
    /// window. `ImageRenderer` can't lay out a scroll view, so the shots use
    /// a plain stack and get the whole panel.
    var scrollable: Bool = true

    @State private var step: Step = .choose
    @State private var name: String = ""
    @State private var author: String = ""
    @State private var url: String = ""
    @State private var code: String = CustomVibescapeGuide.starterTemplate
    @State private var problem: ShaderProblem?
    @State private var preview: NSImage?
    @State private var testing = false
    @State private var showHelp = false
    @State private var isEditing = false
    @State private var editingID: String?

    /// Which of the four opening offers led to the vibescape that got saved, so
    /// `custom_vibescape_saved` can say how people get here. `unknown` means they
    /// came straight to the code step (editing an existing vibescape).
    @State private var routeChosen = "unknown"

    /// A vibescape already on disk, being edited rather than created.
    ///
    /// `initialStep` exists for the headless UI shots, which render each
    /// step of the flow to check it reads well.
    init(editing mode: CustomVibescape? = nil, initialStep: Step = .choose, scrollable: Bool = true) {
        _name = State(initialValue: mode?.name ?? "")
        _author = State(initialValue: mode?.author ?? "")
        _url = State(initialValue: mode?.url ?? "")
        _code = State(initialValue: mode?.shader ?? CustomVibescapeGuide.starterTemplate)
        _isEditing = State(initialValue: mode != nil)
        _editingID = State(initialValue: mode?.id)
        // Editing an existing vibescape goes straight to the code — there's
        // nothing to choose, the vibescape is already there.
        _step = State(initialValue: mode != nil ? .write : initialStep)
        self.scrollable = scrollable
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .choose: chooseStep
            case .write: writeStep
            case .ai: aiStep
            case .mcp: mcpStep
            }
        }
        .frame(width: 640, height: 560)
        .background(Color(red: 0.05, green: 0.02, blue: 0.09))
    }

    // MARK: - Step one: how do you want to do this?

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make your own vibescape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("A world of your own, drawn by your music. Write it yourself, or let an AI write it for you.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                SheetCloseButton()
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 18)

            VStack(spacing: 10) {
                RouteButton(
                    glyph: "cpu",
                    title: "Vibe with your AI of choice",
                    detail: "Point any AI assistant at Vibresia and it can write a vibescape, check it works and show you the result."
                ) {
                    go(.mcp, via: "mcp")
                }
                RouteButton(
                    glyph: "wand.and.stars",
                    title: "Ask an AI to write it",
                    detail: "Copy a short description to your AI assistant, paste the answer back. Easiest if you've never written code."
                ) {
                    go(.ai, via: "ai_paste")
                }
                RouteButton(
                    glyph: "curlybraces",
                    title: "Paste code you already have",
                    detail: "For when you've written a vibescape, or had one written for you."
                ) {
                    go(.write, via: "paste_code")
                }
                RouteButton(
                    glyph: "folder",
                    title: "Open a file",
                    detail: "For a vibescape file somebody sent you, or one you saved earlier."
                ) {
                    routeChosen = "open_file"
                    Task { await Analytics.shared.track("custom_vibescape_route_chosen", ["route": "open_file"]) }
                    openFile()
                }
            }
            .padding(.horizontal, 22)

            Spacer()

            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Text("Your vibescapes are saved on this Mac, in your Application Support folder. Nothing is uploaded.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.4))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.7))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }

    /// What you'd actually type to an agent once it's wired up.
    ///
    /// Short on purpose. The long `CustomVibescapeGuide.agentPrompt` is for the
    /// copy-and-paste route on the step before; with an agent connected you are
    /// having a conversation, not pasting a brief, and a wall of rules makes no
    /// sense to say out loud. This is the shape of a first ask — and it is
    /// worth being able to copy, because retyping an example is how it gets
    /// subtly wrong.
    private static let sampleAsk =
        "\"Make a vibescape of slow blue smoke that swirls to the bass.\""

    // MARK: - Step two: the code

    private var writeStep: some View {
        VStack(spacing: 0) {
            bar

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    nameField
                    creditFields
                    codeEditor
                }
                .frame(maxWidth: .infinity)

                // The explanation and the result live in a column on the
                // right, so the code keeps its full height and the words sit
                // beside it rather than under it.
                VStack(alignment: .leading, spacing: 12) {
                    helpButton
                    resultPanel
                    Spacer(minLength: 0)
                }
                .frame(width: 210)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
    }

    private var bar: some View {
        HStack {
            Button {
                // Editing an existing vibescape has no chooser to go back to, and
                // the write step has no cancel button, so the arrow closes
                // the sheet instead.
                if isEditing {
                    dismiss()
                } else {
                    step = .choose
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.7))
            }
            .buttonStyle(.plain)
            .help(isEditing ? "Close" : "Back to the options")

            Text(isEditing ? "Edit your vibescape"
                 : step == .ai ? "Ask an AI to write it"
                 : step == .mcp ? "Set up your agent"
                 : "Paste your vibescape")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            // The bar already has a back arrow, which steps back through the
            // flow rather than closing it — on the last step, and when editing,
            // it does close. That conditional is the problem: whether there's a
            // way out depends on which step you're on. The ✕ always closes.
            SheetCloseButton()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color(white: 0.45))
            TextField("My Vibescape", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
        }
        .padding(.bottom, 10)
    }

    /// Who made it, and where to find more. Both optional — a vibescape someone
    /// wrote for themselves doesn't need credit, and most vibescapes have no
    /// home page.
    private var creditFields: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Made by")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color(white: 0.45))
                TextField("Your name", text: $author)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Link")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color(white: 0.45))
                TextField("https://…", text: $url)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
            }
        }
        .padding(.bottom, 10)
    }

    private var codeEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(problem == nil ? Color.white.opacity(0.1) : Color(red: 1, green: 0.4, blue: 0.3).opacity(0.6),
                                lineWidth: 1)
                )
            TextEditor(text: $code)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.88))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(7)
                .onChange(of: code) { _ in
                    // Any edit invalidates the last test result — showing a
                    // green tick next to changed code would be a lie.
                    problem = nil
                    preview = nil
                }
        }
    }

    private var helpButton: some View {
        Button {
            showHelp.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showHelp ? "chevron.down" : "questionmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text("What's available?")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(white: 0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    /// The result of the last test, or the last failure.
    @ViewBuilder
    private var resultPanel: some View {
        if showHelp {
            ScrollView {
                Text(CustomVibescapeGuide.reference)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color(white: 0.72))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3))
            )
            .frame(height: 300)
        } else if testing {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Testing…").font(.system(size: 11)).foregroundStyle(Color(white: 0.6))
            }
        } else if let problem {
            failureView(problem)
        } else if preview != nil {
            successView
        } else {
            Text("Press Test to check it works. Nothing is added until it does.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failureView(_ problem: ShaderProblem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.2))
                Text(problem.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.45))
            }
            Text(problem.message)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(white: 0.8))
                .fixedSize(horizontal: false, vertical: true)
            if !problem.driverLog.isEmpty {
                DisclosureGroup("Technical details") {
                    Text(problem.driverLog)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                        .textSelection(.enabled)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(Color(white: 0.5))
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.25, green: 0.1, blue: 0.05).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(red: 1, green: 0.55, blue: 0.2).opacity(0.4), lineWidth: 1)
                )
        )
    }

    private var successView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.5))
                Text("It works")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.95, blue: 0.65))
            }
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text("This is what it looks like.")
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.05, green: 0.18, blue: 0.08).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(red: 0.4, green: 0.9, blue: 0.5).opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Reset to example") {
                code = CustomVibescapeGuide.starterTemplate
                problem = nil
                preview = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color(white: 0.55))
            .help("Put the starting example back")

            Spacer()

            Button("Test") { test() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.14))
                )
                .disabled(testing)

            Button(isEditing ? "Save" : "Add vibescape") { save() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 1, green: 0.17, blue: 0.84))
                )
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
                .help(canSave ? "" : "Test it first — a vibescape is only added once it works.")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// A vibescape can only be added once it has been shown to work, and it needs
    /// a name to go by.
    private var canSave: Bool {
        preview != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Step two: the AI route

    /// Setting an agent up.
    ///
    /// The instructions live here rather than only on the website because
    /// the path is the part that goes wrong: the agent has to launch this
    /// app, wherever it happens to be installed, and a fixed example
    /// doesn't survive the app being moved.
    private var mcpStep: some View {
        VStack(spacing: 0) {
            bar
            if scrollable {
                ScrollView { mcpBody }
            } else {
                mcpBody
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.7))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }

    private var mcpBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Let your agent write it")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("""
                Vibresia has a small local server that AI assistants can talk to. \
                Point an agent at it and it can write a vibescape, check that it \
                compiles, look at what it drew and try again — no copying code \
                back and forth.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.75))
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Give your agent this")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color(white: 0.5))
                CopyableRow(text: MCPSetup.command, monospaced: true,
                           help: "Copy the setup command")
                Text("""
                The name, the program to run and the argument to run it with. \
                Every agent that speaks MCP wants those three, just spelled its \
                own way.
                """)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(white: 0.6))
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Then just ask it for what you want")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                // A CopyableRow, like the setup command above and like the
                // prompt on the step before. This was the one piece of text in
                // the flow you could only read and then retype, which is a
                // strange thing to ask of an example — people copy it rather
                // than remember it, and retyping it exactly is the one way to
                // get a subtly wrong prompt.
                CopyableRow(text: Self.sampleAsk, help: "Copy this example")
                Text("""
                It can also ask what you're hearing right now — the suspected \
                genre and instruments, the tempo, the levels — so it can write \
                something that suits the music you're actually playing.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.75))
                .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if let url = URL(string: MCPSetup.pageURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                    Text("Setup for each agent, in full")
                    Spacer()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .pointingHand()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var aiStep: some View {
        VStack(spacing: 0) {
            bar
            if scrollable {
                ScrollView { aiBody }
            } else {
                aiBody
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.7))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }

    private var aiBody: some View {
        VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("How this works")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("""
                        1. Copy the text below.
                        2. Paste it into ChatGPT, Claude, Gemini — any AI assistant — along with a \
                        description of the visual you want. Something like "slow-moving blue smoke that \
                        swirls to the bass" is plenty.
                        3. Copy the code it gives you back.
                        4. Press "Paste the code" below, then Test.
                        """)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    // The better way round: an agent that can call Vibresia
                    // directly doesn't have to be handed the code by hand.
                    // The instructions live on a page of their own, because
                    // there's more than one kind of agent to set up.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Or let the agent drive Vibresia itself")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                step = .mcp
                            } label: {
                                Label("How to set it up", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color(white: 0.85))
                            }
                            .buttonStyle(.plain)
                        }
                        Text("""
                        Vibresia has a local server that agents can talk to, so they can write a \
                        vibescape, check it works, look at the result and fix it — without you \
                        copying any code. It works with any agent that speaks MCP.
                        """)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    }


            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("The prompt to copy")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color(white: 0.5))
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CustomVibescapeGuide.agentPrompt, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(white: 0.85))
                    }
                    .buttonStyle(.plain)
                }
                Text(CustomVibescapeGuide.agentPrompt)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color(white: 0.75))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.black.opacity(0.35))
                    )
            }

            HStack {
                Spacer()
                Button {
                    step = .write
                } label: {
                    Text("Paste the code →")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 1, green: 0.17, blue: 0.84))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
    }

    // MARK: - Doing the work

    /// Compiles the code and, if it works, draws a picture of it.
    private func test() {
        testing = true
        problem = nil
        preview = nil
        // A turn later, so the spinner is actually on screen before the
        // compile blocks the main thread.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let id = editingID ?? "preview"
            switch app.renderer.installCustomShader(id: id, body: code) {
            case .failure(let p):
                problem = p
                Task { await Analytics.shared.track("custom_vibescape_tested", [
                    "ok": false, "kind": p.analyticsKindName, "line": p.line ?? 0,
                    "editing": isEditing, "route": routeChosen,
                ]) }
            case .success:
                preview = renderPreview(id: id)
                if preview == nil {
                    problem = ShaderProblem(
                        kind: .compileFailed,
                        message: "It compiled, but it couldn't be drawn. Try making it simpler.")
                }
                // Compiling and drawing are separate failures, and only knowing
                // which one happened tells you whether the problem is the code
                // or the graphics driver.
                let drew = preview != nil
                Task { await Analytics.shared.track("custom_vibescape_tested", [
                    "ok": drew, "kind": drew ? "ok" : "notDrawn",
                    "editing": isEditing, "route": routeChosen,
                ]) }
            }
            testing = false
        }
    }

    /// Draws the vibescape offscreen and returns the picture.
    private func renderPreview(id: String) -> NSImage? {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("audiovane-preview-\(id).png")
        app.renderer.renderToPNG(width: 480, height: 270, mode: .custom(id), frames: 12, path: path)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return NSImage(contentsOfFile: path)
    }

    private func save() {
        let finalName = name.trimmingCharacters(in: .whitespaces)
        let finalAuthor = author.trimmingCharacters(in: .whitespaces)
        // A link is only kept if it looks like one, so a half-typed address
        // doesn't end up as a broken link on the card.
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        let finalURL = trimmedURL.isEmpty ? nil : trimmedURL
        let result: Result<CustomVibescape, ShaderProblem>
        if let id = editingID {
            result = app.updateCustomVibescape(id: id, name: finalName, author: finalAuthor,
                                          url: finalURL, shader: code)
        } else {
            result = app.addCustomVibescape(name: finalName, author: finalAuthor,
                                       url: finalURL, shader: code)
        }
        switch result {
        case .success:
            // Whether they filled in an author or a link is the only signal that
            // says whether anyone intends this vibescape to be shared, as
            // opposed to being a private experiment.
            Task { await Analytics.shared.track("custom_vibescape_saved", [
                "editing": editingID != nil, "route": routeChosen,
                "has_author": !finalAuthor.isEmpty, "has_url": finalURL != nil,
            ]) }
            dismiss()
        case .failure(let p):
            problem = p
            preview = nil
            Task { await Analytics.shared.track("custom_vibescape_failed", [
                "stage": "save", "kind": p.analyticsKindName, "line": p.line ?? 0,
                "editing": editingID != nil, "route": routeChosen,
            ]) }
        }
    }

    /// Records which of the four opening offers someone took, so a vibescape
    /// that ends up saved can be attributed back to the route that led to it.
    private func go(_ next: Step, via route: String) {
        routeChosen = route
        Task { await Analytics.shared.track("custom_vibescape_route_chosen", ["route": route]) }
        step = next
    }

    /// Opens a shader file somebody sent.
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a vibescape file — one that contains a render() function."
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                code = text
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = url.deletingPathExtension().lastPathComponent
                }
                step = .write
            } else {
                problem = ShaderProblem(
                    kind: .compileFailed,
                    message: "That file couldn't be read. Vibescape files are plain text — .glsl, .frag or .txt all work.")
            }
        }
    }
}

/// One of the three ways in.
private struct RouteButton: View {
    let glyph: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: glyph)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(red: 1, green: 0.17, blue: 0.84))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 1, green: 0.17, blue: 0.84).opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(white: 0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.35))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// A line of text with a button that copies it.
///
/// The paths and commands here are long and easy to mistype, so copying
/// them is the point.
private struct CopyableRow: View {
    let text: String
    var monospaced: Bool = true
    var help: String = "Copy"

    @State private var copied = false

    var body: some View {
        // The button is laid over the text rather than beside it. A long
        // path and a long command both want more room than the panel has,
        // and side by side the button ends up past the edge.
        ZStack(alignment: .trailing) {
            Text(text)
                .font(.system(size: 10, design: monospaced ? .monospaced : .default))
                .foregroundStyle(Color(white: 0.9))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                // A definite width, so a long path truncates instead of
                // making the row wider than the panel and pushing the
                // button off the end.
                .frame(maxWidth: 500, alignment: .leading)
                .padding(.trailing, 26)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(copied ? Color(red: 0.4, green: 0.9, blue: 0.5) : Color(white: 0.8))
            }
            .buttonStyle(.plain)
            .pointingHand()
            .help(help)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.35))
        )
    }
}
