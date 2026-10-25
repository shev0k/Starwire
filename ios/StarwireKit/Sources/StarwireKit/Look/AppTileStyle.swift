import Foundation

// Which tile a game gets, and how a generated tile looks. Ported from Starwire for Android's
// AppIcons.java (GPL-3.0): kindFor, accentFor, hasNoCoverArt, useIcon, tile and the Starwire
// tile's constructor (StarwireTile) and layout. Colours and the numbers that vary from tile to
// tile come from the same hash and the same `java.util.Random` calls, in the same order, so a
// game has the same colours and the same logo placement on iOS as on Android.
//
// No UIKit, SwiftUI or CoreGraphics here: the app draws the tile from these values.

/// What kind of app a name looks like (AppIcons.Kind). Each kind but `game` has an accent colour.
public enum AppKind: String, CaseIterable, Sendable {
    case desktop, launcher, library, retro, media, terminal, game

    /// The kind's own colour; games have none (their colour comes from their name)
    public var accent: RGBA? {
        switch self {
        case .desktop: return RGBA(argb: 0xFF3B82F6)
        case .launcher: return RGBA(argb: 0xFF06B6D4)
        case .library: return RGBA(argb: 0xFF8B5CF6)
        case .retro: return RGBA(argb: 0xFFF97316)
        case .media: return RGBA(argb: 0xFFEC4899)
        case .terminal: return RGBA(argb: 0xFF22C55E)
        case .game: return nil
        }
    }
}

/// The "cover_style" setting (AppIcons.PREF_COVER_STYLE)
public enum CoverStyle: String, CaseIterable, Sendable {
    /// Our tiles only for the apps hosts add themselves, and for games with no cover
    case missing
    /// Our tiles for every app
    case always
    /// Always the PC's cover, if it has one
    case never
}

/// Where a generated tile's logo lands in a tile of a given size (all in the tile's own units).
/// Angles are in degrees, clockwise on screen. The ring's colours start `ringTurn` degrees round,
/// the orbit is tilted by `tilt` and the moon sits `moonAngle` round it.
public struct LogoPlacement: Equatable, Sendable {
    public var centerX: Double
    public var centerY: Double
    /// The logo's unit: the void is 0.34 of it, the ring 0.39, the orbit 0.6 by 0.18
    public var scale: Double
    public var ringTurn: Double
    public var tilt: Double
    public var moonAngle: Double

    public var voidRadius: Double { scale * 0.34 }
    public var ringRadius: Double { scale * 0.39 }
    public var ringStroke: Double { scale * 0.1 }
    public var orbitRadiusX: Double { scale * 0.6 }
    public var orbitRadiusY: Double { scale * 0.18 }
    public var orbitStroke: Double { max(1, scale * 0.022) }
    public var moonRadius: Double { scale * 0.055 }
    /// The moon's place on the orbit, before the orbit is tilted (relative to the logo's centre)
    public var moonX: Double { orbitRadiusX * cos(moonAngle * .pi / 180) }
    public var moonY: Double { orbitRadiusY * sin(moonAngle * .pi / 180) }
    /// The lower half of the orbit is its front, which crosses over the void
    public var moonInFront: Bool { moonY >= 0 }
    /// The star on the rim, and its glow
    public var starX: Double { centerX + scale * 0.27 }
    public var starY: Double { centerY - scale * 0.27 }
    public var starGlowRadius: Double { scale * 0.2 }
    public var starCoreRadius: Double { scale * 0.07 }
}

/// One star on a generated tile; `x` and `y` are fractions of the tile's width and height.
public struct TileStar: Equatable, Sendable {
    public var x: Float
    public var y: Float
    /// The radius as a fraction of the tile's width; no smaller than `TileStar.minimumRadius`
    public var radiusFraction: Float
    public var alpha: Float

    /// In the tile's own units (pixels on Android)
    public static let minimumRadius: Float = 0.6

    public func radius(tileWidth: Double) -> Double {
        max(Double(TileStar.minimumRadius), tileWidth * Double(radiusFraction))
    }
}

/// A generated Starwire tile (AppIcons.StarwireTile): the logo over deep space with a few stars,
/// and a glow in the game's colour. Each game's name picks its own take on it.
public struct GeneratedTileLook: Equatable, Sendable {
    public var accent: RGBA
    /// A second, fainter colour in the glow's opposite corner
    public var secondColour: RGBA
    /// The space's colour at the top left; it fades to `spaceBottom`
    public var spaceTop: RGBA
    public var ringTurn: Float
    public var tilt: Float
    public var moonAngle: Float
    public var shiftX: Float
    public var shiftY: Float
    public var size: Float
    /// 0 to 3. Bit 0 clear puts the glow on the right, bit 1 clear puts it at the top.
    public var glowCorner: Int
    public var stars: [TileStar]

    /// The bottom right of the space
    public static let spaceBottom = RGBA(argb: 0xFF05040F)
    /// The void behind the ring
    public static let voidColour = RGBA(argb: 0xFF05040F)
    public static let moonColour = RGBA(argb: 0xFFF3EEFF)
    public static let orbitColour = RGBA(argb: 0xB3C4B5FD)
    /// The tile's box art proportions, width over height, for tiles drawn as covers (300 by 400)
    public static let aspectRatio = 3.0 / 4.0

    /// The glow's centre as fractions of the tile
    public var glowCentre: (x: Double, y: Double) {
        (glowCorner & 1 == 0 ? 0.8 : 0.2, glowCorner & 2 == 0 ? 0.12 : 0.88)
    }
    /// The haze's centre: the opposite corner
    public var hazeCentre: (x: Double, y: Double) {
        (1 - glowCentre.x, 1 - glowCentre.y)
    }
    /// The glow's and haze's radii as fractions of the tile's width
    public static let glowRadius = 0.85
    public static let hazeRadius = 0.7
    /// How opaque each is at its centre (0x66 and 0x38 of 255); both fade to nothing
    public static let glowAlpha = Double(0x66) / 255
    public static let hazeAlpha = Double(0x38) / 255

    /// Where the logo lands in a tile of this size
    public func logo(width: Double, height: Double) -> LogoPlacement {
        LogoPlacement(centerX: width / 2 + width * Double(shiftX),
                      centerY: height * (0.42 + Double(shiftY)),
                      scale: min(width, height) * 0.5 * Double(size),
                      ringTurn: Double(ringTurn), tilt: Double(tilt), moonAngle: Double(moonAngle))
    }

    /// The tile's look for this game. The look and the stars come from the name's hash (not its
    /// lower case form, as on Android), so the same game always has the same sky.
    public init(name: String?) {
        let accent = AppTileStyle.accent(forName: name)
        let seed = Int64(name.map(JavaCompat.hashCode) ?? 0)
        self.init(accent: accent, seed: seed)
    }

    /// AppIcons.StarwireTile's constructor and onBoundsChange, with the seed it was given
    init(accent: RGBA, seed: Int64) {
        let accents = AppTileStyle.gameAccents
        var look = JavaRandom(seed: seed &* 31 &+ 17)
        ringTurn = look.nextFloat() * 360
        tilt = -12 - look.nextFloat() * 24
        moonAngle = look.nextFloat() * 360
        shiftX = (look.nextFloat() - 0.5) * 0.1
        shiftY = (look.nextFloat() - 0.5) * 0.06
        size = 0.92 + look.nextFloat() * 0.12
        glowCorner = Int(look.nextInt(4))
        let starCount = 20 + Int(look.nextInt(14))
        let second = accents[Int(look.nextInt(Int32(accents.count)))]
        if second == accent {
            // The same colour twice: take another one (this draws one more number, as on Android)
            secondColour = accents[(Int(look.nextInt(Int32(accents.count - 1))) + 1) % accents.count]
        } else {
            secondColour = second
        }
        spaceTop = RGBA(argb: 0xFF24124F).blended(with: accent, amount: 0.1 + look.nextFloat() * 0.16)
        self.accent = accent

        // The same stars every time for the same app: x, y, radius, alpha
        var random = JavaRandom(seed: seed)
        var list: [TileStar] = []
        for _ in 0..<starCount {
            let x = random.nextFloat()
            let y = random.nextFloat()
            let radius = 0.003 + random.nextFloat() * 0.006
            let alpha = 0.3 + random.nextFloat() * 0.6
            list.append(TileStar(x: x, y: y, radiusFraction: radius, alpha: alpha))
        }
        stars = list
    }
}

/// The icon tile for apps like Steam Big Picture (AppIcons.Tile): a gradient in the kind's
/// colour with a faint grid, a soft sweep of light and a glow behind a white icon.
public struct IconTileLook: Equatable, Sendable {
    public var kind: AppKind
    public var accent: RGBA
    /// The gradient's two ends, from the top left to the bottom right
    public var gradientStart: RGBA
    public var gradientEnd: RGBA

    /// The grid is 0x14 white, 1 unit wide
    public static let gridColour = RGBA(argb: 0x14FFFFFF)
    /// The sheen runs from the top left to 0.6 of the way across and down, 0x22 white to nothing
    public static let sheenAlpha = Double(0x22) / 255
    public static let sheenReach = 0.6
    /// The glow is 0x55 white at its centre, 0.5 of the width in radius, fading to nothing
    public static let glowAlpha = Double(0x55) / 255
    public static let glowRadius = 0.5
    /// The icon and the glow centre at 0.42 of the height; the icon is 0.42 of the shorter side
    public static let centreY = 0.42
    public static let iconSize = 0.42

    public init(kind: AppKind, accent: RGBA) {
        self.kind = kind
        self.accent = accent
        gradientStart = accent.blended(with: RGBA(argb: 0xFFFFFFFF), amount: 0.08)
        gradientEnd = accent.blended(with: RGBA(argb: 0xFF000000), amount: 0.62)
    }

    /// The grid's spacing for a tile this wide
    public static func gridStep(width: Double) -> Double {
        max(8, width / 8)
    }
}

/// Which tile a game shows
public enum AppTileKind: Equatable, Sendable {
    /// The cover the PC sent
    case coverArt
    /// The Starwire tile: logo over deep space, in the game's own colours
    case generated(GeneratedTileLook)
    /// A designed icon tile for a kind of app (Steam Big Picture, a launcher, a terminal)
    case icon(IconTileLook)
}

public enum AppTileStyle {
    /// Colours for games shown as tiles, picked by name so each keeps its colour (GAME_ACCENTS)
    public static let gameAccents: [RGBA] = ([
        0xFFE11D48, 0xFFF97316, 0xFFEAB308, 0xFF22C55E, 0xFF14B8A6, 0xFF3B82F6, 0xFF8B5CF6, 0xFFEC4899,
    ] as [UInt32]).map { RGBA(argb: $0) }

    /// The apps hosts add themselves, which come without real cover art. Matched by their exact
    /// names, so games with similar words in their titles keep their covers (BUILT_IN_APPS).
    static let builtInApps: Set<String> = [
        "desktop", "virtual desktop", "remote desktop", "steam", "steam big picture", "big picture",
        "playnite", "playnite fullscreen", "terminal", "powershell",
    ]

    /// AppIcons.kindFor: the first group whose words the (lower case) name contains wins
    public static func kind(forName name: String?) -> AppKind {
        let lower = JavaCompat.lowercased(name ?? "")
        func has(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }
        if has(["desktop", "remote", "windows"]) { return .desktop }
        if has(["steam", "big picture", "xbox", "game pass"]) { return .launcher }
        if has(["playnite", "launchbox", "gog", "epic", "ubisoft", "battle.net", "ea app", "library", "launcher"]) {
            return .library
        }
        if has(["retroarch", "emulat", "dolphin", "pcsx", "rpcs3", "cemu", "yuzu", "ryujinx", "ppsspp",
                "duckstation", "mame", "es-de", "emulationstation"]) {
            return .retro
        }
        if has(["youtube", "netflix", "plex", "jellyfin", "kodi", "vlc", "spotify", "twitch", "browser",
                "chrome", "firefox", "media"]) {
            return .media
        }
        if has(["terminal", "powershell", "cmd"]) { return .terminal }
        return .game
    }

    /// AppIcons.accentFor: the kind's colour, or for a game one of `gameAccents` picked by the
    /// hash of its lower case name.
    public static func accent(forName name: String?) -> RGBA {
        if let accent = kind(forName: name).accent {
            return accent
        }
        let hash = name.map { JavaCompat.hashCode(JavaCompat.lowercased($0)) } ?? 0
        return gameAccents[Int(JavaCompat.floorMod(hash, Int32(gameAccents.count)))]
    }

    /// AppIcons.hasNoCoverArt
    public static func hasNoCoverArt(name: String?) -> Bool {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return builtInApps.contains(JavaCompat.lowercased(trimmed))
    }

    /// AppIcons.useIcon: whether this app shows a tile of ours instead of the PC's cover
    public static func usesIcon(name: String?, style: CoverStyle = .missing) -> Bool {
        switch style {
        case .always: return true
        case .never: return false
        case .missing: return hasNoCoverArt(name: name)
        }
    }

    /// AppIcons.tile: the tile for an app that shows ours. Desktop and plain games get the
    /// Starwire tile; the other kinds get an icon tile.
    public static func ownTile(forName name: String?) -> AppTileKind {
        let appKind = kind(forName: name)
        if appKind == .desktop || appKind == .game {
            return .generated(GeneratedTileLook(name: name))
        }
        return .icon(IconTileLook(kind: appKind, accent: accent(forName: name)))
    }

    /// Which tile an app shows, as the app grid decides it: our own tile when `usesIcon`, else the
    /// PC's cover if it has one, else the Starwire tile (CachedAppAssetLoader's missing cover).
    public static func tile(forName name: String?, hasCoverArt: Bool, style: CoverStyle = .missing) -> AppTileKind {
        if usesIcon(name: name, style: style) {
            return ownTile(forName: name)
        }
        return hasCoverArt ? .coverArt : .generated(GeneratedTileLook(name: name))
    }
}
