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
///
/// Important invariants:
/// - finger placement is not movement: contact membership must settle before swipe tracking starts;
/// - an axis/direction is locked only after several confident frames;
/// - once locked, the gesture never changes axis during the same touch session;
/// - after a finger is lifted, no lower-finger swipe can start until every finger is off the surface;
/// - a touch session emits at most one swipe.
///
/// These rules intentionally prefer "no action" over the wrong destructive action.
final class GestureRecognizerCore {
    struct Thresholds {
        /// Normalized surface distance required before a Trackpad swipe fires.
        var swipeDistance: Double = 0.078
        /// Magic Mouse has a much smaller usable touch surface and much shorter
        /// practical finger travel than a trackpad. Keep its thresholds separate so
        /// improving mouse responsiveness cannot regress the stricter trackpad logic.
        var magicMouseSwipeDistance: Double = 0.040
        /// Movement needed before we even consider locking a direction.
        var axisLockDistance: Double = 0.036
        var magicMouseAxisLockDistance: Double = 0.018
        /// Dominant axis must beat the other axis by this factor to become a candidate.
        var axisLockDominance: Double = 1.45
        var magicMouseAxisLockDominance: Double = 1.25
        /// The same direction must remain dominant for multiple frames before it is locked.
        var axisConfirmationFrames: Int = 3
        var magicMouseAxisConfirmationFrames: Int = 2
        /// Final trigger requires stronger confidence than the initial axis lock.
        var swipeTriggerDominance: Double = 1.60
        var magicMouseSwipeTriggerDominance: Double = 1.30
        /// Give the intended number of fingers time to land before measuring motion.
        var fingerSettleDuration: TimeInterval = 0.075
        var magicMouseFingerSettleDuration: TimeInterval = 0.035
        /// Avoid treating contact-placement jitter as an ultra-fast swipe.
        var minimumSwipeDuration: TimeInterval = 0.035
        var magicMouseMinimumSwipeDuration: TimeInterval = 0.020
        /// Deliberate slow swipes should still work.
        var maximumSwipeDuration: TimeInterval = 1.75
        var tapMovement: Double = 0.045
        var maximumTapDuration: TimeInterval = 0.45
        var doubleTapInterval: TimeInterval = 0.55
    }

    private struct TapMemory {
        var uptime: TimeInterval
        var fingers: Int
    }

    private struct DeviceState {
        var active = false
        var sessionStartUptime: TimeInterval = 0

        var contactIDs: [Int] = []
        var currentFingerCount = 0
        var peakFingerCount = 0
        var lastMembershipChangeUptime: TimeInterval = 0

        var trackingReady = false
        var stableFingerCount = 0
        var trackingStartUptime: TimeInterval = 0
        var startX: Double = 0
        var startY: Double = 0
        var lastX: Double = 0
        var lastY: Double = 0
        var maxDistance: Double = 0

        var candidateDirection: GestureDirection?
        var candidateFrames = 0
        var lockedDirection: GestureDirection?

        var didEmitSwipe = false
        var swipeSuppressedUntilLift = false
        var tapEligible = true
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

        if contacts.isEmpty {
            return finishSession(device: device, uptime: uptime, state: &state)
        }

        let centroid = Self.centroid(contacts)
        let ids = contacts.map(\.id).sorted()

        if !state.active {
            state.active = true
            state.sessionStartUptime = uptime
            state.contactIDs = ids
            state.currentFingerCount = contacts.count
            state.peakFingerCount = contacts.count
            state.lastMembershipChangeUptime = uptime
            state.trackingReady = false
            state.stableFingerCount = 0
            state.startX = centroid.x
            state.startY = centroid.y
            state.lastX = centroid.x
            state.lastY = centroid.y
            state.maxDistance = 0
            state.candidateDirection = nil
            state.candidateFrames = 0
            state.lockedDirection = nil
            state.didEmitSwipe = false
            state.swipeSuppressedUntilLift = false
            state.tapEligible = true
            return []
        }

        let membershipChanged = ids != state.contactIDs
        if membershipChanged {
            let countDecreased = contacts.count < state.currentFingerCount
            let sameCountReplacement = contacts.count == state.currentFingerCount

            // Once fingers start lifting, never reinterpret the tail of an N-finger
            // gesture as an (N-1)-finger gesture. This is especially important when
            // 2F page navigation and 3F Space navigation coexist.
            if countDecreased {
                state.swipeSuppressedUntilLift = true
            }
            // Replacing one contact with another while keeping the same count is not a
            // clean tap/swipe; conservatively cancel the session's recognizers.
            if sameCountReplacement {
                if device == .magicMouse {
                    state.tapEligible = false
                } else {
                    state.swipeSuppressedUntilLift = true
                    state.tapEligible = false
                }
            }

            state.contactIDs = ids
            state.currentFingerCount = contacts.count
            state.peakFingerCount = max(state.peakFingerCount, contacts.count)
            state.lastMembershipChangeUptime = uptime
            state.trackingReady = false
            state.stableFingerCount = 0
            state.startX = centroid.x
            state.startY = centroid.y
            state.lastX = centroid.x
            state.lastY = centroid.y
            state.candidateDirection = nil
            state.candidateFrames = 0
            state.lockedDirection = nil
            return []
        }

        state.lastX = centroid.x
        state.lastY = centroid.y

        if !state.trackingReady {
            let settleDuration = device == .magicMouse
                ? thresholds.magicMouseFingerSettleDuration
                : thresholds.fingerSettleDuration
            guard uptime - state.lastMembershipChangeUptime >= settleDuration else {
                return []
            }

            // Start measuring only after contact membership has settled. The centroid
            // can jump dramatically while the second/third/fourth finger lands.
            state.trackingReady = true
            state.stableFingerCount = contacts.count
            state.trackingStartUptime = uptime
            state.startX = centroid.x
            state.startY = centroid.y
            state.maxDistance = 0
            state.candidateDirection = nil
            state.candidateFrames = 0
            state.lockedDirection = nil
            return []
        }

        let dx = centroid.x - state.startX
        let dy = centroid.y - state.startY
        let distance = hypot(dx, dy)
        state.maxDistance = max(state.maxDistance, distance)
        if state.maxDistance > thresholds.tapMovement {
            state.tapEligible = false
        }

        guard !state.didEmitSwipe,
              !state.swipeSuppressedUntilLift else {
            return []
        }

        let duration = max(0, uptime - state.trackingStartUptime)
        guard duration <= thresholds.maximumSwipeDuration else { return [] }

        let lockDistance = device == .magicMouse
            ? thresholds.magicMouseAxisLockDistance
            : thresholds.axisLockDistance
        let triggerDistance = device == .magicMouse
            ? thresholds.magicMouseSwipeDistance
            : thresholds.swipeDistance
        let lockDominance = device == .magicMouse
            ? thresholds.magicMouseAxisLockDominance
            : thresholds.axisLockDominance
        let confirmationFrames = device == .magicMouse
            ? thresholds.magicMouseAxisConfirmationFrames
            : thresholds.axisConfirmationFrames
        let triggerDominance = device == .magicMouse
            ? thresholds.magicMouseSwipeTriggerDominance
            : thresholds.swipeTriggerDominance
        let minimumDuration = device == .magicMouse
            ? thresholds.magicMouseMinimumSwipeDuration
            : thresholds.minimumSwipeDuration

        if state.lockedDirection == nil {
            if let candidate = Self.dominantDirection(
                dx: dx,
                dy: dy,
                minimumDistance: lockDistance,
                dominance: lockDominance
            ) {
                if candidate == state.candidateDirection {
                    state.candidateFrames += 1
                } else {
                    state.candidateDirection = candidate
                    state.candidateFrames = 1
                }

                if state.candidateFrames >= max(1, confirmationFrames) {
                    state.lockedDirection = candidate
                }
            } else {
                // Ambiguous/diagonal motion must build confidence again; it cannot
                // inherit a stale candidate from a previous few frames.
                state.candidateDirection = nil
                state.candidateFrames = 0
            }
        }

        guard duration >= minimumDuration,
              let locked = state.lockedDirection else {
            return []
        }

        let components = Self.components(for: locked, dx: dx, dy: dy)
        guard components.primary > 0,
              components.primary >= triggerDistance,
              components.primary >= components.orthogonal * triggerDominance else {
            return []
        }

        state.didEmitSwipe = true
        state.lastTap = nil
        return [RecognizedGesture(
            device: device,
            fingers: max(1, state.stableFingerCount),
            kind: .swipe,
            direction: locked
        )]
    }

    private func finishSession(
        device: GestureDevice,
        uptime: TimeInterval,
        state: inout DeviceState
    ) -> [RecognizedGesture] {
        guard state.active else { return [] }

        let duration = max(0, uptime - state.sessionStartUptime)
        let fingers = max(1, state.peakFingerCount)
        let emittedSwipe = state.didEmitSwipe
        let canBeTap = state.tapEligible &&
            !emittedSwipe &&
            duration <= thresholds.maximumTapDuration &&
            state.maxDistance <= thresholds.tapMovement

        state.active = false
        state.contactIDs = []
        state.currentFingerCount = 0
        state.peakFingerCount = 0
        state.trackingReady = false
        state.stableFingerCount = 0
        state.maxDistance = 0
        state.candidateDirection = nil
        state.candidateFrames = 0
        state.lockedDirection = nil
        state.didEmitSwipe = false
        state.swipeSuppressedUntilLift = false
        state.tapEligible = true

        if emittedSwipe {
            state.lastTap = nil
            return []
        }

        if canBeTap {
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

    private static func dominantDirection(
        dx: Double,
        dy: Double,
        minimumDistance: Double,
        dominance: Double
    ) -> GestureDirection? {
        let absX = abs(dx)
        let absY = abs(dy)
        guard max(absX, absY) >= minimumDistance else { return nil }

        if absX >= absY * dominance {
            return dx < 0 ? .left : .right
        }
        if absY >= absX * dominance {
            // MultitouchSupport's normalized Y grows away from the user.
            return dy < 0 ? .down : .up
        }
        return nil
    }

    private static func components(
        for direction: GestureDirection,
        dx: Double,
        dy: Double
    ) -> (primary: Double, orthogonal: Double) {
        switch direction {
        case .left:
            return (-dx, abs(dy))
        case .right:
            return (dx, abs(dy))
        case .up:
            return (dy, abs(dx))
        case .down:
            return (-dy, abs(dx))
        }
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
