import AppKit
import SwiftUI

/// Borderless panel that takes keyboard focus without activating the app,
/// so the app the user was typing in stays frontmost (like the emoji picker).
final class PickerPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    init(contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

final class PickerController: NSObject, NSWindowDelegate {
    private static let size = NSSize(width: 380, height: 400)
    private static let caretGap: CGFloat = 6

    private let panel = PickerPanel(contentSize: PickerController.size)
    private let model: PickerModel
    private var targetApp: NSRunningApplication?

    var isVisible: Bool { panel.isVisible }

    init(store: IconStore, settings: ShortcutSettings) {
        model = PickerModel(store: store, settings: settings)
        super.init()

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        // A mask image (unlike a layer corner radius) also shapes the window shadow.
        background.maskImage = Self.roundedMask(radius: 12)

        let hosting = NSHostingView(rootView: PickerView(model: model, settings: settings))
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)

        panel.contentView = background
        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }

        model.onClose = { [weak self] in self?.hide() }
        model.onPick = { [weak self] icon, kind in self?.insert(icon, as: kind) }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        targetApp = NSWorkspace.shared.frontmostApplication
        model.prepareForPresentation()
        panel.setFrameOrigin(origin(for: FocusLocator.locate(in: targetApp)))
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: Actions

    private func insert(_ icon: LucideIcon, as kind: PasteKind) {
        hide()
        do {
            Paster.paste(try kind.pasteboardObject(for: icon), into: targetApp)
            model.store.recordRecent(icon.name)
        } catch {
            NSLog("LucideInline: could not prepare \(icon.name): \(error)")
            NSSound.beep()
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if let kind = model.settings.pasteKind(for: event) {
            model.confirm(kind)
            return true
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
            hide()
            return true
        }

        switch Int(event.keyCode) {
        case 53: model.cancel() // esc
        case 123: model.moveSelection(by: -1)
        case 124: model.moveSelection(by: 1)
        case 126: model.moveSelection(by: -PickerModel.columns)
        case 125: model.moveSelection(by: PickerModel.columns)
        default: return false
        }
        return true
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Placement

    private func origin(for anchor: FocusAnchor) -> NSPoint {
        let size = Self.size
        switch anchor {
        case .caret(let caret):
            let visible = screen(containing: NSPoint(x: caret.midX, y: caret.midY)).visibleFrame
            var origin = NSPoint(x: caret.minX - 12, y: caret.minY - Self.caretGap - size.height)
            if origin.y < visible.minY {
                origin.y = caret.maxY + Self.caretGap // not enough room below: open above the caret
            }
            return clamp(origin, size: size, to: visible)

        case .window(let window):
            let visible = screen(containing: NSPoint(x: window.midX, y: window.midY)).visibleFrame
            let origin = NSPoint(x: window.midX - size.width / 2, y: window.midY - size.height / 2)
            return clamp(origin, size: size, to: visible)

        case .none:
            let visible = screen(containing: NSEvent.mouseLocation).visibleFrame
            return NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        }
    }

    private func screen(containing point: NSPoint) -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func clamp(_ origin: NSPoint, size: NSSize, to frame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - size.width),
            y: min(max(origin.y, frame.minY), frame.maxY - size.height)
        )
    }
}
