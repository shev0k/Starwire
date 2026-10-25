//
//  StarwireLogo.swift
//  Starwire
//
//  The Starwire logo: a dark void inside a rainbow ring, a tilted orbit and a bright star on the
//  rim, with a soft violet glow behind. Ported from Starwire for Android's launcher icon
//  (sw_icon_foreground.xml, GPL-3.0), drawn in a Canvas from the same numbers. The ring's colours
//  come from StarwireKit's RainbowPalette.
//
//  The logo is the mark alone, with no background, and fits the space it is given. With
//  `animated` on, the rainbow slowly turns round the ring (one turn every 4 seconds), unless
//  `paused` is set or Reduce Motion is on. VoiceOver reads it as the Starwire logo.
//

import StarwireKit
import SwiftUI

struct StarwireLogo: View {
    var animated: Bool
    var paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(animated: Bool = false, paused: Bool = false) {
        self.animated = animated
        self.paused = paused
    }

    // The vector is drawn in a 108 unit square. Everything that shows lies within 22 to 86, so
    // the logo is cropped to that.
    private static let cropOrigin: CGFloat = 22
    private static let cropSize: CGFloat = 64
    private static let centre: CGFloat = 54

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated || paused || reduceMotion)) { timeline in
            let turn = (animated && !reduceMotion)
                ? RainbowPalette.ringAngle(at: timeline.date.timeIntervalSinceReferenceDate) : 0
            Canvas { context, size in
                Self.draw(in: &context, size: size, ringTurn: turn)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Starwire logo")
        .accessibilityAddTraits(.isImage)
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, ringTurn: Double) {
        let side = min(size.width, size.height)
        let unit = side / cropSize
        // Move the 108 unit drawing so the crop fills the square, centred in the space
        context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        context.scaleBy(x: unit, y: unit)
        context.translateBy(x: -cropOrigin, y: -cropOrigin)
        let middle = CGPoint(x: centre, y: centre)

        // Soft glow behind the ring
        let glow = Gradient(colors: [Color(look: RGBA(argb: 0x667C3AED)), Color(look: RGBA(argb: 0x007C3AED))])
        context.fill(Path(ellipseIn: circle(middle, radius: 32)),
                     with: .radialGradient(glow, center: middle, startRadius: 0, endRadius: 32))

        // The orbit, tilted 24 degrees to the left. The void is drawn over its middle.
        var tilted = context
        tilted.translateBy(x: middle.x, y: middle.y)
        tilted.rotate(by: .degrees(-24))
        tilted.stroke(Path(ellipseIn: CGRect(x: -31, y: -9.5, width: 62, height: 19)),
                      with: .color(Color(look: RGBA(argb: 0xB3C4B5FD))), lineWidth: 1.8)

        // The void
        context.fill(Path(ellipseIn: circle(middle, radius: 18)), with: .color(Color(look: RGBA(argb: 0xFF05040F))))

        // The ring, its rainbow sweeping clockwise from 3 o'clock
        let rainbow = Gradient(colors: RainbowPalette.stops.map { Color(look: $0) })
        context.stroke(Path(ellipseIn: circle(middle, radius: 21)),
                       with: .conicGradient(rainbow, center: middle, angle: .degrees(ringTurn)),
                       lineWidth: 5.5)

        // A star on the rim, with its glow
        let star = CGPoint(x: 69, y: 39)
        let starGlow = Gradient(colors: [Color(look: RGBA(argb: 0xCCFFFFFF)), Color(look: RGBA(argb: 0x00FFFFFF))])
        context.fill(Path(ellipseIn: circle(star, radius: 7)),
                     with: .radialGradient(starGlow, center: star, startRadius: 0, endRadius: 7))
        context.fill(Path(ellipseIn: circle(star, radius: 2.4)), with: .color(.white))
    }

    private static func circle(_ centre: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }
}

private extension Color {
    init(look colour: RGBA) {
        self.init(.sRGB, red: colour.r, green: colour.g, blue: colour.b, opacity: colour.a)
    }
}

#Preview("Still") {
    StarwireLogo()
        .frame(width: 160, height: 160)
        .padding()
        .background(Color(red: 0.02, green: 0.016, blue: 0.06))
}

#Preview("Turning") {
    StarwireLogo(animated: true)
        .frame(width: 240, height: 240)
        .padding()
        .background(Color(red: 0.02, green: 0.016, blue: 0.06))
}
