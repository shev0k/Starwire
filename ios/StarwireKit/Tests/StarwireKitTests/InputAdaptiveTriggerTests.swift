import XCTest
@testable import StarwireKit

final class InputAdaptiveTriggerTests: XCTestCase {
    private func bytes(_ first: [UInt8]) -> [UInt8] {
        first + [UInt8](repeating: 0, count: 10 - first.count)
    }

    func testOffAndShortPayloads() {
        XCTAssertEqual(AdaptiveTriggerEffect.decode(type: 0x00, bytes: bytes([])).mode, .off)
        XCTAssertEqual(AdaptiveTriggerEffect.decode(type: 0x05, bytes: bytes([1, 2])).mode, .off)
        XCTAssertEqual(AdaptiveTriggerEffect.decode(type: 0x01, bytes: [255, 255]).mode, .off, "too short")
        XCTAssertEqual(AdaptiveTriggerEffect.decode(type: 0x7F, bytes: bytes([255, 255])).mode, .off, "unknown type")
    }

    func testSimpleFeedback() {
        let effect = AdaptiveTriggerEffect.decode(type: 0x01, bytes: bytes([255, 51]))
        XCTAssertEqual(effect.mode, .feedback)
        XCTAssertEqual(effect.startPosition, 1)
        XCTAssertEqual(effect.startStrength, 0.2, accuracy: 1e-6)
        // The 0x11 form gives strength in tenths
        XCTAssertEqual(AdaptiveTriggerEffect.decode(type: 0x11, bytes: bytes([0, 5])).startStrength, 0.5)
        // No strength is no effect
        XCTAssertEqual(AdaptiveTriggerEffect.decode(type: 0x01, bytes: bytes([128, 0])).mode, .off)
    }

    func testWeaponSpan() {
        let effect = AdaptiveTriggerEffect.decode(type: 0x25, bytes: bytes([0b0000_0100, 0b0000_0010, 0x07]))
        XCTAssertEqual(effect.mode, .weapon)
        // Zones 2 to 9 of 10
        XCTAssertEqual(effect.startPosition, 2.0 / 9, accuracy: 1e-6)
        XCTAssertEqual(effect.endPosition, 1, accuracy: 1e-6)
        XCTAssertEqual(effect.startStrength, 1)
    }

    func testVibrationNeedsFrequencyAndStrength() {
        let effect = AdaptiveTriggerEffect.decode(type: 0x06, bytes: bytes([255, 255, 0]))
        XCTAssertEqual(effect.mode, .vibration)
        XCTAssertEqual(effect.frequency, 1)
        XCTAssertEqual(AdaptiveTriggerEffect.decode(type: 0x06, bytes: bytes([0, 255, 0])).mode, .off)
    }

    func testPositionalFeedbackAndFallback() {
        // Zones 0 and 1, strengths 1/8 and 8/8
        let effect = AdaptiveTriggerEffect.decode(type: 0x21, bytes: bytes([0b11, 0, 0b0011_1000, 0, 0, 0]))
        XCTAssertEqual(effect.mode, .positionalFeedback)
        XCTAssertEqual(Array(effect.positionalStrength.prefix(3)), [0.125, 1, 0])
        XCTAssertEqual(effect.startStrength, 1)
        XCTAssertEqual(effect.withoutPositionalModes().mode, .feedback)
        let slope = AdaptiveTriggerEffect.decode(type: 0x22, bytes: bytes([0b11, 0, 0b0011_1000]))
        XCTAssertEqual(slope.mode, .slopeFeedback)
        XCTAssertEqual(slope.withoutPositionalModes().mode, .weapon)
        XCTAssertEqual(slope.withoutPositionalModes().startStrength, 1)
    }
}
