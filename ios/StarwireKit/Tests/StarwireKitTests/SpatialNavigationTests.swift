import XCTest
@testable import StarwireKit

final class SpatialNavigationTests: XCTestCase {
    typealias Nav = SpatialNavigation
    typealias R = SpatialNavigation.Rect

    // A game screen: a Play button, a settings button to its right, and a row of four tiles below
    private let screen: [(id: String, frame: R)] = [
        ("play", R(x: 200, y: 280, width: 120, height: 50)),
        ("settings", R(x: 340, y: 280, width: 200, height: 50)),
        ("tile0", R(x: 40, y: 400, width: 120, height: 160)),
        ("tile1", R(x: 180, y: 400, width: 120, height: 160)),
        ("tile2", R(x: 320, y: 400, width: 120, height: 160)),
        ("tile3", R(x: 460, y: 400, width: 120, height: 160)),
    ]

    func testNothingHighlightedStartsTopLeft() {
        XCTAssertEqual(Nav.next(from: nil, direction: .down, targets: screen), "play")
        XCTAssertEqual(Nav.next(from: "gone", direction: .down, targets: screen), "play")
    }

    func testAlongARow() {
        XCTAssertEqual(Nav.next(from: "tile1", direction: .right, targets: screen), "tile2")
        XCTAssertEqual(Nav.next(from: "tile1", direction: .left, targets: screen), "tile0")
        XCTAssertNil(Nav.next(from: "tile0", direction: .left, targets: screen))
        XCTAssertNil(Nav.next(from: "tile3", direction: .right, targets: screen))
        XCTAssertEqual(Nav.next(from: "play", direction: .right, targets: screen), "settings")
    }

    func testStraightAheadWinsOverACloserOneToTheSide() {
        // Down from Play (x 200 to 320) lands on tile1 (180 to 300), which overlaps it
        XCTAssertEqual(Nav.next(from: "play", direction: .down, targets: screen), "tile1")
        XCTAssertEqual(Nav.next(from: "settings", direction: .down, targets: screen), "tile2")
        // Up from the far tiles goes to the button above them
        XCTAssertEqual(Nav.next(from: "tile3", direction: .up, targets: screen), "settings")
        XCTAssertEqual(Nav.next(from: "tile0", direction: .up, targets: screen), "play")
        XCTAssertNil(Nav.next(from: "play", direction: .up, targets: screen))
    }

    func testAGridMovesByColumn() {
        var grid: [(id: String, frame: R)] = []
        for row in 0..<3 {
            for column in 0..<4 {
                grid.append(("\(row)-\(column)", R(x: Double(column) * 100, y: Double(row) * 120, width: 90, height: 110)))
            }
        }
        XCTAssertEqual(Nav.next(from: "0-2", direction: .down, targets: grid), "1-2")
        XCTAssertEqual(Nav.next(from: "2-3", direction: .up, targets: grid), "1-3")
        XCTAssertNil(Nav.next(from: "2-1", direction: .down, targets: grid))
        XCTAssertEqual(Nav.next(from: "1-0", direction: .right, targets: grid), "1-1")
    }

    func testStickDirections() {
        XCTAssertNil(Nav.direction(x: 0.2, y: -0.3))
        XCTAssertEqual(Nav.direction(x: 0.9, y: 0.2), .right)
        XCTAssertEqual(Nav.direction(x: -0.7, y: 0.1), .left)
        XCTAssertEqual(Nav.direction(x: 0.1, y: 0.8), .up)
        XCTAssertEqual(Nav.direction(x: 0.3, y: -1), .down)
        // The d-pad gives exactly 1
        XCTAssertEqual(Nav.direction(x: 0, y: 1, threshold: 0.5), .up)
    }

    func testHoldingRepeatsAfterADelay() {
        var repeater = DirectionRepeater()
        XCTAssertEqual(repeater.update(.down, now: 10), .down)
        XCTAssertEqual(repeater.nextDeadline ?? 0, 10.4, accuracy: 1e-9)
        XCTAssertNil(repeater.update(.down, now: 10.2))
        XCTAssertEqual(repeater.update(.down, now: 10.4), .down)
        XCTAssertEqual(repeater.update(.down, now: 10.53), .down)
        XCTAssertNil(repeater.update(.down, now: 10.6))
        // Another direction presses at once
        XCTAssertEqual(repeater.update(.left, now: 10.61), .left)
        XCTAssertNil(repeater.update(nil, now: 10.7))
        XCTAssertNil(repeater.nextDeadline)
        XCTAssertEqual(repeater.update(.left, now: 10.8), .left)
    }
}
