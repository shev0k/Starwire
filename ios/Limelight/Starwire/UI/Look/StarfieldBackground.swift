//
//  StarfieldBackground.swift
//  Starwire
//
//  Starwire's space background: deep space with soft nebula clouds and small stars, a few of
//  which twinkle. Ported from Starwire for Android's StarfieldView.java and the glow in AppView
//  (GPL-3.0). The stars, clouds and animation come from StarwireKit's StarfieldModel.
//
//  Give it a CoverPalette and the background takes the cover's colour: the space turns to the
//  palette's deep colour and a soft light of its tint drifts in the top right corner, fading to
//  the new colour over 0.6 seconds when the cover changes. With no palette it is plain deep
//  space; pass CoverPalette.fallback for the game screen's violet before a cover has loaded.
//
//  Set `paused` while streaming. With Reduce Motion on, the stars hold still. The whole
//  background is hidden from VoiceOver.
//

import StarwireKit
import SwiftUI

struct StarfieldBackground: View {
    /// Android's plain background colour (cg_settings_background), used with no cover palette
    static let plainSpace = RGBA(argb: 0xFF0A0918)
    /// How long the colour takes to change to a new cover's (AppView.animateTint)
    static let tintSeconds = 0.6

    var cover: CoverPalette?
    var paused: Bool

    init(cover: CoverPalette? = nil, paused: Bool = false) {
        self.cover = cover
        self.paused = paused
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(look: cover?.deep ?? Self.plainSpace))
                if let cover {
                    StarfieldGlow(tint: cover.tint, paused: paused)
                }
                StarfieldSky(size: geometry.size, paused: paused)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .animation(.easeInOut(duration: Self.tintSeconds), value: cover)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The light in the top right corner, tinted with the cover's colour. It drifts slowly while
/// animations are allowed (AppView's glowAnimator).
private struct StarfieldGlow: View {
    let tint: RGBA
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused || reduceMotion)) { timeline in
            GeometryReader { geometry in
                let drift = reduceMotion ? 0 : StarfieldModel.glowDrift(at: timeline.date.timeIntervalSinceReferenceDate)
                let radius = StarfieldModel.Glow.gradientRadius
                let diameter = StarfieldModel.Glow.diameter
                let scale = 1 + (StarfieldModel.Glow.driftScale - 1) * drift
                // The light is a flat tint seen through a white gradient, so the tint can fade
                Rectangle()
                    .fill(Color(look: tint))
                    .animation(.easeInOut(duration: StarfieldBackground.tintSeconds), value: tint)
                    .mask(
                        RadialGradient(
                            stops: [
                                .init(color: .white.opacity(StarfieldModel.Glow.innerAlpha), location: 0),
                                .init(color: .white.opacity(StarfieldModel.Glow.middleAlpha), location: 0.5),
                                .init(color: .white.opacity(0), location: 1),
                            ],
                            center: .center, startRadius: 0, endRadius: radius)
                    )
                    .frame(width: radius * 2, height: radius * 2)
                    .scaleEffect(scale)
                    .opacity(StarfieldModel.Glow.opacity)
                    // The circle's right edge is 200 past the screen's, its top 300 above it
                    .position(x: geometry.size.width - StarfieldModel.Glow.offsetRight - diameter / 2
                                + StarfieldModel.Glow.driftX * drift,
                              y: StarfieldModel.Glow.offsetTop + diameter / 2 + StarfieldModel.Glow.driftY * drift)
            }
        }
    }
}

/// The nebula clouds and the stars, in one Canvas
private struct StarfieldSky: View {
    let model: StarfieldModel
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(size: CGSize, paused: Bool) {
        model = StarfieldModel(width: Double(size.width), height: Double(size.height))
        self.paused = paused
    }

    var body: some View {
        // The twinkle takes seven seconds, so 30 frames a second is plenty
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused || reduceMotion)) { timeline in
            let angle = reduceMotion ? 0 : StarfieldModel.twinkleAngle(at: timeline.date.timeIntervalSinceReferenceDate)
            Canvas { context, size in
                for cloud in StarfieldModel.clouds {
                    let centre = CGPoint(x: cloud.x * size.width, y: cloud.y * size.height)
                    let radius = max(1, cloud.radius * max(size.width, size.height))
                    let gradient = Gradient(colors: [Color(look: cloud.colour), Color(look: cloud.colour.withAlpha(0))])
                    let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(rect),
                                 with: .radialGradient(gradient, center: centre, startRadius: 0, endRadius: radius))
                }
                for star in model.stars {
                    let alpha = StarfieldModel.alpha(of: star, angle: angle)
                    let radius = CGFloat(star.radius)
                    let rect = CGRect(x: CGFloat(star.x) * size.width - radius, y: CGFloat(star.y) * size.height - radius,
                                      width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(look: star.colour).opacity(alpha)))
                }
            }
        }
    }
}

private extension Color {
    init(look colour: RGBA) {
        self.init(.sRGB, red: colour.r, green: colour.g, blue: colour.b, opacity: colour.a)
    }
}

#Preview("Plain space") {
    StarfieldBackground()
}

#Preview("Cover colour") {
    StarfieldBackground(cover: CoverPalette(tint: RGBA(argb: 0xFF22C55E)))
}

#Preview("Paused, default tint") {
    StarfieldBackground(cover: .fallback, paused: true)
}
