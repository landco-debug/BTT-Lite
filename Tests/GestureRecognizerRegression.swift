import Foundation

@main
struct GestureRecognizerRegression {
    static func main() {
        testSequentialFingerLandingDoesNotBecomeTwoFingerSwipe()
        testAllFourCardinalDirections()
        testDiagonalMotionDoesNotTrigger()
        testAxisLocksAndCannotFlipMidGesture()
        testFingerDropDoesNotBecomeLowerFingerSwipe()
        testSlowDeliberateSwipeStillTriggers()
        testThreeFingerDoubleTapSurvivesSequentialLanding()
        testMagicMouseFastHorizontalSwipesBothDirections()
        testMagicMouseRecoversFromSameCountIdentityReplacement()
        print("GestureRecognizerRegression: OK")
    }

    static func contacts(
        _ count: Int,
        centerX: Double = 0.50,
        centerY: Double = 0.50
    ) -> [RawTouchContact] {
        let spacing = 0.035
        let offset = Double(count - 1) * spacing / 2
        return (0..<count).map { index in
            RawTouchContact(
                id: index + 1,
                x: centerX + Double(index) * spacing - offset,
                y: centerY,
                size: 1
            )
        }
    }

    static func shifted(_ contacts: [RawTouchContact], dx: Double, dy: Double) -> [RawTouchContact] {
        contacts.map { c in
            RawTouchContact(id: c.id, x: c.x + dx, y: c.y + dy, size: c.size)
        }
    }

    static func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAILED: \(message)\n", stderr)
            exit(1)
        }
    }

    static func feed(
        _ core: GestureRecognizerCore,
        _ frames: [(TimeInterval, [RawTouchContact])],
        deviceID: UInt = 1,
        device: GestureDevice = .trackpad
    ) -> [RecognizedGesture] {
        var out: [RecognizedGesture] = []
        for (time, contacts) in frames {
            out += core.processFrame(deviceID: deviceID, device: device, contacts: contacts, uptime: time)
        }
        return out
    }

    static func testSequentialFingerLandingDoesNotBecomeTwoFingerSwipe() {
        let core = GestureRecognizerCore()

        let one = [RawTouchContact(id: 1, x: 0.15, y: 0.50, size: 1)]
        let two = [
            RawTouchContact(id: 1, x: 0.15, y: 0.50, size: 1),
            RawTouchContact(id: 2, x: 0.85, y: 0.50, size: 1)
        ]
        let three = contacts(3)

        let out = feed(core, [
            (0.00, one),
            (0.025, two),   // huge centroid jump: old recognizer could fire a 2F swipe here
            (0.050, three),
            (0.130, three), // settle/rebase
            (0.150, shifted(three, dx: 0.01, dy: -0.02)),
            (0.175, shifted(three, dx: 0.01, dy: -0.045)),
            (0.200, shifted(three, dx: 0.01, dy: -0.070)),
            (0.225, shifted(three, dx: 0.01, dy: -0.095)),
            (0.250, [])
        ])

        assert(out.filter { $0.fingers == 2 && $0.kind == .swipe }.isEmpty,
               "sequential 1→2→3 finger placement produced a 2-finger swipe")
        assert(out.contains { $0.fingers == 3 && $0.kind == .swipe && $0.direction == .down },
               "settled 3-finger down swipe was not recognized")
    }

    static func cardinalResult(dx: Double, dy: Double) -> [RecognizedGesture] {
        let core = GestureRecognizerCore()
        let base = contacts(3)
        return feed(core, [
            (0.00, base),
            (0.080, base),
            (0.110, shifted(base, dx: dx * 0.25, dy: dy * 0.25)),
            (0.140, shifted(base, dx: dx * 0.50, dy: dy * 0.50)),
            (0.170, shifted(base, dx: dx * 0.75, dy: dy * 0.75)),
            (0.200, shifted(base, dx: dx, dy: dy)),
            (0.230, [])
        ])
    }

    static func testAllFourCardinalDirections() {
        let cases: [(Double, Double, GestureDirection)] = [
            (-0.10, 0.012, .left),
            ( 0.10, 0.012, .right),
            ( 0.012, 0.10, .up),
            ( 0.012,-0.10, .down)
        ]
        for (dx, dy, expected) in cases {
            let out = cardinalResult(dx: dx, dy: dy)
            assert(out.filter { $0.kind == .swipe }.count == 1,
                   "cardinal \(expected) should emit exactly one swipe")
            assert(out.first(where: { $0.kind == .swipe })?.direction == expected,
                   "cardinal \(expected) misclassified")
        }
    }

    static func testDiagonalMotionDoesNotTrigger() {
        let core = GestureRecognizerCore()
        let base = contacts(3)
        let out = feed(core, [
            (0.00, base),
            (0.080, base),
            (0.110, shifted(base, dx: 0.03, dy: 0.028)),
            (0.140, shifted(base, dx: 0.055, dy: 0.052)),
            (0.170, shifted(base, dx: 0.080, dy: 0.076)),
            (0.200, shifted(base, dx: 0.11, dy: 0.105)),
            (0.230, [])
        ])
        assert(out.filter { $0.kind == .swipe }.isEmpty,
               "ambiguous diagonal motion must not choose an arbitrary axis")
    }

    static func testAxisLocksAndCannotFlipMidGesture() {
        let core = GestureRecognizerCore()
        let base = contacts(3)
        let out = feed(core, [
            (0.00, base),
            (0.080, base),
            (0.110, shifted(base, dx: 0.04, dy: 0.010)),
            (0.140, shifted(base, dx: 0.055, dy: 0.012)),
            (0.170, shifted(base, dx: 0.065, dy: 0.014)), // horizontal lock
            (0.200, shifted(base, dx: 0.070, dy: 0.060)),
            (0.230, shifted(base, dx: 0.072, dy: 0.105)), // vertical later dominates
            (0.260, [])
        ])
        assert(out.filter { $0.kind == .swipe }.isEmpty,
               "a gesture that veers across axes after locking should cancel, not flip direction")
    }

    static func testFingerDropDoesNotBecomeLowerFingerSwipe() {
        let core = GestureRecognizerCore()
        let three = contacts(3)
        let two = contacts(2)
        let out = feed(core, [
            (0.00, three),
            (0.080, three),
            (0.110, shifted(three, dx: 0.035, dy: 0.005)),
            (0.140, shifted(three, dx: 0.050, dy: 0.005)),
            (0.160, shifted(two, dx: 0.055, dy: 0.005)),  // one finger lifts
            (0.240, shifted(two, dx: 0.14, dy: 0.005)),   // residual 2F movement
            (0.270, [])
        ])
        assert(out.filter { $0.kind == .swipe }.isEmpty,
               "3→2 finger tail was reinterpreted as a new swipe")
    }

    static func testSlowDeliberateSwipeStillTriggers() {
        let core = GestureRecognizerCore()
        let base = contacts(3)
        let out = feed(core, [
            (0.00, base),
            (0.090, base),
            (0.40, shifted(base, dx: 0.025, dy: -0.004)),
            (0.70, shifted(base, dx: 0.045, dy: -0.006)),
            (1.00, shifted(base, dx: 0.060, dy: -0.008)),
            (1.30, shifted(base, dx: 0.080, dy: -0.010)),
            (1.55, shifted(base, dx: 0.100, dy: -0.012)),
            (1.60, [])
        ])
        assert(out.contains { $0.kind == .swipe && $0.direction == .right },
               "slow deliberate swipe should not look like a hung recognizer")
    }

    static func testMagicMouseFastHorizontalSwipesBothDirections() {
        for (dx, expected) in [(-0.055, GestureDirection.left), (0.055, GestureDirection.right)] {
            let core = GestureRecognizerCore()
            let base = contacts(3)
            let out = feed(core, [
                (0.000, base),
                (0.040, base),
                (0.055, shifted(base, dx: dx * 0.45, dy: 0.003)),
                (0.073, shifted(base, dx: dx * 0.75, dy: 0.004)),
                (0.091, shifted(base, dx: dx, dy: 0.005)),
                (0.110, [])
            ], device: .magicMouse)

            assert(out.contains { $0.kind == .swipe && $0.fingers == 3 && $0.direction == expected },
                   "fast Magic Mouse 3F \(expected) swipe was missed")
        }
    }

    static func testMagicMouseRecoversFromSameCountIdentityReplacement() {
        let core = GestureRecognizerCore()
        let base = contacts(3)
        let replacement = base.enumerated().map { index, c in
            RawTouchContact(id: index + 11, x: c.x, y: c.y, size: c.size)
        }
        let out = feed(core, [
            (0.000, base),
            (0.040, base),
            (0.055, shifted(base, dx: 0.018, dy: 0.002)),
            (0.070, replacement),
            (0.108, replacement),
            (0.125, shifted(replacement, dx: 0.024, dy: 0.002)),
            (0.145, shifted(replacement, dx: 0.040, dy: 0.003)),
            (0.165, shifted(replacement, dx: 0.055, dy: 0.004)),
            (0.185, [])
        ], device: .magicMouse)

        assert(out.contains { $0.kind == .swipe && $0.fingers == 3 && $0.direction == .right },
               "Magic Mouse same-count identity replacement cancelled the remaining swipe")
    }

    static func testThreeFingerDoubleTapSurvivesSequentialLanding() {
        let core = GestureRecognizerCore()
        let one = contacts(1)
        let two = contacts(2)
        let three = contacts(3)
        var out: [RecognizedGesture] = []

        out += feed(core, [
            (0.00, one), (0.020, two), (0.040, three), (0.120, three), (0.170, []),
            (0.310, one), (0.330, two), (0.350, three), (0.430, three), (0.480, [])
        ])

        assert(out.contains { $0.kind == .doubleTap && $0.fingers == 3 },
               "sequential finger landing broke the 3-finger double-tap")
    }
}
