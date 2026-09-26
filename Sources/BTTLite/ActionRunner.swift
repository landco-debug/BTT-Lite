import AppKit
import ApplicationServices
import Foundation

@MainActor
final class ActionRunner {
    // Compatibility marker used by RuSwitcher 3.3.0 to ignore synthetic events.
    // It is harmless when RuSwitcher is not installed and prevents injected
    // shortcuts from entering RuSwitcher's word-conversion buffer.
    static let syntheticEventTag: Int64 = 0x52555300

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
            if let script = action.parameters["script"], !script.isEmpty {
                await transformSelectionWithJavaScript(script: script)
            }
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
            let address = action.parameters["address"] ?? ""
            let name = action.parameters["deviceName"] ?? ""
            if !address.isEmpty || !name.isEmpty {
                await runBundledHelper("BTTLiteBluetoothHelper", arguments: [address, name])
            }
        case .activateHoveredDockApp:
            activateHoveredDockApp()
        case .clipboardHistory:
            NSLog("BTT Lite: clipboard history action is preserved but not implemented")
        case .builtIn, .unsupported:
            NSLog("BTT Lite: skipped preserved action: %@", action.title)
        }
    }

    private struct JavaScriptTransformRequest: Codable {
        var script: String
        var text: String
    }

    private struct JavaScriptTransformResponse: Codable {
        var ok: Bool
        var result: String?
        var error: String?
    }

    private func transformSelectionWithJavaScript(script: String) async {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        sendKeyCode(8, modifiers: [.command]) // ⌘C
        await waitForClipboardChange(timeout: 1.0)
        guard pasteboard.changeCount != initialChangeCount,
              let selectedText = pasteboard.string(forType: .string) else {
            NSLog("BTT Lite: JavaScript transform could not copy the current selection")
            return
        }

        let request = JavaScriptTransformRequest(script: script, text: selectedText)
        guard let requestData = try? JSONEncoder().encode(request),
              let responseData = await runBundledHelperCapture("BTTLiteJavaScriptHelper", stdin: requestData),
              let response = try? JSONDecoder().decode(JavaScriptTransformResponse.self, from: responseData),
              response.ok, let replacement = response.result else {
            NSLog("BTT Lite: JavaScript transform helper failed")
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(replacement, forType: .string)
        sendKeyCode(9, modifiers: [.command]) // ⌘V
    }

    private func sendShortcut(_ action: RuleAction) {
        guard let rawCode = action.parameters["keyCode"],
              let code = UInt16(rawCode) else {
            // Never fall back to virtual key 0 ("A", or "Ф" on a Russian layout).
            // A malformed/preserved action must be skipped instead of typing text.
            NSLog("BTT Lite: skipped shortcut action without a valid key code: %@", action.title)
            return
        }
        let modifiers = ModifierSet(rawValue: UInt64(action.parameters["modifiers"] ?? "") ?? 0)
        sendKeyCode(code, modifiers: modifiers)
    }

    private func sendKeyCode(_ keyCode: UInt16, modifiers: ModifierSet) {
        // Mission Control and some global hotkey listeners ignore synthetic events
        // made from combinedSessionState. hidSystemState follows the hardware path.
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        struct PhysicalModifier {
            let member: ModifierSet
            let keyCode: CGKeyCode
            let flag: CGEventFlags
        }
        let physical: [PhysicalModifier] = [
            PhysicalModifier(member: .control, keyCode: 59, flag: .maskControl),
            PhysicalModifier(member: .option, keyCode: 58, flag: .maskAlternate),
            PhysicalModifier(member: .shift, keyCode: 56, flag: .maskShift),
            PhysicalModifier(member: .command, keyCode: 55, flag: .maskCommand)
        ]

        func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, type: CGEventType? = nil) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            if let type { event.type = type }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
            event.post(tap: .cghidEventTap)
        }

        var flags: CGEventFlags = []
        if modifiers.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }

        for modifier in physical where modifiers.contains(modifier.member) {
            flags.insert(modifier.flag)
            post(modifier.keyCode, down: true, flags: flags, type: .flagsChanged)
        }

        post(CGKeyCode(keyCode), down: true, flags: flags)
        post(CGKeyCode(keyCode), down: false, flags: flags)

        for modifier in physical.reversed() where modifiers.contains(modifier.member) {
            flags.remove(modifier.flag)
            post(modifier.keyCode, down: false, flags: flags, type: .flagsChanged)
        }
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

    private func runBundledHelperCapture(_ name: String, stdin: Data) async -> Data? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(name)
        return await runProcessCapture(url.path, arguments: [], stdin: stdin)
    }

    private func runProcessCapture(_ executable: String, arguments: [String], stdin: Data) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let inputPipe = Pipe()
                let outputPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    inputPipe.fileHandleForWriting.write(stdin)
                    try? inputPipe.fileHandleForWriting.close()
                    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 ? output : nil)
                } catch {
                    NSLog("BTT Lite: helper failed: %@", String(describing: error))
                    continuation.resume(returning: nil)
                }
            }
        }
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
