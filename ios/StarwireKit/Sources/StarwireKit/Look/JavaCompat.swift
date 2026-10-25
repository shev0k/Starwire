import Foundation

// Java behaviour that Starwire for Android's look depends on (GPL-3.0). Android picks each
// game's colours and each tile's stars from `String.hashCode()` and a seeded `java.util.Random`,
// so the same game gets the same tile on iOS only if these are reproduced exactly.

enum JavaCompat {
    /// `String.hashCode()`: 31 * h + c over the UTF-16 code units, wrapping at 32 bits.
    static func hashCode(_ text: String) -> Int32 {
        var hash: Int32 = 0
        for unit in text.utf16 {
            hash = hash &* 31 &+ Int32(unit)
        }
        return hash
    }

    /// `String.toLowerCase(Locale.ROOT)`
    static func lowercased(_ text: String) -> String {
        text.lowercased()
    }

    /// `Math.floorMod(x, y)` for a positive `y`
    static func floorMod(_ x: Int32, _ y: Int32) -> Int32 {
        let remainder = x % y
        return remainder < 0 ? remainder + y : remainder
    }

    /// `Math.round(float)`: halves round up. Done in `Double`, where adding 0.5 is exact for a
    /// 32 bit float, so there's no early rounding.
    static func round(_ value: Float) -> Int {
        Int((Double(value) + 0.5).rounded(.down))
    }
}

/// `java.util.Random`: the same 48 bit generator and the same `nextFloat`/`nextInt(bound)`, so a
/// seed gives the numbers Android's code got.
struct JavaRandom {
    private var seed: UInt64
    private static let multiplier: UInt64 = 0x5DEECE66D
    private static let mask: UInt64 = (1 << 48) - 1

    /// `new Random(seed)`; a negative seed is a Java `long`, so pass it sign-extended.
    init(seed: Int64) {
        self.seed = (UInt64(bitPattern: seed) ^ JavaRandom.multiplier) & JavaRandom.mask
    }

    private mutating func next(_ bits: Int) -> Int32 {
        seed = (seed &* JavaRandom.multiplier &+ 0xB) & JavaRandom.mask
        return Int32(truncatingIfNeeded: Int64(bitPattern: seed >> UInt64(48 - bits)))
    }

    /// `nextFloat()`: 24 random bits over 2^24
    mutating func nextFloat() -> Float {
        Float(next(24)) / Float(1 << 24)
    }

    /// `nextInt(bound)` for a positive bound
    mutating func nextInt(_ bound: Int32) -> Int32 {
        var bits = next(31)
        let m = bound &- 1
        if bound & m == 0 {
            return Int32(truncatingIfNeeded: (Int64(bound) &* Int64(bits)) >> 31)
        }
        var value = bits % bound
        while bits &- value &+ m < 0 {
            bits = next(31)
            value = bits % bound
        }
        return value
    }
}
