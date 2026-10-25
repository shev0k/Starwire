import Foundation

/// Measures input to picture on a stream of ios/scripts/input-latency.html: the page flips one
/// square black or white each time it gets input (wheel, pointer or touch) and a second square
/// each time its list scrolls. The app reads both squares' brightness from every decoded frame.
///
/// - Latency: from the first packet sent after the last flip to the frame that shows the flip.
///   It covers the PC taking the input, capture, encoding, the network and decoding; showing the
///   frame adds about one refresh more.
/// - Smoothness: while the list scrolls, the share of frames whose second square flipped. A list
///   that moves every frame scores 1; one that moves every other frame 0.5.
///
/// Thread safe: packets are noted on the main thread, frames on the decoder's.
public final class InputLatencyProbe: @unchecked Sendable {
    /// Brightness (0 to 1, the luma code over its maximum) above which a square is white. Low
    /// enough for SDR white in an HDR (PQ) stream, which sits near 0.55.
    public static let threshold = 0.3
    /// Where the squares' centres are, as fractions of the picture (the page's 10vw squares)
    public static let inputSquare = (x: 0.05, y: 0.05)
    public static let scrollSquare = (x: 0.15, y: 0.05)
    /// A scroll run ends when the list hasn't moved for this long
    public static let runGap: TimeInterval = 0.25

    public struct Summary: Equatable, Sendable {
        public var inputLatencies: [TimeInterval] = []
        public var scrollLatencies: [TimeInterval] = []
        /// Frames during scroll runs, and those that showed the list moved
        public var scrollFrames = 0
        public var scrollFlips = 0

        public var smoothness: Double { scrollFrames > 0 ? Double(scrollFlips) / Double(scrollFrames) : 0 }

        static func percentile(_ values: [TimeInterval], _ p: Double) -> TimeInterval {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            return sorted[min(Int((Double(sorted.count - 1) * p).rounded()), sorted.count - 1)]
        }

        /// "Latency probe: input 38 ms median, 52 ms p95 (n 40); scroll shown 120 ms median (n 12); list moved in 98% of frames"
        public var line: String {
            String(format: "Latency probe: input %.0f ms median, %.0f ms p95 (n %d); scroll shown %.0f ms median (n %d); "
                   + "list moved in %.0f%% of frames",
                   Self.percentile(inputLatencies, 0.5) * 1000, Self.percentile(inputLatencies, 0.95) * 1000,
                   inputLatencies.count, Self.percentile(scrollLatencies, 0.5) * 1000, scrollLatencies.count,
                   smoothness * 100)
        }
    }

    private let lock = NSLock()
    private var inputWhite: Bool?
    private var scrollWhite: Bool?
    private var inputPending: TimeInterval?
    private var scrollPending: TimeInterval?
    private var lastScrollFlip: TimeInterval?
    private var runFrames = 0
    private var runFlips = 0
    private var summary = Summary()

    public init() {}

    /// A packet that the page reacts to went to the PC.
    public func sent(at now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if inputPending == nil { inputPending = now }
        if scrollPending == nil { scrollPending = now }
    }

    /// A decoded frame, with its two squares' brightness (0 to 1).
    public func frame(at now: TimeInterval, input: Double, scroll: Double) {
        lock.lock()
        defer { lock.unlock() }
        let inputNow = input > Self.threshold
        let scrollNow = scroll > Self.threshold
        defer {
            inputWhite = inputNow
            scrollWhite = scrollNow
        }
        guard let lastInput = inputWhite, let lastScroll = scrollWhite else { return }

        if inputNow != lastInput, let since = inputPending {
            summary.inputLatencies.append(now - since)
            inputPending = nil
        }

        let scrolled = scrollNow != lastScroll
        if let last = lastScrollFlip, now - last > Self.runGap {
            endRun()
        }
        if scrolled {
            if lastScrollFlip == nil, let since = scrollPending {
                // The first frame of a run: how long the list took to start moving
                summary.scrollLatencies.append(now - since)
            }
            scrollPending = nil
            lastScrollFlip = now
            // The frames since the last flip, and this one
            runFrames += framesSinceFlip + 1
            runFlips += 1
            framesSinceFlip = 0
        } else if lastScrollFlip != nil {
            framesSinceFlip += 1
        }
    }

    /// A run counts from its first flip to its last; a lone flip says nothing about smoothness.
    private func endRun() {
        if runFlips > 1 {
            summary.scrollFrames += runFrames - 1
            summary.scrollFlips += runFlips - 1
        }
        runFrames = 0
        runFlips = 0
        framesSinceFlip = 0
        lastScrollFlip = nil
    }

    private var framesSinceFlip = 0

    /// What was measured, with a scroll run still going counted as ended.
    public var result: Summary {
        lock.lock()
        defer { lock.unlock() }
        var copy = summary
        if runFlips > 1 {
            copy.scrollFrames += runFrames - 1
            copy.scrollFlips += runFlips - 1
        }
        return copy
    }
}
