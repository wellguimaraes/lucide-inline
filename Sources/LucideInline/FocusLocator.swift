import AppKit
import ApplicationServices

/// Where the picker should appear. Rects are in Cocoa screen coordinates (bottom-left origin).
enum FocusAnchor {
    case caret(CGRect)
    case window(CGRect)
    case none
}

/// Uses the Accessibility API to find the text caret (or the focused window) of the frontmost app.
enum FocusLocator {
    private static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]
    private static let maxSingleLineHeight: CGFloat = 60

    static func locate(in app: NSRunningApplication?) -> FocusAnchor {
        guard AXIsProcessTrusted(), let app else { return .none }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        // Electron apps only build their accessibility tree when asked to.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        if let focused: AXUIElement = attribute(appElement, kAXFocusedUIElementAttribute), isTextInput(focused) {
            if let caret = caretRect(of: focused) {
                return .caret(toCocoa(caret))
            }
            // No caret bounds (e.g. Ghostty): a single-line field still makes a good anchor,
            // but a large text area (terminal, editor) gives no hint where the caret is, so center over it.
            if let frame = frame(of: focused) {
                return frame.height <= maxSingleLineHeight
                    ? .caret(toCocoa(CGRect(x: frame.minX, y: frame.minY, width: 0, height: frame.height)))
                    : .window(toCocoa(frame))
            }
        }

        if let window: AXUIElement = attribute(appElement, kAXFocusedWindowAttribute), let frame = frame(of: window) {
            return .window(toCocoa(frame))
        }
        return .none
    }

    // MARK: Helpers

    private static func isTextInput(_ element: AXUIElement) -> Bool {
        if let role: String = attribute(element, kAXRoleAttribute), textRoles.contains(role) {
            return true
        }
        // Rich editors (contenteditable, custom text views) expose a settable value plus a selection.
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        let range: AXValue? = attribute(element, kAXSelectedTextRangeAttribute)
        return settable.boolValue && range != nil
    }

    private static func caretRect(of element: AXUIElement) -> CGRect? {
        guard
            let rangeValue: AXValue = attribute(element, kAXSelectedTextRangeAttribute),
            let selection = rangeValue.cfRange
        else { return nil }

        // Some apps return an empty rect for a zero-length range, so fall back to neighbouring characters.
        if let rect = bounds(of: element, range: CFRange(location: selection.location, length: selection.length)) {
            return rect
        }
        if let next = bounds(of: element, range: CFRange(location: selection.location, length: 1)) {
            return CGRect(x: next.minX, y: next.minY, width: 0, height: next.height)
        }
        if selection.location > 0, let prev = bounds(of: element, range: CFRange(location: selection.location - 1, length: 1)) {
            return CGRect(x: prev.maxX, y: prev.minY, width: 0, height: prev.height)
        }
        return nil
    }

    private static func bounds(of element: AXUIElement, range: CFRange) -> CGRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result
        )
        guard status == .success, let value = result, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        guard let rect = (value as! AXValue).cgRect, rect.height > 0, rect.origin != .zero else { return nil }
        return rect
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard
            let posValue: AXValue = attribute(element, kAXPositionAttribute),
            let sizeValue: AXValue = attribute(element, kAXSizeAttribute),
            let position = posValue.cgPoint,
            let size = sizeValue.cgSize,
            size.width > 0, size.height > 0
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self, CFGetTypeID(value) == AXUIElementGetTypeID() { return (value as! T) }
        if T.self == AXValue.self, CFGetTypeID(value) == AXValueGetTypeID() { return (value as! T) }
        return value as? T
    }

    /// AX uses a top-left origin anchored to the primary screen; Cocoa uses bottom-left.
    private static func toCocoa(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

private extension AXValue {
    var cfRange: CFRange? { value(.cfRange, CFRange()) }
    var cgRect: CGRect? { value(.cgRect, CGRect.zero) }
    var cgPoint: CGPoint? { value(.cgPoint, CGPoint.zero) }
    var cgSize: CGSize? { value(.cgSize, CGSize.zero) }

    private func value<T: BitwiseCopyable>(_ type: AXValueType, _ initial: T) -> T? {
        guard AXValueGetType(self) == type else { return nil }
        var result = initial
        return AXValueGetValue(self, type, &result) ? result : nil
    }
}
