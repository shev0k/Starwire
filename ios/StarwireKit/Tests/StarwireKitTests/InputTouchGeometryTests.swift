import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import StarwireKit

final class InputTouchGeometryTests: XCTestCase {
    // The iPad 10th gen in landscape (1180x820 points) showing a 16:9 stream: bars top and bottom
    private let ipad = VideoGeometry(viewSize: CGSize(width: 1180, height: 820), streamSize: CGSize(width: 1920, height: 1080))

    func testFitsKeepingTheAspectRatio() {
        let rect = ipad.videoRect
        XCTAssertEqual(rect.width, 1180)
        XCTAssertEqual(rect.height, 663.75, accuracy: 0.001)
        XCTAssertEqual(rect.minY, (820 - 663.75) / 2, accuracy: 0.001)
        let tall = VideoGeometry(viewSize: CGSize(width: 1000, height: 1000), streamSize: CGSize(width: 2360, height: 1640))
        XCTAssertEqual(tall.videoRect.width, 1000)
        let narrow = VideoGeometry(viewSize: CGSize(width: 2000, height: 820), streamSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(narrow.videoRect.height, 820)
        XCTAssertEqual(narrow.videoRect.minX, (2000 - 820 * 16 / 9) / 2, accuracy: 0.001)
    }

    func testStretchFillsTheView() {
        var stretched = ipad
        stretched.stretch = true
        XCTAssertEqual(stretched.videoRect, CGRect(x: 0, y: 0, width: 1180, height: 820))
    }

    func testPointsMapToStreamPixelsAndClampToTheEdge() {
        let centre = ipad.streamPoint(CGPoint(x: 590, y: 410))
        XCTAssertEqual(centre.x, 960)
        XCTAssertEqual(centre.y, 540)
        let inBar = ipad.streamPoint(CGPoint(x: -20, y: 10))
        XCTAssertEqual(inBar.x, 0)
        XCTAssertEqual(inBar.y, 0)
        let corner = ipad.streamPoint(CGPoint(x: 5000, y: 5000))
        XCTAssertEqual(corner.x, 1919)
        XCTAssertEqual(corner.y, 1079)
        XCTAssertEqual(ipad.mousePosition(CGPoint(x: 590, y: 410)), .mousePosition(x: 960, y: 540, width: 1920, height: 1080))
    }

    func testZoomAndPanMoveThePicture() {
        var zoomed = ipad
        zoomed.zoom = 2
        XCTAssertEqual(zoomed.videoRect.width, 2360)
        // The view's centre still shows the picture's centre
        XCTAssertEqual(zoomed.streamPoint(CGPoint(x: 590, y: 410)).x, 960)
        zoomed.pan = CGPoint(x: 590, y: 0)
        // Panned right by half the view: the view's left edge shows the picture's left edge
        XCTAssertEqual(zoomed.streamPoint(CGPoint(x: 0, y: 410)).x, 0)
        XCTAssertEqual(zoomed.pixelsPerPoint, 1920.0 / 2360.0, accuracy: 1e-9)
    }

    func testClampKeepsThePictureOverTheView() {
        var geometry = ipad
        geometry.zoom = 0.5
        XCTAssertEqual(geometry.clamped().zoom, 1)
        geometry.zoom = 9
        XCTAssertEqual(geometry.clamped().zoom, 4)
        geometry.zoom = 2
        geometry.pan = CGPoint(x: 10_000, y: -10_000)
        let clamped = geometry.clamped()
        XCTAssertEqual(clamped.pan.x, (2360 - 1180) / 2)
        XCTAssertEqual(clamped.pan.y, -(663.75 * 2 - 820) / 2, accuracy: 0.001)
        XCTAssertEqual(clamped.videoRect.minX, 0, accuracy: 0.001)
    }

    func testAccumulatorKeepsFractions() {
        var accumulator = MouseAccumulator()
        XCTAssertNil(accumulator.add(dx: 0.4, dy: -0.4))
        XCTAssertNil(accumulator.add(dx: 0.4, dy: -0.4))
        XCTAssertEqual(accumulator.add(dx: 0.4, dy: -0.4), .mouseMove(dx: 1, dy: -1))
        XCTAssertEqual(accumulator.remainder.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(accumulator.remainder.y, -0.2, accuracy: 1e-9)
        XCTAssertEqual(accumulator.add(dx: 2.9, dy: 0), .mouseMove(dx: 3, dy: 0))
        // A thousand tiny moves add up to exactly the distance travelled
        var slow = MouseAccumulator()
        var total = 0
        for _ in 0..<1000 {
            if case .mouseMove(let dx, _) = slow.add(dx: 0.05, dy: 0) { total += dx }
        }
        XCTAssertEqual(total, 50)
    }

    func testPressureCurves() {
        XCTAssertEqual(PressureCurve.linear.value(at: 0.3), 0.3, accuracy: 0.001)
        XCTAssertEqual(PressureCurve.linear.value(at: 0), 0)
        XCTAssertEqual(PressureCurve.linear.value(at: 1), 1, accuracy: 0.001)
        XCTAssertGreaterThan(PressureCurve.soft.value(at: 0.25), 0.3)
        XCTAssertLessThan(PressureCurve.firm.value(at: 0.5), 0.45)
        // Curves rise steadily
        for curve in [PressureCurve.soft, .firm] {
            var last = -1.0
            for i in 0...20 {
                let v = curve.value(at: Double(i) / 20)
                XCTAssertGreaterThanOrEqual(v, last - 1e-6)
                last = v
            }
        }
        let calibrated = PressureCurve.calibrated(maxPressure: 0.6)
        XCTAssertEqual(calibrated.value(at: 0.6), 1, accuracy: 0.01)
        XCTAssertEqual(calibrated.value(at: 0.9), 1, accuracy: 0.001)
        XCTAssertEqual(PressureCurve(encoded: PressureCurve.soft.encoded), PressureCurve.soft)
        XCTAssertNil(PressureCurve(encoded: "nonsense"))
    }

    func testPencilEvents() {
        let input = PencilInput(curve: .linear)
        let upright = PencilSample(phase: .down, location: CGPoint(x: 590, y: 410), force: 0.5, altitude: .pi / 2, azimuth: .pi / 2)
        XCTAssertEqual(input.event(for: upright, geometry: ipad),
                       .pen(phase: .down, tool: .pen, buttons: 0, x: 0.5, y: 0.5, pressure: 0.5, rotation: 0, tilt: 0))
        // Tilted to 30 degrees from flat and pointing west: tilt 60, rotation 270... after the
        // force is corrected for the tilt (0.25 / sin 30 = 0.5)
        let tilted = PencilSample(phase: .move, location: CGPoint(x: 590, y: 410), force: 0.25, altitude: .pi / 6, azimuth: .pi)
        guard case .pen(_, _, _, _, _, let pressure, let rotation, let tilt) = input.event(for: tilted, geometry: ipad) else {
            return XCTFail("not a pen event")
        }
        XCTAssertEqual(pressure, 0.5, accuracy: 0.002)
        XCTAssertEqual(rotation, 90)
        XCTAssertEqual(tilt, 60)
        XCTAssertEqual(PencilInput.rotation(azimuth: 0), 270)
        let hover = PencilSample(phase: .hover, location: CGPoint(x: 0, y: 0), hoverDistance: 0.3)
        XCTAssertEqual(input.event(for: hover, geometry: ipad),
                       .pen(phase: .hover, tool: .pen, buttons: 0, x: 0, y: 0, pressure: 0.3, rotation: 270, tilt: 0))
        let noPressure = PencilInput(hasPressure: false)
        guard case .pen(_, _, _, _, _, let fixed, _, _) = noPressure.event(for: tilted, geometry: ipad) else { return XCTFail() }
        XCTAssertEqual(fixed, 1)
        let eraserUp = PencilSample(phase: .up, location: .zero, force: 0.9, eraser: true)
        guard case .pen(.up, .eraser, _, _, _, 0, _, _) = input.event(for: eraserUp, geometry: ipad) else { return XCTFail() }
    }
}
