import AppKit

enum PasteKind {
    case name
    case svgCode
    case svgFile

    func pasteboardObject(for icon: LucideIcon) throws -> NSPasteboardWriting {
        switch self {
        case .name:
            return icon.name as NSString
        case .svgCode:
            return icon.svg as NSString
        case .svgFile:
            // Lives in the temp dir so apps that read the file lazily (uploads, Finder) still find it.
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LucideInline", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(icon.name).svg")
            try Data(icon.svg.utf8).write(to: url)
            return url as NSURL
        }
    }
}

final class PickerModel: ObservableObject {
    static let columns = 9

    @Published var query = "" {
        didSet { refresh() }
    }
    @Published private(set) var results: [LucideIcon] = []
    @Published var selection = 0
    /// Bumped every time the panel opens so the view can re-focus the search field.
    @Published private(set) var presentation = 0

    let store: IconStore
    let settings: ShortcutSettings
    var onPick: (LucideIcon, PasteKind) -> Void = { _, _ in }
    var onClose: () -> Void = {}

    init(store: IconStore, settings: ShortcutSettings) {
        self.store = store
        self.settings = settings
        refresh()
    }

    var selectedIcon: LucideIcon? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    func prepareForPresentation() {
        if query.isEmpty { refresh() } else { query = "" }
        presentation += 1
    }

    private func refresh() {
        results = store.search(query)
        selection = 0
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    func confirm(_ kind: PasteKind, index: Int? = nil) {
        if let index { selection = index }
        guard let icon = selectedIcon else { return }
        onPick(icon, kind)
    }

    func cancel() {
        onClose()
    }
}
