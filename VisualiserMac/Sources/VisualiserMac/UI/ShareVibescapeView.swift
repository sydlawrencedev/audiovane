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
    /// Where the exported movie went, so the button can say so.
    @State private var savedVideoPath: String?
    @State private var hoverShare = false
    @State private var hoverSave = false
    /// The short link, once the site has made it. Nil until then, and nil
    /// for good if the site could not be reached.
    @State private var shortLink: String?
    /// Why the site could not make the link, so the sheet says so rather
    /// than handing out the long form.
    @State private var linkFailure: ShareLinkStore.Failure?
    @State private var makingLink = false
    /// The make that is running, so the Share button can wait for it rather
    /// than starting a second one.
    @State private var linkTask: Task<String?, Never>?

    /// The name of whoever made this, as it will be published.
    ///
    /// Editable here because this is the last moment before it goes out: the
    /// name ends up on the link, and — if the gallery is ticked — on the
    /// front page of the site.
    @State private var author: String = ""
    /// Whether this goes in the public gallery.
    ///
    /// On by default. A share is a link anybody can open; the gallery is
    /// different — it lists them, so anything in it is findable by anybody at
    /// all. The name and the author on it are public, and the sheet says so.
    @State private var inGallery: Bool = true
    /// Whether the video is being written.
    @State private var exportingVideo = false
    /// Whether the name field has the keyboard.
    @FocusState private var authorFieldFocused: Bool

    init(vibescape: VibescapeID) {
        _vibescape = State(initialValue: vibescape)
        // The name as it stands, so the field is never empty on the way in.
        // `onAppear` sets it too, for the case where the app has not finished
        // starting when the sheet is made.
        _author = State(initialValue: ShareVibescapeView.storedAuthor(for: vibescape))
    }

    /// The author on a vibescape, as it stands on disk.
    static func storedAuthor(for vibescape: VibescapeID) -> String {
        guard case .custom(let id) = vibescape,
              let author = AppState.shared?.customVibescape(id: id)?.author,
              !author.isEmpty else {
            return VibescapeMetadata.author
        }
        return author
    }

    /// The link to show, to copy and to share.
    ///
    /// A built-in vibescape's link is already short: the site has a page for
    /// every one of them. A custom vibescape's link is the short one the
    /// site makes, and nothing else.
    ///
    /// The long form — the payload in the query string, about 370 characters
    /// — still works, and the site still resolves it, but it is never shown,
    /// never copied and never shared. It is not a link anybody wants to put
    /// in a message, and the short one is the same vibescape behind it.
    ///
    /// So a custom vibescape waits for the short link rather than falling
    /// back to the long one. If the site cannot be reached, the sheet says
    /// so and offers another go, rather than quietly handing out a URL that
    /// looks broken.
    ///
    /// Recomputed by SwiftUI on each render, which is cheap (a couple of
    /// `URLComponents` operations) and keeps the URL box in sync if the
    /// active vibescape ever changes.
    private var shareURL: URL? {
        switch vibescape {
        case .builtin:
            return getShareURL(for: vibescape)
        case .custom:
            guard let shortLink, let url = URL(string: shortLink) else { return nil }
            return url
        }
    }

    /// What goes on the system share sheet: the pitch, and the short link.
    ///
    /// The link is there by the time the sheet opens — the Share button
    /// waits for it — so this is only ever the short one.
    private var shareItems: [Any] {
        guard let url = shareURL else { return [pitch] }
        return [pitch, url]
    }

    /// What the URL box says.
    ///
    /// The link, once there is one. Before that it says what is happening,
    /// which is better than a long URL that silently changes length a moment
    /// later.
    private var urlBoxText: String {
        if let shareURL { return shareURL.absoluteString }
        if makingLink { return "Making the link…" }
        if let linkFailure { return linkFailure.message }
        return "Preparing the link…"
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
                exportVideoButton
            }

            Divider().overlay(Color.white.opacity(0.1))

            // Only for custom vibescapes: a built-in is a slug in the URL and
            // has nothing to publish.
            if vibescape.isCustom {
                authorSection
                gallerySection
            }
        }
        .padding(22)
        .frame(width: 540)
        .background(Color(red: 0.06, green: 0.03, blue: 0.11))
        .onAppear {
            // The name on the link, and the picture of it, are made from the
            // vibescape's own author.
            author = currentAuthor
            // Start making the short link as soon as the sheet is up, so it
            // is usually ready before the person reaches for Share. The box
            // shows the link once it is there, and what is happening until
            // then — never the long form, which is not a link anybody wants
            // to put in a message.
            Task { @MainActor in
                guard vibescape.isCustom else { return }
                _ = await shortLinkWhenReady()
            }
        }
    }


    /// Whoever made this, as it will be published.
    ///
    /// The name goes on the link, and — if the gallery is ticked — on the
    /// front page of the site, so the sheet says so rather than leaving it
    /// to be found out.
    ///
    /// Read-only for a vibescape somebody sent you. It is theirs, and
    /// changing it would make it a different vibescape with a different
    /// link — and the link is the thing everybody who has it is holding.
    private var authorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR NAME")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color(white: 0.55))

            if isShared {
                Text(author)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                    )
                    .help("This vibescape came from somebody else, so the name on it is theirs")
                Text("This one came from somebody else, so it keeps their name.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("Your name", text: $author)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .focused($authorFieldFocused)
                    .onSubmit { commitAuthor() }
                    .onChange(of: authorFieldFocused) { _, focused in
                        if !focused { commitAuthor() }
                    }

                Text("This is public. It goes on the link, and on the gallery if you tick the box below.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Whether this goes in the public gallery.
    private var gallerySection: some View {
        Toggle(isOn: $inGallery) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Public gallery")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("Lists it at vibresia.com/vibescapes, where anybody can find it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(Color(red: 1, green: 0.17, blue: 0.84))
        // The tickbox has to reach the site. It used to be read only when a
        // share was made, so unticking it on a share that already existed
        // did nothing at all — the share stayed in the gallery and the
        // tickbox just went back to how it was.
        .onChange(of: inGallery) { _, wanted in
            pushGallery(wanted)
        }
    }

    /// Puts the share in the gallery, or takes it out.
    ///
    /// Only once there is a share to do it to. Before that the tick is
    /// carried into the share that gets made.
    private func pushGallery(_ wanted: Bool) {
        guard let shareID = currentShareID else { return }
        Task {
            let ok = await ShareLinkStore().setGallery(shareID: shareID, inGallery: wanted)
            if ok {
                ShareLinkCache.remember(shareID: shareID, for: currentKey, isPublic: wanted)
            } else {
                // The site didn't take it. Put the tick back, rather than
                // leaving it showing something that isn't true.
                await MainActor.run { inGallery = !wanted }
            }
        }
    }

    /// The share this vibescape has, if it has one.
    private var currentShareID: String? {
        guard case .custom(let id) = vibescape,
              let mode = app.customVibescape(id: id) else { return nil }
        return mode.shareID
    }

    /// The key this vibescape's content makes.
    private var currentKey: String {
        guard case .custom(let id) = vibescape,
              let mode = app.customVibescape(id: id) else { return "" }
        return ShareIdentity.key(name: mode.name, author: author,
                                 url: mode.url, shader: mode.shader)
    }

    /// Saves the name, and makes the link again.
    ///
    /// The name is part of what a share is, so a share with a new name is a
    /// different one — and gets its own link. The old link keeps working.
    private func commitAuthor() {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = trimmed.isEmpty ? VibescapeMetadata.author : trimmed
        guard wanted != currentAuthor else { return }

        if case .custom(let id) = vibescape {
            app.setCustomVibescapeAuthor(id: id, author: wanted)
        }
        shortLink = nil
        linkFailure = nil
        Task { @MainActor in
            _ = await shortLinkWhenReady()
        }
    }

    /// True when this vibescape came from somebody else, so it cannot be
    /// edited and keeps the link it arrived on.
    private var isShared: Bool {
        guard case .custom(let id) = vibescape,
              let mode = app.customVibescape(id: id) else { return false }
        return mode.isShared
    }

    /// The name on the vibescape as it stands.
    private var currentAuthor: String {
        switch vibescape {
        case .builtin:
            return VibescapeMetadata.author
        case .custom(let id):
            let author = app.customVibescape(id: id)?.author ?? ""
            return author.isEmpty ? VibescapeMetadata.author : author
        }
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
            // Not in a scroll view any more: the long form is gone, and the
            // short link is thirty-odd characters, so there is nothing to
            // scroll to. The truncation stays as a safety net.
            Text(urlBoxText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(shareURL == nil ? Color(white: 0.45) : Color(red: 0.17, green: 0.95, blue: 1.0))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Another go, when the site could not make the link. The long
            // form would still work, but it is not the link, so the sheet
            // asks again rather than handing one out.
            if let linkFailure {
                Button {
                    retryLink()
                } label: {
                    Text("Retry")
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
                .help("Try making the link again — the site said: \(linkFailure.detail)")
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
        .background(VibescapeSharePickerAnchor(isPresented: $isSharing, items: shareItems))
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
    @discardableResult
    private func makeShortLink() async -> String? {
        guard vibescape.isCustom, shortLink == nil, !makingLink else { return shortLink }
        guard case .custom(let id) = vibescape,
              let mode = app.customVibescape(id: id) else { return nil }

        makingLink = true
        defer { makingLink = false }

        // The name as it is in the sheet, which is the name as it will be
        // published. The key is of the same thing, so that two Macs holding
        // the same vibescape work out the same link.
        let author = ShareIdentity.shownAuthor(author)
        let key = ShareIdentity.key(name: mode.name, author: author,
                                     url: mode.url, shader: mode.shader)

        // The link this vibescape arrived on, if it arrived on one and
        // hasn't been edited since. Sharing it on hands back that link:
        // the person who sent it to you sent you that link, and the person
        // you send it to should get the same one. Edit it and it's a
        // different vibescape, so it gets its own link.
        if let shareID = mode.shareID, mode.isStillShared(as: key) {
            shortLink = "\(ShareLinkStore.site)/s/\(shareID)"
            await syncGalleryState(shareID: shareID, key: key)
            return shortLink
        }

        // A share this Mac has already made for this vibescape. Asking
        // again would upload the picture again to arrive at a URL we know.
        if let shareID = ShareLinkCache.shareID(for: key) {
            shortLink = "\(ShareLinkStore.site)/s/\(shareID)"
            inGallery = ShareLinkCache.isPublic(for: key) ?? inGallery
            return shortLink
        }

        // The shader as it is, compressed — not minified unless it has to
        // be. The link is short whatever this is, and the recipient gets the
        // code somebody wrote; a big vibescape is minified rather than
        // refused, because a share that is a little less pretty is much
        // better than a share that does not exist.
        guard let payload = ShareLinkStore.payload(for: mode) else {
            linkFailure = .tooBig
            NSLog("[SHARE] the code is too big to share")
            return nil
        }
        let name = mode.name
        let target = vibescape
        // The share this one supersedes, if there is one. Changing your
        // name makes a different vibescape, and the old share goes with it
        // rather than sitting in the gallery for ever.
        let replaces = mode.shareID

        // The picture is rendered off the main thread — it is a GPU job and
        // takes a moment — so the sheet doesn't stutter while it is made.
        // It is also made small enough for the site to take: a detailed
        // vibescape makes a picture twice the size the site will store.
        let image = await ShareImageBuilder.jpeg(
            renderer: app.renderer, mode: target,
            width: 1200, height: 630, time: 6.0,
            title: ShareImageBuilder.title(name: app.displayName(for: target),
                                          author: author))

        let made = await ShareLinkStore().makeLink(
            payload: payload, name: name, author: author, image: image,
            key: key, inGallery: inGallery, replaces: replaces)
        switch made {
        case .success(let link):
            shortLink = link.url
            ShareLinkCache.remember(shareID: link.id, for: key, isPublic: link.inGallery)
            // The vibescape remembers its own link, so that changing your
            // name later knows which share to replace.
            app.setCustomVibescapeShare(id: id, shareID: link.id, key: key)
        case .failure(let why):
            linkFailure = why
            NSLog("[SHARE] could not make the link: %@", why.detail)
        }
        return shortLink
    }

    /// Sets the tickbox to what the site actually has.
    ///
    /// The sheet opens with the tick on, because a share that has not been
    /// made yet will be made with the tick on. A share that already exists
    /// may be the other way round, and the tick has to show what is true.
    private func syncGalleryState(shareID: String, key: String) async {
        if let cached = ShareLinkCache.isPublic(for: key) {
            inGallery = cached
            return
        }
        guard let details = await ShareLinkStore().details(shareID: shareID) else { return }
        inGallery = details.inGallery
        ShareLinkCache.remember(shareID: shareID, for: key, isPublic: details.inGallery)
    }

    /// The Share button. Waits for the short link if there isn't one yet, so
    /// the link that goes into the chat is the short one — and if the site
    /// cannot make one, says so instead of sharing the long form, which is
    /// not a link anybody wants in a message.
    ///
    /// It waits for the link that is already being made rather than
    /// starting another: two makes at once would race, and the slower one
    /// would win.
    private func shareTapped() {
        Task { @MainActor in
            guard await linkToShare() != nil else { return }
            isSharing = true
        }
        Task { await Analytics.shared.track("share_sheet_opened", [
            "kind": vibescape.isCustom ? "custom" : "builtin"
        ]) }
    }

    /// The link to hand out: the short one.
    ///
    /// A built-in vibescape's link is short already. A custom one waits for
    /// the site to make it, and there is no fallback: the long form is never
    /// shown, copied or shared.
    private func linkToShare() async -> URL? {
        if vibescape.isCustom {
            guard let link = await shortLinkWhenReady(),
                  let url = URL(string: link) else { return nil }
            return url
        }
        return getShareURL(for: vibescape)
    }

    /// Asks the site for the link again, after it could not be reached.
    private func retryLink() {
        linkFailure = nil
        makingLink = false
        Task { @MainActor in
            _ = await shortLinkWhenReady()
        }
    }

    /// The short link, waiting for the one being made if there is one.
    private func shortLinkWhenReady() async -> String? {
        if let shortLink { return shortLink }
        if let linkTask { return await linkTask.value }
        let task = Task { await makeShortLink() }
        linkTask = task
        let link = await task.value
        linkTask = nil
        return link
    }

    /// Puts the link on the clipboard.
    ///
    /// The short one, always. If it isn't there yet, the link is made first
    /// — and if it cannot be made, nothing is copied: the long form still
    /// works, but it is not the link, so the sheet says what went wrong
    /// rather than quietly handing one out.
    private func copyLink() {
        Task { @MainActor in
            guard let url = await linkToShare() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            copied = true
            Task { await Analytics.shared.track("share_link_copied", [
                "kind": vibescape.isCustom ? "custom" : "builtin"
            ]) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }
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
        Task { @MainActor in
            let data = await ShareImageBuilder.png(
                renderer: app.renderer, mode: vibescape,
                width: 1280, height: 720, frames: 60,
                title: ShareImageBuilder.title(name: app.displayName(for: vibescape),
                                              author: author))
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

    /// Saves the last few bars of the vibescape, with the music, as a movie
    /// in Downloads.
    private var exportVideoButton: some View {
        Button {
            exportVideo()
        } label: {
            HStack(spacing: 6) {
                if exportingVideo {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Text(exportingVideo ? "Recording…" : "Export video")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 100)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(Color(red: 0.17, green: 0.95, blue: 1.0), lineWidth: 1.5)
                    )
            )
            .foregroundStyle(Color(red: 0.17, green: 0.95, blue: 1.0))
        }
        .buttonStyle(.plain)
        .disabled(exportingVideo)
        .help("Save \(videoClip.description) of this vibescape, with the music, as a movie")
    }

    /// How long the recording will be: a number of bars of whatever is
    /// playing.
    private var videoClip: VideoExporter.Clip {
        VideoExporter.Clip.forTempo(app.bpm)
    }

    /// Records the clip and writes it to Downloads.
    private func exportVideo() {
        guard let app = AppState.shared else { return }
        exportingVideo = true
        let mode = vibescape
        let clip = videoClip
        let slug = previewFilenameSlug()
        let downloads = FileManager.default.urls(for: .downloadsDirectory,
                                                 in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        let url = downloads.appendingPathComponent("vibescape-\(slug).mp4")

        Task { @MainActor in
            do {
                try await VideoExporter.export(
                    renderer: app.renderer, mode: mode,
                    title: ShareImageBuilder.title(name: app.displayName(for: mode),
                                                  author: author),
                    audio: app.audio, clip: clip, to: url)
                savedVideoPath = url.path
                NSWorkspace.shared.activateFileViewerSelecting([url])
                Task { await Analytics.shared.track("share_video_exported", [
                    "kind": mode.isCustom ? "custom" : "builtin",
                    "bars": clip.bars,
                    "seconds": Int(clip.seconds.rounded()),
                ]) }
            } catch {
                NSLog("[SHARE] could not export the video: \(error)")
                Task { await Analytics.shared.track("share_video_failed", [
                    "kind": mode.isCustom ? "custom" : "builtin",
                    "reason": String(describing: error),
                ]) }
            }
            exportingVideo = false
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
            let encoded = ShareImporter.encodePayload(mode, minify: false)
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
