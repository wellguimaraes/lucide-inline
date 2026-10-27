import AppKit

/// Inserts content (text or a file URL) into the frontmost app by placing it on the clipboard
/// and sending ⌘V, then restores whatever was on the clipboard before.
enum Paster {
    private static let restoreDelay: TimeInterval = 0.6

    static func paste(_ object: NSPasteboardWriting, into target: NSRunningApplication?) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.writeObjects([object])

        // Without Accessibility permission we can't send keystrokes; leave the content on the clipboard.
        guard AXIsProcessTrusted() else {
            NSSound.beep()
            return
        }

        target?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendCommandV()
            let changeCount = pasteboard.changeCount
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                // Only restore if nobody else touched the clipboard in the meantime.
                guard pasteboard.changeCount == changeCount, !saved.isEmpty else { return }
                pasteboard.clearContents()
                pasteboard.writeObjects(saved)
            }
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }
}
