import XCTest
@testable import StarwireKit

/// The touch modes on the iPad 10th gen's screen in landscape (1180x820 points, 2x), showing a
/// 1920x1080 stream. Every test drives time itself and checks the exact packets.
final class InputTouchModesTests: XCTestCase {
    private var sink: RecordingInputSink!
    private var outcomes: [TouchOutcome] = []

    private func dispatcher(_ mode: TouchMode, longPressRightClick: Bool = true, absoluteMouse: Bool = false,
                            hostTouch: Bool = true, pinch: Bool = true) -> TouchDispatcher {
        sink = RecordingInputSink()
        outcomes = []
        let geometry = VideoGeometry(viewSize: CGSize(width: 1180, height: 820), streamSize: CGSize(width: 1920, height: 1080))
        let env = TouchEnvironment(geometry: geometry, viewPixelSize: CGSize(width: 2360, height: 1640),
                                   longPressRightClick: longPressRightClick, absoluteMouseMode: absoluteMouse) { [unowned self] in
            self.sink.send($0)
        }
        let d = TouchDispatcher(mode: mode, environment: env, pixelScale: 2, pinchToZoom: pinch, hostSupportsTouch: hostTouch)
        d.onOutcome = { [unowned self] in self.outcomes.append($0) }
        return d
    }

    private func p(_ id: Int, _ x: CGFloat, _ y: CGFloat) -> TouchPointer {
        TouchPointer(id: id, point: CGPoint(x: x, y: y))
    }

    private func tap(_ d: TouchDispatcher, at point: CGPoint, time: TimeInterval, length: TimeInterval = 0.05) {
        let finger = TouchPointer(id: 1, point: point)
        d.handle(.down(index: 0, pointers: [finger]), at: time)
        d.handle(.up(index: 0, pointers: [finger]), at: time + length)
    }

    private let left = { (down: Bool) in InputEvent.mouseButton(button: 1, down: down) }
    private let right = { (down: Bool) in InputEvent.mouseButton(button: 3, down: down) }

    // MARK: Direct touch

    func testDirectTapClicksUnderTheFinger() {
        let d = dispatcher(.direct)
        tap(d, at: CGPoint(x: 590, y: 410), time: 0)
        XCTAssertEqual(sink.events, [.mousePosition(x: 960, y: 540, width: 1920, height: 1080), left(true)])
        d.tick(now: 0.149)
        XCTAssertEqual(sink.events.count, 2, "the button stays down for 100 ms")
        d.tick(now: 0.151)
        XCTAssertEqual(sink.events.last, left(false))
        XCTAssertNil(d.nextDeadline)
    }

    func testDirectLongPressRightClicks() {
        let d = dispatcher(.direct)
        let finger = p(1, 590, 410)
        d.handle(.down(index: 0, pointers: [finger]), at: 0)
        d.tick(now: 0.1)
        XCTAssertEqual(sink.events, [.mousePosition(x: 960, y: 540, width: 1920, height: 1080), left(true)])
        d.tick(now: 0.65)
        d.handle(.up(index: 0, pointers: [finger]), at: 1.0)
        XCTAssertEqual(Array(sink.events.dropFirst(2)), [left(false), right(true), right(false)])
    }

    func testDirectLongPressCanBeTurnedOff() {
        let d = dispatcher(.direct, longPressRightClick: false)
        let finger = p(1, 590, 410)
        d.handle(.down(index: 0, pointers: [finger]), at: 0)
        d.tick(now: 2)
        d.handle(.up(index: 0, pointers: [finger]), at: 2)
        XCTAssertEqual(sink.events, [.mousePosition(x: 960, y: 540, width: 1920, height: 1080), left(true), left(false)])
    }

    func testDirectDoubleTapKeepsTheFirstSpot() {
        let d = dispatcher(.direct)
        tap(d, at: CGPoint(x: 590, y: 410), time: 0)
        d.tick(now: 0.2)
        // 10 points away and 200 ms later: within the double-tap window, so no new position
        tap(d, at: CGPoint(x: 600, y: 410), time: 0.25)
        d.tick(now: 0.5)
        XCTAssertEqual(sink.events, [.mousePosition(x: 960, y: 540, width: 1920, height: 1080), left(true), left(false),
                                     left(true), left(false)])
    }

    func testDirectDragMovesWithTheFinger() {
        let d = dispatcher(.direct)
        d.handle(.down(index: 0, pointers: [p(1, 590, 410)]), at: 0)
        d.handle(.move(pointers: [p(1, 595, 410)]), at: 0.02)
        XCTAssertEqual(sink.events, [], "inside the 20 pixel dead zone")
        d.handle(.move(pointers: [p(1, 610, 410)]), at: 0.04)
        d.handle(.up(index: 0, pointers: [p(1, 610, 410)]), at: 0.06)
        XCTAssertEqual(sink.events, [.mousePosition(x: 960, y: 540, width: 1920, height: 1080), left(true),
                                     .mousePosition(x: 992, y: 540, width: 1920, height: 1080), left(false)])
    }

    func testDirectSecondFingerScrolls() {
        let d = dispatcher(.direct)
        d.handle(.down(index: 0, pointers: [p(1, 500, 400)]), at: 0)
        d.handle(.down(index: 1, pointers: [p(1, 500, 400), p(2, 600, 400)]), at: 0.01)
        d.handle(.move(pointers: [p(1, 500, 400), p(2, 600, 410)]), at: 0.05)
        XCTAssertEqual(sink.events, [.scroll(amount: 60)])
    }

    func testSwappedClicksTradeButtons() {
        let d = dispatcher(.directSwapped)
        tap(d, at: CGPoint(x: 590, y: 410), time: 0)
        d.tick(now: 0.2)
        XCTAssertEqual(sink.events, [.mousePosition(x: 960, y: 540, width: 1920, height: 1080), right(true), right(false)])
    }

    // MARK: Natural trackpad

    func testNaturalTapClicksWhereTheCursorIs() {
        let d = dispatcher(.naturalTrackpad)
        tap(d, at: CGPoint(x: 100, y: 100), time: 0, length: 0.1)
        XCTAssertEqual(sink.events, [left(true)])
        d.tick(now: 0.33)
        XCTAssertEqual(sink.events, [left(true), left(false)])
    }

    func testNaturalMoveUsesTheSpeedCurveAndKeepsFractions() {
        let d = dispatcher(.naturalTrackpad)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        // 20 points is 40 pixels: 40 * cbrt(40 / 8) = 68.4
        d.handle(.move(pointers: [p(1, 120, 100)]), at: 0.02)
        XCTAssertEqual(sink.events, [.mouseMove(dx: 68, dy: 0)])
        d.handle(.move(pointers: [p(1, 140, 100)]), at: 0.04)
        // 68.4 again plus the 0.4 kept
        XCTAssertEqual(sink.events.last, .mouseMove(dx: 68, dy: 0))
        d.handle(.move(pointers: [p(1, 160, 100)]), at: 0.06)
        XCTAssertEqual(sink.events.last, .mouseMove(dx: 69, dy: 0))
    }

    func testNaturalSensitivityScalesMovement() {
        let d = dispatcher(.naturalTrackpad)
        d.setSensitivity(200)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        d.handle(.move(pointers: [p(1, 120, 100)]), at: 0.02)
        XCTAssertEqual(sink.events, [.mouseMove(dx: 136, dy: 0)])
    }

    func testNaturalTwoFingerTapRightClicks() {
        let d = dispatcher(.naturalTrackpad)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        d.handle(.down(index: 1, pointers: [p(1, 100, 100), p(2, 200, 100)]), at: 0.01)
        d.handle(.up(index: 1, pointers: [p(1, 100, 100), p(2, 200, 100)]), at: 0.1)
        d.handle(.up(index: 0, pointers: [p(1, 100, 100)]), at: 0.12)
        d.tick(now: 0.4)
        XCTAssertEqual(sink.events, [right(true), right(false)])
    }

    func testNaturalTwoFingerScroll() {
        let d = dispatcher(.naturalTrackpad)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        d.handle(.down(index: 1, pointers: [p(1, 100, 100), p(2, 200, 100)]), at: 0)
        d.handle(.move(pointers: [p(1, 100, 120), p(2, 200, 120)]), at: 0.05)
        XCTAssertEqual(sink.events, [.scroll(amount: 204)])
    }

    func testNaturalTapThenDragDrags() {
        let d = dispatcher(.naturalTrackpad)
        tap(d, at: CGPoint(x: 100, y: 100), time: 0, length: 0.1)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0.2)
        d.handle(.move(pointers: [p(1, 120, 100)]), at: 0.25)
        d.tick(now: 0.5)
        d.handle(.up(index: 0, pointers: [p(1, 120, 100)]), at: 0.6)
        XCTAssertEqual(sink.events, [left(true), .mouseMove(dx: 68, dy: 0), left(false)])
    }

    func testNaturalFlickKeepsGoing() {
        let d = dispatcher(.naturalTrackpad)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        d.handle(.move(pointers: [p(1, 120, 100)]), at: 0.010)
        d.handle(.move(pointers: [p(1, 140, 100)]), at: 0.020)
        d.handle(.up(index: 0, pointers: [p(1, 140, 100)]), at: 0.020)
        let afterLift = sink.events.count
        XCTAssertGreaterThan(afterLift, 2, "the first momentum frame goes out at once")
        d.tick(now: 1.0)
        let moves = sink.events.compactMap { event -> Int? in
            if case .mouseMove(let dx, _) = event { return dx }
            return nil
        }
        XCTAssertGreaterThan(moves.count, 10)
        XCTAssertGreaterThan(moves[2], moves.last! + 20, "momentum slows down")
        XCTAssertNil(d.nextDeadline, "the flick has stopped by itself")
    }

    // MARK: Gaming trackpad

    func testGamingMovesScaledToTheReferenceAndKeepsFractions() {
        let d = dispatcher(.gamingTrackpad)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        // 40 pixels * 1280 / 2360 = 21.69
        d.handle(.move(pointers: [p(1, 120, 100)]), at: 0.02)
        d.handle(.move(pointers: [p(1, 140, 100)]), at: 0.04)
        XCTAssertEqual(sink.events, [.mouseMove(dx: 21, dy: 0), .mouseMove(dx: 22, dy: 0)])
    }

    func testGamingTapAndTwoFingerTap() {
        let d = dispatcher(.gamingTrackpad)
        tap(d, at: CGPoint(x: 100, y: 100), time: 0)
        d.tick(now: 0.2)
        XCTAssertEqual(sink.events, [left(true), left(false)])
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 1)
        d.handle(.down(index: 1, pointers: [p(1, 100, 100), p(2, 200, 100)]), at: 1.01)
        d.handle(.up(index: 1, pointers: [p(1, 100, 100), p(2, 200, 100)]), at: 1.1)
        d.handle(.up(index: 0, pointers: [p(1, 100, 100)]), at: 1.11)
        d.tick(now: 1.3)
        XCTAssertEqual(Array(sink.events.dropFirst(2)), [right(true), right(false)])
    }

    func testGamingHoldRightClicksOrDrags() {
        let d = dispatcher(.gamingTrackpad)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        d.tick(now: 0.65)
        d.handle(.up(index: 0, pointers: [p(1, 100, 100)]), at: 0.8)
        XCTAssertEqual(sink.events, [right(true), right(false)])

        let drag = dispatcher(.gamingTrackpad, longPressRightClick: false)
        drag.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        drag.tick(now: 0.65)
        drag.handle(.move(pointers: [p(1, 120, 100)]), at: 0.7)
        drag.handle(.up(index: 0, pointers: [p(1, 120, 100)]), at: 0.8)
        XCTAssertEqual(sink.events, [left(true), .mouseMove(dx: 21, dy: 0), left(false)])
    }

    func testGamingRemoteDesktopMouseMode() {
        let d = dispatcher(.gamingTrackpad, absoluteMouse: true)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        d.handle(.move(pointers: [p(1, 120, 100)]), at: 0.02)
        XCTAssertEqual(sink.events, [.mouseMoveAsPosition(dx: 21, dy: 0, width: 2360, height: 1640)])
    }

    func testGamingTwoFingerScroll() {
        let d = dispatcher(.gamingTrackpad)
        d.handle(.down(index: 0, pointers: [p(1, 100, 100)]), at: 0)
        d.handle(.down(index: 1, pointers: [p(1, 100, 100), p(2, 200, 100)]), at: 0)
        d.handle(.move(pointers: [p(1, 100, 120), p(2, 200, 120)]), at: 0.05)
        // 40 pixels * 720 / 1640 * 5 = 87.8
        XCTAssertEqual(sink.events, [.scroll(amount: 87)])
    }

    // MARK: Menu, multi-touch, disabled

    func testThreeFingerTapOpensTheMenuWithoutClicking() {
        for mode in [TouchMode.naturalTrackpad, .gamingTrackpad, .direct] {
            let d = dispatcher(mode)
            let a = p(1, 100, 100), b = p(2, 200, 100), c = p(3, 300, 100)
            d.handle(.down(index: 0, pointers: [a]), at: 0)
            d.handle(.down(index: 1, pointers: [a, b]), at: 0.01)
            d.handle(.down(index: 2, pointers: [a, b, c]), at: 0.02)
            d.handle(.up(index: 2, pointers: [a, b, c]), at: 0.1)
            d.handle(.up(index: 1, pointers: [a, b]), at: 0.11)
            d.handle(.up(index: 0, pointers: [a]), at: 0.12)
            d.tick(now: 2)
            XCTAssertEqual(outcomes, [.openMenu], "\(mode)")
            XCTAssertEqual(sink.events, [], "\(mode)")
        }
    }

    func testSlowThreeFingerTouchIsNotAMenuTap() {
        let d = dispatcher(.naturalTrackpad)
        let a = p(1, 100, 100), b = p(2, 200, 100), c = p(3, 300, 100)
        d.handle(.down(index: 0, pointers: [a]), at: 0)
        d.handle(.down(index: 1, pointers: [a, b]), at: 0)
        d.handle(.down(index: 2, pointers: [a, b, c]), at: 0)
        d.handle(.up(index: 2, pointers: [a, b, c]), at: 0.5)
        d.handle(.up(index: 1, pointers: [a, b]), at: 0.5)
        d.handle(.up(index: 0, pointers: [a]), at: 0.5)
        XCTAssertEqual(outcomes, [])
    }

    func testMultiTouchPassesFingersThrough() {
        let d = dispatcher(.multiTouch)
        d.handle(.down(index: 0, pointers: [p(7, 590, 410)]), at: 0)
        d.handle(.down(index: 1, pointers: [p(7, 590, 410), p(9, 0, 0)]), at: 0.01)
        d.handle(.move(pointers: [p(7, 590, 410), p(9, 1180, 0)]), at: 0.02)
        d.handle(.up(index: 0, pointers: [p(7, 590, 410), p(9, 1180, 0)]), at: 0.03)
        d.handle(.cancel(pointers: [p(9, 1180, 0)]), at: 0.04)
        let unknown = InputEvent.unknownRotation
        XCTAssertEqual(sink.events, [
            .touch(id: 7, phase: .down, x: 0.5, y: 0.5, rotation: unknown),
            .touch(id: 9, phase: .down, x: 0, y: 0, rotation: unknown),
            .touch(id: 7, phase: .move, x: 0.5, y: 0.5, rotation: unknown),
            .touch(id: 9, phase: .move, x: 1, y: 0, rotation: unknown),
            .touch(id: 7, phase: .up, x: 0.5, y: 0.5, rotation: unknown),
            .touch(id: 0, phase: .cancelAll, x: 0, y: 0, rotation: unknown),
        ])
    }

    func testMultiTouchFallsBackToDirectWithoutHostSupport() {
        let d = dispatcher(.multiTouch, hostTouch: false)
        tap(d, at: CGPoint(x: 590, y: 410), time: 0)
        XCTAssertEqual(sink.events, [.mousePosition(x: 960, y: 540, width: 1920, height: 1080), left(true)])
    }

    func testDisabledSendsNothingButThreeFingersOpenTheMenu() {
        let d = dispatcher(.disabled)
        tap(d, at: CGPoint(x: 590, y: 410), time: 0)
        d.tick(now: 2)
        XCTAssertEqual(sink.events, [])
        let a = p(1, 100, 100), b = p(2, 200, 100), c = p(3, 300, 100)
        d.handle(.down(index: 0, pointers: [a]), at: 3)
        d.handle(.down(index: 1, pointers: [a, b]), at: 3)
        d.handle(.down(index: 2, pointers: [a, b, c]), at: 3)
        XCTAssertEqual(outcomes, [.openMenu])
    }

    func testChangingModeLetsGoOfAHeldButton() {
        let d = dispatcher(.direct)
        d.handle(.down(index: 0, pointers: [p(1, 590, 410)]), at: 0)
        d.tick(now: 0.1)
        d.setMode(.naturalTrackpad)
        XCTAssertEqual(sink.events.last, left(false))
        XCTAssertEqual(d.mode, .naturalTrackpad)
    }

    // MARK: Zoom

    func testPinchZoomsAboutTheFingersWithoutClicking() {
        let d = dispatcher(.naturalTrackpad)
        let before = d.geometry.normalized(CGPoint(x: 550, y: 400))
        d.handle(.down(index: 0, pointers: [p(1, 500, 400)]), at: 0)
        d.handle(.down(index: 1, pointers: [p(1, 500, 400), p(2, 600, 400)]), at: 0.01)
        d.handle(.move(pointers: [p(1, 450, 400), p(2, 650, 400)]), at: 0.05)
        d.handle(.up(index: 1, pointers: [p(1, 450, 400), p(2, 650, 400)]), at: 0.1)
        d.handle(.up(index: 0, pointers: [p(1, 450, 400)]), at: 0.11)
        d.tick(now: 1)
        XCTAssertEqual(sink.events, [])
        guard case .geometry(let g)? = outcomes.last else { return XCTFail("no zoom") }
        XCTAssertEqual(g.zoom, 2, accuracy: 1e-9)
        let after = g.normalized(CGPoint(x: 550, y: 400))
        XCTAssertEqual(after.x, before.x, accuracy: 1e-6)
        XCTAssertEqual(after.y, before.y, accuracy: 1e-6)
        XCTAssertEqual(d.geometry, g)
    }

    func testPinchCanBeTurnedOff() {
        let d = dispatcher(.naturalTrackpad, pinch: false)
        d.handle(.down(index: 0, pointers: [p(1, 500, 400)]), at: 0)
        d.handle(.down(index: 1, pointers: [p(1, 500, 400), p(2, 600, 400)]), at: 0.01)
        d.handle(.move(pointers: [p(1, 450, 400), p(2, 650, 400)]), at: 0.05)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testPanZoomModePansAndDoubleTapResets() {
        let d = dispatcher(.direct)
        d.togglePanZoomMode()
        XCTAssertEqual(outcomes, [.notice("Pan and zoom mode on")])
        d.geometry.zoom = 2
        d.handle(.down(index: 0, pointers: [p(1, 500, 400)]), at: 0)
        d.handle(.move(pointers: [p(1, 600, 400)]), at: 0.05)
        d.handle(.up(index: 0, pointers: [p(1, 600, 400)]), at: 0.1)
        XCTAssertEqual(d.geometry.pan.x, 100)
        tap(d, at: CGPoint(x: 500, y: 400), time: 1)
        tap(d, at: CGPoint(x: 505, y: 400), time: 1.2)
        XCTAssertEqual(d.geometry.zoom, 1)
        XCTAssertEqual(d.geometry.pan, .zero)
        XCTAssertEqual(sink.events, [], "nothing reaches the PC in pan and zoom mode")
    }
}
