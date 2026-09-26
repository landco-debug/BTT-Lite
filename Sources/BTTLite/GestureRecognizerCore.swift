import Foundation

struct RawTouchContact: Equatable {
    var id: Int
    var x: Double
    var y: Double
    var size: Double
}

struct RecognizedGesture: Equatable {
    var device: GestureDevice
    var fingers: Int
    var kind: GestureKind
    var direction: GestureDirection?
}

/// Stateful, allocation-light recognizer for the gesture vocabulary BTT Lite exposes.
/// It is intentionally independent of AppKit/private APIs so it can be unit tested.
final class GestureRecognizerCore {
    struct Thresholds {
        var swipeDistance: Double = 0.070
        var swipeDominance: Double = 1.15
        var maximumSwipeDuration: TimeInterval = 1.20
        var tapMovement: Double = 0.060
        var maximumTapDuration: TimeInterval = 0.40
        var doubleTapInterval: TimeInterval = 0.55
    }

    private struct TapMemory {
        var uptime: TimeInterval
        var fingers: Int
    }

    private struct DeviceState {
        var active = false
        var startUptime: TimeInterval = 0
        var startX: Double = 0
        var startY: Double = 0
        var lastX: Double = 0
        var lastY: Double = 0
        var maxFingerCount = 0
        var maxDistance: Double = 0
        var didEmitSwipe = false
        var lastTap: TapMemory?
    }

    var thresholds = Thresholds()
    private var states: [UInt: DeviceState] = [:]

    func reset() {
        states.removeAll(keepingCapacity: true)
    }

    func processFrame(
        deviceID: UInt,
        device: GestureDevice,
        contacts: [RawTouchContact],
        uptime: TimeInterval
    ) -> [RecognizedGesture] {
        var state = states[deviceID] ?? DeviceState()
        defer { states[deviceID] = state }

        guard !contacts.isEmpty else {
            guard state.active else { return [] }
            let duration = max(0, uptime - state.startUptime)
            let dx = state.lastX - state.startX
            let dy = state.lastY - state.startY
            let absX = abs(dx)
            let absY = abs(dy)
            let fingers = max(1, state.maxFingerCount)

            state.active = false
            state.maxFingerCount = 0
            state.maxDistance = 0

            if state.didEmitSwipe {
                state.didEmitSwipe = false
                return []
            }
            state.didEmitSwipe = false

            if duration <= thresholds.maximumSwipeDuration,
               max(absX, absY) >= thresholds.swipeDistance {
                let direction: GestureDirection?
                if absX >= absY * thresholds.swipeDominance {
                    direction = dx < 0 ? .left : .right
                } else if absY >= absX * thresholds.swipeDominance {
                    // MultitouchSupport's normalized Y grows away from the user.
                    direction = dy < 0 ? .down : .up
                } else {
                    direction = nil
                }
                if let direction {
                    state.lastTap = nil
                    return [RecognizedGesture(device: device, fingers: fingers, kind: .swipe, direction: direction)]
                }
            }

            if duration <= thresholds.maximumTapDuration,
               state.maxDistance <= thresholds.tapMovement {
                if let previous = state.lastTap,
                   previous.fingers == fingers,
                   uptime - previous.uptime <= thresholds.doubleTapInterval {
                    state.lastTap = nil
                    return [RecognizedGesture(device: device, fingers: fingers, kind: .doubleTap, direction: nil)]
                }
                state.lastTap = TapMemory(uptime: uptime, fingers: fingers)
            } else {
                state.lastTap = nil
            }
            return []
        }

        let centroid = Self.centroid(contacts)
        if !state.active {
            state.active = true
            state.startUptime = uptime
            state.startX = centroid.x
            state.startY = centroid.y
            state.lastX = centroid.x
            state.lastY = centroid.y
            state.maxFingerCount = contacts.count
            state.maxDistance = 0
            state.didEmitSwipe = false
            return []
        }

        state.lastX = centroid.x
        state.lastY = centroid.y
        state.maxFingerCount = max(state.maxFingerCount, contacts.count)
        let dx = centroid.x - state.startX
        let dy = centroid.y - state.startY
        state.maxDistance = max(state.maxDistance, hypot(dx, dy))

        // Emit a swipe as soon as it is unambiguous instead of waiting for every
        // finger to leave the surface. Magic Mouse can keep a lingering contact
        // alive after the visible swipe, which previously made the action appear dead.
        let duration = max(0, uptime - state.startUptime)
        if !state.didEmitSwipe,
           duration <= thresholds.maximumSwipeDuration,
           max(abs(dx), abs(dy)) >= thresholds.swipeDistance {
            let direction: GestureDirection?
            if abs(dx) >= abs(dy) * thresholds.swipeDominance {
                direction = dx < 0 ? .left : .right
            } else if abs(dy) >= abs(dx) * thresholds.swipeDominance {
                direction = dy < 0 ? .down : .up
            } else {
                direction = nil
            }
            if let direction {
                state.didEmitSwipe = true
                state.lastTap = nil
                return [RecognizedGesture(
                    device: device,
                    fingers: max(1, state.maxFingerCount),
                    kind: .swipe,
                    direction: direction
                )]
            }
        }
        return []
    }

    private static func centroid(_ contacts: [RawTouchContact]) -> (x: Double, y: Double) {
        var x = 0.0
        var y = 0.0
        for contact in contacts {
            x += contact.x
            y += contact.y
        }
        let divisor = Double(max(1, contacts.count))
        return (x / divisor, y / divisor)
    }
}
