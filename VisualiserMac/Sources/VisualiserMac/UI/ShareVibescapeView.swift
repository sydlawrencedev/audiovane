import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The sheet `ShareVibescapeButton` opens. Shows the share URL for the
/// currently-active vibescape and routes the three sharing actions a person
/// actually reaches for: copy the link, drop it into a chat/email via the
/// system share sheet, or save a PNG preview image to attach to a service
/// that doesn't render link previews.
///
/// Built-in vibescapes get a short, readable URL (`vibresia.com/share/<slug>`).
/// Custom vibescapes carry the shader in the URL fragment as base64; the
/// page on the other end (`site/share?d=…`) decodes the payload and gives
/// the recipient a working vibescape without any backend storage.
///
/// The view's input is captured once when the sheet is presented — the URL
/// and preview render against the active vibescape at that moment. Switch
/// vibescapes first and then open the share sheet; switching underneath it
/// would look like the URL magically updates mid-share.
struct ShareVibescapeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var vibescape: VibescapeID
    @State private var copied: Bool = false
    @State private var isSharing: Bool = false
    @State private var savingPreview: Bool = false
    @State private var savedPreviewPath: String?
    @State private var hoverShare = false
    @State private var hoverSave = false

    /// Off by default, and not because minifying is bad at it — it roughly
    /// halves the link again. Because it is the one part of a share that costs
    /// the recipient something: the app saves whatever arrives verbatim, so
    /// turning this on hands them a shader with the comments gone and the
    /// spacing crushed, and that is what they will be looking at.
    ///
    /// Compression is on unconditionally and costs them nothing, which is why it
    /// isn't behind this switch. This one only exists for links that still
    /// don't fit in whatever they're being pasted into.
    @State private var minifyLink = false

    init(vibescape: VibescapeID) {
        _vibescape = State(initialValue: vibescape)
    }

    /// The URL the recipient gets. Recomputed by SwiftUI on each render,
    /// which is cheap (a couple of `URLComponents` operations) and keeps
    /// the URL box in sync if the active vibescape ever changes.
    private var shareURL: URL {
        getShareURL(for: vibescape)
    }

    /// A short, human-readable summary of what the URL contains, used as
    /// the pitch on the system share sheet and for analytics. Title-cased
    /// so the share doesn't read like the vibescape name is shouting.
    private var pitch: String {
        switch vibescape {
        case .builtin(let m):
            let name = titleCased(m.displayName)
            return "Try this Vibresia vibescape — \(name) — free, no account."
        case .custom(let id):
            let name = app.customVibescape(id: id)?.name ?? "custom"
            return "Try this Vibresia vibescape — \(name) — free, no account."
        }
    }

    private func titleCased(_ s: String) -> String {
        // Vibescape.displayName returns upper-case titles ("RIBBONS"); "as-is"
        // in a chat pitch reads like shouting, so title-case for messages.
        s.lowercased().capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(alignment: .leading, spacing: 6) {
                Text("LINK TO SHARE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color(white: 0.55))
                urlBox
            }

            HStack(spacing: 10) {
                shareButton
                Spacer(minLength: 6)
                savePreviewButton
            }

            Divider().overlay(Color.white.opacity(0.1))

            Text(recipientHint)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            // Only for custom vibescapes: a built-in is a slug in the URL and
            // has nothing to shorten.
            if vibescape.isCustom {
                shorterLinkToggle
            }
        }
        .padding(22)
        .frame(width: 540)
        .background(Color(red: 0.06, green: 0.03, blue: 0.11))
    }


    /// The one setting in this sheet that trades something away, so it says so
    /// on its face rather than hiding behind a tooltip. The link is already
    /// compressed by default — this is what you reach for when it still won't
    /// fit in whatever it's being pasted into.
    private var shorterLinkToggle: some View {
        Toggle(isOn: $minifyLink) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Shorter link")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("Strips the comments and spacing out of the code. Halves the link again — and whoever opens it gets back the stripped version, so only turn this on if the link is being truncated on the way out.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(Color(red: 1, green: 0.17, blue: 0.84))
        .padding(.top, 2)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SHARE THIS VIBESCAPE")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(.white)
            Text(secondaryTitle)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color(white: 0.6))
        }
    }

    private var urlBox: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(shareURL.absoluteString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.17, green: 0.95, blue: 1.0))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copyLink()
            } label: {
                Text(copied ? "Copied" : "Copy")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 64, minHeight: 26)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(white: 0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var shareButton: some View {
        Button {
            isSharing = true
            Task { await Analytics.shared.track("share_sheet_opened", [
                "kind": vibescape.isCustom ? "custom" : "builtin"
            ]) }
        } label: {
            Text("Share…")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 100)
                        .fill(Color(red: 1, green: 0.17, blue: 0.84))
                        .shadow(color: Color(red: 1, green: 0.17, blue: 0.84).opacity(0.4),
                                radius: 10)
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .onHover { hoverShare = $0 }
        .background(VibescapeSharePickerAnchor(isPresented: $isSharing, items: [pitch, shareURL]))
    }
    private var savePreviewButton: some View {
        Button {
            savePreviewImage()
        } label: {
            HStack(spacing: 6) {
                if savingPreview {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Text(savedPreviewPath == nil ? "Save preview image" : "Saved — Reveal")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 100)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(Color(red: 1, green: 0.76, blue: 0.35), lineWidth: 1.5)
                    )
            )
            .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.35))
        }
        .buttonStyle(.plain)
        .onHover { hoverSave = $0 }
        .disabled(savingPreview)
    }


    // MARK: - Behaviour

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareURL.absoluteString, forType: .string)
        copied = true
        Task { await Analytics.shared.track("share_link_copied", [
            "kind": vibescape.isCustom ? "custom" : "builtin"
        ]) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func savePreviewImage() {
        guard let app = AppState.shared else { return }
        savingPreview = true
        let slug = previewFilenameSlug()
        // Output to ~/Downloads so it's right where the user expects. Filename
        // mirror's the share URL slug so it's recognisable in Finder.
        let downloads = FileManager.default.urls(for: .downloadsDirectory,
                                                 in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        let url = downloads.appendingPathComponent("vibescape-\(slug).png")
        // Render against the same renderer that powers the live display —
        // 1280x720 is the existing snapshot size and a reasonable attachment
        // for chats that don't show link previews.
        DispatchQueue.global(qos: .userInitiated).async {
            app.renderer.renderToPNG(width: 1280, height: 720,
                                     mode: vibescape, frames: 60,
                                     path: url.path)
            DispatchQueue.main.async {
                savingPreview = false
                savedPreviewPath = url.path
                NSWorkspace.shared.activateFileViewerSelecting([url])
                Task { await Analytics.shared.track("share_preview_saved", [
                    "kind": vibescape.isCustom ? "custom" : "builtin"
                ]) }
            }
        }
    }

    private func previewFilenameSlug() -> String {
        switch vibescape {
        case .builtin(let m): return m.rawValue
        case .custom(let id): return id
        }
    }

    private var secondaryTitle: String {
        switch vibescape {
        case .builtin(let m):
            return m == .autoScan
                ? "Auto Scan is cycling — share one specific vibescape instead."
                : "Made with ❤ by \(VibescapeMetadata.author) — share it with someone."
        case .custom(let id):
            let m = app.customVibescape(id: id)
            let author = m?.author.isEmpty == false ? m!.author : "Minith Labs"
            return "Made with ❤ by \(author) — share it with someone."
        }
    }

    private var recipientHint: String {
        switch vibescape {
        case .builtin:
            return "Anyone who clicks it sees a page with the vibescape preview and an “Open in Vibresia” button — works whether they already have the app or not."
        case .custom:
            return "The shader rides in the link, so it's yours to send without an account or a database. Clicking it adds the vibescape to their list."
        }
    }

    // MARK: - URL construction

    private func getShareURL(for id: VibescapeID) -> URL {
        switch id {
        case .builtin(let mode):
            // Auto Scan isn't itself a stable vibescape — share the
            // current visualised vibescape when on Auto Scan, falling
            // back to tunnel (the shipped default).
            let stable = (mode == .autoScan)
                ? (app.scanCycle.first?.builtin ?? .tunnel)
                : mode
            return URL(string: "https://vibresia.com/share/\(stable.rawValue)")!
        case .custom(let id):
            guard let mode = app.customVibescape(id: id) else {
                return URL(string: "https://vibresia.com/share")!
            }
            let encoded = ShareImporter.encodePayload(mode, minify: minifyLink)
            var comps = URLComponents(string: "https://vibresia.com/share")!
            comps.queryItems = [URLQueryItem(name: "d", value: encoded)]
            return comps.url!
        }
    }
}

/// `NSSharingServicePicker` needs a parent view to position its menu
/// relative to. We park one behind the "Share…" button — same pattern
/// used by `SharewareLink` in `AboutButton.swift`. This is the
/// vibescape-specific copy (kept separate from the private one in
/// `AboutButton.swift` so the share feature doesn't have to widen the
/// credit popover's API surface to reach in).
struct VibescapeSharePickerAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.alphaValue = 0  // Frame is what matters, not visibility.
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented, !context.coordinator.isShowing else { return }
        context.coordinator.isShowing = true
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .maxY)
        // Re-arm so a second tap works without restarting. Done on the next
        // runloop turn because `isShowing` is only read from `updateNSView`.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            context.coordinator.isShowing = false
            if self.isPresented { self.isPresented = false }
        }
    }

    final class Coordinator {
        var isShowing = false
    }
}
