//
//  ChipRow.swift
//  Starwire
//
//  The game screen's row of stream-setting chips ("HEVC", "1080p · 120 FPS", "HDR"). Ported from
//  Starwire for Android's cg_hero_chip and cg_chip drawables and its ChipRow (GPL-3.0): small
//  rounded labels, white 12 percent with a thin 22 percent white border, bold white text, 14 point
//  sides and 7 point tops, 8 points apart.
//
//  Android's row leaves out the chips that don't fit, so the header never grows taller. Here the
//  chips wrap onto another line instead, so every setting stays visible on a narrow screen. The
//  row lines up with the leading edge (the right edge in right to left languages) and its height
//  follows its content and Dynamic Type. VoiceOver reads each chip in order.
//

import SwiftUI

struct ChipRow: View {
    var chips: [String]
    var spacing: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection

    init(_ chips: [String], spacing: CGFloat = 8) {
        self.chips = chips
        self.spacing = spacing
    }

    var body: some View {
        WrappingLayout(spacing: spacing, rightToLeft: layoutDirection == .rightToLeft) {
            ForEach(Array(chips.enumerated()), id: \.offset) { entry in
                ChipLabel(text: entry.element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One chip
struct ChipLabel: View {
    var text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .circular)
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(shape.fill(Color.white.opacity(0.12)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Lays its children out left to right (right to left when asked), starting a new line when the
/// next one doesn't fit. Each line is as tall as its tallest child, with the others centred.
struct WrappingLayout: Layout {
    var spacing: CGFloat
    var rightToLeft: Bool

    private struct Arrangement {
        var frames: [CGRect] = []
        var size: CGSize = .zero
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in arrangement.frames.enumerated() {
            let x = rightToLeft ? bounds.maxX - frame.maxX : bounds.minX + frame.minX
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY + frame.minY), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    /// The chips' places counted from the leading edge. With no width to fit in (nil or
    /// infinite) they all go on one line.
    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        var limit = CGFloat.infinity
        if let width, width.isFinite {
            limit = width
        }
        let proposal = ProposedViewSize(width: limit.isFinite ? limit : nil, height: nil)
        var arrangement = Arrangement()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        var lineStart = 0

        // Centres the chips of the line that has just ended, by their heights
        func finishLine(upTo end: Int) {
            for index in lineStart..<end {
                arrangement.frames[index].origin.y = y + (lineHeight - arrangement.frames[index].height) / 2
            }
            lineStart = end
        }

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(proposal)
            if x > 0, x + size.width > limit {
                finishLine(upTo: index)
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            arrangement.frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width
            widest = max(widest, x)
            lineHeight = max(lineHeight, size.height)
            x += spacing
        }
        finishLine(upTo: subviews.count)
        arrangement.size = CGSize(width: widest, height: subviews.isEmpty ? 0 : y + lineHeight)
        return arrangement
    }
}

private struct ChipRowPreview: View {
    let chips = ["HEVC", "1080p · 120 FPS", "HDR"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ChipRow(chips)
            ChipRow(chips).frame(width: 220)
            ChipRow(chips).frame(width: 150)
            ChipRow(chips)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(width: 220)
            ChipRow(chips)
                .environment(\.dynamicTypeSize, .accessibility2)
        }
        .padding()
        .background(Color(red: 0.04, green: 0.035, blue: 0.09))
    }
}

#Preview("Chips") {
    ChipRowPreview()
}
