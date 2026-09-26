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
