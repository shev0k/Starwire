import Foundation

// Colours for Starwire's look. Ported from Starwire for Android's colour handling in AppIcons.java
// and CoverGlow.java (GPL-3.0): colours there are packed ARGB ints, here they are `RGBA` with
// each channel from 0 to 1. `argb` converts back, so a colour can be compared with Android's
// hex value (like 0xFF7C3AED).

public struct RGBA: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// From Android's packed 0xAARRGGBB
    public init(argb: UInt32) {
        self.init(r: Double((argb >> 16) & 0xFF) / 255, g: Double((argb >> 8) & 0xFF) / 255,
                  b: Double(argb & 0xFF) / 255, a: Double((argb >> 24) & 0xFF) / 255)
    }

    /// From 8 bit channels
    public init(red: Int, green: Int, blue: Int, alpha: Int = 255) {
        self.init(r: Double(red) / 255, g: Double(green) / 255, b: Double(blue) / 255, a: Double(alpha) / 255)
    }

    /// Back to Android's packed 0xAARRGGBB, rounding each channel
    public var argb: UInt32 {
        func byte(_ value: Double) -> UInt32 { UInt32(min(255, max(0, (value * 255).rounded()))) }
        return byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// The same colour with another opacity
    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: alpha)
    }

    /// The 8 bit channels (red, green, blue), as Android's Color.red/green/blue give them
    var bytes: (red: Int, green: Int, blue: Int) {
        let packed = argb
        return (Int((packed >> 16) & 0xFF), Int((packed >> 8) & 0xFF), Int(packed & 0xFF))
    }

    /// AppIcons.blend: moves each channel from this colour towards `other` by `amount` (0 to 1),
    /// in 32 bit floats and rounded half up like Java's Math.round, and gives an opaque colour.
    public func blended(with other: RGBA, amount: Float) -> RGBA {
        let from = bytes
        let to = other.bytes
        let keep = Float(1) - amount
        func mix(_ a: Int, _ b: Int) -> Int { JavaCompat.round(Float(a) * keep + Float(b) * amount) }
        return RGBA(red: mix(from.red, to.red), green: mix(from.green, to.green), blue: mix(from.blue, to.blue))
    }
}
