import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindowController: SettingsWindowController?
    private let store = ConfigStore.shared
    private lazy var actionRunner = ActionRunner()
    private lazy var keyboardEngine = KeyboardEngine(store: store, runner: actionRunner)

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        keyboardEngine.start(promptForPermission: true)
        NotificationCenter.default.addObserver(forName: .bttLiteConfigDidChange, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.keyboardEngine.start(promptForPermission: false) }
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "BTT Lite")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Import BetterTouchTool Preset…", action: #selector(importBTTPreset), keyEquivalent: "i")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BTT Lite", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: store)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func importBTTPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a BetterTouchTool .bttpreset file"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let profile = try BTTImporter().importPreset(from: url)
            store.mutate { config in
                var imported = profile
                if config.profiles.contains(where: { $0.name == imported.name }) {
                    imported.name += " (Imported)"
                }
                config.profiles.append(imported)
                config.activeProfileID = imported.id
            }
            openSettings()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
