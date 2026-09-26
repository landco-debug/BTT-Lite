import Foundation

struct AppConfiguration: Codable, Equatable {
    var schemaVersion: Int = 1
    var activeProfileID: UUID
    var profiles: [Profile]

    static var empty: AppConfiguration {
        let profile = Profile(name: "Default", rules: [])
        return AppConfiguration(activeProfileID: profile.id, profiles: [profile])
    }

    var activeProfileIndex: Int? {
        profiles.firstIndex { $0.id == activeProfileID }
    }

    var activeProfile: Profile? {
        get { activeProfileIndex.map { profiles[$0] } }
        set {
            guard let newValue else { return }
            if let index = profiles.firstIndex(where: { $0.id == newValue.id }) {
                profiles[index] = newValue
            }
        }
    }
}

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var rules: [Rule]
}

struct Rule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var enabled: Bool = true
    var scope: RuleScope = .global
    var trigger: Trigger
    var actions: [RuleAction]
}

enum RuleScope: Codable, Equatable {
    case global
    case application(name: String, bundleIdentifier: String)

    private enum CodingKeys: String, CodingKey { case type, name, bundleIdentifier }
    private enum Kind: String, Codable { case global, application }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .global:
            self = .global
        case .application:
            self = .application(
                name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Application",
                bundleIdentifier: try c.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global:
            try c.encode(Kind.global, forKey: .type)
        case let .application(name, bundleIdentifier):
            try c.encode(Kind.application, forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encode(bundleIdentifier, forKey: .bundleIdentifier)
        }
    }
}

enum Trigger: Codable, Equatable {
    case keyboard(KeyboardTrigger)
    case gesture(GestureTrigger)
    case systemKey(SystemKeyTrigger)
    case unsupported(description: String, rawType: Int?)

    private enum CodingKeys: String, CodingKey { case type, keyboard, gesture, systemKey, description, rawType }
    private enum Kind: String, Codable { case keyboard, gesture, systemKey, unsupported }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .keyboard: self = .keyboard(try c.decode(KeyboardTrigger.self, forKey: .keyboard))
        case .gesture: self = .gesture(try c.decode(GestureTrigger.self, forKey: .gesture))
        case .systemKey: self = .systemKey(try c.decode(SystemKeyTrigger.self, forKey: .systemKey))
        case .unsupported:
            self = .unsupported(
                description: try c.decodeIfPresent(String.self, forKey: .description) ?? "Unsupported trigger",
                rawType: try c.decodeIfPresent(Int.self, forKey: .rawType)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .keyboard(value):
            try c.encode(Kind.keyboard, forKey: .type)
            try c.encode(value, forKey: .keyboard)
        case let .gesture(value):
            try c.encode(Kind.gesture, forKey: .type)
            try c.encode(value, forKey: .gesture)
        case let .systemKey(value):
            try c.encode(Kind.systemKey, forKey: .type)
            try c.encode(value, forKey: .systemKey)
        case let .unsupported(description, rawType):
            try c.encode(Kind.unsupported, forKey: .type)
            try c.encode(description, forKey: .description)
            try c.encodeIfPresent(rawType, forKey: .rawType)
        }
    }
}

struct KeyboardTrigger: Codable, Equatable {
    var keyCode: UInt16
    var displayKey: String
    var modifiers: ModifierSet
    var triggerOnKeyDown: Bool = true
    /// Optional for backward-compatible decoding of C00-C13 config.json.
    var modifierSides: ModifierSideSet? = nil
    var differentiateModifierSides: Bool? = nil
}

struct SystemKeyTrigger: Codable, Equatable {
    var code: Int
    var displayName: String
}

struct ModifierSet: Codable, OptionSet, Hashable {
    let rawValue: UInt64

    static let capsLock = ModifierSet(rawValue: 1 << 16)
    static let shift = ModifierSet(rawValue: 1 << 17)
    static let control = ModifierSet(rawValue: 1 << 18)
    static let option = ModifierSet(rawValue: 1 << 19)
    static let command = ModifierSet(rawValue: 1 << 20)
    static let numericPad = ModifierSet(rawValue: 1 << 21)
    static let help = ModifierSet(rawValue: 1 << 22)
    static let function = ModifierSet(rawValue: 1 << 23)

    static let userRelevant: ModifierSet = [.capsLock, .shift, .control, .option, .command, .function]
}

/// Device-dependent modifier bits used by macOS/NXEvent and by BTT's
/// BTTShortcutAdvancedModifierKeys when left/right differentiation is enabled.
struct ModifierSideSet: Codable, OptionSet, Hashable {
    let rawValue: UInt64

    static let leftControl  = ModifierSideSet(rawValue: 0x00000001)
    static let leftShift    = ModifierSideSet(rawValue: 0x00000002)
    static let rightShift   = ModifierSideSet(rawValue: 0x00000004)
    static let leftCommand  = ModifierSideSet(rawValue: 0x00000008)
    static let rightCommand = ModifierSideSet(rawValue: 0x00000010)
    static let leftOption   = ModifierSideSet(rawValue: 0x00000020)
    static let rightOption  = ModifierSideSet(rawValue: 0x00000040)
    static let rightControl = ModifierSideSet(rawValue: 0x00002000)

    static let all: ModifierSideSet = [
        .leftControl, .rightControl,
        .leftShift, .rightShift,
        .leftOption, .rightOption,
        .leftCommand, .rightCommand
    ]
}

struct GestureTrigger: Codable, Equatable {
    var device: GestureDevice
    var fingers: Int
    var gesture: GestureKind
    var direction: GestureDirection?
    /// Required modifiers. nil/empty means no modifier guard.
    var modifiers: ModifierSet? = nil
    var modifierSides: ModifierSideSet? = nil
    var differentiateModifierSides: Bool? = nil
}

enum GestureDevice: String, Codable, CaseIterable { case magicMouse, trackpad }
enum GestureKind: String, Codable, CaseIterable { case swipe, click, doubleTap }
enum GestureDirection: String, Codable, CaseIterable { case left, right, up, down }

enum ActionKind: String, Codable, CaseIterable {
    case sendShortcut
    case runShortcut
    case launchPath
    case openURL
    case terminalCommand
    case shellScript
    case appleScript
    case javascriptTransform
    case waitForClipboardChange
    case moveSpaceLeft
    case moveSpaceRight
    case pageBack
    case pageForward
    case launchpad
    case toggleBluetoothDevice
    case activateHoveredDockApp
    case clipboardHistory
    case builtIn
    case unsupported

    var displayName: String {
        switch self {
        case .sendShortcut: "Send Keyboard Shortcut"
        case .runShortcut: "Run Apple Shortcut"
        case .launchPath: "Launch Application / Open File"
        case .openURL: "Open URL"
        case .terminalCommand: "Run Terminal Command"
        case .shellScript: "Run Shell Script"
        case .appleScript: "Run AppleScript"
        case .javascriptTransform: "Transform Selection with JavaScript"
        case .waitForClipboardChange: "Wait for Clipboard Change"
        case .moveSpaceLeft: "Move Left a Space"
        case .moveSpaceRight: "Move Right a Space"
        case .pageBack: "Page Back"
        case .pageForward: "Page Forward"
        case .launchpad: "Open Launchpad"
        case .toggleBluetoothDevice: "Toggle Bluetooth Device"
        case .activateHoveredDockApp: "Activate Hovered Dock App"
        case .clipboardHistory: "Clipboard History"
        case .builtIn: "Built-in Action"
        case .unsupported: "Unsupported / Preserved Action"
        }
    }
}

struct RuleAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var enabled: Bool = true
    var kind: ActionKind
    var title: String
    var parameters: [String: String] = [:]
    var sourceMetadata: [String: String] = [:]
}


extension RuleAction {
    /// Concise BTT-style summary used by the trigger browser.
    /// Prefer the concrete target (Shortcut/device/key) over a generic imported action title.
    var displaySummary: String {
        switch kind {
        case .sendShortcut:
            let keyCode = UInt16(parameters["keyCode"] ?? "") ?? 0
            let key = parameters["displayKey"].flatMap { $0.isEmpty ? nil : $0 } ?? "Key " + String(keyCode)
            let modifiers = ModifierSet(rawValue: UInt64(parameters["modifiers"] ?? "") ?? 0)
            let sides = ModifierSideSet(rawValue: UInt64(parameters["modifierSides"] ?? "") ?? 0)
            let prefix = sides.isEmpty ? modifiers.symbols : sides.symbols(generic: modifiers)
            return "Send Keyboard Shortcut: " + prefix + key
        case .runShortcut:
            return titled("Run Shortcut", value: parameters["name"])
        case .launchPath:
            if let path = parameters["path"], !path.isEmpty {
                return "Launch: " + URL(fileURLWithPath: path).lastPathComponent
            }
            return title
        case .openURL:
            return titled("Open URL", value: parameters["url"])
        case .toggleBluetoothDevice:
            return titled("Toggle Bluetooth Device Connection", value: parameters["deviceName"])
        case .builtIn:
            if let name = parameters["name"], !name.isEmpty { return name }
            return title
        default:
            return title.isEmpty ? kind.displayName : title
        }
    }

    private func titled(_ fallback: String, value: String?) -> String {
        guard let value, !value.isEmpty else { return title.isEmpty ? fallback : title }
        return fallback + ": " + value
    }
}

extension Trigger {
    var compactDisplayName: String {
        switch self {
        case let .keyboard(k):
            let prefix = k.differentiateModifierSides == true
                ? (k.modifierSides ?? []).symbols(generic: k.modifiers)
                : k.modifiers.symbols
            return prefix + k.displayKey
        case let .gesture(g):
            let generic = g.modifiers ?? []
            let modifierPrefix = g.differentiateModifierSides == true
                ? (g.modifierSides ?? []).symbols(generic: generic)
                : generic.symbols
            let base = "\(modifierPrefix)\(g.fingers) Finger \(g.gesture.displayName)"
            if let direction = g.direction { return "\(base) \(direction.rawValue.capitalized)" }
            return base
        case let .systemKey(k):
            return k.displayName
        case let .unsupported(description, _):
            return description
        }
    }

    var displayName: String {
        switch self {
        case let .keyboard(k):
            let prefix = k.differentiateModifierSides == true
                ? (k.modifierSides ?? []).symbols(generic: k.modifiers)
                : k.modifiers.symbols
            return prefix + k.displayKey
        case let .gesture(g):
            let device = g.device == .magicMouse ? "Magic Mouse" : "Trackpad"
            let generic = g.modifiers ?? []
            let modifierPrefix = g.differentiateModifierSides == true
                ? (g.modifierSides ?? []).symbols(generic: generic)
                : generic.symbols
            let base = "\(modifierPrefix)\(g.fingers) Finger \(g.gesture.displayName)"
            if let direction = g.direction { return "\(device): \(base) \(direction.rawValue.capitalized)" }
            return "\(device): \(base)"
        case let .systemKey(k):
            return "System Key: \(k.displayName)"
        case let .unsupported(description, _):
            return description
        }
    }

    var category: RuleCategory {
        switch self {
        case .keyboard, .systemKey: .keyboard
        case let .gesture(g): g.device == .magicMouse ? .magicMouse : .trackpad
        case .unsupported: .other
        }
    }
}

extension ModifierSet {
    var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        if contains(.function) { s += "fn " }
        if contains(.capsLock) { s += "⇪" }
        return s
    }
}

extension ModifierSideSet {
    func symbols(generic: ModifierSet) -> String {
        var s = ""
        func appendPair(_ left: ModifierSideSet, _ right: ModifierSideSet, symbol: String) {
            if contains(left) { s += "L" + symbol }
            if contains(right) { s += "R" + symbol }
        }
        appendPair(.leftControl, .rightControl, symbol: "⌃")
        appendPair(.leftOption, .rightOption, symbol: "⌥")
        appendPair(.leftShift, .rightShift, symbol: "⇧")
        appendPair(.leftCommand, .rightCommand, symbol: "⌘")
        if generic.contains(.function) { s += "fn " }
        if generic.contains(.capsLock) { s += "⇪" }
        return s
    }
}

extension GestureKind {
    var displayName: String {
        switch self {
        case .swipe: "Swipe"
        case .click: "Click"
        case .doubleTap: "Double-Tap"
        }
    }
}

enum RuleCategory: String, CaseIterable {
    case all = "All Triggers"
    case global = "Global"
    case keyboard = "Keyboard"
    case magicMouse = "Magic Mouse"
    case trackpad = "Trackpad"
    case applications = "Applications"
    case other = "Other"
}
