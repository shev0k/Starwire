import XCTest
@testable import StarwireKit

// Tests for GamepadMath.swift: the arithmetic of Starwire for Android's ControllerHandler.

private func packet(_ number: Int = 0, mask: Int = 1, buttons: Int = 0, leftTrigger: Int = 0, rightTrigger: Int = 0,
                    leftX: Int = 0, leftY: Int = 0, rightX: Int = 0, rightY: Int = 0) -> InputEvent {
    .controller(ControllerState(number: number, activeMask: mask, buttons: buttons, leftTrigger: leftTrigger,
                                rightTrigger: rightTrigger, leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY))
}

private let still: (x: Float, y: Float) = (0, 0)

final class InputGamepadDeadzoneTests: XCTestCase {
    func testTheDeadzoneIsThePercentOver100AndAtLeastOne() {
        XCTAssertEqual(GamepadMath.deadzoneRadius(percent: 7), Float(0.07))
        XCTAssertEqual(GamepadMath.deadzoneRadius(percent: 20), Float(0.2))
        XCTAssertEqual(GamepadMath.deadzoneRadius(percent: 1), Float(0.01))
        XCTAssertEqual(GamepadMath.deadzoneRadius(percent: 0), Float(0.01), "Android treats 0 as 1")
        XCTAssertEqual(GamepadMath.deadzoneRadius(percent: -5), Float(0.01))
    }

    func testInsideTheDeadzoneIsZero() {
        let deadzone = GamepadMath.deadzoneRadius(percent: 7)
        XCTAssertTrue(GamepadMath.stick(x: 0.05, y: 0, deadzone: deadzone) == (0, 0))
        XCTAssertTrue(GamepadMath.stick(x: 0, y: -0.06, deadzone: deadzone) == (0, 0))
        XCTAssertTrue(GamepadMath.stick(x: 0, y: 0, deadzone: deadzone) == (0, 0))
    }

    func testExactlyOnTheEdgeIsStillZero() {
        let deadzone = GamepadMath.deadzoneRadius(percent: 7)
        XCTAssertTrue(GamepadMath.stick(x: deadzone, y: 0, deadzone: deadzone) == (0, 0), "Android's test is <=")
        XCTAssertTrue(GamepadMath.stick(x: 0, y: deadzone, deadzone: deadzone) == (0, 0))
    }

    func testJustOutsideThePassesThroughWithoutRescaling() {
        let deadzone = GamepadMath.deadzoneRadius(percent: 7)
        // 0.0701 * 32766 is 2296.9, cut down. A rescaled stick would start from 0.
        XCTAssertTrue(GamepadMath.stick(x: 0.0701, y: 0, deadzone: deadzone) == (2296, 0))
        XCTAssertTrue(GamepadMath.stick(x: 0, y: 0.5, deadzone: deadzone) == (0, 16383))
    }

    func testFullDeflectionIs32766() {
        let deadzone = GamepadMath.deadzoneRadius(percent: 7)
        XCTAssertTrue(GamepadMath.stick(x: 1, y: 0, deadzone: deadzone) == (32766, 0))
        XCTAssertTrue(GamepadMath.stick(x: -1, y: 0, deadzone: deadzone) == (-32766, 0))
        XCTAssertTrue(GamepadMath.stick(x: 0, y: 1, deadzone: deadzone) == (0, 32766))
        XCTAssertTrue(GamepadMath.stick(x: 0, y: -1, deadzone: deadzone) == (0, -32766))
    }

    func testTheDeadzoneIsRadialNotPerAxis() {
        let deadzone = GamepadMath.deadzoneRadius(percent: 7)
        // Each axis is under 0.07, but together they are 0.0849 from the centre: both pass, whole
        XCTAssertTrue(GamepadMath.stick(x: 0.06, y: 0.06, deadzone: deadzone) == (1965, 1965))
        // Diagonal at the rim
        XCTAssertTrue(GamepadMath.stick(x: 0.6, y: -0.8, deadzone: deadzone) == (19659, -26212))
    }

    func testOtherDeadzoneSettings() {
        XCTAssertTrue(GamepadMath.stick(x: 0.15, y: 0, deadzone: GamepadMath.deadzoneRadius(percent: 20)) == (0, 0))
        XCTAssertTrue(GamepadMath.stick(x: 0.25, y: 0, deadzone: GamepadMath.deadzoneRadius(percent: 20)) == (8191, 0))
        XCTAssertTrue(GamepadMath.stick(x: 0.02, y: 0, deadzone: GamepadMath.deadzoneRadius(percent: 1)) == (655, 0))
    }

    func testTriggers() {
        XCTAssertEqual(GamepadMath.trigger(0), 0)
        XCTAssertEqual(GamepadMath.trigger(0.13), 0, "at the deadzone is zero")
        XCTAssertEqual(GamepadMath.trigger(0.14), 35)
        XCTAssertEqual(GamepadMath.trigger(0.5), 127)
        XCTAssertEqual(GamepadMath.trigger(1), 255)
        XCTAssertEqual(GamepadMath.trigger(0.29, deadzone: 0.30), 0)
        XCTAssertEqual(GamepadMath.defaultTriggerDeadzone, 0.13)
    }

    func testTheOptionsComeFromTheSettings() throws {
        let store = SettingsStore(storage: MemorySettingsStorage())
        XCTAssertEqual(GamepadOptions(store: store), GamepadOptions(deadzonePercent: 7, flipFaceButtons: false,
                                                                    analogScrolling: .right, touchpadAsMouse: false))
        try store.set(.int(12), for: "seekbar_deadzone")
        try store.set(.bool(true), for: "checkbox_flip_face_buttons")
        try store.set(.string("left"), for: "analog_scrolling")
        try store.set(.bool(true), for: "checkbox_gamepad_touchpad_as_mouse")
        XCTAssertEqual(GamepadOptions(store: store), GamepadOptions(deadzonePercent: 12, flipFaceButtons: true,
                                                                    analogScrolling: .left, touchpadAsMouse: true))
        try store.set(.string("none"), for: "analog_scrolling")
        XCTAssertEqual(GamepadOptions(store: store).analogScrolling, .none)
    }
}

final class InputGamepadFlipTests: XCTestCase {
    func testFlipSwapsAWithBAndXWithY() {
        XCTAssertEqual(GamepadMath.flipFaceButtons(GamepadButton.a), GamepadButton.b)
        XCTAssertEqual(GamepadMath.flipFaceButtons(GamepadButton.b), GamepadButton.a)
        XCTAssertEqual(GamepadMath.flipFaceButtons(GamepadButton.x), GamepadButton.y)
        XCTAssertEqual(GamepadMath.flipFaceButtons(GamepadButton.y), GamepadButton.x)
        XCTAssertEqual(GamepadMath.flipFaceButtons(GamepadButton.a | GamepadButton.y), GamepadButton.b | GamepadButton.x)
        XCTAssertEqual(GamepadMath.flipFaceButtons(GamepadButton.a | GamepadButton.b), GamepadButton.a | GamepadButton.b)
    }

    func testFlipLeavesTheOtherButtonsAlone() {
        let others = GamepadButton.up | GamepadButton.leftBumper | GamepadButton.start | GamepadButton.guide
            | GamepadButton.touchpad | GamepadButton.paddle1
        XCTAssertEqual(GamepadMath.flipFaceButtons(others | GamepadButton.a), others | GamepadButton.b)
        XCTAssertEqual(GamepadMath.flipFaceButtons(others), others)
    }

    func testFlippingTwiceIsNoChange() {
        for buttons in [0, GamepadButton.a, GamepadButton.x | GamepadButton.b, 0xF000 | GamepadButton.up] {
            XCTAssertEqual(GamepadMath.flipFaceButtons(GamepadMath.flipFaceButtons(buttons)), buttons)
        }
    }

    func testTheProcessorFlipsOnlyWhenAsked() {
        let plain = GamepadProcessor(options: GamepadOptions(flipFaceButtons: false))
        XCTAssertEqual(plain.update(buttons: GamepadButton.a, leftStick: still, rightStick: still, leftTrigger: 0, rightTrigger: 0),
                       [packet(buttons: GamepadButton.a)])
        let flipped = GamepadProcessor(options: GamepadOptions(flipFaceButtons: true))
        XCTAssertEqual(flipped.update(buttons: GamepadButton.a | GamepadButton.x, leftStick: still, rightStick: still,
                                      leftTrigger: 0, rightTrigger: 0),
                       [packet(buttons: GamepadButton.b | GamepadButton.y)])
    }
}

final class InputGamepadProcessorTests: XCTestCase {
    func testTheStateGoesOutWithTheDeadzoneApplied() {
        let processor = GamepadProcessor(options: GamepadOptions(deadzonePercent: 7), controllerNumber: 1, activeMask: 0b11)
        let events = processor.update(buttons: GamepadButton.leftBumper, leftStick: (0.5, -0.25), rightStick: (0.04, 0.04),
                                      leftTrigger: 1, rightTrigger: 0.1)
        XCTAssertEqual(events, [packet(1, mask: 3, buttons: GamepadButton.leftBumper, leftTrigger: 255, rightTrigger: 0,
                                       leftX: 16383, leftY: -8191, rightX: 0, rightY: 0)])
    }

    func testAnUnchangedStateIsNotSentAgain() {
        let processor = GamepadProcessor()
        XCTAssertEqual(processor.update(buttons: 0, leftStick: still, rightStick: still, leftTrigger: 0, rightTrigger: 0), [],
                       "an idle controller is what the PC already has")
        XCTAssertEqual(processor.update(buttons: GamepadButton.a, leftStick: still, rightStick: still, leftTrigger: 0,
                                        rightTrigger: 0).count, 1)
        XCTAssertEqual(processor.update(buttons: GamepadButton.a, leftStick: (0.01, 0), rightStick: still, leftTrigger: 0,
                                        rightTrigger: 0), [], "still inside the deadzone")
    }

    func testTheTriggerDeadzoneCanBeChanged() {
        let processor = GamepadProcessor()
        processor.triggerDeadzone = 0.30
        XCTAssertEqual(processor.update(buttons: 0, leftStick: still, rightStick: still, leftTrigger: 0.25, rightTrigger: 0.5),
                       [packet(rightTrigger: 127)])
    }
}

final class InputGamepadMouseEmulationTests: XCTestCase {
    func testTheMouseMovesLikeTheCubeOfTheStick() {
        // A half push is 0.5; times 4 is 2; times its own square (4) is 8
        XCTAssertEqual(GamepadMath.emulatedMouseMove(stickX: 16383, stickY: 0), [.mouseMove(dx: 8, dy: 0)])
        // Y is up on the stick and down on the screen
        XCTAssertEqual(GamepadMath.emulatedMouseMove(stickX: 0, stickY: 16383), [.mouseMove(dx: 0, dy: -8)])
        XCTAssertEqual(GamepadMath.emulatedMouseMove(stickX: -16383, stickY: -16383).count, 1)
    }

    func testAFullPushMoves64() {
        let full = GamepadMath.emulatedMovement(stickX: 32766, stickY: 0)
        XCTAssertEqual(full.x, 64, accuracy: 0.001)
        // Whole pixels are cut down, so a float step landing a hair under 64 would give 63. The
        // sums here are Android's, in Android's order, and give 64.
        guard case .mouseMove(let dx, _)? = GamepadMath.emulatedMouseMove(stickX: 32766, stickY: 0).first else {
            return XCTFail("no move")
        }
        XCTAssertEqual(dx, 64)
    }

    func testUnderOnePixelSendsNothing() {
        // 2000 / 32766 * 4 = 0.244; cubed it is 0.0146
        XCTAssertEqual(GamepadMath.emulatedMouseMove(stickX: 2000, stickY: 0), [])
        XCTAssertEqual(GamepadMath.emulatedMouseMove(stickX: 0, stickY: 0), [])
        XCTAssertEqual(GamepadMath.emulatedMouseScroll(stickX: 2000, stickY: 0), [])
    }

    func testScrollSendsBothAxesAndTheStickUpScrollsUp() {
        XCTAssertEqual(GamepadMath.emulatedMouseScroll(stickX: 0, stickY: 16383), [.scroll(amount: 8), .hScroll(amount: 0)])
        XCTAssertEqual(GamepadMath.emulatedMouseScroll(stickX: -16383, stickY: 0), [.scroll(amount: 0), .hScroll(amount: -8)])
    }

    func testItIsOffUntilToggledAndTheReportRunsEvery50Milliseconds() {
        let processor = GamepadProcessor(options: GamepadOptions(analogScrolling: .right))
        XCTAssertFalse(processor.mouseEmulationActive)
        XCTAssertNil(processor.nextDeadline)
        XCTAssertEqual(processor.tick(now: 100), [])

        processor.toggleMouseEmulation(now: 10)
        XCTAssertTrue(processor.mouseEmulationActive)
        XCTAssertEqual(processor.nextDeadline ?? 0, 10.05, accuracy: 1e-9)

        _ = processor.update(buttons: 0, leftStick: (0.5, 0), rightStick: still, leftTrigger: 0, rightTrigger: 0)
        XCTAssertEqual(processor.tick(now: 10.04), [], "not yet")
        XCTAssertEqual(processor.tick(now: 10.06), [.mouseMove(dx: 8, dy: 0)])
        XCTAssertEqual(processor.nextDeadline ?? 0, 10.11, accuracy: 1e-9)
        XCTAssertEqual(processor.tick(now: 10.12), [.mouseMove(dx: 8, dy: 0)])

        // Late: Android runs it once and requeues from then
        XCTAssertEqual(processor.tick(now: 10.30), [.mouseMove(dx: 8, dy: 0)])
        XCTAssertEqual(processor.nextDeadline ?? 0, 10.35, accuracy: 1e-9)

        processor.toggleMouseEmulation(now: 11)
        XCTAssertFalse(processor.mouseEmulationActive)
        XCTAssertNil(processor.nextDeadline)
        XCTAssertEqual(processor.tick(now: 12), [])
    }

    func testWhileOnThePCSeesAnIdleController() {
        let processor = GamepadProcessor()
        processor.toggleMouseEmulation(now: 0)
        // Sticks, triggers and most buttons do not reach the PC at all
        let events = processor.update(buttons: GamepadButton.x | GamepadButton.start, leftStick: (1, 0), rightStick: (0, 1),
                                      leftTrigger: 1, rightTrigger: 1)
        XCTAssertEqual(events, [])
        // Having been something else before, going idle is sent
        let before = GamepadProcessor()
        _ = before.update(buttons: GamepadButton.x, leftStick: still, rightStick: still, leftTrigger: 0, rightTrigger: 0)
        before.toggleMouseEmulation(now: 0)
        XCTAssertEqual(before.update(buttons: GamepadButton.x, leftStick: still, rightStick: still, leftTrigger: 0, rightTrigger: 0),
                       [packet()])
    }

    func testAAndBClickTheMouse() {
        let processor = GamepadProcessor()
        processor.toggleMouseEmulation(now: 0)
        XCTAssertEqual(processor.update(buttons: GamepadButton.a, leftStick: still, rightStick: still, leftTrigger: 0, rightTrigger: 0),
                       [.mouseButton(button: 1, down: true)])
        XCTAssertEqual(processor.update(buttons: GamepadButton.a | GamepadButton.b, leftStick: still, rightStick: still,
                                        leftTrigger: 0, rightTrigger: 0),
                       [.mouseButton(button: 3, down: true)])
        XCTAssertEqual(processor.update(buttons: GamepadButton.b, leftStick: still, rightStick: still, leftTrigger: 0, rightTrigger: 0),
                       [.mouseButton(button: 1, down: false)])
        XCTAssertEqual(processor.update(buttons: 0, leftStick: still, rightStick: still, leftTrigger: 0, rightTrigger: 0),
                       [.mouseButton(button: 3, down: false)])
    }

    func testTheDpadScrollsOneNotchPerPress() {
        let processor = GamepadProcessor()
        processor.toggleMouseEmulation(now: 0)
        func press(_ buttons: Int) -> [InputEvent] {
            processor.update(buttons: buttons, leftStick: still, rightStick: still, leftTrigger: 0, rightTrigger: 0)
        }
        XCTAssertEqual(press(GamepadButton.up), [.scroll(amount: 120)])
        XCTAssertEqual(press(0), [], "letting go sends nothing")
        XCTAssertEqual(press(GamepadButton.down), [.scroll(amount: -120)])
        XCTAssertEqual(press(0), [])
        XCTAssertEqual(press(GamepadButton.right), [.hScroll(amount: 120)])
        XCTAssertEqual(press(0), [])
        XCTAssertEqual(press(GamepadButton.left), [.hScroll(amount: -120)])
        XCTAssertEqual(press(GamepadButton.left | GamepadButton.up), [.scroll(amount: 120)], "left is still held")
    }

    func testFlippedFaceButtonsClickTheOtherWay() {
        let processor = GamepadProcessor(options: GamepadOptions(flipFaceButtons: true))
        processor.toggleMouseEmulation(now: 0)
        XCTAssertEqual(processor.update(buttons: GamepadButton.a, leftStick: still, rightStick: still, leftTrigger: 0, rightTrigger: 0),
                       [.mouseButton(button: 3, down: true)])
    }

    func testRightScrollingMovesWithTheLeftStickAndScrollsWithTheRight() {
        let processor = GamepadProcessor(options: GamepadOptions(analogScrolling: .right))
        processor.toggleMouseEmulation(now: 0)
        _ = processor.update(buttons: 0, leftStick: (0.5, 0), rightStick: (0, 0.5), leftTrigger: 0, rightTrigger: 0)
        XCTAssertEqual(processor.tick(now: 0.05),
                       [.mouseMove(dx: 8, dy: 0), .scroll(amount: 8), .hScroll(amount: 0)])
    }

    func testLeftScrollingMovesWithTheRightStickAndScrollsWithTheLeft() {
        let processor = GamepadProcessor(options: GamepadOptions(analogScrolling: .left))
        processor.toggleMouseEmulation(now: 0)
        _ = processor.update(buttons: 0, leftStick: (0.5, 0), rightStick: (0, 0.5), leftTrigger: 0, rightTrigger: 0)
        XCTAssertEqual(processor.tick(now: 0.05),
                       [.mouseMove(dx: 0, dy: -8), .scroll(amount: 0), .hScroll(amount: 8)])
    }

    func testNoScrollingMovesWithBothSticks() {
        let processor = GamepadProcessor(options: GamepadOptions(analogScrolling: AnalogScrolling.none))
        processor.toggleMouseEmulation(now: 0)
        _ = processor.update(buttons: 0, leftStick: (0.5, 0), rightStick: (0, 0.5), leftTrigger: 0, rightTrigger: 0)
        XCTAssertEqual(processor.tick(now: 0.05), [.mouseMove(dx: 8, dy: 0), .mouseMove(dx: 0, dy: -8)])
    }

    func testTheDeadzoneAppliesToTheMouseToo() {
        let processor = GamepadProcessor()
        processor.toggleMouseEmulation(now: 0)
        _ = processor.update(buttons: 0, leftStick: (0.06, 0), rightStick: still, leftTrigger: 0, rightTrigger: 0)
        XCTAssertEqual(processor.tick(now: 0.05), [])
    }
}

final class InputGamepadTouchpadTests: XCTestCase {
    func testWithMouseOffTouchesGoToThePCAsTheControllersTouchpad() {
        var pad = GamepadTouchpad(controllerNumber: 1, asMouse: false)
        XCTAssertEqual(pad.touch(id: 4, phase: .down, x: 0.25, y: 0.5, pressure: 0.5),
                       [.controllerTouch(number: 1, phase: .down, id: 4, x: 0.25, y: 0.5, pressure: 0.5)])
        XCTAssertEqual(pad.touch(id: 4, phase: .move, x: 0.5, y: 0.5),
                       [.controllerTouch(number: 1, phase: .move, id: 4, x: 0.5, y: 0.5, pressure: 0)])
        XCTAssertEqual(pad.touch(id: 4, phase: .up, x: 0.5, y: 0.5),
                       [.controllerTouch(number: 1, phase: .up, id: 4, x: 0.5, y: 0.5, pressure: 0)])
        XCTAssertEqual(pad.touch(id: 0, phase: .cancelAll, x: 0, y: 0),
                       [.controllerTouch(number: 1, phase: .cancelAll, id: 0, x: 0, y: 0, pressure: 0)])
        XCTAssertEqual(pad.click(down: true), [], "the pad's button is in the controller's buttons")
    }

    func testWithMouseOnFingerMovementMovesTheMouseAndNothingGoesToTheControllersTouchpad() {
        var pad = GamepadTouchpad(asMouse: true, countsAcrossPad: 1500)
        XCTAssertEqual(pad.touch(id: 1, phase: .down, x: 0.5, y: 0.25), [], "putting a finger down moves nothing")
        // A quarter of the pad across is 375 counts; an eighth up is 187.5, cut toward zero
        XCTAssertEqual(pad.touch(id: 1, phase: .move, x: 0.75, y: 0.125), [.mouseMove(dx: 375, dy: -187)])
        XCTAssertEqual(pad.touch(id: 1, phase: .move, x: 0.75, y: 0.125), [], "no movement")
        XCTAssertEqual(pad.touch(id: 1, phase: .up, x: 0.75, y: 0.125), [])
        // A new touch starts from where it lands
        XCTAssertEqual(pad.touch(id: 1, phase: .down, x: 0.1, y: 0.1), [])
        XCTAssertEqual(pad.touch(id: 1, phase: .move, x: 0.1, y: 0.1), [])
    }

    func testWithMouseOnTheClickIsALeftClick() {
        let pad = GamepadTouchpad(asMouse: true)
        XCTAssertEqual(pad.click(down: true), [.mouseButton(button: 1, down: true)])
        XCTAssertEqual(pad.click(down: false), [.mouseButton(button: 1, down: false)])
    }

    func testTheMouseFollowsEachFingerOnItsOwn() {
        var pad = GamepadTouchpad(asMouse: true, countsAcrossPad: 1000)
        _ = pad.touch(id: 1, phase: .down, x: 0.25, y: 0.25)
        _ = pad.touch(id: 2, phase: .down, x: 0.75, y: 0.75)
        XCTAssertEqual(pad.touch(id: 2, phase: .move, x: 0.5, y: 0.75), [.mouseMove(dx: -250, dy: 0)])
        XCTAssertEqual(pad.touch(id: 1, phase: .move, x: 0.5, y: 0.25), [.mouseMove(dx: 250, dy: 0)])
    }
}
