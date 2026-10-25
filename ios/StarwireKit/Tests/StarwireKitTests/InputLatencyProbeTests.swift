import XCTest
@testable import StarwireKit

final class InputLatencyProbeTests: XCTestCase {
    private let frame = 1.0 / 120

    func testLatencyRunsFromTheFirstPacketToTheFrameThatShowsTheFlip() {
        let probe = InputLatencyProbe()
        probe.frame(at: 0, input: 0.06, scroll: 0.06)
        probe.sent(at: 0.010)
        probe.sent(at: 0.018) // the same input still on its way: not a new start
        probe.frame(at: 0.030, input: 0.06, scroll: 0.06)
        probe.frame(at: 0.048, input: 0.92, scroll: 0.06)
        XCTAssertEqual(probe.result.inputLatencies.count, 1)
        XCTAssertEqual(probe.result.inputLatencies[0], 0.038, accuracy: 1e-9)

        // A flip back with nothing sent is the page's own and isn't measured
        probe.frame(at: 0.060, input: 0.06, scroll: 0.06)
        XCTAssertEqual(probe.result.inputLatencies.count, 1)
    }

    func testHDRWhiteCountsAsWhite() {
        let probe = InputLatencyProbe()
        probe.frame(at: 0, input: 0.06, scroll: 0.06)
        probe.sent(at: 0)
        probe.frame(at: 0.04, input: 0.55, scroll: 0.06)
        XCTAssertEqual(probe.result.inputLatencies.count, 1)
    }

    func testAListMovingEveryFrameIsFullySmooth() {
        let probe = InputLatencyProbe()
        probe.frame(at: 0, input: 0, scroll: 0)
        probe.sent(at: 0.001)
        var white = false
        for i in 1...30 {
            white.toggle()
            probe.frame(at: Double(i) * frame, input: 0, scroll: white ? 1 : 0)
        }
        let result = probe.result
        XCTAssertEqual(result.smoothness, 1, accuracy: 1e-9)
        XCTAssertEqual(result.scrollLatencies.count, 1)
        XCTAssertEqual(result.scrollLatencies[0], frame - 0.001, accuracy: 1e-9)
    }

    func testAListMovingEveryOtherFrameIsHalfSmoothAndRunsAreSeparate() {
        let probe = InputLatencyProbe()
        probe.frame(at: 0, input: 0, scroll: 0)
        var white = false
        var t = 0.0
        for i in 1...21 {
            t = Double(i) * frame
            if i % 2 == 1 { white.toggle() }
            probe.frame(at: t, input: 0, scroll: white ? 1 : 0)
        }
        XCTAssertEqual(probe.result.smoothness, 0.5, accuracy: 1e-9)

        // Half a second at rest, then a second run that moves every frame: its start is timed again
        for i in 1...60 {
            probe.frame(at: t + Double(i) * frame, input: 0, scroll: white ? 1 : 0)
        }
        t += 0.5
        probe.sent(at: t)
        for i in 1...21 {
            white.toggle()
            probe.frame(at: t + Double(i) * frame, input: 0, scroll: white ? 1 : 0)
        }
        let result = probe.result
        XCTAssertEqual(result.scrollLatencies.count, 1, "the first run had no packet to time from")
        XCTAssertEqual(result.scrollFrames, 20 + 20)
        XCTAssertEqual(result.scrollFlips, 10 + 20)
        XCTAssertEqual(result.smoothness, 0.75, accuracy: 1e-9)
    }

    func testTheLine() {
        var summary = InputLatencyProbe.Summary()
        summary.inputLatencies = [0.030, 0.040, 0.050]
        summary.scrollLatencies = [0.120]
        summary.scrollFrames = 100
        summary.scrollFlips = 98
        XCTAssertEqual(summary.line, "Latency probe: input 40 ms median, 50 ms p95 (n 3); scroll shown 120 ms median (n 1); "
                       + "list moved in 98% of frames")
    }
}
