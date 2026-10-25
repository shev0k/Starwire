import XCTest
@testable import StarwireKit

final class InputTallyTests: XCTestCase {
    func testCountsByKindAndShowsTheLastPacket() {
        let tally = InputTally()
        XCTAssertEqual(tally.line, "Input: touch 0, pen 0, mouse 0, buttons 0, scroll 0, keys 0, text 0, controller 0, motion 0; last none")
        tally.record(.mouseMove(dx: 3, dy: -1))
        tally.record(.mousePosition(x: 1, y: 2, width: 3, height: 4))
        tally.record(.mouseButton(button: 1, down: true))
        tally.record(.scroll(amount: 120))
        tally.record(.hScroll(amount: -120))
        tally.record(.key(code: 0x41, down: false, modifiers: KeyModifier.shift))
        XCTAssertEqual(tally.count(.mouse), 2)
        XCTAssertEqual(tally.count(.scroll), 2)
        XCTAssertEqual(tally.line, "Input: touch 0, pen 0, mouse 2, buttons 1, scroll 2, keys 1, text 0, controller 0, motion 0; last key 0x41 up mods 1")
        tally.reset()
        XCTAssertEqual(tally.count(.mouse), 0)
    }

    func testDescriptions() {
        XCTAssertEqual(InputTally.describe(.controller(ControllerState(number: 1, buttons: GamepadButton.a))), "controller 1 buttons 0x1000")
        XCTAssertEqual(InputTally.describe(.touch(id: 4, phase: .down, x: 0, y: 0)), "touch 4 down")
        XCTAssertEqual(InputTally.describe(.text("héllo")), "text 5 characters")
        XCTAssertEqual(InputTally.kind(of: .controllerMotion(number: 0, sensor: .gyroscope, x: 0, y: 0, z: 0)), .motion)
    }
}
