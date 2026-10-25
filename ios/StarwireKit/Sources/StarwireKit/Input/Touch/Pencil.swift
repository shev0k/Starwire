import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Apple Pencil to pen events, with a pressure curve.
//
// PressureCurve is ported from VoidLink's PressureCurve.swift (GPL-3.0, True砖家 / The-Fried-Fish):
// a smooth curve through control points, built from cubic Bézier segments. VoidLink sells it as
// part of a paid pack; here it is always on. The angle conversions follow moonlight-ios's
// StreamView.m (GPL-3.0, Cameron Gutman). Barrel roll is left out: Vibeshine ignores it.

/// Maps the Pencil's pressure (0 to 1) to what is sent (0 to 1), through a curve the owner
/// shapes with control points. Two points, (0, 0) and (1, 1), is a straight line.
public struct PressureCurve: Equatable, Sendable {
    public private(set) var points: [CGPoint]
    private var segments: [Segment] = []

    private struct Segment: Equatable, Sendable {
        var p0: CGPoint, c1: CGPoint, c2: CGPoint, p1: CGPoint
    }

    /// Points must be sorted by x, from x = 0 to x = 1. Values are clamped to 0...1.
    public init(points: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]) {
        var clean = points.map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }.sorted { $0.x < $1.x }
        if clean.count < 2 {
            clean = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]
        }
        self.points = clean
        segments = Self.buildSegments(clean)
    }

    public static let linear = PressureCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
    /// More output for a light touch.
    public static let soft = PressureCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.5), CGPoint(x: 1, y: 1)])
    /// Needs a firmer press for the same output.
    public static let firm = PressureCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.6, y: 0.35), CGPoint(x: 1, y: 1)])

    /// The curves offered by name, in the order the settings show them.
    public static let presets: [(name: String, curve: PressureCurve)] = [("Linear", .linear), ("Soft", .soft), ("Firm", .firm)]

    /// A curve from a calibration stroke, as VoidLink makes one: if the hardest press in the
    /// stroke was below 1, that press already gives full output.
    public static func calibrated(maxPressure: Double) -> PressureCurve {
        let top = min(max(maxPressure, 0), 1)
        guard top > 0, top < 1 else { return .linear }
        return PressureCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: top, y: 1), CGPoint(x: top, y: 1), CGPoint(x: 1, y: 1)])
    }

    public func value(at x: Double) -> Double {
        guard let first = points.first, CGFloat(x) >= first.x else { return 0 }
        if points == Self.linear.points {
            return min(max(x, 0), 1)
        }
        let xc = CGFloat(min(max(x, 0), 1))
        if xc == first.x {
            return Double(first.y)
        }
        for seg in segments where xc >= seg.p0.x && xc <= seg.p1.x {
            let t = Self.solveT(forX: xc, seg.p0.x, seg.c1.x, seg.c2.x, seg.p1.x)
            return Double(min(max(Self.cubic(seg.p0.y, seg.c1.y, seg.c2.y, seg.p1.y, t), 0), 1))
        }
        return Double(segments.last?.p1.y ?? 0)
    }

    /// Saved as "x,y;x,y;..." in the settings store.
    public var encoded: String {
        points.map { String(format: "%.4f,%.4f", Double($0.x), Double($0.y)) }.joined(separator: ";")
    }

    public init?(encoded: String) {
        let pairs = encoded.split(separator: ";").map { $0.split(separator: ",").compactMap { Double($0) } }
        guard pairs.count >= 2, pairs.allSatisfy({ $0.count == 2 }) else { return nil }
        self.init(points: pairs.map { CGPoint(x: $0[0], y: $0[1]) })
    }

    public static func == (lhs: PressureCurve, rhs: PressureCurve) -> Bool {
        lhs.points == rhs.points
    }

    // The curve passes through the first and last points and the midpoints between the inner
    // ones; tangents come from the neighbouring points, scaled by a factor fitted to the number
    // of inner points (VoidLink's constants).
    private static func buildSegments(_ polyline: [CGPoint]) -> [Segment] {
        var cuts = [polyline[0]]
        if polyline.count > 3 {
            for i in 0..<(polyline.count - 3) {
                cuts.append(CGPoint(x: (polyline[i + 1].x + polyline[i + 2].x) / 2, y: (polyline[i + 1].y + polyline[i + 2].y) / 2))
            }
        }
        cuts.append(polyline[polyline.count - 1])
        let inner = polyline.count - 2
        let factor: CGFloat = inner > 0 ? 0.30538319 * pow(CGFloat(inner), -2.1518917) + 0.36128348 : 2.0 / 3.0
        var segments: [Segment] = []
        for i in 0..<(cuts.count - 1) {
            let p0 = cuts[i], p1 = cuts[i + 1]
            let tangentStart = i < polyline.count - 1
                ? CGPoint(x: (polyline[i + 1].x - polyline[i].x) * factor, y: (polyline[i + 1].y - polyline[i].y) * factor) : .zero
            let tangentEnd = i + 1 < polyline.count - 1
                ? CGPoint(x: (polyline[i + 2].x - polyline[i + 1].x) * factor, y: (polyline[i + 2].y - polyline[i + 1].y) * factor) : .zero
            segments.append(Segment(p0: p0, c1: CGPoint(x: p0.x + tangentStart.x, y: p0.y + tangentStart.y),
                                    c2: CGPoint(x: p1.x - tangentEnd.x, y: p1.y - tangentEnd.y), p1: p1))
        }
        return segments
    }

    private static func solveT(forX x: CGFloat, _ p0: CGFloat, _ c1: CGFloat, _ c2: CGFloat, _ p1: CGFloat) -> CGFloat {
        var low: CGFloat = 0, high: CGFloat = 1, t: CGFloat = 0.5
        for _ in 0..<18 {
            t = (low + high) / 2
            if cubic(p0, c1, c2, p1, t) < x { low = t } else { high = t }
        }
        return t
    }

    private static func cubic(_ p0: CGFloat, _ c1: CGFloat, _ c2: CGFloat, _ p1: CGFloat, _ t: CGFloat) -> CGFloat {
        let mt = 1 - t
        return mt * mt * mt * p0 + 3 * mt * mt * t * c1 + 3 * mt * t * t * c2 + t * t * t * p1
    }
}

/// One Pencil sample, as UIKit reports it.
public struct PencilSample: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case down, move, up, cancel
        /// Hovering above the screen (iPad Pro with a Pencil that supports it)
        case hover
        case hoverEnded
    }

    public var phase: Phase
    /// The point in the stream view, in points.
    public var location: CGPoint
    /// `force / maximumPossibleForce`, 0 to 1. 0 for hover.
    public var force: Double
    /// Radians: 0 lying flat, pi/2 upright.
    public var altitude: Double
    /// Radians, as `azimuthAngle(in:)` gives it: 0 pointing right (east), clockwise.
    public var azimuth: Double
    /// Hover height (`zOffset`, 0 to 1), when hovering.
    public var hoverDistance: Double
    public var eraser: Bool

    public init(phase: Phase, location: CGPoint, force: Double = 0, altitude: Double = .pi / 2, azimuth: Double = 0,
                hoverDistance: Double = 0, eraser: Bool = false) {
        self.phase = phase
        self.location = location
        self.force = force
        self.altitude = altitude
        self.azimuth = azimuth
        self.hoverDistance = hoverDistance
        self.eraser = eraser
    }
}

/// Turns Pencil samples into pen events. Needs a host with pen support
/// (`LI_FF_PEN_TOUCH_EVENTS`); without it the app treats the Pencil as a finger.
public struct PencilInput: Sendable {
    public var curve: PressureCurve
    /// Pencils without pressure (the USB-C one) report a fixed force; this sends full pressure
    /// while touching instead.
    public var hasPressure: Bool

    public init(curve: PressureCurve = .linear, hasPressure: Bool = true) {
        self.curve = curve
        self.hasPressure = hasPressure
    }

    public func event(for sample: PencilSample, geometry: VideoGeometry) -> InputEvent {
        let p = geometry.normalized(sample.location)
        let tool: PenTool = sample.eraser ? .eraser : .pen
        let rotation = Self.rotation(azimuth: sample.azimuth)
        let tilt = Self.tilt(altitude: sample.altitude)
        let phase: TouchPhase
        var pressure: Double
        switch sample.phase {
        case .down: phase = .down
        case .move: phase = .move
        case .up: phase = .up
        case .cancel: phase = .cancel
        case .hover: phase = .hover
        case .hoverEnded: phase = .hoverLeave
        }
        switch sample.phase {
        case .hover, .hoverEnded:
            pressure = min(max(sample.hoverDistance, 0), 1)
        case .up, .cancel:
            pressure = 0
        case .down, .move:
            if hasPressure {
                // The Pencil reports less force when tilted; moonlight-ios divides by the sine of
                // the altitude to undo that.
                let raw = sample.force / max(sin(sample.altitude), 0.1)
                pressure = curve.value(at: min(max(raw, 0), 1))
            } else {
                pressure = 1
            }
        }
        return .pen(phase: phase, tool: tool, buttons: 0, x: Double(p.x), y: Double(p.y), pressure: pressure,
                    rotation: rotation, tilt: tilt)
    }

    /// iOS's azimuth is 0 pointing east; the host wants 0 pointing north, clockwise, in degrees.
    public static func rotation(azimuth: Double) -> Int {
        var degrees = Int(((azimuth - .pi / 2) * 180 / .pi).rounded(.towardZero))
        degrees %= 360
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// iOS's altitude is 0 lying flat; the host wants a tilt of 0 upright, up to 90.
    public static func tilt(altitude: Double) -> Int {
        let degrees = min(abs(Int((altitude * 180 / .pi).rounded())), 90)
        return 90 - degrees
    }
}
