import XCTest
@testable import StarwireKit

final class ControllerKeyboardTests: XCTestCase {
    private var keyboard: ControllerKeyboard!
    private var sink: RecordingInputSink!
    private var now: TimeInterval = 100

    override func setUp() {
        keyboard = ControllerKeyboard()
        sink = RecordingInputSink()
    }

    /// Presses and releases buttons, one frame each, sending what comes out to the sink.
    private func press(_ buttons: Int, leftTrigger: Int = 0, rightTrigger: Int = 0) {
        send(ControllerState(buttons: buttons, leftTrigger: leftTrigger, rightTrigger: rightTrigger))
        send(ControllerState())
    }

    private func send(_ state: ControllerState) {
        keyboard.handle(state, now: now).forEach(sink.send)
        now += 0.016
    }

    private func tap(_ code: Int) -> [InputEvent] {
        [.key(code: code, down: true, modifiers: 0), .key(code: code, down: false, modifiers: 0)]
    }

    func testItStartsOnQAndTypesItAsAKeyPress() {
        XCTAssertEqual(keyboard.focusedKey.label, "q")
        press(GamepadButton.a)
        XCTAssertEqual(sink.events, tap(0x51))
        XCTAssertEqual(keyboard.preview, "q")
    }

    func testTheDpadMovesAndWrapsAround() {
        press(GamepadButton.right)
        XCTAssertEqual(keyboard.focusedKey.label, "w")
        press(GamepadButton.left)
        press(GamepadButton.left)
        XCTAssertEqual(keyboard.focusedKey.label, "p", "left from the first column wraps to the last")
        press(GamepadButton.up)
        XCTAssertEqual(keyboard.focusedKey.label, "0")
        press(GamepadButton.up)
        XCTAssertEqual(keyboard.focusedKey.label, "Enter", "up from the top wraps to the bottom row")
        XCTAssertTrue(sink.events.isEmpty, "moving sends nothing")
    }

    func testTheBottomRowsWideKeysAreOneStepEach() {
        press(GamepadButton.down)
        press(GamepadButton.down)
        press(GamepadButton.down)
        XCTAssertEqual(keyboard.focusedKey.label, "Shift")
        press(GamepadButton.right)
        XCTAssertEqual(keyboard.focusedKey.label, "&123")
        press(GamepadButton.right)
        XCTAssertEqual(keyboard.focusedKey.label, "Space")
        press(GamepadButton.right)
        XCTAssertEqual(keyboard.focusedKey.label, "Back")
        press(GamepadButton.up)
        XCTAssertEqual(keyboard.focusedKey.label, ",", "up from Back lands on the key above it")
    }

    func testShouldersAndStartAreBackspaceSpaceAndEnter() {
        press(GamepadButton.a)
        press(GamepadButton.rightBumper)
        XCTAssertEqual(keyboard.preview, "q ")
        press(GamepadButton.leftBumper)
        XCTAssertEqual(keyboard.preview, "q")
        press(GamepadButton.start)
        XCTAssertEqual(keyboard.preview, "", "Enter sends the line")
        XCTAssertEqual(sink.events, tap(0x51) + tap(0x20) + tap(0x08) + tap(0x0D))
    }

    func testLeftTriggerShiftsOnceAndTwiceLocksCaps() {
        press(0, leftTrigger: 255)
        XCTAssertEqual(keyboard.shift, .once)
        press(GamepadButton.a)
        XCTAssertEqual(sink.events, [
            .key(code: 0xA0, down: true, modifiers: KeyModifier.shift),
            .key(code: 0x51, down: true, modifiers: KeyModifier.shift),
            .key(code: 0x51, down: false, modifiers: KeyModifier.shift),
            .key(code: 0xA0, down: false, modifiers: 0),
        ])
        XCTAssertEqual(keyboard.shift, .off, "one shifted letter, then lower case again")

        press(0, leftTrigger: 255)
        press(0, leftTrigger: 255)
        XCTAssertEqual(keyboard.shift, .locked)
        press(GamepadButton.a)
        press(GamepadButton.a)
        XCTAssertEqual(keyboard.preview, "QQQ")
        XCTAssertEqual(keyboard.shift, .locked)
    }

    func testAHeldTriggerIsOnePress() {
        send(ControllerState(leftTrigger: 200))
        send(ControllerState(leftTrigger: 255))
        XCTAssertEqual(keyboard.shift, .once)
    }

    func testRightTriggerSwitchesToSymbolsWithTheArrowKeys() {
        press(0, rightTrigger: 255)
        XCTAssertEqual(keyboard.page, .symbols)
        XCTAssertEqual(keyboard.focusedKey.label, "-")
        press(GamepadButton.down)
        press(GamepadButton.down)
        press(GamepadButton.right)
        press(GamepadButton.right)
        press(GamepadButton.a)
        XCTAssertEqual(sink.events, tap(0x25), "the left arrow")
    }

    func testTappingAKeyOnTheScreenTypesIt() {
        XCTAssertEqual(keyboard.tap(row: 0, column: 0, now: now), tap(0x31))
    }

    func testTheStickMovesWithHysteresisAndRepeatsWhenHeld() {
        send(ControllerState(leftX: 20000))
        XCTAssertEqual(keyboard.focusedKey.label, "w")
        send(ControllerState(leftX: 12000))
        XCTAssertEqual(keyboard.focusedKey.label, "w", "still leaning: no new move")
        XCTAssertNotNil(keyboard.nextDeadline)
        now = keyboard.nextDeadline!
        keyboard.tick(now: now)
        XCTAssertEqual(keyboard.focusedKey.label, "e", "held past the delay: it repeats")
        now += ControllerKeyboard.repeatInterval
        keyboard.tick(now: now)
        XCTAssertEqual(keyboard.focusedKey.label, "r")
        send(ControllerState(leftX: 2000))
        XCTAssertNil(keyboard.nextDeadline)
    }

    func testBClosesAndNothingIsSentAfter() {
        press(GamepadButton.b)
        XCTAssertFalse(keyboard.isOpen)
        press(GamepadButton.a)
        XCTAssertTrue(sink.events.isEmpty)
        keyboard.reopen()
        XCTAssertTrue(keyboard.isOpen)
        XCTAssertEqual(keyboard.focusedKey.label, "q")
    }

    func testTheButtonThatOpenedItDoesNotType() {
        keyboard = ControllerKeyboard(holding: GamepadButton.a)
        send(ControllerState(buttons: GamepadButton.a))
        XCTAssertTrue(sink.events.isEmpty, "A was already down")
        send(ControllerState())
        press(GamepadButton.a)
        XCTAssertEqual(sink.events, tap(0x51))
    }

    func testTheTypedLineKeepsTheLastCharacters() {
        for _ in 0..<(ControllerKeyboard.previewLength + 5) {
            press(GamepadButton.a)
        }
        XCTAssertEqual(keyboard.preview.count, ControllerKeyboard.previewLength)
    }
}
