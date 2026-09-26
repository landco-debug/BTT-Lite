import Foundation

@main
struct BTTImporterRegression {
    static func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAILED: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() throws {
        let preset: [String: Any] = [
            "BTTPresetName": "Modifier Regression",
            "BTTPresetContent": [[
                "BTTAppName": "Global",
                "BTTAppBundleIdentifier": "BT.G",
                "BTTTriggers": [
                    [
                        "BTTTriggerClass": "BTTTriggerTypeKeyboardShortcut",
                        "BTTShortcutKeyCode": 37,
                        "BTTLayoutIndependentChar": "l",
                        "BTTShortcutModifierKeys": 1048576,
                        "BTTShortcutAdvancedModifierKeys": "1048592",
                        "BTTTriggerOnDown": 1,
                        "BTTTriggerConfig": ["BTTLeftRightModifierDifferentiation": 1],
                        "BTTActionsToExecute": [[
                            "BTTShortcutToSend": "54,37",
                            "BTTLayoutIndependentActionChar": "l"
                        ]]
                    ],
                    [
                        "BTTTriggerClass": "BTTTriggerTypeKeyboardShortcut",
                        "BTTShortcutKeyCode": 12,
                        "BTTLayoutIndependentChar": "q",
                        "BTTShortcutModifierKeys": 1048576,
                        "BTTShortcutAdvancedModifierKeys": "1048584",
                        "BTTTriggerOnDown": 1,
                        "BTTTriggerConfig": ["BTTLeftRightModifierDifferentiation": 1],
                        "BTTActionsToExecute": []
                    ],
                    [
                        "BTTTriggerClass": "BTTTriggerTypeMagicMouse",
                        "BTTTriggerTypeDescriptionReadOnly": "2 Finger Swipe Up",
                        "BTTRequiredModifierKeys": 524288,
                        "BTTAdditionalConfiguration": "524320",
                        "BTTTriggerConfig": ["BTTLeftRightModifierDifferentiation": 1],
                        "BTTActionsToExecute": []
                    ]
                ]
            ]]
        ]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("btt-lite-modifier-regression.bttpreset")
        let data = try JSONSerialization.data(withJSONObject: preset, options: [.prettyPrinted])
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let profile = try BTTImporter().importPreset(from: url)
        assert(profile.rules.count == 3, "expected three imported rules")

        guard case let .keyboard(rightCommand) = profile.rules[0].trigger else {
            assert(false, "right Command trigger not imported as keyboard")
            return
        }
        assert(rightCommand.differentiateModifierSides == true, "right Command differentiation flag lost")
        assert(rightCommand.modifierSides?.contains(.rightCommand) == true, "right Command side lost")
        assert(rightCommand.modifierSides?.contains(.leftCommand) != true, "right Command became left Command")

        guard let action = profile.rules[0].actions.first else {
            assert(false, "shortcut action missing")
            return
        }
        let actionSides = ModifierSideSet(rawValue: UInt64(action.parameters["modifierSides"] ?? "") ?? 0)
        assert(actionSides.contains(.rightCommand), "right Command action side lost")

        guard case let .keyboard(leftCommand) = profile.rules[1].trigger else {
            assert(false, "left Command trigger not imported as keyboard")
            return
        }
        assert(leftCommand.modifierSides?.contains(.leftCommand) == true, "left Command side lost")
        assert(leftCommand.modifierSides?.contains(.rightCommand) != true, "left Command became right Command")

        guard case let .gesture(mouseGesture) = profile.rules[2].trigger else {
            assert(false, "modifier-guarded Magic Mouse gesture was not imported")
            return
        }
        assert(mouseGesture.fingers == 2 && mouseGesture.direction == .up, "Magic Mouse gesture geometry changed")
        assert(mouseGesture.modifiers?.contains(.option) == true, "gesture Option guard lost")
        assert(mouseGesture.modifierSides?.contains(.leftOption) == true, "gesture left Option side lost")

        let runShortcut = RuleAction(
            kind: .runShortcut,
            title: "Run Shortcut from Shortcuts App",
            parameters: ["name": "Imgur"]
        )
        assert(runShortcut.displaySummary == "Run Shortcut: Imgur", "Shortcut target missing from browser summary")

        let bluetooth = RuleAction(
            kind: .toggleBluetoothDevice,
            title: "Toggle Bluetooth Device Connection",
            parameters: ["deviceName": "Win"]
        )
        assert(bluetooth.displaySummary == "Toggle Bluetooth Device Connection: Win", "Bluetooth device missing from browser summary")

        print("BTTImporterRegression: OK")
    }
}
