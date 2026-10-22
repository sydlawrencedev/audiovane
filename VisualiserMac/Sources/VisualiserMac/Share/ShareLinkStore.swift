import Foundation

/// Turns a vibescape into a short link on vibresia.com.
///
/// A custom vibescape used to travel as its payload in the query string of
/// the link: about 370 characters, and a redirect on the way in that
/// WhatsApp's link-preview crawler did not follow, so the preview was blank
/// and the link looked broken in a chat.
///
/// Now the payload is stored on the site and the link is `/s/<id>` — short,
/// on the same domain, and with a picture of the vibescape behind it so the
/// preview shows the world rather than the generic Vibresia one.
actor ShareLinkStore {
    /// Where the site takes a share. The Worker serves `/s/<id>` and
    /// `/og/<id>.jpg` from the same place.
    ///
    /// `VIBRESIA_SHARE_ENDPOINT` points it somewhere else, which is how the
    /// flow gets tested against a local Worker rather than the live one.
    static let endpoint = URL(
        string: ProcessInfo.processInfo.environment["VIBRESIA_SHARE_ENDPOINT"]
            ?? "https://vibresia.com/api/share"
    )!

    /// Where the site lives. The short links point here, and so do the
    /// built-in ones.
    static let site = "https://vibresia.com"

    /// The token the Worker checks. It ships inside the app, so it is a
    /// speed bump rather than a lock — its job is to stop a script using the
    /// site as free storage, not to keep anyone out.
    static var token: String {
        Bundle.main.object(forInfoDictionaryKey: "ShareToken") as? String ?? ""
    }

    /// What the site will take, so the app keeps inside it rather than
    /// finding out at the far end.
    ///
    /// A share that is refused is a share that does not exist, and the
    /// person who wanted it is left with nothing to show for the effort.
    ///
    /// The payload is the code, base64url of the deflated JSON, and a big
    /// vibescape is a lot of code. The site used to take eight kilobytes of
    /// it, because the payload used to travel in the query string of the
    /// link and a URL is about eight kilobytes before servers start
    /// refusing it. The short link stores the payload instead, so there is
    /// room for twice that — which is a big vibescape with room to spare.
    static let maxPayloadChars = 16384
    static let maxImageBytes = 400 * 1024

    /// Why a share could not be made.
    ///
    /// The two are different and the sheet says different things about them:
    /// a site that cannot be reached is a thing to try again later, and a
    /// site that says no is a thing to say what it said.
    enum Failure: Error, Equatable {
        /// The site could not be reached at all.
        case unreachable
        /// The site said no, and said why.
        case refused(String)
        /// The vibescape is bigger than the site will hold.
        case tooBig

        /// What to tell the person.
        var message: String {
            switch self {
            case .unreachable:
                return "Couldn't reach the site"
            case .refused:
                return "The site wouldn't make the link"
            case .tooBig:
                return "This vibescape is too big to share"
            }
        }

        /// The site's own words, for the log and for a tooltip.
        var detail: String {
            switch self {
            case .unreachable:
                return "The site could not be reached."
            case .refused(let reason):
                return reason
            case .tooBig:
                return "The code is larger than the site will store, even minified."
            }
        }
    }

    /// A link for this vibescape, or the reason there is not one.
    ///
    /// `image` is the picture of the vibescape, as JPEG. It is optional:
    /// without one the link still works, it just has the generic preview.
    ///
    /// `key` is the vibescape's identity — see `ShareIdentity`. The site
    /// uses it to find the share this vibescape already has rather than
    /// making a second one, so the same vibescape always gets the same
    /// link.
    ///
    /// `inGallery` is whether it goes in the public gallery. The sheet asks,
    /// and says there that the name and the author are public.
    ///
    /// `replaces` is the share this one supersedes, if it supersedes one —
    /// somebody changed their name, which makes a different vibescape, which
    /// gets a different link. The old share goes with it, so the gallery does
    /// not fill up with every version of the same vibescape.
    func makeLink(payload: String, name: String, author: String,
                  image: Data?, key: String, inGallery: Bool,
                  replaces: String? = nil) async -> Result<ShareLink, Failure> {
        guard !payload.isEmpty, !ShareLinkStore.token.isEmpty else {
            return .failure(.refused("the link was empty"))
        }

        var request = URLRequest(url: ShareLinkStore.endpoint)
        request.httpMethod = "POST"
        request.setValue(ShareLinkStore.token, forHTTPHeaderField: "x-av-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "payload": payload,
            "name": String(name.prefix(120)),
            "author": String(author.prefix(120)),
        ]
        if !key.isEmpty {
            body["key"] = key
        }
        body["public"] = inGallery
        if let replaces, !replaces.isEmpty {
            body["replaces"] = replaces
        }
        if let image, !image.isEmpty {
            body["image"] = image.base64EncodedString()
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                // What the site said, so a failure can be told apart from a
                // flat "it did not work". A share that fails silently is a
                // share nobody can fix.
                let said = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                NSLog("[SHARE] the site said %d %@", status, said ?? "(no reason)")
                return .failure(.refused(said ?? "the site said \(status)"))
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.refused("the site sent something unreadable"))
            }
            guard let url = json["url"] as? String, let id = json["id"] as? String else {
                return .failure(.refused("the site sent no link"))
            }
            return .success(ShareLink(id: id, url: url, inGallery: json["public"] as? Bool ?? inGallery))
        } catch {
            NSLog("[SHARE] could not reach the site: %@", error.localizedDescription)
            return .failure(.unreachable)
        }
    }

    /// The payload for the site, small enough for it to take.
    ///
    /// The site will not take a payload over sixteen kilobytes, and a big
    /// vibescape can be over that even compressed. The code is minified then
    /// — the comments and the spacing go, the code does not — because a
    /// share that is a little less pretty is much better than a share that
    /// does not exist.
    ///
    /// Nil when it will not fit at all: a vibescape bigger than the site
    /// will hold, and the sheet says so rather than uploading it to be
    /// refused.
    static func payload(for mode: CustomVibescape) -> String? {
        let plain = ShareImporter.encodePayload(mode, minify: false)
        guard plain.count > maxPayloadChars else { return plain }
        let minified = ShareImporter.encodePayload(mode, minify: true)
        NSLog("[SHARE] the code was %d characters, so it was minified to %d",
              plain.count, minified.count)
        return minified.count <= maxPayloadChars ? minified : nil
    }

    /// Puts a share in the public gallery, or takes it out.
    /// Puts a share in the public gallery, or takes it out.
    ///
    /// The tickbox in the share sheet has to reach the site. It used to be
    /// read only when a share was made, so unticking it on a share that
    /// already existed did nothing at all.
    func setGallery(shareID: String, inGallery: Bool) async -> Bool {
        guard !shareID.isEmpty, !ShareLinkStore.token.isEmpty else { return false }
        guard let url = URL(string: "\(ShareLinkStore.site)/api/share/\(shareID)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(ShareLinkStore.token, forHTTPHeaderField: "x-av-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["public": inGallery])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// What the site knows about a share — in particular whether it is in
    /// the public gallery, so the tickbox can show what is true.
    func details(shareID: String) async -> ShareDetails? {
        guard !shareID.isEmpty else { return nil }
        guard let url = URL(string: "\(ShareLinkStore.site)/api/share/\(shareID)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return ShareDetails(name: json["name"] as? String ?? "",
                                author: json["author"] as? String ?? "",
                                inGallery: json["public"] as? Bool ?? false)
        } catch {
            return nil
        }
    }
}

/// What the site knows about a share.
struct ShareDetails: Equatable {
    let name: String
    let author: String
    let inGallery: Bool
}

/// A short link the site made, and the share it belongs to.
struct ShareLink: Equatable {
    /// The share's id — the last part of the URL, and what the app hands
    /// back when the vibescape is shared on.
    let id: String
    /// The link itself.
    let url: String
    /// Whether the share is in the public gallery, as the site has it.
    let inGallery: Bool
}
