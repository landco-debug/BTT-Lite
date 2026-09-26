import ApplicationServices
import Foundation

@main
struct InputSemanticsRegression {
    static func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAILED: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        testFnPressReleaseIsNotSticky()
        testEventFnBitWorksWithoutPriorTransition()
        testLeftRightModifierTracking()
        testModifierSideMaskMatchesNXLayout()
        testMissionControlSymbolicHotKeyParsing()
        print("InputSemanticsRegression: OK")
    }

    static func testFnPressReleaseIsNotSticky() {
        var state = KeyboardModifierState()

        state.observeFlagsChanged(keyCode: 63, eventFlags: [.maskSecondaryFn])
        assert(state.effectiveModifiers(eventFlags: []).contains(.function),
               "Fn press was not remembered for the following number key")

        state.observeFlagsChanged(keyCode: 63, eventFlags: [])
        assert(!state.effectiveModifiers(eventFlags: []).contains(.function),
               "Fn release remained sticky and would hijack a later plain digit")
    }

    static func testEventFnBitWorksWithoutPriorTransition() {
        let state = KeyboardModifierState()
        assert(state.effectiveModifiers(eventFlags: [.maskSecondaryFn]).contains(.function),
               "Fn bit on the key event itself must be accepted")
    }

    static func testLeftRightModifierTracking() {
        var state = KeyboardModifierState()
        let leftCommandFlags = CGEventFlags(rawValue: ModifierSet.command.rawValue | ModifierSideSet.leftCommand.rawValue)
        state.observeFlagsChanged(keyCode: 55, eventFlags: leftCommandFlags)
        assert(state.effectiveModifierSides(eventFlags: []).contains(.leftCommand),
               "left Command side was not tracked")
        assert(!state.effectiveModifierSides(eventFlags: []).contains(.rightCommand),
               "left Command was confused with right Command")

        let rightCommandFlags = CGEventFlags(rawValue: ModifierSet.command.rawValue | ModifierSideSet.rightCommand.rawValue)
        state.observeFlagsChanged(keyCode: 54, eventFlags: rightCommandFlags)
        assert(state.effectiveModifierSides(eventFlags: []).contains(.rightCommand),
               "right Command side was not tracked")
        assert(!state.effectiveModifierSides(eventFlags: []).contains(.leftCommand),
               "right Command was confused with left Command")

        state.observeFlagsChanged(keyCode: 54, eventFlags: [])
        assert(state.effectiveModifierSides(eventFlags: []).isEmpty,
               "modifier side remained stuck after release")
    }

    static func testModifierSideMaskMatchesNXLayout() {
        assert(ModifierSideSet.leftControl.rawValue == 0x0001, "left Control NX mask changed")
        assert(ModifierSideSet.leftShift.rawValue == 0x0002, "left Shift NX mask changed")
        assert(ModifierSideSet.rightShift.rawValue == 0x0004, "right Shift NX mask changed")
        assert(ModifierSideSet.leftCommand.rawValue == 0x0008, "left Command NX mask changed")
        assert(ModifierSideSet.rightCommand.rawValue == 0x0010, "right Command NX mask changed")
        assert(ModifierSideSet.leftOption.rawValue == 0x0020, "left Option NX mask changed")
        assert(ModifierSideSet.rightOption.rawValue == 0x0040, "right Option NX mask changed")
        assert(ModifierSideSet.rightControl.rawValue == 0x2000, "right Control NX mask changed")
    }

    static func testMissionControlSymbolicHotKeyParsing() {
        let hotKeys: [String: Any] = [
            "79": [
                "enabled": true,
                "value": [
                    "parameters": [65535, 123, 8650752],
                    "type": "standard"
                ]
            ],
            "81": [
                "enabled": true,
                "value": [
                    "parameters": [65535, 124, 8650752],
                    "type": "standard"
                ]
            ]
        ]

        guard let left = SystemSymbolicHotKeyResolver.parse(id: 79, hotKeys: hotKeys),
              let right = SystemSymbolicHotKeyResolver.parse(id: 81, hotKeys: hotKeys) else {
            assert(false, "Mission Control symbolic shortcuts were not parsed")
            return
        }

        assert(left.keyCode == 123, "Move Left a Space key code changed")
        assert(right.keyCode == 124, "Move Right a Space key code changed")
        assert(left.modifiers.contains(.control) && left.modifiers.contains(.function),
               "modern Control+Left symbolic shortcut must preserve Control and Fn")
        assert(right.modifiers.contains(.control) && right.modifiers.contains(.function),
               "modern Control+Right symbolic shortcut must preserve Control and Fn")
    }
}
