import XCTest
@testable import StarwireKit

final class TouchRateMeterTests: XCTestCase {
    func testAGestureIsMeasuredFromFirstFingerDownToLastUp() {
        let meter = TouchRateMeter()
        meter.fingersChanged(to: 1, at: 10)
        meter.fingersChanged(to: 2, at: 10.01)
        // Half a second of deliveries at 120 Hz, two coalesced samples each, 4 ms late
        for i in 0..<60 {
            let now = 10.02 + Double(i) / 120
            meter.moved(samples: 2, touchTime: now - 0.004, at: now)
            meter.sent(.scroll(amount: 6))
        }
        meter.fingersChanged(to: 1, at: 10.5)
        XCTAssertNil(meter.lastGesture, "a finger is still down")
        meter.fingersChanged(to: 0, at: 10.5)

        let gesture = meter.lastGesture!
        XCTAssertEqual(gesture.duration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(gesture.eventsPerSecond, 120, accuracy: 1e-6)
        XCTAssertEqual(gesture.samplesPerSecond, 240, accuracy: 1e-6)
        XCTAssertEqual(gesture.meanDelivery, 0.004, accuracy: 1e-9)
        XCTAssertEqual(gesture.sentPerSecond(.scroll), 120, accuracy: 1e-6)
        XCTAssertEqual(meter.line,
                       "Touch rate: 120 events/s, 240 samples/s, delivery 4.0 ms (max 4.0); sent touch 0/s, scroll 120/s, mouse 0/s")
    }

    func testATapIsNotKept() {
        let meter = TouchRateMeter()
        meter.fingersChanged(to: 1, at: 0)
        meter.moved(samples: 1, touchTime: 0.01, at: 0.01)
        meter.fingersChanged(to: 0, at: 0.05)
        XCTAssertNil(meter.lastGesture)
        XCTAssertEqual(meter.line, "Touch rate: no gesture yet")
    }

    func testSendsOutsideAGestureAreNotCounted() {
        let meter = TouchRateMeter()
        meter.sent(.mouseMove(dx: 1, dy: 1))
        meter.fingersChanged(to: 1, at: 0)
        meter.moved(samples: 1, touchTime: 0.2, at: 0.2)
        meter.fingersChanged(to: 0, at: 1)
        XCTAssertEqual(meter.lastGesture?.sent[.mouse], nil)
    }
}
