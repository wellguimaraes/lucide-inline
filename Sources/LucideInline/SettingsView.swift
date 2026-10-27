import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ShortcutSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                ForEach(ShortcutAction.allCases) { action in
                    GridRow {
                        Text(action.title)
                            .gridColumnAlignment(.trailing)
                        ShortcutRecorder(settings: settings, action: action)
                    }
                }
            }

            Text("Click a shortcut, then press the new keys. Press Esc to cancel. Clicking an icon with the same modifier keys as a paste shortcut also uses that paste type.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Restore Defaults") { settings.resetToDefaults() }
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// A button that records the next key press as the shortcut for `action`.
private struct ShortcutRecorder: View {
    @ObservedObject var settings: ShortcutSettings
    let action: ShortcutAction

    @State private var monitor: Any?
    @State private var problem: String?

    private var isRecording: Bool { monitor != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { isRecording ? stop() : start() }) {
                Text(isRecording ? "Type shortcut…" : settings[action].display)
                    .frame(minWidth: 130)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        problem = nil
        settings.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let shortcut = Shortcut(event: event)
            if event.keyCode == 53, shortcut.modifiers.isEmpty { // plain esc cancels
                stop()
            } else if let problem = settings.problem(with: shortcut, for: action) {
                self.problem = problem
            } else {
                settings[action] = shortcut
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settings.isRecording = false
    }
}

final class SettingsWindowController {
    private let settings: ShortcutSettings
    private var window: NSWindow?

    init(settings: ShortcutSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.title = "Lucide Inline Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
