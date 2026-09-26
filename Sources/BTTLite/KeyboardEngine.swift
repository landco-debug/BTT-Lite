import AppKit
import ApplicationServices
import Foundation

@MainActor
final class KeyboardEngine {
    private static let systemDefinedEventType = CGEventType(rawValue: 14)!
    private static let fnKeyCode: CGKeyCode = 63 // kVK_Function / Globe

    private let store: ConfigStore
    private let runner: ActionRunner
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var suppressedKeyUps: Set<UInt16> = []
    private var modifierState = KeyboardModifierState()

    init(store: ConfigStore, runner: ActionRunner) {
        self.store = store
        self.runner = runner
    }

    func start(promptForPermission: Bool) {
        stop()

        let trusted: Bool
        if promptForPermission {
            trusted = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
        } else {
            trusted = AXIsProcessTrusted()
        }
        guard trusted else {
            NSLog("BTT Lite: Accessibility permission is required for keyboard triggers")
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
                   CGEventMask(1 << CGEventType.keyUp.rawValue) |
                   CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
                   CGEventMask(1 << Self.systemDefinedEventType.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<KeyboardEngine>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated {
                    engine.modifierState.reset()
                    engine.suppressedKeyUps.removeAll(keepingCapacity: true)
                    if let tap = engine.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
                return Unmanaged.passUnretained(event)
            }

            if event.getIntegerValueField(.eventSourceUserData) == ActionRunner.syntheticEventTag {
                return Unmanaged.passUnretained(event)
            }

            let consumed = MainActor.assumeIsolated {
                engine.handle(type: type, event: event)
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }

        let info = Unmanaged.passUnretained(self).toOpaque()

        // BTT's Fn support is a custom shortcut path. A session tap gives us the
        // complete flagsChanged/key stream needed for that state machine and was also
        // the most reliable path for the user's Fn+number rules. HID is a fallback.
        let tap =
            CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: info
            ) ??
            CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: info
            )

        guard let tap else {
            NSLog("BTT Lite: could not create keyboard event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        suppressedKeyUps.removeAll(keepingCapacity: true)
        modifierState.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if frontmostBundleID == Bundle.main.bundleIdentifier { return false }

        if type == .flagsChanged {
            modifierState.observeFlagsChanged(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                eventFlags: event.flags
            )
            return false
        }

        if type == .keyUp {
            let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            if suppressedKeyUps.remove(keyCode) != nil { return true }
            return false
        }

        guard let profile = store.activeProfile() else { return false }

        let matching: [Rule]
        if type == .keyDown {
            let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))

            // Once this physical key press has been claimed, swallow every autorepeat
            // until its keyUp. Otherwise releasing Fn while still holding "4" can let
            // a repeat event escape into the active text field after the action fired.
            if suppressedKeyUps.contains(keyCode) {
                return true
            }

            let observedModifiers = modifierState.effectiveModifiers(eventFlags: event.flags)

            matching = profile.rules.filter { rule in
                guard rule.enabled,
                      scopeMatches(rule.scope, frontmostBundleID: frontmostBundleID),
                      case let .keyboard(trigger) = rule.trigger,
                      trigger.keyCode == keyCode,
                      trigger.triggerOnKeyDown else {
                    return false
                }
                return modifiersMatch(observed: observedModifiers, expected: trigger.modifiers)
            }
        } else if type == Self.systemDefinedEventType {
            guard let nsEvent = NSEvent(cgEvent: event) else { return false }
            let systemCode = Int((nsEvent.data1 & 0xFFFF0000) >> 16)
            matching = profile.rules.filter { rule in
                guard rule.enabled,
                      scopeMatches(rule.scope, frontmostBundleID: frontmostBundleID),
                      case let .systemKey(trigger) = rule.trigger else {
                    return false
                }
                return trigger.code == systemCode
            }
        } else {
            return false
        }

        guard !matching.isEmpty else { return false }

        for rule in matching { runner.execute(rule) }

        if type == .keyDown {
            let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            suppressedKeyUps.insert(keyCode)
        }
        return true
    }

    private func modifiersMatch(observed: ModifierSet, expected: ModifierSet) -> Bool {
        var normalized = observed
        // Caps Lock is a keyboard state, not normally part of a hotkey chord.
        // Do not let an enabled Caps Lock prevent an imported BTT shortcut from firing
        // unless the shortcut explicitly asked for Caps Lock.
        if !expected.contains(.capsLock) {
            normalized.remove(.capsLock)
        }
        return normalized == expected
    }

    private func scopeMatches(_ scope: RuleScope, frontmostBundleID: String?) -> Bool {
        switch scope {
        case .global:
            return true
        case let .application(_, bundleIdentifier):
            guard let frontmostBundleID else { return false }
            return frontmostBundleID == bundleIdentifier
        }
    }
}
