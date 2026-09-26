import AppKit
import ApplicationServices
import Foundation

@MainActor
final class ActionRunner {
    static let syntheticEventTag: Int64 = 0x4254544C495445 // "BTTLITE"

    func execute(_ rule: Rule) {
        let actions = rule.actions.filter(\.enabled)
        Task { [weak self] in
            guard let self else { return }
            for action in actions {
                await self.execute(action)
            }
        }
    }

    private func execute(_ action: RuleAction) async {
        switch action.kind {
        case .sendShortcut:
            sendShortcut(action)
        case .runShortcut:
            if let name = action.parameters["name"], !name.isEmpty {
                await runProcess("/usr/bin/shortcuts", arguments: ["run", name])
            }
        case .launchPath:
            if let path = action.parameters["path"], !path.isEmpty {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        case .openURL:
            if let raw = action.parameters["url"], let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
            }
        case .terminalCommand:
            if let command = action.parameters["command"], !command.isEmpty {
                await runProcess("/bin/zsh", arguments: ["-lc", command])
            }
        case .shellScript:
            if let script = action.parameters["script"], !script.isEmpty {
                await runProcess("/bin/zsh", arguments: ["-lc", script])
            }
        case .appleScript:
            if let script = action.parameters["script"], !script.isEmpty {
                await runProcess("/usr/bin/osascript", arguments: ["-e", script])
            }
        case .javascriptTransform:
            // Kept separate from the always-on process. A dedicated helper will
            // be added so JavaScriptCore/network support does not inflate idle RSS.
            NSLog("BTT Lite: JavaScript transform is preserved but not executable yet")
        case .waitForClipboardChange:
            let timeout = Double(action.parameters["timeout"] ?? "") ?? 5.0
            await waitForClipboardChange(timeout: max(0.1, timeout))
        case .moveSpaceLeft:
            sendKeyCode(123, modifiers: [.control])
        case .moveSpaceRight:
            sendKeyCode(124, modifiers: [.control])
        case .pageBack:
            // Common native navigation fallback. Gesture-native navigation is
            // implemented with the gesture engine in a later commit.
            sendKeyCode(33, modifiers: [.command]) // ⌘[
        case .pageForward:
            sendKeyCode(30, modifiers: [.command]) // ⌘]
        case .launchpad:
            await runProcess("/usr/bin/open", arguments: ["-a", "Launchpad"])
        case .toggleBluetoothDevice:
            if let address = action.parameters["address"], !address.isEmpty {
                await runBundledHelper("BTTLiteBluetoothHelper", arguments: [address])
            }
        case .activateHoveredDockApp:
            activateHoveredDockApp()
        case .clipboardHistory:
            NSLog("BTT Lite: clipboard history action is preserved but not implemented")
        case .builtIn, .unsupported:
            NSLog("BTT Lite: skipped preserved action: %@", action.title)
        }
    }

    private func sendShortcut(_ action: RuleAction) {
        let code = UInt16(action.parameters["keyCode"] ?? "") ?? 0
        let modifiers = ModifierSet(rawValue: UInt64(action.parameters["modifiers"] ?? "") ?? 0)
        sendKeyCode(code, modifiers: modifiers)
    }

    private func sendKeyCode(_ keyCode: UInt16, modifiers: ModifierSet) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }

        let flags = cgFlags(from: modifiers)
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func cgFlags(from modifiers: ModifierSet) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private func waitForClipboardChange(timeout: Double) async {
        let pasteboard = NSPasteboard.general
        let initial = pasteboard.changeCount
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != initial { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func runProcess(_ executable: String, arguments: [String]) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    NSLog("BTT Lite: process failed: %@", String(describing: error))
                }
                continuation.resume()
            }
        }
    }

    private func runBundledHelper(_ name: String, arguments: [String]) async {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(name)
        await runProcess(url.path, arguments: arguments)
    }

    private func activateHoveredDockApp() {
        let mouse = NSEvent.mouseLocation
        let system = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(mouse.x), Float(mouse.y), &element)
        guard result == .success, let element else { return }

        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let candidate = current else { break }
            var roleValue: CFTypeRef?
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(candidate, kAXRoleAttribute as CFString, &roleValue)
            AXUIElementCopyAttributeValue(candidate, kAXTitleAttribute as CFString, &titleValue)
            let role = roleValue as? String ?? ""
            let title = titleValue as? String ?? ""
            if (role == kAXDockItemRole as String || role == kAXButtonRole as String), !title.isEmpty {
                let result = AXUIElementPerformAction(candidate, kAXPressAction as CFString)
                if result == .success { return }
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue else { break }
            current = unsafeBitCast(parentValue, to: AXUIElement.self)
        }
    }
}
