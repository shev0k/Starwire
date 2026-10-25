import Foundation

// Starwire's background: soft purple and blue nebula clouds with a field of small stars, a few
// of which slowly twinkle. Ported from Starwire for Android's StarfieldView.java (GPL-3.0). The
// stars are placed from a fixed seed with `java.util.Random`, so the sky is the same every time
// and the first stars are the same at any size.
//
// Android places the stars in pixels and counts them per megapixel; here sizes are in points,
// which is what the app draws in. The drift of the glow behind everything is from AppView.java.
//
// No UIKit, SwiftUI or CoreGraphics: the model holds numbers, the app draws them, and the
// animation is a function of the time passed in.

/// One star. `x` and `y` are fractions of the view's width and height.
public struct Star: Equatable, Sendable {
    public var x: Float
    public var y: Float
    /// In points
    public var radius: Float
    /// Opaque; the star's opacity comes from `StarfieldModel.alpha(of:at:)`
    public var colour: RGBA
    /// Where in its twinkle the star starts, in radians
    public var phase: Float
    public var twinkles: Bool
}

/// A soft cloud: a radial gradient from `colour` at the centre to nothing at the edge
public struct NebulaCloud: Equatable, Sendable {
    /// Fractions of the view's width and height
    public var x: Double
    public var y: Double
    /// A fraction of the view's longer side
    public var radius: Double
    /// With the cloud's peak opacity in its alpha
    public var colour: RGBA
}

public struct StarfieldModel: Equatable, Sendable {
    public static let seed: Int64 = 0x7015
    public static let starsPerMegapixel = 110
    public static let minimumStars = 40
    /// One full twinkle
    public static let twinkleSeconds = 7.0
    /// How opaque a star is that doesn't twinkle
    public static let steadyAlpha = 0.55
    public static let starColours: [RGBA] = ([0xFFFFFFFF, 0xFFE9D5FF, 0xFFBFDBFE, 0xFFFDE68A] as [UInt32])
        .map { RGBA(argb: $0) }

    /// A violet cloud top left, a magenta one bottom right and a faint blue one mid left
    public static let clouds: [NebulaCloud] = [
        NebulaCloud(x: 0.12, y: 0.18, radius: 0.55, colour: RGBA(argb: 0x387C3AED)),
        NebulaCloud(x: 0.88, y: 0.92, radius: 0.50, colour: RGBA(argb: 0x26C026D3)),
        NebulaCloud(x: 0.30, y: 0.75, radius: 0.40, colour: RGBA(argb: 0x1A2563EB)),
    ]

    /// The light behind everything (R.drawable.cg_glow, `coverGlow` in activity_app_view.xml), in
    /// points: a circle 720 across whose right edge is 200 past the screen's right edge and whose
    /// top is 300 above the screen's top. Its gradient is white at 0x99 in the middle, 0x33 halfway
    /// out to `gradientRadius` and nothing from there, tinted with the cover's colour, at 0.45
    /// opacity. The gradient is centred on the circle.
    public enum Glow {
        public static let diameter = 720.0
        public static let gradientRadius = 320.0
        public static let offsetRight = -200.0
        public static let offsetTop = -300.0
        public static let opacity = 0.45
        public static let innerAlpha = Double(0x99) / 255
        public static let middleAlpha = Double(0x33) / 255
        /// It drifts 30 left and 21 down while growing to 1.08 times its size, and back
        public static let driftX = -30.0
        public static let driftY = 21.0
        public static let driftScale = 1.08
        public static let driftSeconds = 4.5
    }

    public let width: Double
    public let height: Double
    public let stars: [Star]

    /// How many stars a view this size gets: 110 per megapixel, and at least 40
    public static func starCount(width: Double, height: Double) -> Int {
        max(minimumStars, Int(width * height * Double(starsPerMegapixel) / 1_000_000))
    }

    /// The stars for a view `width` by `height` points
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
        var random = JavaRandom(seed: StarfieldModel.seed)
        var list: [Star] = []
        let count = StarfieldModel.starCount(width: width, height: height)
        list.reserveCapacity(count)
        for _ in 0..<count {
            let x = random.nextFloat()
            let y = random.nextFloat()
            // Mostly tiny stars, a few brighter ones
            let size = random.nextFloat()
            let radius = 0.35 + size * size * size * 1.4
            let phase = random.nextFloat() * Float(Double.pi * 2)
            let colour = StarfieldModel.starColours[Int(random.nextInt(Int32(StarfieldModel.starColours.count)))]
            let twinkles = random.nextFloat() < 0.18
            list.append(Star(x: x, y: y, radius: radius, colour: colour, phase: phase, twinkles: twinkles))
        }
        stars = list
    }

    // MARK: Animation, as functions of time

    /// Where the twinkle is at `time` seconds, in radians from 0 to 2π
    public static func twinkleAngle(at time: TimeInterval) -> Double {
        fraction(time / twinkleSeconds) * Double.pi * 2
    }

    /// The star's opacity at `time` seconds. A star that twinkles swings between 0.35 and 0.95.
    public static func alpha(of star: Star, at time: TimeInterval) -> Double {
        alpha(of: star, angle: twinkleAngle(at: time))
    }

    /// The star's opacity for a twinkle angle in radians. With Reduce Motion on, pass 0: the
    /// stars hold still, as Android's do with animations off.
    public static func alpha(of star: Star, angle: Double) -> Double {
        guard star.twinkles else {
            return steadyAlpha
        }
        return 0.35 + 0.6 * (0.5 + 0.5 * sin(angle + Double(star.phase)))
    }

    /// How far the glow has drifted at `time` seconds, 0 (home) to 1 (furthest). It eases each
    /// way over 4.5 seconds and comes back, like an animator that reverses.
    public static func glowDrift(at time: TimeInterval) -> Double {
        let cycle = fraction(time / (Glow.driftSeconds * 2))
        let linear = cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2
        // Android's accelerate-decelerate interpolator
        return cos((linear + 1) * Double.pi) / 2 + 0.5
    }

    /// The part after the point, for a time or a count that may be negative
    static func fraction(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}
