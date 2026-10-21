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
/// Custom vibescapes used to carry the shader in the URL's query string as
/// base64 — around 370 characters, behind a redirect that WhatsApp's
/// link-preview crawler did not follow, so the preview was blank and the
/// link looked broken in a chat.
///
/// Now a custom vibescape's link is `/s/<id>`: the payload is stored on the
/// site, the URL is short, and the page behind it has a picture of the
/// vibescape for the preview. The long form still works and is what falls
/// back if the site cannot be reached — sharing is not allowed to depend on
/// the network.
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
    /// The short link, once the site has made it. Nil until then, and nil
    /// for good if the site could not be reached.
    @State private var shortLink: String?
    @State private var makingLink = false

    /// Off by default, and not because minifying is bad at it — it roughly
    /// halves the payload again. Because it is the one part of a share that costs
    /// the recipient something: the app saves whatever arrives verbatim, so
    /// turning this on hands them a shader with the comments gone and the
    /// spacing crushed, and that is what they will be looking at.
    ///
    /// Compression is on unconditionally and costs them nothing, which is why it
    /// isn't behind this switch.
    ///
    /// The short link makes length a non-issue, so this is now about the
    /// fallback: the long form, which still carries the payload with it, and
    /// which is what gets shared if the site can't be reached. It also makes
    /// the stored payload smaller.
    @State private var minifyLink = false

    init(vibescape: VibescapeID) {
        _vibescape = State(initialValue: vibescape)
    }

    /// The URL the recipient gets. Recomputed by SwiftUI on each render,
    /// which is cheap (a couple of `URLComponents` operations) and keeps
    /// the URL box in sync if the active vibescape ever changes.
    private var shareURL: URL {
        // The short link once there is one, the long one otherwise. The long
        // one always works — it carries the payload with it — so a site that
        // is down or a rate limit that trips costs the prettiness of the
        // link, not the link itself.
        if let shortLink, let url = URL(string: shortLink) { return url }
        return longShareURL
    }

    /// The long form: the payload in the query string. Always works, with
    /// nothing stored anywhere.
    private var longShareURL: URL {
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
        .onAppear {
            // Start making the short link as soon as the sheet is up, so it
            // is usually ready before the person reaches for Share. If it
            // never arrives, the long link is still there.
            Task { await makeShortLink() }
        }
        .onChange(of: minifyLink) { _ in
            // The payload that was stored was the one made with the old
            // setting, so the link has to be made again — otherwise the
            // toggle would claim to do something it no longer does.
            shortLink = nil
            Task { await makeShortLink() }
        }
    }


    /// The one setting in this sheet that trades something away, so it says so
    /// on its face rather than hiding behind a tooltip.
    ///
    /// It used to halve the short link. It doesn't any more: a short link is
    /// the same length whatever this says, because the vibescape is stored on
    /// the site rather than carried in the URL. What it still changes is the
    /// long fallback link — the one that carries the shader itself — and the
    /// payload the first share of a vibescape stores.
    private var shorterLinkToggle: some View {
        Toggle(isOn: $minifyLink) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Shorter link")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("Strips the comments and spacing out of the code. The short link is the same length either way — this is for the fallback link, and for the first share of a vibescape. Whoever opens it gets back the stripped version.")
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("SHARE THIS VIBESCAPE")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                // This sheet used to have no visible way out at all. Escape
                // worked, which is not the same as being able to see it.
                SheetCloseButton()
            }
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

            // Says what is going on rather than showing a long URL that
            // silently changes length a moment later.
            if vibescape.isCustom && shortLink == nil {
                if makingLink {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Text("Long link")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.45))
                }
            }

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
            shareTapped()
        } label: {
            HStack(spacing: 6) {
                if makingLink {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
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

    /// Asks the site to store this vibescape and give back a short link,
    /// with a picture of it for the preview.
    ///
    /// The picture is rendered at the same moment the share page draws its
    /// still — six seconds in, so anything driven by time has reached its
    /// stride — so the preview in a chat is the picture the recipient gets.
    ///
    /// Most of the time nothing is asked of the site at all: a vibescape
    /// keeps the link it has, and the same link is the answer however many
    /// times it is shared.
    private func makeShortLink() async {
        guard vibescape.isCustom, shortLink == nil, !makingLink else { return }
        guard case .custom(let id) = vibescape,
              let mode = app.customVibescape(id: id) else { return }

        makingLink = true
        defer { makingLink = false }

        let key = ShareIdentity.key(name: mode.name, author: mode.author,
                                    url: mode.url, shader: mode.shader)

        // The link this vibescape arrived on, if it arrived on one and
        // hasn't been edited since. Sharing it on hands back that link:
        // the person who sent it to you sent you that link, and the person
        // you send it to should get the same one. Edit it and it's a
        // different vibescape, so it gets its own link.
        if let shareID = mode.shareID, mode.shareKey == key {
            shortLink = "\(ShareLinkStore.site)/s/\(shareID)"
            return
        }

        // A share this Mac has already made for this vibescape. Asking
        // again would upload the picture again to arrive at a URL we know.
        if let shareID = ShareLinkCache.shareID(for: key) {
            shortLink = "\(ShareLinkStore.site)/s/\(shareID)"
            return
        }

        let payload = ShareImporter.encodePayload(mode, minify: minifyLink)
        let name = mode.name
        let author = mode.author.isEmpty ? "Minith Labs" : mode.author
        let target = vibescape

        // Rendering is a GPU job and takes a moment, so it happens off the
        // main thread — otherwise the sheet would stutter while the user is
        // looking at it.
        let image: Data? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ShareImageBuilder.jpeg(
                    renderer: app.renderer, mode: target,
                    width: 1200, height: 630, time: 6.0, author: author))
            }
        }

        let link = await ShareLinkStore().makeLink(
            payload: payload, name: name, author: author, image: image, key: key)
        shortLink = link?.url
        if let shareID = link?.id {
            ShareLinkCache.remember(shareID: shareID, for: key)
        }
    }

    /// The Share button. Waits for the short link if there isn't one yet, so
    /// the link that goes into the chat is the short one — but shares the
    /// long one if the site can't be reached, rather than doing nothing.
    private func shareTapped() {
        if vibescape.isCustom && shortLink == nil {
            Task { @MainActor in
                await makeShortLink()
                isSharing = true
            }
        } else {
            isSharing = true
        }
        Task { await Analytics.shared.track("share_sheet_opened", [
            "kind": vibescape.isCustom ? "custom" : "builtin"
        ]) }
    }

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
        let author = previewAuthor()
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
            let data = ShareImageBuilder.png(
                renderer: app.renderer, mode: vibescape,
                width: 1280, height: 720, frames: 60, author: author)
            DispatchQueue.main.async {
                savingPreview = false
                guard let data else {
                    Task { await Analytics.shared.track("share_preview_failed", [
                        "kind": vibescape.isCustom ? "custom" : "builtin"
                    ]) }
                    return
                }
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    NSLog("[SHARE] could not write the preview image: \(error)")
                    return
                }
                savedPreviewPath = url.path
                NSWorkspace.shared.activateFileViewerSelecting([url])
                Task { await Analytics.shared.track("share_preview_saved", [
                    "kind": vibescape.isCustom ? "custom" : "builtin"
                ]) }
            }
        }
    }

    /// Who the credit names: the vibescape's author, or the app's own name
    /// when the vibescape doesn't say.
    private func previewAuthor() -> String {
        switch vibescape {
        case .builtin:
            return VibescapeMetadata.author
        case .custom(let id):
            let author = app.customVibescape(id: id)?.author ?? ""
            return author.isEmpty ? VibescapeMetadata.author : author
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
            return "The vibescape is stored on the site, so the link stays short — and it stays the same link however many times you share it. Clicking it adds the vibescape to their list."
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
            return URL(string: "\(ShareLinkStore.site)/share/\(stable.rawValue)")!
        case .custom(let id):
            guard let mode = app.customVibescape(id: id) else {
                return URL(string: "https://vibresia.com/share")!
            }
            let encoded = ShareImporter.encodePayload(mode, minify: minifyLink)
            // The trailing slash matters. Without it the URL is /share?d=… and
            // the server answers with a 307 to /share/?d=… — a redirect that
            // some link-preview crawlers (WhatsApp's among them) do not
            // follow, which left the preview blank and the link looking
            // broken in a chat. The built-in vibescape links are
            // /share/<slug> and never redirect, and now neither do these.
            var comps = URLComponents(string: "https://vibresia.com/share/")!
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
