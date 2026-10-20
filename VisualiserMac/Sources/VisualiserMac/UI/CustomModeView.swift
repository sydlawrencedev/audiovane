import SwiftUI
import AppKit

/// The Custom Mode sheet: the way a person adds a mode of their own.
///
/// It opens on a choice of three routes, because "write some code" is a
/// dead end for most people and the app shouldn't pretend otherwise:
/// paste in code they already have, ask an AI assistant to write it, or open
/// a file somebody sent them. Whichever route they take, they end in the
/// same place — a box of code, a name, and a Test button that tells them
/// honestly whether it works.
struct CustomModeView: View {
    /// Where in the flow they are.
    enum Step {
        case choose
        case write
        case ai
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
    @State private var code: String = CustomModeGuide.starterTemplate
    @State private var problem: ShaderProblem?
    @State private var preview: NSImage?
    @State private var testing = false
    @State private var showHelp = false
    @State private var isEditing = false
    @State private var editingID: String?

    /// A mode already on disk, being edited rather than created.
    ///
    /// `initialStep` exists for the headless UI shots, which render each
    /// step of the flow to check it reads well.
    init(editing mode: CustomMode? = nil, initialStep: Step = .choose, scrollable: Bool = true) {
        _name = State(initialValue: mode?.name ?? "")
        _author = State(initialValue: mode?.author ?? "")
        _url = State(initialValue: mode?.url ?? "")
        _code = State(initialValue: mode?.shader ?? CustomModeGuide.starterTemplate)
        _isEditing = State(initialValue: mode != nil)
        _editingID = State(initialValue: mode?.id)
        // Editing an existing mode goes straight to the code — there's
        // nothing to choose, the mode is already there.
        _step = State(initialValue: mode != nil ? .write : initialStep)
        self.scrollable = scrollable
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .choose: chooseStep
            case .write: writeStep
            case .ai: aiStep
            }
        }
        .frame(width: 640, height: 560)
        .background(Color(red: 0.05, green: 0.02, blue: 0.09))
    }

    // MARK: - Step one: how do you want to do this?

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make your own mode")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text("A mode is a small piece of code that draws to the music. Pick whichever way suits you.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 18)

            VStack(spacing: 10) {
                RouteButton(
                    glyph: "wand.and.stars",
                    title: "Ask an AI to write it",
                    detail: "Copy a short description to your AI assistant, paste the answer back. Easiest if you've never written code."
                ) {
                    step = .ai
                }
                RouteButton(
                    glyph: "curlybraces",
                    title: "Paste code you already have",
                    detail: "For when you've written a mode, or had one written for you."
                ) {
                    step = .write
                }
                RouteButton(
                    glyph: "folder",
                    title: "Open a file",
                    detail: "For a mode file somebody sent you, or one you saved earlier."
                ) {
                    openFile()
                }
            }
            .padding(.horizontal, 22)

            // The agent route needs no copying and pasting at all, so it's
            // mentioned here as well as on the "ask an AI" page.
            VStack(alignment: .leading, spacing: 5) {
                Text("Have an agent write it for you?")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.8))
                Text("""
                Vibresia has a local server that agents can talk to. Give it this command and the \
                agent can write a mode, check it compiles, look at the result and try again — all \
                without you copying a thing.
                """)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(white: 0.6))
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(MCPSetup.command)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.85))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(MCPSetup.command, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Copy the setup command")
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.05))
                )
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            Spacer()

            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Text("Your modes are saved on this Mac, in your Application Support folder. Nothing is uploaded.")
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
                // Editing an existing mode has no chooser to go back to, and
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

            Text(isEditing ? "Edit your mode" : step == .ai ? "Ask an AI to write it" : "Paste your mode")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
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
            TextField("My Mode", text: $name)
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

    /// Who made it, and where to find more. Both optional — a mode someone
    /// wrote for themselves doesn't need credit, and most modes have no
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
                Text(CustomModeGuide.reference)
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
                code = CustomModeGuide.starterTemplate
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

            Button(isEditing ? "Save" : "Add mode") { save() }
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
                .help(canSave ? "" : "Test it first — a mode is only added once it works.")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// A mode can only be added once it has been shown to work, and it needs
    /// a name to go by.
    private var canSave: Bool {
        preview != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Step two: the AI route

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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Or let the agent drive Vibresia itself")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(MCPSetup.command, forType: .string)
                            } label: {
                                Label("Copy the setup command", systemImage: "doc.on.doc")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color(white: 0.85))
                            }
                            .buttonStyle(.plain)
                        }
                        Text("""
                        Vibresia has a local server that agents can talk to, so they can write a mode, \
                        check it compiles, look at the result and fix it — without you copying any code.
                        Add it to your agent with:
                        """)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        Text(MCPSetup.command)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(white: 0.9))
                            .textSelection(.enabled)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.black.opacity(0.35))
                            )
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
                        NSPasteboard.general.setString(CustomModeGuide.agentPrompt, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(white: 0.85))
                    }
                    .buttonStyle(.plain)
                }
                Text(CustomModeGuide.agentPrompt)
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
            case .success:
                preview = renderPreview(id: id)
                if preview == nil {
                    problem = ShaderProblem(
                        kind: .compileFailed,
                        message: "It compiled, but it couldn't be drawn. Try making it simpler.")
                }
            }
            testing = false
        }
    }

    /// Draws the mode offscreen and returns the picture.
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
        let result: Result<CustomMode, ShaderProblem>
        if let id = editingID {
            result = app.updateCustomMode(id: id, name: finalName, author: finalAuthor,
                                          url: finalURL, shader: code)
        } else {
            result = app.addCustomMode(name: finalName, author: finalAuthor,
                                       url: finalURL, shader: code)
        }
        switch result {
        case .success:
            dismiss()
        case .failure(let p):
            problem = p
            preview = nil
        }
    }

    /// Opens a shader file somebody sent.
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a mode file — one that contains a render() function."
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
                    message: "That file couldn't be read. Mode files are plain text — .glsl, .frag or .txt all work.")
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
