//
//  AppTileView.swift
//  Starwire
//
//  A game's tile: its cover if the PC sent one, else a tile of ours. Ported from Starwire for
//  Android's AppIcons.java and AppGridAdapter (GPL-3.0). Which tile comes from StarwireKit's
//  AppTileStyle, which decides it as Android does:
//
//  - Cover art: the PC's cover, filling the tile.
//  - Generated tile: the Starwire logo over deep space and a few stars, in the game's own colours,
//    with the name at the bottom. Games with no cover and Desktop get this one, and each name
//    gives its own take on it (where the ring's colours start, the orbit's tilt, where the moon
//    and the glow are).
//  - Icon tile: a gradient in the kind's colour with a faint grid and a white icon, with the name
//    at the bottom, for apps like Steam Big Picture. The icons are SF Symbols close to Android's.
//
//  The tile is 3 to 4 (box art proportions) and fills the width it is given; corners are 22
//  points. VoiceOver reads the game's name; the picture is not read. Whoever puts the tile in a
//  button adds the button trait. The hero beside the title hides the name with `showsName`.
//  `isSelected` draws the rainbow ring Android puts round the selected game; it turns unless
//  `paused` is set or Reduce Motion is on.
//

import StarwireKit
import SwiftUI
import UIKit

struct AppTileView: View {
    var name: String
    var cover: UIImage?
    var style: CoverStyle
    var showsName: Bool
    var isSelected: Bool
    var paused: Bool

    /// Android's cover corner radius (cg_cover)
    static let cornerRadius: CGFloat = 22

    init(name: String, cover: UIImage? = nil, style: CoverStyle = .missing, showsName: Bool = true,
         isSelected: Bool = false, paused: Bool = false) {
        self.name = name
        self.cover = cover
        self.style = style
        self.showsName = showsName
        self.isSelected = isSelected
        self.paused = paused
    }

    private var tile: AppTileKind {
        AppTileStyle.tile(forName: name, hasCoverArt: cover != nil, style: style)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                picture(size: geometry.size)
                if showsName, tile != .coverArt {
                    Text(name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .circular))
        }
        .aspectRatio(GeneratedTileLook.aspectRatio, contentMode: .fit)
        .overlay {
            if isSelected {
                SelectedRing(paused: paused)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    @ViewBuilder
    private func picture(size: CGSize) -> some View {
        switch tile {
        case .coverArt:
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        case .generated(let look):
            Canvas { context, canvasSize in
                Self.draw(look, in: &context, size: canvasSize)
            }
        case .icon(let look):
            ZStack {
                Canvas { context, canvasSize in
                    Self.draw(look, in: &context, size: canvasSize)
                }
                Image(systemName: Self.symbol(for: look.kind))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: min(size.width, size.height) * IconTileLook.iconSize,
                           height: min(size.width, size.height) * IconTileLook.iconSize)
                    .position(x: size.width / 2, y: size.height * IconTileLook.centreY)
            }
        }
    }

    // MARK: Icons

    /// The SF Symbol for a kind of app, standing in for Android's icon: a display for Desktop, a
    /// gamepad for the launchers, a folder, an arcade stick, a play triangle and a terminal. A
    /// symbol this iOS doesn't have gives way to the next one in the list.
    static func symbol(for kind: AppKind) -> String {
        let choices: [String]
        switch kind {
        case .desktop: choices = ["display", "desktopcomputer"]
        case .launcher, .game: choices = ["gamecontroller.fill", "gamecontroller"]
        case .library: choices = ["folder.fill", "folder"]
        case .retro: choices = ["arcade.stick", "gamecontroller.fill"]
        case .media: choices = ["play.fill", "play"]
        case .terminal: choices = ["terminal.fill", "terminal", "chevron.left.forwardslash.chevron.right"]
        }
        return choices.first { UIImage(systemName: $0) != nil } ?? "square"
    }

    // MARK: Drawing

    /// AppIcons.StarwireTile.draw
    private static func draw(_ look: GeneratedTileLook, in context: inout GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        let whole = CGRect(origin: .zero, size: size)

        // Deep space, with the game's glow in one corner and a fainter second colour in the other
        let space = Gradient(colors: [Color(look: look.spaceTop), Color(look: GeneratedTileLook.spaceBottom)])
        context.fill(Path(whole), with: .linearGradient(space, startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
        let glowAt = CGPoint(x: w * look.glowCentre.x, y: h * look.glowCentre.y)
        let glow = Gradient(colors: [Color(look: look.accent.withAlpha(GeneratedTileLook.glowAlpha)),
                                     Color(look: look.accent.withAlpha(0))])
        context.fill(Path(whole), with: .radialGradient(glow, center: glowAt, startRadius: 0,
                                                        endRadius: max(1, w * GeneratedTileLook.glowRadius)))
        let hazeAt = CGPoint(x: w * look.hazeCentre.x, y: h * look.hazeCentre.y)
        let haze = Gradient(colors: [Color(look: look.secondColour.withAlpha(GeneratedTileLook.hazeAlpha)),
                                     Color(look: look.secondColour.withAlpha(0))])
        context.fill(Path(whole), with: .radialGradient(haze, center: hazeAt, startRadius: 0,
                                                        endRadius: max(1, w * GeneratedTileLook.hazeRadius)))

        // Stars
        for star in look.stars {
            let radius = star.radius(tileWidth: w)
            let rect = CGRect(x: Double(star.x) * w - radius, y: Double(star.y) * h - radius,
                              width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(Double(star.alpha))))
        }

        // The logo. The orbit passes behind the void, then its front half crosses over it.
        let logo = look.logo(width: w, height: h)
        let centre = CGPoint(x: logo.centerX, y: logo.centerY)
        let orbit = Path(ellipseIn: CGRect(x: -logo.orbitRadiusX, y: -logo.orbitRadiusY,
                                           width: logo.orbitRadiusX * 2, height: logo.orbitRadiusY * 2))
        let orbitShading = GraphicsContext.Shading.color(Color(look: GeneratedTileLook.orbitColour))
        let moon = Path(ellipseIn: CGRect(x: logo.moonX - logo.moonRadius, y: logo.moonY - logo.moonRadius,
                                          width: logo.moonRadius * 2, height: logo.moonRadius * 2))
        let moonShading = GraphicsContext.Shading.color(Color(look: GeneratedTileLook.moonColour))

        var back = context
        back.translateBy(x: centre.x, y: centre.y)
        back.rotate(by: .degrees(logo.tilt))
        back.stroke(orbit, with: orbitShading, lineWidth: logo.orbitStroke)
        if !logo.moonInFront {
            back.fill(moon, with: moonShading)
        }

        context.fill(Path(ellipseIn: circle(centre, radius: logo.voidRadius)),
                     with: .color(Color(look: GeneratedTileLook.voidColour)))
        let rainbow = Gradient(colors: RainbowPalette.stops.map { Color(look: $0) })
        context.stroke(Path(ellipseIn: circle(centre, radius: logo.ringRadius)),
                       with: .conicGradient(rainbow, center: centre, angle: .degrees(logo.ringTurn)),
                       lineWidth: logo.ringStroke)

        var front = context
        front.translateBy(x: centre.x, y: centre.y)
        front.rotate(by: .degrees(logo.tilt))
        // Only the lower half of the orbit, which is the front
        front.clip(to: Path(CGRect(x: -logo.orbitRadiusX * 2, y: 0, width: logo.orbitRadiusX * 4,
                                   height: logo.orbitRadiusY * 2)))
        front.stroke(orbit, with: orbitShading, lineWidth: logo.orbitStroke)
        if logo.moonInFront {
            front.fill(moon, with: moonShading)
        }

        // The star on the rim, with its glow
        let star = CGPoint(x: logo.starX, y: logo.starY)
        let starGlow = Gradient(colors: [Color.white.opacity(Double(0xCC) / 255), Color.white.opacity(0)])
        context.fill(Path(ellipseIn: circle(star, radius: logo.starGlowRadius)),
                     with: .radialGradient(starGlow, center: star, startRadius: 0, endRadius: max(1, logo.starGlowRadius)))
        context.fill(Path(ellipseIn: circle(star, radius: logo.starCoreRadius)), with: .color(.white))
    }

    /// AppIcons.Tile.draw, without the icon (the icon is a symbol on top)
    private static func draw(_ look: IconTileLook, in context: inout GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        let whole = CGRect(origin: .zero, size: size)

        let fill = Gradient(colors: [Color(look: look.gradientStart), Color(look: look.gradientEnd)])
        context.fill(Path(whole), with: .linearGradient(fill, startPoint: .zero, endPoint: CGPoint(x: w, y: h)))

        // A faint HUD grid
        let step = IconTileLook.gridStep(width: w)
        var grid = Path()
        var x = step
        while x < w {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: h))
            x += step
        }
        var y = step
        while y < h {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: w, y: y))
            y += step
        }
        context.stroke(grid, with: .color(Color(look: IconTileLook.gridColour)), lineWidth: 1)

        // A soft sweep of light from the top left
        let sheen = Gradient(colors: [Color.white.opacity(IconTileLook.sheenAlpha), Color.white.opacity(0)])
        context.fill(Path(whole), with: .linearGradient(sheen, startPoint: .zero,
                                                        endPoint: CGPoint(x: w * IconTileLook.sheenReach,
                                                                          y: h * IconTileLook.sheenReach)))

        // A glow behind the icon
        let centre = CGPoint(x: w / 2, y: h * IconTileLook.centreY)
        let glow = Gradient(colors: [Color.white.opacity(IconTileLook.glowAlpha), Color.white.opacity(0)])
        context.fill(Path(whole), with: .radialGradient(glow, center: centre, startRadius: 0,
                                                        endRadius: max(1, w * IconTileLook.glowRadius)))
    }

    private static func circle(_ centre: CGPoint, radius: Double) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }
}

/// The ring round the selected game (Android's Rainbow.Ring): 3 points wide, its rainbow turning
/// once every 4 seconds, drawn just outside the tile.
private struct SelectedRing: View {
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused || reduceMotion)) { timeline in
            let turn = reduceMotion ? 0 : RainbowPalette.ringAngle(at: timeline.date.timeIntervalSinceReferenceDate)
            RoundedRectangle(cornerRadius: AppTileView.cornerRadius + 4, style: .circular)
                .strokeBorder(
                    AngularGradient(gradient: Gradient(colors: RainbowPalette.stops.map { Color(look: $0) }),
                                    center: .center, angle: .degrees(turn)),
                    lineWidth: 3)
                .padding(-7)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension Color {
    init(look colour: RGBA) {
        self.init(.sRGB, red: colour.r, green: colour.g, blue: colour.b, opacity: colour.a)
    }
}

private struct AppTilePreviewGrid: View {
    let names = ["Cyberpunk 2077", "Elden Ring", "Desktop", "Steam Big Picture", "Hollow Knight: Silksong",
                 "Playnite", "RetroArch", "YouTube", "PowerShell"]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 16) {
                ForEach(Array(names.enumerated()), id: \.offset) { entry in
                    AppTileView(name: entry.element, isSelected: entry.offset == 1, paused: true)
                }
            }
            .padding(24)
        }
        .background(Color(red: 0.04, green: 0.035, blue: 0.09))
    }
}

private struct AppTilePreviewCovers: View {
    private let cover = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { renderer in
        UIColor.systemTeal.setFill()
        renderer.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
    }

    var body: some View {
        HStack(spacing: 16) {
            AppTileView(name: "Some Game", cover: cover)
            AppTileView(name: "Hades II", showsName: false)
            AppTileView(name: "Steam", cover: cover, style: .never)
        }
        .padding()
        .background(Color(red: 0.04, green: 0.035, blue: 0.09))
    }
}

#Preview("Tiles") {
    AppTilePreviewGrid()
}

#Preview("Cover art and the hero") {
    AppTilePreviewCovers()
}
