import XCTest
@testable import StarwireKit

final class ScrollPacerTests: XCTestCase {
    /// Deliveries at 108 a second against refreshes at 120: some refreshes get none
    func testEveryRefreshMovesWhenDeliveriesSkipOne() {
        let pacer = ScrollPacer()
        let sink = RecordingInputSink()
        var refreshesWithMovement = 0
        var nextDelivery = 0.0
        for frame in 0..<120 {
            let time = Double(frame) / 120
            while nextDelivery <= time {
                XCTAssertTrue(pacer.add(.scroll(amount: 12)))
                nextDelivery += 1.0 / 108
            }
            let events = pacer.tick()
            events.forEach(sink.send)
            if !events.isEmpty { refreshesWithMovement += 1 }
        }
        // Without spreading, 108 of 120 refreshes would move
        XCTAssertEqual(refreshesWithMovement, 120)
        let total = sink.events.reduce(0) { sum, event in
            if case .scroll(let amount) = event { return sum + amount }
            return sum
        }
        pacer.flush().forEach(sink.send)
        let all = sink.events.reduce(0) { sum, event in
            if case .scroll(let amount) = event { return sum + amount }
            return sum
        }
        XCTAssertEqual(all, 108 * 12, "nothing is lost (the last delivery's half came with the flush)")
        XCTAssertLessThanOrEqual(total, all)
    }

    func testHalfNowHalfAtTheNextRefresh() {
        let pacer = ScrollPacer()
        _ = pacer.add(.scroll(amount: 30))
        _ = pacer.add(.hScroll(amount: -10))
        XCTAssertEqual(pacer.tick(), [.scroll(amount: 15), .hScroll(amount: -5)])
        XCTAssertEqual(pacer.tick(), [.scroll(amount: 15), .hScroll(amount: -5)])
        XCTAssertEqual(pacer.tick(), [])
    }

    func testFractionsAreKept() {
        let pacer = ScrollPacer()
        _ = pacer.add(.scroll(amount: 3))
        XCTAssertEqual(pacer.tick(), [.scroll(amount: 1)])
        XCTAssertEqual(pacer.tick(), [.scroll(amount: 2)], "the two halves of 1.5 add up to 3")
    }

    func testWithoutSpreadingItAllGoesAtTheNextRefresh() {
        let pacer = ScrollPacer(spread: false)
        _ = pacer.add(.scroll(amount: 30))
        _ = pacer.add(.scroll(amount: 6))
        XCTAssertEqual(pacer.tick(), [.scroll(amount: 36)])
        XCTAssertEqual(pacer.tick(), [])
    }

    func testOtherPacketsAreNotTaken() {
        XCTAssertFalse(ScrollPacer().add(.mouseMove(dx: 1, dy: 1)))
    }
}
