import AppKit
import ApplicationServices
import Foundation

@MainActor
final class ActionRunner {
    // Compatibility marker used by RuSwitcher 3.3.0 to ignore synthetic events.
    // It is harmless when RuSwitcher is not installed and prevents injected
    // shortcuts from entering RuSwitcher's word-conversion buffer.
    static let syntheticEventTag: Int64 = 0x52555300

    private struct RecentCloseTarget {
        var processIdentifier: pid_t
        var bundleIdentifier: String?
        var bundleURL: URL?
        var capturedAt: Date
    }

    private var recentCloseTarget: RecentCloseTarget?
    private var bluetoothToggleInFlight = false
    private var lastBluetoothDisconnectAt: Date?

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
            sendSpaceShortcut(symbolicHotKeyID: 79, fallbackKeyCode: 123)
        case .moveSpaceRight:
            sendSpaceShortcut(symbolicHotKeyID: 81, fallbackKeyCode: 124)
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
                await toggleBluetoothDevice(address: address, name: name)
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

        // BetterTouchTool-style close/reopen workflows need to keep the application
        // context even after ⌘W closes the last window (common with Chrome/Safari web apps).
        if code == 13, modifiers == [.command] { // ⌘W
            rememberCurrentApplicationAsCloseTarget()
            sendKeyCode(code, modifiers: modifiers)
            return
        }
        if code == 17, modifiers == [.shift, .command], restoreRecentCloseTargetIfAvailable() { // ⇧⌘T
            return
        }

        sendKeyCode(code, modifiers: modifiers)
    }

    private func rememberCurrentApplicationAsCloseTarget() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        recentCloseTarget = RecentCloseTarget(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            bundleURL: app.bundleURL,
            capturedAt: Date()
        )
    }

    private func restoreRecentCloseTargetIfAvailable() -> Bool {
        guard let target = recentCloseTarget,
              Date().timeIntervalSince(target.capturedAt) <= 600 else {
            recentCloseTarget = nil
            return false
        }

        let running = NSWorkspace.shared.runningApplications.first { app in
            if app.processIdentifier == target.processIdentifier { return true }
            if let bundleIdentifier = target.bundleIdentifier {
                return app.bundleIdentifier == bundleIdentifier
            }
            return false
        }

        if let running {
            _ = running.activate(options: [.activateIgnoringOtherApps])
            sendKeyCode(17, modifiers: [.shift, .command], targetPID: running.processIdentifier)
            return true
        }

        // A standalone web app may terminate when its last window closes. In that
        // case reopening its bundle is the closest equivalent to BTT's "restore it"
        // behavior; sending ⇧⌘T to the newly frontmost unrelated app would be wrong.
        if let bundleURL = target.bundleURL, NSWorkspace.shared.open(bundleURL) {
            return true
        }

        return false
    }

    private func sendSpaceShortcut(symbolicHotKeyID: Int, fallbackKeyCode: UInt16) {
        if let configured = SystemSymbolicHotKeyResolver.current(id: symbolicHotKeyID) {
            sendKeyCode(configured.keyCode, modifiers: configured.modifiers, holdDuration: 0.012)
            return
        }

        // Modern MacBook defaults encode Control+Arrow with the secondary-Fn bit.
        // This fallback is only used if the user's symbolic-hotkey preference cannot
        // be read. Normally we use the exact System Settings value above, like BTT.
        NSLog("BTT Lite: Mission Control symbolic hotkey %d could not be resolved; using fallback", symbolicHotKeyID)
        sendKeyCode(fallbackKeyCode, modifiers: [.control, .function], holdDuration: 0.012)
    }

    private func sendKeyCode(
        _ keyCode: UInt16,
        modifiers: ModifierSet,
        targetPID: pid_t? = nil,
        holdDuration: TimeInterval = 0
    ) {
        // A HID-state source plus flags on the actual key event is enough for ordinary
        // AppKit shortcuts and for Mission Control's Ctrl+←/→ on macOS Sequoia.
        //
        // Do NOT synthesize separate modifier flagsChanged events. Modifier-only hotkey
        // tools (dictation utilities in particular) can interpret those fake Control /
        // Option / Command edges as real user presses and launch unexpectedly.
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        source.localEventsSuppressionInterval = 0

        var flags: CGEventFlags = []
        if modifiers.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.numericPad) { flags.insert(.maskNumericPad) }
        if modifiers.contains(.help) { flags.insert(.maskHelp) }

        func post(_ down: Bool) {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: down
            ) else { return }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
            if let targetPID {
                event.postToPid(targetPID)
            } else {
                event.post(tap: .cghidEventTap)
            }
        }

        post(true)
        if holdDuration > 0 {
            Thread.sleep(forTimeInterval: holdDuration)
        }
        post(false)
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
                    if process.terminationStatus != 0 {
                        NSLog("BTT Lite: process %@ exited with status %d", executable, process.terminationStatus)
                    }
                } catch {
                    NSLog("BTT Lite: process failed: %@", String(describing: error))
                }
                continuation.resume()
            }
        }
    }

    private struct ProcessResult {
        var status: Int32
        var output: String
        var error: String
    }

    private func bundledHelperURL(_ name: String) -> URL {
        let helpers = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)

        if name == "BTTLiteBluetoothHelper" {
            return helpers
                .appendingPathComponent("BTTLiteBluetoothHelper.app", isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent(name)
        }
        return helpers.appendingPathComponent(name)
    }

    private func toggleBluetoothDevice(address: String, name: String) async {
        guard !bluetoothToggleInFlight else {
            NSLog("BTT Lite: ignored overlapping Bluetooth toggle")
            return
        }
        bluetoothToggleInFlight = true
        defer { bluetoothToggleInFlight = false }

        if let lastDisconnect = lastBluetoothDisconnectAt {
            let elapsed = Date().timeIntervalSince(lastDisconnect)
            let minimumGap: TimeInterval = 1.25
            if elapsed < minimumGap {
                let remaining = minimumGap - elapsed
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }

        let result = await runProcessResult(
            bundledHelperURL("BTTLiteBluetoothHelper").path,
            arguments: [address, name]
        )

        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status == 0 {
            if output == "disconnected" {
                lastBluetoothDisconnectAt = Date()
            } else if output == "connected" {
                lastBluetoothDisconnectAt = nil
            }
            return
        }

        let detail = !result.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Bluetooth helper exited with status \(result.status)."

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Bluetooth action failed"
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func runProcessResult(_ executable: String, arguments: [String]) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: ProcessResult(
                        status: process.terminationStatus,
                        output: String(data: output, encoding: .utf8) ?? "",
                        error: String(data: error, encoding: .utf8) ?? ""
                    ))
                } catch {
                    continuation.resume(returning: ProcessResult(
                        status: -1,
                        output: "",
                        error: String(describing: error)
                    ))
                }
            }
        }
    }

    private func runBundledHelper(_ name: String, arguments: [String]) async {
        await runProcess(bundledHelperURL(name).path, arguments: arguments)
    }

    private func runBundledHelperCapture(_ name: String, stdin: Data) async -> Data? {
        let url = bundledHelperURL(name)
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
