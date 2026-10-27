import AppKit

struct LucideIcon: Codable, Identifiable, Hashable {
    let name: String
    let tags: [String]
    let svg: String

    var id: String { name }
}

/// The on-disk icons.json format, shared by the bundled copy and downloaded updates.
struct IconSet: Codable {
    let version: String
    let icons: [LucideIcon]
}

/// Loads the newest available icon set, searches it, and renders icons to template images.
final class IconStore {
    private static let recentsKey = "recentIcons"
    private static let maxRecents = 18

    /// Where downloaded updates live; preferred over the bundled copy when newer.
    static let downloadedURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lucide Inline", isDirectory: true)
        .appendingPathComponent("icons.json")

    private(set) var version = "?"
    private(set) var icons: [LucideIcon] = []
    private var byName: [String: LucideIcon] = [:]
    private var imageCache: [String: NSImage] = [:]

    init() {
        reload()
    }

    /// Picks whichever of the downloaded and bundled icon sets has the higher version.
    func reload() {
        let candidates = [Self.downloadedURL, Bundle.main.url(forResource: "icons", withExtension: "json")]
            .compactMap { $0 }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(IconSet.self, from: $0) } }
        guard let set = candidates.max(by: { $0.version.isOlderVersion(than: $1.version) }) else {
            NSLog("LucideInline: no icons.json found")
            return
        }
        version = set.version
        icons = set.icons
        byName = Dictionary(set.icons.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        imageCache = [:]
    }

    // MARK: Search

    func search(_ query: String) -> [LucideIcon] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            let recents = recentNames.compactMap { byName[$0] }
            let recentSet = Set(recents.map(\.name))
            return recents + icons.filter { !recentSet.contains($0.name) }
        }

        let dashed = q.replacingOccurrences(of: " ", with: "-")
        let tokens = q.split(separator: " ").map(String.init)

        let scored: [(LucideIcon, Int)] = icons.compactMap { icon in
            let name = icon.name
            if name == dashed { return (icon, 10_000) }
            if name.hasPrefix(dashed) { return (icon, 5_000 - name.count) }
            if name.contains(dashed) { return (icon, 3_000 - name.count) }

            let segments = name.split(separator: "-")
            var score = 0
            for token in tokens {
                if segments.contains(where: { $0.hasPrefix(token) }) {
                    score += 60
                } else if name.contains(token) {
                    score += 40
                } else if icon.tags.contains(where: { $0.lowercased().hasPrefix(token) }) {
                    score += 20
                } else if icon.tags.contains(where: { $0.lowercased().contains(token) }) {
                    score += 10
                } else {
                    return nil
                }
            }
            return (icon, score)
        }

        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
            .map(\.0)
    }

    // MARK: Recents

    var recentNames: [String] {
        UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    func recordRecent(_ name: String) {
        var names = recentNames.filter { $0 != name }
        names.insert(name, at: 0)
        UserDefaults.standard.set(Array(names.prefix(Self.maxRecents)), forKey: Self.recentsKey)
    }

    // MARK: Rendering

    func icon(named name: String) -> LucideIcon? { byName[name] }

    func image(for icon: LucideIcon) -> NSImage {
        if let cached = imageCache[icon.name] { return cached }
        let svg = icon.svg.replacingOccurrences(of: "currentColor", with: "#000000")
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
        image.isTemplate = true
        imageCache[icon.name] = image
        return image
    }
}
