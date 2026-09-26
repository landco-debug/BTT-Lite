import ApplicationServices
import Foundation

/// Small state machine for Apple's special Fn/Globe modifier.
///
/// Fn is not treated like Command/Shift by macOS shortcut registration. We follow
/// the actual flagsChanged stream and use maskSecondaryFn on the event that matters.
/// Crucially, release events overwrite the state instead of OR-ing it with old/HID
/// state, which prevents a released Fn key from becoming "sticky".
struct KeyboardModifierState {
    private(set) var fnIsDown = false
    private(set) var modifierSides: ModifierSideSet = []

    mutating func reset() {
        fnIsDown = false
        modifierSides = []
    }

    mutating func observeFlagsChanged(keyCode: Int64, eventFlags: CGEventFlags) {
        // Device-dependent NX bits are the canonical left/right modifier identity
        // and are the same low bits BetterTouchTool stores in its advanced mask.
        modifierSides = ModifierSideSet(rawValue: UInt64(eventFlags.rawValue)).intersection(.all)

        if eventFlags.contains(.maskSecondaryFn) {
            fnIsDown = true
            return
        }

        // kVK_Function / Globe is virtual key 63. Some Apple keyboard paths report
        // -1 for this transition, so accept that only for the release edge.
        if keyCode == 63 || keyCode == -1 {
            fnIsDown = false
        }
    }

    func effectiveModifiers(eventFlags: CGEventFlags) -> ModifierSet {
        var result = ModifierSet(rawValue: UInt64(eventFlags.rawValue))
            .intersection(.userRelevant)

        if fnIsDown || eventFlags.contains(.maskSecondaryFn) {
            result.insert(.function)
        } else {
            result.remove(.function)
        }
        return result
    }

    func effectiveModifierSides(eventFlags: CGEventFlags) -> ModifierSideSet {
        let eventSides = ModifierSideSet(rawValue: UInt64(eventFlags.rawValue)).intersection(.all)
        return eventSides.union(modifierSides)
    }
}
