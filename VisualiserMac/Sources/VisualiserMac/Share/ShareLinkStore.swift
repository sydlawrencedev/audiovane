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
///
/// The long link still works, and is what falls back if any of this fails.
/// Sharing is not allowed to depend on the network.
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

    /// A link for this vibescape, or nil if the site could not make one.
    ///
    /// `image` is the picture of the vibescape, as JPEG. It is optional:
    /// without one the link still works, it just has the generic preview.
    ///
    /// `key` is the vibescape's identity — see `ShareIdentity`. The site
    /// uses it to find the share this vibescape already has rather than
    /// making a second one, so the same vibescape always gets the same
    /// link.
    func makeLink(payload: String, name: String, author: String,
                  image: Data?, key: String) async -> ShareLink? {
        guard !payload.isEmpty, !ShareLinkStore.token.isEmpty else { return nil }

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
        if let image, !image.isEmpty {
            body["image"] = image.base64EncodedString()
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            guard let url = json["url"] as? String, let id = json["id"] as? String else { return nil }
            return ShareLink(id: id, url: url, imageURL: json["imageUrl"] as? String)
        } catch {
            return nil
        }
    }
}

/// A short link the site made, and the share it belongs to.
struct ShareLink: Equatable {
    /// The share's id — the last part of the URL, and what the app hands
    /// back when the vibescape is shared on.
    let id: String
    /// The link itself.
    let url: String
    /// The picture behind it, if the share has one.
    let imageURL: String?
}
