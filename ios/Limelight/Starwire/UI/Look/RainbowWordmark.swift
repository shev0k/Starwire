//
//  RainbowWordmark.swift
//  Starwire
//
//  The "Starwire" wordmark: heavy white-weight lettering painted with the flowing rainbow (blue,
//  purple, pink, orange). Ported from Starwire for Android's Rainbow.applyTo and the game
//  screen's cgWordmark (GPL-3.0): sans serif black at 26 points, letters drawn 1 percent of
//  their size closer, and a gradient two text widths long that flows to the right, once round
//  every 6 seconds. The colours and the flow come from StarwireKit's RainbowPalette.
//
//  The flow stops while `paused` is set or Reduce Motion is on. The text grows with Dynamic
//  Type and has no fixed height. VoiceOver reads it as a heading.
//

import StarwireKit
import SwiftUI

struct RainbowWordmark: View {
    var text: String
    var paused: Bool
    @ScaledMetric(relativeTo: .title) private var fontSize: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: String = "Starwire", paused: Bool = false) {
        self.text = text
        self.paused = paused
    }

    private var label: Text {
        Text(text)
            .font(.system(size: fontSize, weight: .black))
            .kerning(-0.01 * fontSize)
    }

    var body: some View {
        label
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            // The invisible text gives the wordmark its size; the rainbow shows through the letters
            .opacity(0)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused || reduceMotion)) { timeline in
                        let phase = reduceMotion ? 0 : RainbowPalette.textPhase(at: timeline.date.timeIntervalSinceReferenceDate)
                        rainbow(width: geometry.size.width, height: geometry.size.height, phase: phase)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
                .mask {
                    label
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }

    /// The colours over a strip four text widths wide (two repeats), moved so that at phase 0 the
    /// first colour is at the start of the text and, as the phase grows, the colours move right.
    private func rainbow(width: CGFloat, height: CGFloat, phase: Double) -> some View {
        let stops = RainbowPalette.stops
        var gradientStops: [Gradient.Stop] = []
        for repeatIndex in 0..<2 {
            for (index, colour) in stops.enumerated() where repeatIndex == 0 || index > 0 {
                let position = (Double(repeatIndex) + Double(index) / Double(stops.count - 1)) / 2
                gradientStops.append(Gradient.Stop(color: Color(look: colour), location: position))
            }
        }
        let span = width * RainbowPalette.textSpanFactor
        return Rectangle()
            .fill(LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing))
            .frame(width: span * 2, height: height)
            .offset(x: span * phase - span)
    }
}

private extension Color {
    init(look colour: RGBA) {
        self.init(.sRGB, red: colour.r, green: colour.g, blue: colour.b, opacity: colour.a)
    }
}

#Preview("Wordmark") {
    RainbowWordmark()
        .padding()
        .background(Color(red: 0.04, green: 0.035, blue: 0.09))
}

#Preview("Large type, paused") {
    RainbowWordmark(paused: true)
        .padding()
        .background(Color(red: 0.04, green: 0.035, blue: 0.09))
        .environment(\.dynamicTypeSize, .accessibility3)
}
