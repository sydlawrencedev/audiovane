import Foundation

/// The gallery, as the site lists it.
///
/// The app does not keep its own copy of the list: the site has one, and
/// it is the same list the app's Gallery tab shows and the same one
/// `/vibescapes` shows. The sort is asked for rather than done here, so
/// the two cannot drift apart — "most viewed" in the app is the same
/// order as "most viewed" on the site.
@MainActor
final class GalleryModel: ObservableObject {
    /// One vibescape in the gallery.
    struct Item: Identifiable {
        let id: String
        let name: String
        /// The page it can be opened at.
        let url: URL
        /// Its picture.
        let imageURL: URL
        /// Whether it is one of the vibescapes that ship with the app.
        let isBuiltIn: Bool

        /// What the site calls the image, which is what the file is called
        /// on disk as well.
        static func imageURL(from path: String) -> URL? {
            URL(string: path)
        }
    }

    /// The two orders the gallery can be in.
    enum Sort: String, CaseIterable, Identifiable {
        case recent
        case viewed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recent: return "Most recent"
            case .viewed: return "Most viewed"
            }
        }
    }

    /// Where the gallery is.
    static let endpoint = URL(string: "https://vibresia.com/api/gallery")!

    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published var sort: Sort = .recent {
        didSet { if sort != oldValue { Task { await load() } } }
    }

    /// A sample list, for the headless UI shots, which have no gallery to
    /// fetch and no time to wait for one.
    static let sample: [Item] = [
        Item(id: "sample-one", name: "Neon Current",
             url: URL(string: "https://vibresia.com/share/band")!,
             imageURL: URL(string: "https://vibresia.com/media/modes/band.jpg")!,
             isBuiltIn: false),
        Item(id: "sample-two", name: "Glass Garden",
             url: URL(string: "https://vibresia.com/share/flux")!,
             imageURL: URL(string: "https://vibresia.com/media/modes/flux.jpg")!,
             isBuiltIn: false),
        Item(id: "sample-three", name: "Long Exposure",
             url: URL(string: "https://vibresia.com/share/silk")!,
             imageURL: URL(string: "https://vibresia.com/media/modes/silk.jpg")!,
             isBuiltIn: false),
        Item(id: "sample-four", name: "Deep Field",
             url: URL(string: "https://vibresia.com/share/vortex")!,
             imageURL: URL(string: "https://vibresia.com/media/modes/vortex.jpg")!,
             isBuiltIn: false),
        Item(id: "sample-five", name: "Undertow",
             url: URL(string: "https://vibresia.com/share/liquid")!,
             imageURL: URL(string: "https://vibresia.com/media/modes/liquid.jpg")!,
             isBuiltIn: false),
    ]

    /// Puts the sample list in place, without asking the network.
    func loadSample() {
        items = Self.sample
    }

    /// Fetches the gallery.
    ///
    /// A failure is not a big deal: the panel says so and carries on, and
    /// the Installed tab — which is where the panel opens — does not need
    /// the network at all.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        failed = false
        defer { isLoading = false }

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        if let url = URL(string: Self.endpoint.absoluteString + "?sort=" + sort.rawValue) {
            request.url = url
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                failed = true
                return
            }
            items = Self.parse(data)
        } catch {
            failed = true
        }
    }

    /// The gallery, as the API sends it.
    private static func parse(_ data: Data) -> [Item] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["vibescapes"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry["id"] as? String,
                  let urlString = entry["url"] as? String,
                  let url = URL(string: urlString),
                  let imageString = entry["imageUrl"] as? String,
                  let imageURL = URL(string: imageString) else { return nil }
            return Item(id: id,
                        name: entry["name"] as? String ?? id,
                        url: url,
                        imageURL: imageURL,
                        isBuiltIn: entry["builtin"] as? Bool ?? false)
        }
    }
}
