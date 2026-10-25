import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import StarwireKit

/// Four and five-finger taps over every touch mode, with the packets the PC gets.
final class InputGestureTests: XCTestCase {
    private var sink: RecordingInputSink!
    private var outcomes: [TouchOutcome] = []

    private func dispatcher(_ mode: TouchMode, settings: GestureSettings = GestureSettings()) -> TouchDispatcher {
        sink = RecordingInputSink()
        outcomes = []
        let geometry = VideoGeometry(viewSize: CGSize(width: 1180, height: 820), streamSize: CGSize(width: 1920, height: 1080))
        let env = TouchEnvironment(geometry: geometry, viewPixelSize: CGSize(width: 2360, height: 1640)) { [unowned self] in
            self.sink.send($0)
        }
        let d = TouchDispatcher(mode: mode, environment: env, pixelScale: 2, hostSupportsTouch: true)
        d.gestures.settings = settings
        d.onOutcome = { [unowned self] in self.outcomes.append($0) }
        return d
    }

    private func fingers(_ count: Int, dx: CGFloat = 0) -> [TouchPointer] {
        (0..<count).map { TouchPointer(id: $0 + 1, point: CGPoint(x: 300 + CGFloat($0) * 80 + dx, y: 400)) }
    }

    /// Fingers land 20 ms apart, then lift together `hold` seconds after the first landed.
    private func tap(_ d: TouchDispatcher, count: Int, start: TimeInterval = 0, hold: TimeInterval = 0.15, moveBy: CGFloat = 0) {
        let all = fingers(count)
        for n in 1...count {
            d.handle(.down(index: n - 1, pointers: Array(all.prefix(n))), at: start + Double(n - 1) * 0.02)
        }
        if moveBy != 0 {
            d.handle(.move(pointers: fingers(count, dx: moveBy)), at: start + hold / 2)
        }
        var remaining = moveBy != 0 ? fingers(count, dx: moveBy) : all
        for _ in 0..<count {
            d.handle(.up(index: remaining.count - 1, pointers: remaining), at: start + hold)
            remaining.removeLast()
        }
    }

    private var cancelAll: InputEvent {
        .touch(id: 0, phase: .cancelAll, x: 0, y: 0, pressure: 0, contactMajor: 0, contactMinor: 0, rotation: InputEvent.unknownRotation)
    }

    func testAFourFingerTapInMultiTouchCancelsThePCsTouchesAndOpensTheKeyboard() {
        let d = dispatcher(.multiTouch)
        tap(d, count: 4)
        XCTAssertEqual(outcomes, [.gesture(.fullKeyboard)])
        let touches = sink.events
        // Three fingers reached the PC, then everything was cancelled, then nothing more
        XCTAssertEqual(touches.filter { if case .touch(_, .down, _, _, _, _, _, _) = $0 { return true }; return false }.count, 3)
        XCTAssertEqual(touches.last, cancelAll)
        XCTAssertFalse(touches.contains { if case .touch(_, .up, _, _, _, _, _, _) = $0 { return true }; return false },
                       "no finger lifts on the PC, so it makes no click")
    }

    func testAFiveFingerTapOpensTheMenu() {
        let d = dispatcher(.multiTouch)
        tap(d, count: 5)
        XCTAssertEqual(outcomes, [.openMenu])
    }

    func testThreeFingersInMultiTouchStillBelongToThePC() {
        let d = dispatcher(.multiTouch)
        tap(d, count: 3)
        XCTAssertEqual(outcomes, [])
        XCTAssertEqual(sink.events.count, 6, "three downs and three ups")
    }

    func testASlowOrMovingFourFingerGestureRunsNothingButStaysOffThePC() {
        var d = dispatcher(.multiTouch)
        tap(d, count: 4, hold: 1.0)
        XCTAssertEqual(outcomes, [])
        XCTAssertEqual(sink.events.last, cancelAll)

        d = dispatcher(.multiTouch)
        tap(d, count: 4, moveBy: 120)
        XCTAssertEqual(outcomes, [])
        XCTAssertEqual(sink.events.last, cancelAll, "the moves were dropped")
    }

    func testFingersLandingTooFarApartAreNotAGesture() {
        let d = dispatcher(.multiTouch)
        let all = fingers(4)
        d.handle(.down(index: 0, pointers: [all[0]]), at: 0)
        d.handle(.down(index: 1, pointers: Array(all.prefix(2))), at: 0.1)
        d.handle(.down(index: 2, pointers: Array(all.prefix(3))), at: 0.2)
        d.handle(.down(index: 3, pointers: all), at: 0.4)
        XCTAssertFalse(sink.events.contains(cancelAll))
        XCTAssertFalse(d.gestures.isClaimed)
    }

    func testInTheTrackpadAFourFingerTapIsNotAThreeFingerMenuTap() {
        let d = dispatcher(.gamingTrackpad, settings: GestureSettings(fourFingerTap: .stats))
        tap(d, count: 4)
        XCTAssertEqual(outcomes, [.gesture(.stats)])
        XCTAssertTrue(sink.events.isEmpty, "no clicks reached the PC: \(sink.events)")
    }

    func testTheThreeFingerTapCanBeChangedOutsideMultiTouch() {
        let d = dispatcher(.naturalTrackpad, settings: GestureSettings(threeFingerTap: .systemKeyboard))
        tap(d, count: 3, hold: 0.1)
        XCTAssertEqual(outcomes, [.gesture(.systemKeyboard)])
    }

    func testGesturesSetToNothingLeaveFourFingersToThePC() {
        let d = dispatcher(.multiTouch, settings: GestureSettings(fourFingerTap: .none, fiveFingerTap: .none))
        tap(d, count: 4)
        XCTAssertEqual(outcomes, [])
        XCTAssertFalse(sink.events.contains(cancelAll))
        XCTAssertEqual(sink.events.count, 8)
    }

    func testTheSettingsAreReadFromTheStore() throws {
        let store = SettingsStore(storage: MemorySettingsStorage())
        XCTAssertEqual(GestureSettings(store: store), GestureSettings())
        try store.set(.string("stats"), for: GestureSettings.fourFingerKey)
        XCTAssertEqual(GestureSettings(store: store).fourFingerTap, .stats)
    }
}
