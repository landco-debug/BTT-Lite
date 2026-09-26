import Foundation

struct BTTImporter {
    enum ImportError: Error, LocalizedError {
        case invalidRoot
        case noContent

        var errorDescription: String? {
            switch self {
            case .invalidRoot: "The selected file is not a valid BetterTouchTool preset."
            case .noContent: "The BetterTouchTool preset contains no trigger sections."
            }
        }
    }

    func importPreset(from url: URL) throws -> Profile {
        let data = try Data(contentsOf: url)
        let rootObject = try JSONSerialization.jsonObject(with: data)
        guard let root = rootObject as? [String: Any] else { throw ImportError.invalidRoot }
        guard let sections = root["BTTPresetContent"] as? [[String: Any]] else { throw ImportError.noContent }

        let profileName = (root["BTTPresetName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var rules: [Rule] = []

        for section in sections {
            let appName = section["BTTAppName"] as? String ?? "Application"
            let bundleID = section["BTTAppBundleIdentifier"] as? String ?? ""
            let scope: RuleScope = bundleID == "BT.G" || appName == "Global"
                ? .global
                : .application(name: appName, bundleIdentifier: bundleID)

            for rawTrigger in section["BTTTriggers"] as? [[String: Any]] ?? [] {
                let trigger = mapTrigger(rawTrigger)
                let actions = (rawTrigger["BTTActionsToExecute"] as? [[String: Any]] ?? []).map(mapAction)
                let generatedName = rawTrigger["BTTTriggerName"] as? String
                let rule = Rule(
                    name: generatedName?.isEmpty == false ? generatedName! : trigger.displayName,
                    enabled: isEnabled(rawTrigger),
                    scope: scope,
                    trigger: trigger,
                    actions: actions
                )
                rules.append(rule)
            }
        }

        return Profile(name: (profileName?.isEmpty == false ? profileName! : url.deletingPathExtension().lastPathComponent), rules: rules)
    }

    private func mapTrigger(_ raw: [String: Any]) -> Trigger {
        let triggerClass = raw["BTTTriggerClass"] as? String ?? ""
        if triggerClass == "BTTTriggerTypeKeyboardShortcut" {
            let keyCode = UInt16(clamping: intValue(raw["BTTShortcutKeyCode"]))
            let display = raw["BTTLayoutIndependentChar"] as? String ?? "Key \(keyCode)"
            let modifiers = ModifierSet(rawValue: UInt64(max(0, intValue(raw["BTTShortcutModifierKeys"]))))
            return .keyboard(KeyboardTrigger(
                keyCode: keyCode,
                displayKey: normalizedDisplayKey(display),
                modifiers: modifiers.intersection(.userRelevant),
                triggerOnKeyDown: boolValue(raw["BTTTriggerOnDown"], default: true)
            ))
        }

        if triggerClass == "BTTTriggerTypeMagicMouse" || triggerClass == "BTTTriggerTypeTouchpadAll" {
            let description = raw["BTTTriggerTypeDescriptionReadOnly"] as? String ?? "Gesture"
            let device: GestureDevice = triggerClass == "BTTTriggerTypeMagicMouse" ? .magicMouse : .trackpad
            return .gesture(parseGesture(description: description, device: device))
        }

        return .unsupported(
            description: raw["BTTTriggerTypeDescriptionReadOnly"] as? String ?? "BTT Trigger \(intValue(raw["BTTTriggerType"]))",
            rawType: raw["BTTTriggerType"] as? Int
        )
    }

    private func parseGesture(description: String, device: GestureDevice) -> GestureTrigger {
        let lower = description.lowercased()
        let fingers = Int(description.split(separator: " ").first ?? "1") ?? 1
        let kind: GestureKind
        if lower.contains("double") && lower.contains("tap") { kind = .doubleTap }
        else if lower.contains("swipe") { kind = .swipe }
        else { kind = .click }

        let direction: GestureDirection?
        if lower.contains("left") { direction = .left }
        else if lower.contains("right") { direction = .right }
        else if lower.contains("up") { direction = .up }
        else if lower.contains("down") { direction = .down }
        else { direction = nil }
        return GestureTrigger(device: device, fingers: fingers, gesture: kind, direction: direction)
    }

    private func mapAction(_ raw: [String: Any]) -> RuleAction {
        let enabled = isEnabled(raw)
        let predefinedType = intValue(raw["BTTPredefinedActionType"])
        let predefinedName = raw["BTTPredefinedActionName"] as? String ?? ""
        var kind: ActionKind = .builtIn
        var parameters: [String: String] = [:]

        if let shortcut = raw["BTTShortcutToSend"] as? String {
            kind = .sendShortcut
            let parsed = parseBTTShortcut(shortcut)
            parameters["keyCode"] = String(parsed.keyCode)
            parameters["modifiers"] = String(parsed.modifiers.rawValue)
            if let char = raw["BTTLayoutIndependentActionChar"] as? String { parameters["displayKey"] = normalizedDisplayKey(char) }
        } else if let command = raw["BTTTerminalCommand"] as? String {
            kind = .terminalCommand
            parameters["command"] = command
        } else if let script = raw["BTTShellTaskActionScript"] as? String {
            kind = .shellScript
            parameters["script"] = script
        } else if let script = raw["BTTInlineAppleScript"] as? String {
            kind = .appleScript
            parameters["script"] = script
        } else {
            switch predefinedType {
            case 49:
                kind = .launchPath
                parameters["path"] = raw["BTTLaunchPath"] as? String ?? ""
            case 77: kind = .pageBack
            case 78: kind = .pageForward
            case 114: kind = .moveSpaceRight
            case 113: kind = .moveSpaceLeft
            case 115: kind = .launchpad
            case 150: kind = .activateHoveredDockApp
            case 172:
                kind = .appleScript
                parameters["script"] = raw["BTTInlineAppleScript"] as? String ?? nestedString(raw, path: ["BTTAdditionalActionData", "BTTAppleScriptString"])
            case 203: kind = .clipboardHistory
            case 206:
                kind = .shellScript
                parameters["script"] = raw["BTTShellTaskActionScript"] as? String ?? ""
            case 276:
                kind = .toggleBluetoothDevice
                parameters["deviceName"] = raw["BTTActionBluetoothDeviceName"] as? String ?? ""
                parameters["address"] = raw["BTTActionBluetoothDeviceAddress"] as? String ?? ""
            case 284:
                kind = .javascriptTransform
                parameters["script"] = nestedString(raw, path: ["BTTAdditionalActionData", "BTTClipboardTransformerJS"])
            case 295:
                kind = .runShortcut
                parameters["name"] = raw["BTTGenericActionConfig"] as? String ?? ""
            case 499:
                kind = .waitForClipboardChange
                parameters["timeout"] = nestedString(raw, path: ["BTTAdditionalActionData", "BTTActionWaitForClipboardTimeout"])
            default:
                kind = .builtIn
                if !predefinedName.isEmpty { parameters["name"] = predefinedName }
                parameters["bttActionType"] = String(predefinedType)
            }
        }

        var metadata: [String: String] = [:]
        if let uuid = raw["BTTUUID"] as? String { metadata["bttUUID"] = uuid }
        if !predefinedName.isEmpty { metadata["bttName"] = predefinedName }
        if predefinedType != 0 { metadata["bttActionType"] = String(predefinedType) }

        let title = !predefinedName.isEmpty ? predefinedName : kind.displayName
        return RuleAction(enabled: enabled, kind: kind, title: title, parameters: parameters, sourceMetadata: metadata)
    }

    private func parseBTTShortcut(_ value: String) -> (keyCode: UInt16, modifiers: ModifierSet) {
        let codes = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard let final = codes.last else { return (0, []) }
        var modifiers: ModifierSet = []
        for code in codes.dropLast() {
            switch code {
            case 55: modifiers.insert(.command)
            case 56: modifiers.insert(.shift)
            case 58: modifiers.insert(.option)
            case 59: modifiers.insert(.control)
            case 63: modifiers.insert(.function)
            default: break
            }
        }
        return (UInt16(clamping: final), modifiers)
    }

    private func nestedString(_ raw: [String: Any], path: [String]) -> String {
        var current: Any = raw
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else { return "" }
            current = next
        }
        if let s = current as? String { return s }
        if let n = current as? NSNumber { return n.stringValue }
        return ""
    }

    private func isEnabled(_ raw: [String: Any]) -> Bool {
        guard let value = raw["BTTEnabled2"] else { return true }
        return boolValue(value, default: true)
    }

    private func boolValue(_ value: Any?, default fallback: Bool) -> Bool {
        if let b = value as? Bool { return b }
        if let i = value as? Int { return i != 0 }
        if let n = value as? NSNumber { return n.boolValue }
        return fallback
    }

    private func intValue(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let i = Int(s) { return i }
        return 0
    }

    private func normalizedDisplayKey(_ value: String) -> String {
        switch value.uppercased() {
        case "LEFT": "←"
        case "RIGHT": "→"
        case "UP": "↑"
        case "DOWN": "↓"
        case "SPACE": "Space"
        default: value
        }
    }
}
