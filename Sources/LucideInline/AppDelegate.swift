import AppKit
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = IconStore()
    private let settings = ShortcutSettings()
    private lazy var picker = PickerController(store: store, settings: settings)
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private lazy var updater = IconUpdater(store: store)
    private var hotKey: HotKey?
    private var hotKeyObserver: AnyCancellable?
    private var statusItem: NSStatusItem?
    private let openItem = NSMenuItem(title: "Open Picker", action: #selector(openPicker), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "Check for Icon Updates", action: #selector(checkForIconUpdates), keyEquivalent: "")
    private let versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Re-register whenever the shortcut changes; drop it while a recorder is listening.
        hotKeyObserver = settings.$shortcuts
            .combineLatest(settings.$isRecording)
            .sink { [weak self] shortcuts, isRecording in
                self?.registerHotKey(shortcuts[.openPicker], paused: isRecording)
            }

        setUpStatusItem()
        updater.startDailyChecks()

        // Prompts once; needed to read the caret position and to send ⌘V.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func registerHotKey(_ shortcut: Shortcut?, paused: Bool) {
        hotKey = nil
        guard let shortcut, !paused else { return }
        hotKey = HotKey(keyCode: Int(shortcut.keyCode), modifiers: shortcut.carbonModifiers) { [weak self] in
            self?.picker.toggle()
        }
        if hotKey == nil {
            NSLog("LucideInline: could not register \(shortcut.display); another app may own it")
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = store.icon(named: "shapes") {
            let image = store.image(for: icon).copy() as! NSImage
            image.size = NSSize(width: 16, height: 16)
            item.button?.image = image
        } else {
            item.button?.title = "L"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(accessibilityItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lucide Inline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }

        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        openItem.title = "Open Picker  \(settings[.openPicker].display)"
        accessibilityItem.isHidden = AXIsProcessTrusted()
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        versionItem.title = "Lucide \(store.version) · \(store.icons.count) icons"
        updateItem.title = updater.isChecking ? "Checking for Icon Updates…" : "Check for Icon Updates"
        updateItem.isEnabled = !updater.isChecking
    }

    @objc private func openPicker() {
        // Let the menu finish closing so the previously focused app is frontmost again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.picker.show() }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func checkForIconUpdates() {
        updater.check { result in
            let alert = NSAlert()
            switch result {
            case .success(.upToDate(let version)):
                alert.messageText = "Icons are up to date"
                alert.informativeText = "You have the latest Lucide icons (\(version))."
            case .success(.updated(let from, let to, let count)):
                alert.messageText = "Icons updated"
                alert.informativeText = "Lucide \(from) → \(to), \(count) icons."
            case .failure(let error):
                alert.alertStyle = .warning
                alert.messageText = "Couldn't update icons"
                alert.informativeText = error.localizedDescription
            }
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("LucideInline: launch at login failed: \(error)")
        }
    }
}
