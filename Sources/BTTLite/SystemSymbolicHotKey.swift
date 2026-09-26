import Foundation

struct SystemSymbolicHotKey {
    var keyCode: UInt16
    var modifiers: ModifierSet
}

/// Resolves the exact Mission Control shortcuts configured by macOS.
///
/// BetterTouchTool's normal "Move Left/Right a Space" action delegates to the
/// shortcuts configured in System Settings. Reading AppleSymbolicHotKeys keeps BTT
/// Lite aligned with the user's current shortcut instead of assuming Ctrl+Arrow.
enum SystemSymbolicHotKeyResolver {
    private static let domain = "com.apple.symbolichotkeys"
    private static let rootKey = "AppleSymbolicHotKeys"

    static func current(id: Int) -> SystemSymbolicHotKey? {
        let appID = domain as CFString
        CFPreferencesAppSynchronize(appID)
        guard let raw = CFPreferencesCopyAppValue(rootKey as CFString, appID),
              let hotKeys = raw as? [String: Any] else {
            return defaultShortcut(id: id)
        }
        return parse(id: id, hotKeys: hotKeys) ?? defaultShortcut(id: id)
    }

    private static func defaultShortcut(id: Int) -> SystemSymbolicHotKey? {
        switch id {
        case 79:
            return SystemSymbolicHotKey(keyCode: 123, modifiers: [.control, .function])
        case 81:
            return SystemSymbolicHotKey(keyCode: 124, modifiers: [.control, .function])
        default:
            return nil
        }
    }

    static func parse(id: Int, hotKeys: [String: Any]) -> SystemSymbolicHotKey? {
        guard let entry = hotKeys[String(id)] as? [String: Any],
              isEnabled(entry["enabled"]),
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any],
              parameters.count >= 3,
              let rawKeyCode = integer(parameters[1]),
              let rawModifiers = integer(parameters[2]),
              rawKeyCode >= 0,
              rawKeyCode <= Int(UInt16.max),
              rawModifiers >= 0 else {
            return nil
        }

        let supported: ModifierSet = [
            .capsLock, .shift, .control, .option, .command,
            .numericPad, .help, .function
        ]
        let modifiers = ModifierSet(rawValue: UInt64(rawModifiers)).intersection(supported)
        return SystemSymbolicHotKey(keyCode: UInt16(rawKeyCode), modifiers: modifiers)
    }

    private static func isEnabled(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? Int { return value != 0 }
        return false
    }

    private static func integer(_ value: Any) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
