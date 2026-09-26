import AppKit
import ApplicationServices
import Foundation

private final class GestureProcessingState {
    struct Snapshot {
        var device: GestureDevice
        var fingerCount: Int
        var uptime: TimeInterval
        var fingerCountSince: TimeInterval
    }

    private let lock = NSLock()
    private let recognizer = GestureRecognizerCore()
    private var liveStates: [UInt: Snapshot] = [:]

    func reset() {
        lock.lock()
        liveStates.removeAll(keepingCapacity: true)
        recognizer.reset()
        lock.unlock()
    }

    func process(device: MultitouchBridge.Device, contacts: [RawTouchContact], uptime: TimeInterval) -> [RecognizedGesture] {
        lock.lock()
        defer { lock.unlock() }
        let prior = liveStates[device.id]
        let countSince = prior?.fingerCount == contacts.count
            ? (prior?.fingerCountSince ?? uptime)
            : uptime
        liveStates[device.id] = Snapshot(
            device: device.kind,
            fingerCount: contacts.count,
            uptime: uptime,
            fingerCountSince: countSince
        )
        return recognizer.processFrame(
            deviceID: device.id,
            device: device.kind,
            contacts: contacts,
            uptime: uptime
        )
    }

    func mostRecentActive(
        maxAge: TimeInterval,
        minimumStableDuration: TimeInterval,
        now: TimeInterval
    ) -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        return liveStates.values
            .filter {
                $0.fingerCount > 0 &&
                now - $0.uptime <= maxAge &&
                now - $0.fingerCountSince >= minimumStableDuration
            }
            .max { $0.uptime < $1.uptime }
    }
}

@MainActor
final class GestureEngine {
    private let store: ConfigStore
    private let runner: ActionRunner
    private let bridge = MultitouchBridge()
    private let processor = GestureProcessingState()
    private var clickEventTap: CFMachPort?
    private var clickRunLoopSource: CFRunLoopSource?
    private var suppressNextMouseUp = false

    init(store: ConfigStore, runner: ActionRunner) {
        self.store = store
        self.runner = runner
    }

    func start() {
        stop()
        guard hasEnabledGestureRules else { return }

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        if hasEnabledClickRules && !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
        }

        processor.reset()
        let processor = self.processor
        let started = bridge.start { [weak self] device, contacts, uptime in
            let recognized = processor.process(device: device, contacts: contacts, uptime: uptime)
            guard !recognized.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for gesture in recognized { self.dispatch(gesture) }
            }
        }
        if !started {
            NSLog("BTT Lite: MultitouchSupport is unavailable or no multitouch devices were found")
        }
        if hasEnabledClickRules { installClickTap() }
    }

    func stop() {
        bridge.stop()
        processor.reset()
        suppressNextMouseUp = false

        if let tap = clickEventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = clickRunLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        clickRunLoopSource = nil
        clickEventTap = nil
    }

    private var hasEnabledGestureRules: Bool {
        guard let profile = store.activeProfile() else { return false }
        return profile.rules.contains { rule in
            guard rule.enabled else { return false }
            if case .gesture = rule.trigger { return true }
            return false
        }
    }

    private var hasEnabledClickRules: Bool {
        guard let profile = store.activeProfile() else { return false }
        return profile.rules.contains { rule in
            guard rule.enabled, case let .gesture(trigger) = rule.trigger else { return false }
            return trigger.gesture == .click
        }
    }

    private func installClickTap() {
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
                   CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<GestureEngine>.fromOpaque(userInfo).takeUnretainedValue()
            let suppress = MainActor.assumeIsolated { engine.handleClickEvent(type: type) }
            return suppress ? nil : Unmanaged.passUnretained(event)
        }
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: info
        ) else {
            NSLog("BTT Lite: could not create physical-click event tap")
            return
        }
        clickEventTap = tap
        clickRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = clickRunLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleClickEvent(type: CGEventType) -> Bool {
        if type == .leftMouseUp, suppressNextMouseUp {
            suppressNextMouseUp = false
            return true
        }
        guard type == .leftMouseDown else { return false }
        guard let live = processor.mostRecentActive(
            maxAge: 0.20,
            minimumStableDuration: 0.055,
            now: ProcessInfo.processInfo.systemUptime
        ), live.fingerCount > 0 else { return false }

        let gesture = RecognizedGesture(device: live.device, fingers: live.fingerCount, kind: .click, direction: nil)
        let matched = matchingRules(for: gesture)
        guard !matched.isEmpty else { return false }
        for rule in matched { runner.execute(rule) }
        suppressNextMouseUp = true
        return true
    }

    private func dispatch(_ gesture: RecognizedGesture) {
        for rule in matchingRules(for: gesture) { runner.execute(rule) }
    }

    private func matchingRules(for gesture: RecognizedGesture) -> [Rule] {
        guard let profile = store.activeProfile() else { return [] }
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return profile.rules.filter { rule in
            guard rule.enabled, scopeMatches(rule.scope, frontmostBundleID: frontmostBundleID) else { return false }
            guard case let .gesture(trigger) = rule.trigger else { return false }
            guard trigger.device == gesture.device &&
                  trigger.fingers == gesture.fingers &&
                  trigger.gesture == gesture.kind &&
                  trigger.direction == gesture.direction else {
                return false
            }
            return gestureModifiersMatch(trigger)
        }
    }

    private func gestureModifiersMatch(_ trigger: GestureTrigger) -> Bool {
        let required = trigger.modifiers ?? []
        guard !required.isEmpty else { return true }

        let sessionFlags = CGEventSource.flagsState(.combinedSessionState)
        let hidFlags = CGEventSource.flagsState(.hidSystemState)
        let raw = sessionFlags.rawValue | hidFlags.rawValue
        let observed = ModifierSet(rawValue: UInt64(raw)).intersection(.userRelevant)

        // Gesture modifiers are a guard: the requested modifiers must be down.
        // Extra modifiers do not disable the gesture, matching BTT's "required" semantics.
        guard observed.intersection(required) == required else { return false }

        if trigger.differentiateModifierSides == true {
            let observedSides = ModifierSideSet(rawValue: UInt64(raw)).intersection(.all)
            let expectedSides = trigger.modifierSides ?? []
            guard observedSides.intersection(expectedSides) == expectedSides else { return false }
        }
        return true
    }

    private func scopeMatches(_ scope: RuleScope, frontmostBundleID: String?) -> Bool {
        switch scope {
        case .global:
            return true
        case let .application(_, bundleIdentifier):
            return frontmostBundleID == bundleIdentifier
        }
    }
}
