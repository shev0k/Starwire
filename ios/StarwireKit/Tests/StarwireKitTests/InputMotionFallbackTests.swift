import XCTest
@testable import StarwireKit

final class InputMotionFallbackTests: XCTestCase {
    func testAndroidsAxisTable() {
        let v: (x: Float, y: Float, z: Float) = (1, 2, 3)
        let r0 = MotionFallback.controllerAxes(v, rotation: .r0)
        XCTAssertEqual([r0.x, r0.y, r0.z], [1, 3, -2])
        let r90 = MotionFallback.controllerAxes(v, rotation: .r90)
        XCTAssertEqual([r90.x, r90.y, r90.z], [-2, 3, -1])
        let r180 = MotionFallback.controllerAxes(v, rotation: .r180)
        XCTAssertEqual([r180.x, r180.y, r180.z], [-1, 3, 2])
        let r270 = MotionFallback.controllerAxes(v, rotation: .r270)
        XCTAssertEqual([r270.x, r270.y, r270.z], [2, 3, 1])
    }

    func testLyingFlatReadsGravityUpLikeAController() {
        // Face up on a table in landscape: Core Motion says -1 g on z
        let event = MotionFallback.accelerometerEvent(number: 0, g: (0, 0, -1), rotation: .r90)
        guard case .controllerMotion(0, .accelerometer, let x, let y, let z) = event else { return XCTFail() }
        XCTAssertEqual(x, 0, accuracy: 1e-6)
        XCTAssertEqual(y, 9.80665, accuracy: 1e-4, "a controller lying flat reads +1 g on y")
        XCTAssertEqual(z, 0, accuracy: 1e-6)
    }

    func testGyroIsInDegreesPerSecond() {
        let event = MotionFallback.gyroEvent(number: 0, radiansPerSecond: (0, 0, Double.pi), rotation: .r0)
        guard case .controllerMotion(0, .gyroscope, _, let y, _) = event else { return XCTFail() }
        XCTAssertEqual(y, 180, accuracy: 1e-3)
    }

    func testRateIsCapped() {
        XCTAssertEqual(MotionFallback.rate(requested: 1000), 200)
        XCTAssertEqual(MotionFallback.rate(requested: 100), 100)
        XCTAssertEqual(MotionFallback.rate(requested: 0), 0)
    }
}
