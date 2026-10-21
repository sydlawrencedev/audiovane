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
    static func key(name: String, author: String, url: String?, shader: String) -> String {
        var text = ""
        for field in [name, author, url ?? "", shader] {
            text += "\(field.utf8.count):\(field)"
        }
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
    }

    /// The share id for a key, if this Mac has made one.
    static func shareID(for key: String) -> String? {
        guard !key.isEmpty else { return nil }
        return entries().first { $0.key == key }?.id
    }

    /// Remembers the share id for a key.
    static func remember(shareID: String, for key: String) {
        guard !key.isEmpty, !shareID.isEmpty else { return }
        var all = entries().filter { $0.key != key }
        all.append(Entry(key: key, id: shareID))
        // A bounded number of them, most recent last: the shares somebody
        // is likely to make again are the ones they have just made. This is
        // a convenience, not a record.
        if all.count > 64 { all.removeFirst(all.count - 64) }
        UserDefaults.standard.set(all.map { [$0.key, $0.id] }, forKey: defaultsKey)
    }

    private static func entries() -> [Entry] {
        let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [[String]] ?? []
        return stored.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return Entry(key: pair[0], id: pair[1])
        }
    }
}
