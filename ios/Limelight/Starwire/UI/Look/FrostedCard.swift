//
//  FrostedCard.swift
//  Starwire
//
//  The frosted card: a rounded panel of translucent white over a blur, with a thin light border,
//  as Starwire for Android's cards (cg_pc_card, GPL-3.0): corners 22 points, white at 10 percent
//  (18 percent when focused) and, when focused, a 3 point white ring. Android has no blur and no
//  border on a card at rest; the material and the hairline are added here so a card still reads
//  over the bright parts of the starfield.
//
//      Text("GAMING-PC").frostedCard()
//      PCCard().frostedCard(cornerRadius: 22, focused: isFocused)
//
//  The card draws behind its content and always looks dark, whatever the system setting, since
//  Starwire's background is. It adds no accessibility of its own.
//

import SwiftUI

struct FrostedCardStyle: ViewModifier {
    var cornerRadius: CGFloat
    var focused: Bool
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        content
            .padding(padding)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(focused ? 0.18 : 0.10))
                }
                .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(focused ? 1 : 0.14), lineWidth: focused ? 3 : 1)
            }
            .contentShape(shape)
    }
}

extension View {
    /// Puts the view on a frosted card. `padding` is the space between the content and the
    /// card's edge (Android's PC card has 20).
    func frostedCard(cornerRadius: CGFloat = 22, focused: Bool = false, padding: CGFloat = 20) -> some View {
        modifier(FrostedCardStyle(cornerRadius: cornerRadius, focused: focused, padding: padding))
    }
}

private struct FrostedCardPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.14, green: 0.07, blue: 0.31), Color(red: 0.02, green: 0.016, blue: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Image(systemName: "desktopcomputer")
                        .font(.largeTitle)
                    Text("GAMING-PC")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frostedCard()

                Text("A card in focus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frostedCard(focused: true)

                Text("A small one, with large text that wraps onto a second line when it has to")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frostedCard(cornerRadius: 12, padding: 12)
                    .frame(maxWidth: 260)
            }
            .padding()
        }
    }
}

#Preview("Frosted cards") {
    FrostedCardPreview()
}
