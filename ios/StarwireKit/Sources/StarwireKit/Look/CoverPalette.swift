import Foundation

// The colour a game's cover gives the screen. Ported from Starwire for Android's CoverGlow.java
// (GPL-3.0): tintFromBitmap, tintFromPixels, deep and panel.
//
// The tint is the cover's most vivid colour: saturated pixels weigh most, so a dark cover with a
// red logo turns red rather than grey. `deep` darkens it for the background and `panel` for
// frosted panels, so white text stays readable on both. A cover with almost no colour gets the
// violet fallback.
//
// The HSV conversions follow Skia's SkRGBToHSV and SkHSVToColor, which Android's Color.colorToHSV
// and Color.HSVToColor call, in 32 bit floats. They have not been compared byte for byte with a
// device.

public struct CoverPalette: Equatable, Sendable {
    /// The cover's colour, at 0.85 brightness
    public var tint: RGBA
    /// The background behind everything: the tint, mostly darkened
    public var deep: RGBA
    /// Frosted panels and sheets: a little lighter than `deep`, nearly opaque
    public var panel: RGBA

    public init(tint: RGBA) {
        self.tint = tint
        deep = CoverPalette.deepColour(tint)
        panel = CoverPalette.panelColour(tint)
    }

    /// Violet, used before a cover has loaded or when a cover has no colour (DEFAULT_TINT)
    public static let defaultTint = RGBA(argb: 0xFF7C3AED)
    /// The palette to show with no cover
    public static let fallback = CoverPalette(tint: defaultTint)

    /// The size Android scales a cover to before it picks a colour
    public static let sampleWidth = 24
    public static let sampleHeight = 32

    /// The palette for a cover given as RGBA8 bytes (red, green, blue, alpha per pixel, rows from
    /// the top, no padding), `width` by `height`. Anything that isn't a whole picture gets the
    /// fallback. The bytes should be straight (not premultiplied) or opaque, as box art is.
    public static func from(width: Int, height: Int, rgba: [UInt8]) -> CoverPalette {
        guard let pixels = samplePixels(width: width, height: height, rgba: rgba) else {
            return fallback
        }
        return CoverPalette(tint: tintColour(fromPixels: pixels))
    }

    /// CoverGlow.tintFromBitmap's colour for a cover given as RGBA8 bytes
    public static func tintColour(width: Int, height: Int, rgba: [UInt8]) -> RGBA {
        from(width: width, height: height, rgba: rgba).tint
    }

    /// The cover scaled to 24 by 32 as 0xRRGGBB values, or nil if the bytes don't fit the size.
    /// Each small pixel is the average of the pixels it covers (a box filter; Android's bilinear
    /// filter gives close, not identical, values). A cover already 24 by 32 is used as it is.
    static func samplePixels(width: Int, height: Int, rgba: [UInt8]) -> [UInt32]? {
        guard width > 0, height > 0, width <= 1 << 15, height <= 1 << 15, rgba.count >= width * height * 4 else {
            return nil
        }
        var out: [UInt32] = []
        out.reserveCapacity(sampleWidth * sampleHeight)
        for ty in 0..<sampleHeight {
            let y0 = ty * height / sampleHeight
            let y1 = max(y0 + 1, (ty + 1) * height / sampleHeight)
            for tx in 0..<sampleWidth {
                let x0 = tx * width / sampleWidth
                let x1 = max(x0 + 1, (tx + 1) * width / sampleWidth)
                var red = 0, green = 0, blue = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let at = (y * width + x) * 4
                        red += Int(rgba[at])
                        green += Int(rgba[at + 1])
                        blue += Int(rgba[at + 2])
                    }
                }
                let count = (y1 - y0) * (x1 - x0)
                // Rounded to the nearest, so a flat colour stays exactly that colour
                out.append(UInt32((red + count / 2) / count) << 16 | UInt32((green + count / 2) / count) << 8
                            | UInt32((blue + count / 2) / count))
            }
        }
        return out
    }

    /// CoverGlow.tintFromPixels: the colour for these pixels, 0xRRGGBB each (alpha is ignored)
    public static func tintColour(fromPixels pixels: [UInt32]) -> RGBA {
        var x = 0.0, y = 0.0, weightSum = 0.0, satSum = 0.0
        for pixel in pixels {
            let hsv = rgbToHSV(red: Int((pixel >> 16) & 0xFF), green: Int((pixel >> 8) & 0xFF),
                               blue: Int(pixel & 0xFF))
            // Vivid, not-too-dark pixels decide the colour
            let weight = Double(hsv.s * hsv.s) * min(1.0, Double(hsv.v) * 1.5)
            if weight <= 0 {
                continue
            }
            // Hue is an angle, so average it as a direction
            let angle = Double(hsv.h) * .pi / 180
            x += cos(angle) * weight
            y += sin(angle) * weight
            weightSum += weight
            satSum += Double(hsv.s) * weight
        }
        if weightSum < Double(pixels.count) * 0.02 {
            // Almost no colour in the cover (black and white art)
            return defaultTint
        }
        let hue = Float((atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360))
        let saturation = Float(max(0.55, min(0.9, satSum / weightSum)))
        return hsvToColour(hue: hue, saturation: saturation, value: 0.85)
    }

    /// CoverGlow.deep
    public static func deepColour(_ tint: RGBA) -> RGBA {
        let c = tint.bytes
        return RGBA(red: darken(c.red, keep: 0.16, floor: 8), green: darken(c.green, keep: 0.16, floor: 8),
                    blue: darken(c.blue, keep: 0.16, floor: 8))
    }

    /// CoverGlow.panel: 0xF4 opaque
    public static func panelColour(_ tint: RGBA) -> RGBA {
        let c = tint.bytes
        return RGBA(red: darken(c.red, keep: 0.22, floor: 10), green: darken(c.green, keep: 0.22, floor: 10),
                    blue: darken(c.blue, keep: 0.22, floor: 10), alpha: 0xF4)
    }

    private static func darken(_ channel: Int, keep: Float, floor: Int) -> Int {
        JavaCompat.round(Float(channel) * keep + Float(floor))
    }

    // MARK: Colour conversions, as Skia does them

    /// SkRGBToHSV: hue in degrees, saturation and value from 0 to 1
    static func rgbToHSV(red: Int, green: Int, blue: Int) -> (h: Float, s: Float, v: Float) {
        let top = max(red, green, blue)
        let bottom = min(red, green, blue)
        let delta = top - bottom
        let value = Float(top) / 255
        if delta == 0 {
            return (0, 0, value)
        }
        let saturation = Float(delta) / Float(top)
        var hue: Float
        if red == top {
            hue = Float(green - blue) / Float(delta)
        } else if green == top {
            hue = 2 + Float(blue - red) / Float(delta)
        } else {
            hue = 4 + Float(red - green) / Float(delta)
        }
        hue *= 60
        if hue < 0 {
            hue += 360
        }
        return (hue, saturation, value)
    }

    /// SkHSVToColor with full opacity
    static func hsvToColour(hue: Float, saturation: Float, value: Float) -> RGBA {
        let s = min(max(saturation, 0), 1)
        let v = min(max(value, 0), 1)
        let top = JavaCompat.round(v * 255)
        if s < 1.0 / 4096 {
            return RGBA(red: top, green: top, blue: top)
        }
        let hx: Float = (hue < 0 || hue >= 360) ? 0 : hue / 60
        let whole = hx.rounded(.down)
        let fraction = hx - whole
        let p = JavaCompat.round((1 - s) * v * 255)
        let q = JavaCompat.round((1 - s * fraction) * v * 255)
        let t = JavaCompat.round((1 - s * (1 - fraction)) * v * 255)
        switch Int(whole) {
        case 0: return RGBA(red: top, green: t, blue: p)
        case 1: return RGBA(red: q, green: top, blue: p)
        case 2: return RGBA(red: p, green: top, blue: t)
        case 3: return RGBA(red: p, green: q, blue: top)
        case 4: return RGBA(red: t, green: p, blue: top)
        default: return RGBA(red: top, green: p, blue: q)
        }
    }
}
