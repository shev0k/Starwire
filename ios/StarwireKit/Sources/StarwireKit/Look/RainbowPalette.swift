import Foundation

// Starwire's one flourish: a slowly flowing rainbow (blue, purple, pink, orange), used only on
// the wordmark and the ring around the selected game. Ported from Starwire for Android's
// Rainbow.java (GPL-3.0). With animations off (Reduce Motion) the colours stay put: pass time 0.
//
// No UIKit, SwiftUI or CoreGraphics: the colours and the phase are numbers, the app draws them.

public enum RainbowPalette {
    /// The colours, evenly spaced; the last repeats the first so the flow loops without a seam
    public static let stops: [RGBA] = ([0xFF0894FF, 0xFFC959DD, 0xFFFF2E54, 0xFFFF9004, 0xFF0894FF] as [UInt32])
        .map { RGBA(argb: $0) }

    /// The wordmark's colours make one trip across it in this many seconds
    public static let textLoopSeconds = 6.0
    /// The ring's colours make one turn in this many seconds
    public static let ringLoopSeconds = 4.0
    /// The wordmark's gradient is this many times as wide as the text (one repeat of the colours)
    public static let textSpanFactor = 2.0

    /// The colour at `position` along the colours, where 0 is the first stop and 1 the last.
    /// Positions past that wrap round, so it works for any phase. Blends between neighbouring
    /// stops in sRGB, as Android's gradients do.
    public static func colour(at position: Double) -> RGBA {
        let wrapped = position - position.rounded(.down)
        let segments = Double(stops.count - 1)
        let scaled = wrapped * segments
        let index = min(Int(scaled.rounded(.down)), stops.count - 2)
        let t = scaled - Double(index)
        let from = stops[index]
        let to = stops[index + 1]
        return RGBA(r: from.r + (to.r - from.r) * t, g: from.g + (to.g - from.g) * t,
                    b: from.b + (to.b - from.b) * t, a: from.a + (to.a - from.a) * t)
    }

    /// How far the wordmark's colours have flowed at `time` seconds, from 0 up to but not
    /// including 1: a fraction of one repeat of the colours (`textSpanFactor` text widths), moving
    /// to the right.
    public static func textPhase(at time: TimeInterval) -> Double {
        fraction(time / textLoopSeconds)
    }

    /// The angle the ring's sweep has turned to at `time` seconds, in degrees from 0 up to but not
    /// including 360, clockwise on screen. The sweep starts at 3 o'clock.
    public static func ringAngle(at time: TimeInterval) -> Double {
        fraction(time / ringLoopSeconds) * 360
    }

    private static func fraction(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}
