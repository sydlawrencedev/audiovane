import CryptoKit
import Foundation

/// The identity of a vibescape, for sharing.
///
/// A share's URL is a function of what the vibescape *is*, not of when it
/// was shared. The same shader, name and author always resolve to the same
/// link, so sharing the same vibescape twice gives you the same URL, and
/// re-sharing one somebody sent you gives you the URL it came with.
enum ShareIdentity {
    /// A stable key for a vibescape's content.
    ///
    /// SHA-256 over the fields that make a vibescape what it is, with each
    /// one's length in front of it — so no two different vibescapes can
    /// produce the same key by moving text between the fields.
    ///
    /// The shader goes in whole rather than minified. Minifying is a choice
    /// about how long the link is, not a different vibescape, and it must not
    /// give the same vibescape a second identity and a second link.
    ///
    /// The author is normalised the same way everywhere it is worked out —
    /// an empty one is Minith Labs, because that is what it is called on
    /// screen. It has to be: the key is worked out once when a vibescape
    /// arrives on a link and again when it is shared on, and if the two
    /// disagreed about an empty author then a share with no author would
    /// not recognise its own link and would make a new one.
    static func key(name: String, author: String, url: String?, shader: String) -> String {
        var text = ""
        for field in [name, shownAuthor(author), url ?? "", shader] {
            text += "\(field.utf8.count):\(field)"
        }
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The author as it is shown, which is what a key is worked out from.
    static func shownAuthor(_ author: String) -> String {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? VibescapeMetadata.author : trimmed
    }
}

/// The share a vibescape already has, remembered on this Mac.
///
/// The site can work this out too — the same key finds the same row — but
/// asking means uploading the picture again, which is a megabyte or so of
/// somebody's bandwidth to arrive at a URL we already knew. The key is the
/// same one the site uses, so the two agree.
enum ShareLinkCache {
    private static let defaultsKey = "vibresia.shareLinks"

    /// One remembered share.
    private struct Entry {
        let key: String
        let id: String
        /// Whether the share is in the public gallery, so the tickbox in the
        /// share sheet can show what is true rather than what it was set to
        /// when the sheet opened.
        let isPublic: Bool
    }

    /// The share id for a key, if this Mac has made one.
    static func shareID(for key: String) -> String? {
        guard !key.isEmpty else { return nil }
        return entries().first { $0.key == key }?.id
    }

    /// Whether a share this Mac made is in the public gallery.
    static func isPublic(for key: String) -> Bool? {
        guard !key.isEmpty else { return nil }
        return entries().first { $0.key == key }?.isPublic
    }

    /// Remembers the share id for a key.
    static func remember(shareID: String, for key: String, isPublic: Bool = true) {
        guard !key.isEmpty, !shareID.isEmpty else { return }
        var all = entries().filter { $0.key != key }
        all.append(Entry(key: key, id: shareID, isPublic: isPublic))
        // A bounded number of them, most recent last: the shares somebody
        // is likely to make again are the ones they have just made. This is
        // a convenience, not a record.
        if all.count > 64 { all.removeFirst(all.count - 64) }
        UserDefaults.standard.set(all.map { [$0.key, $0.id, $0.isPublic ? "1" : "0"] },
                                 forKey: defaultsKey)
    }

    private static func entries() -> [Entry] {
        let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [[String]] ?? []
        return stored.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return Entry(key: pair[0], id: pair[1], isPublic: pair.count > 2 && pair[2] == "1")
        }
    }
}
