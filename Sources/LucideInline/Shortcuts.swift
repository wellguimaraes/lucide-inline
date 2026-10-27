import AppKit
import Carbon
import SwiftUI

/// A key plus modifiers, recorded from a real key press.
struct Shortcut: Codable, Equatable {
    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    private static let returnKey: UInt16 = 36
    private static let keypadEnter: UInt16 = 76
    private static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106]
    private static let navigationKeys: Set<UInt16> = [53, 123, 124, 125, 126] // esc, arrows
    private static let keyLabels: [UInt16: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16",
    ]

    let keyCode: UInt16
    let modifierFlags: UInt
    let key: String

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection(Self.relevantModifiers).rawValue
        self.key = key
    }

    init(event: NSEvent) {
        let key = Self.keyLabels[event.keyCode]
            ?? event.characters(byApplyingModifiers: [])?.uppercased()
            ?? "?"
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags, key: key)
    }

    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }

    var carbonModifiers: Int {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        return flags
    }

    /// Return and keypad Enter count as the same key.
    func matches(_ event: NSEvent) -> Bool {
        Self.normalized(event.keyCode) == Self.normalized(keyCode)
            && event.modifierFlags.intersection(Self.relevantModifiers) == modifiers
    }

    var hasCommandLikeModifier: Bool { !modifiers.intersection([.command, .control, .option]).isEmpty }
    var isFunctionKey: Bool { Self.functionKeys.contains(keyCode) }
    var isNavigationKey: Bool { Self.navigationKeys.contains(keyCode) }
    var isReturnOrTab: Bool { [Self.returnKey, Self.keypadEnter, 48].contains(keyCode) }

    private static func normalized(_ code: UInt16) -> UInt16 { code == keypadEnter ? returnKey : code }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case openPicker
    case pasteName
    case pasteSVGCode
    case pasteSVGFile

    var id: Self { self }

    var title: String {
        switch self {
        case .openPicker: "Open picker"
        case .pasteName: "Paste icon name"
        case .pasteSVGCode: "Paste SVG code"
        case .pasteSVGFile: "Paste SVG file"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .openPicker: Shortcut(keyCode: UInt16(kVK_ANSI_L), modifiers: [.control, .command], key: "L")
        case .pasteName: Shortcut(keyCode: 36, modifiers: [], key: "↩")
        case .pasteSVGCode: Shortcut(keyCode: 36, modifiers: [.command], key: "↩")
        case .pasteSVGFile: Shortcut(keyCode: 36, modifiers: [.command, .shift], key: "↩")
        }
    }

    var pasteKind: PasteKind? {
        switch self {
        case .openPicker: nil
        case .pasteName: .name
        case .pasteSVGCode: .svgCode
        case .pasteSVGFile: .svgFile
        }
    }
}

final class ShortcutSettings: ObservableObject {
    private static let defaultsKey = "shortcuts"

    @Published private(set) var shortcuts: [ShortcutAction: Shortcut]
    /// True while a recorder is listening, so the global hotkey doesn't fire mid-recording.
    @Published var isRecording = false

    init() {
        let stored = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) } ?? [:]
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { action in
            (action, stored[action.rawValue] ?? action.defaultShortcut)
        })
    }

    subscript(action: ShortcutAction) -> Shortcut {
        get { shortcuts[action] ?? action.defaultShortcut }
        set {
            shortcuts[action] = newValue
            save()
        }
    }

    func resetToDefaults() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        save()
    }

    /// The paste action bound to this key press inside the picker, if any.
    func pasteKind(for event: NSEvent) -> PasteKind? {
        ShortcutAction.allCases.first { $0.pasteKind != nil && self[$0].matches(event) }?.pasteKind
    }

    /// Clicks reuse the paste shortcuts' modifiers; a plain click falls back to the name.
    func pasteKind(forClickWith modifiers: NSEvent.ModifierFlags) -> PasteKind {
        let pressed = modifiers.intersection(Shortcut.relevantModifiers)
        return ShortcutAction.allCases.first { $0.pasteKind != nil && self[$0].modifiers == pressed }?.pasteKind ?? .name
    }

    /// Why `shortcut` can't be used for `action`, or nil if it can.
    func problem(with shortcut: Shortcut, for action: ShortcutAction) -> String? {
        if let other = ShortcutAction.allCases.first(where: { $0 != action && self[$0] == shortcut }) {
            return "Already used for “\(other.title)”."
        }
        if action == .openPicker {
            return shortcut.hasCommandLikeModifier || shortcut.isFunctionKey
                ? nil : "Add ⌘, ⌃ or ⌥ so it doesn't fire while you type."
        }
        if shortcut.keyCode == UInt16(kVK_ANSI_W), shortcut.modifiers == .command {
            return "⌘W closes the picker."
        }
        if shortcut.isNavigationKey, !shortcut.hasCommandLikeModifier {
            return "Arrows and Esc are used to navigate the picker."
        }
        if !shortcut.hasCommandLikeModifier, !shortcut.isReturnOrTab, !shortcut.isFunctionKey {
            return "Add ⌘, ⌃ or ⌥ so it doesn't block typing in the search field."
        }
        return nil
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
