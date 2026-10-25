import XCTest
@testable import StarwireKit

// Tests for Starwire's look (Sources/StarwireKit/Look). The expected numbers for the hash, the
// colours and the stars were not worked out by hand: each was printed by a small Java program
// that holds a verbatim copy of Starwire for Android's AppIcons.StarwireTile constructor,
// accentFor, blend and StarfieldView's star loop, run with a real java.util.Random (Java 26;
// Random's algorithm is fixed by its specification, so Android's gives the same numbers). The
// cases ported from Android's AppIconsTest and CoverGlowTest are named as they are there.
final class LookTests: XCTestCase {
    // MARK: Java behaviour

    func testStringHashCodeMatchesJava() {
        XCTAssertEqual(JavaCompat.hashCode(""), 0)
        XCTAssertEqual(JavaCompat.hashCode("a"), 97)
        XCTAssertEqual(JavaCompat.hashCode("Desktop"), -1073207300)
        XCTAssertEqual(JavaCompat.hashCode("Cyberpunk 2077"), 488801379)
        XCTAssertEqual(JavaCompat.hashCode("cyberpunk 2077"), 1490794563)
        // UTF-16 code units: the emoji is two of them
        XCTAssertEqual(JavaCompat.hashCode("\u{1F3AE} Game"), 1534535808)
        XCTAssertEqual(JavaCompat.hashCode("\u{C9}lan"), 6094896)
    }

    func testRandomMatchesJava() {
        var random = JavaRandom(seed: 42)
        XCTAssertEqual(random.nextInt(4), 2)
        XCTAssertEqual(random.nextInt(7), 5)
        XCTAssertEqual(random.nextInt(8), 5)
        XCTAssertEqual(random.nextFloat(), 0.0479393)
        // A negative seed is sign-extended, as a Java long
        var negative = JavaRandom(seed: -123456789)
        XCTAssertEqual(negative.nextFloat(), 0.3357827)
        XCTAssertEqual(negative.nextInt(14), 5)
    }

    func testRoundGoesHalfUp() {
        XCTAssertEqual(JavaCompat.round(2.5), 3)
        XCTAssertEqual(JavaCompat.round(2.4999), 2)
        XCTAssertEqual(JavaCompat.round(0), 0)
    }

    // MARK: Colours

    func testRGBAKeepsAndroidsPackedValue() {
        for packed: UInt32 in [0xFF7C3AED, 0xFF000000, 0xFFFFFFFF, 0xB3C4B5FD, 0x00123456] {
            XCTAssertEqual(RGBA(argb: packed).argb, packed)
        }
        XCTAssertEqual(RGBA(argb: 0xFF0894FF).r, 8.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(RGBA(argb: 0x80FFFFFF).a, 128.0 / 255, accuracy: 1e-12)
    }

    func testBlendRoundsLikeAndroid() {
        // 0.5 of the way from black to white is 127.5, which Math.round takes up
        XCTAssertEqual(RGBA(argb: 0xFF000000).blended(with: RGBA(argb: 0xFFFFFFFF), amount: 0.5).argb, 0xFF808080)
        XCTAssertEqual(RGBA(argb: 0xFF123456).blended(with: RGBA(argb: 0xFF123456), amount: 0.3).argb, 0xFF123456)
    }

    // MARK: Which tile (AppIconsTest)

    func testKindsByName() {
        XCTAssertEqual(AppTileStyle.kind(forName: "Desktop"), .desktop)
        XCTAssertEqual(AppTileStyle.kind(forName: "Remote Desktop"), .desktop)
        XCTAssertEqual(AppTileStyle.kind(forName: "Steam Big Picture"), .launcher)
        XCTAssertEqual(AppTileStyle.kind(forName: "Xbox"), .launcher)
        XCTAssertEqual(AppTileStyle.kind(forName: "Playnite Fullscreen"), .library)
        XCTAssertEqual(AppTileStyle.kind(forName: "Epic Games Launcher"), .library)
        XCTAssertEqual(AppTileStyle.kind(forName: "RetroArch"), .retro)
        XCTAssertEqual(AppTileStyle.kind(forName: "ES-DE"), .retro)
        XCTAssertEqual(AppTileStyle.kind(forName: "YouTube"), .media)
        XCTAssertEqual(AppTileStyle.kind(forName: "PowerShell"), .terminal)
        XCTAssertEqual(AppTileStyle.kind(forName: "Elden Ring"), .game)
        XCTAssertEqual(AppTileStyle.kind(forName: ""), .game)
        XCTAssertEqual(AppTileStyle.kind(forName: nil), .game)
    }

    // Desktop is checked before the launchers, so "Steam Desktop" is a desktop
    func testTheFirstMatchingKindWins() {
        XCTAssertEqual(AppTileStyle.kind(forName: "Steam Desktop"), .desktop)
        XCTAssertEqual(AppTileStyle.kind(forName: "Steam Library"), .launcher)
    }

    // Only the apps hosts add themselves, by their exact names: games with the same words keep their covers
    func testOnlyBuiltInAppsHaveNoCoverArt() {
        for name in ["Desktop", "desktop", " Desktop ", "Virtual Desktop", "Steam Big Picture", "Big Picture", "Steam",
                     "Playnite", "Playnite Fullscreen", "Terminal", "PowerShell"] {
            XCTAssertTrue(AppTileStyle.hasNoCoverArt(name: name), name)
        }
        let games: [String?] = ["Desktop Dungeons", "Steamworld Dig", "Terminal Velocity", "Elden Ring", "", nil]
        for name in games {
            XCTAssertFalse(AppTileStyle.hasNoCoverArt(name: name), String(describing: name))
        }
    }

    func testAccentColours() {
        XCTAssertEqual(AppTileStyle.accent(forName: "Desktop"), AppKind.desktop.accent)
        // A game keeps its colour whatever the case, and it's opaque
        XCTAssertEqual(AppTileStyle.accent(forName: "Elden Ring"), AppTileStyle.accent(forName: "ELDEN RING"))
        XCTAssertEqual(AppTileStyle.accent(forName: "Elden Ring").a, 1)
        XCTAssertEqual(AppTileStyle.accent(forName: nil).a, 1)
        // Every kind but game has a colour of its own
        for kind in AppKind.allCases where kind != .game {
            XCTAssertNotNil(kind.accent, kind.rawValue)
        }
        XCTAssertNil(AppKind.game.accent)
    }

    func testGameColoursComeFromTheLowerCaseNamesHash() {
        // floorMod(hash of the lower case name, 8) picks from Android's eight colours
        XCTAssertEqual(AppTileStyle.accent(forName: "Cyberpunk 2077").argb, 0xFF22C55E)
        XCTAssertEqual(AppTileStyle.accent(forName: "Elden Ring").argb, 0xFFEAB308)
        XCTAssertEqual(AppTileStyle.accent(forName: "Hades II").argb, 0xFFEC4899)
        XCTAssertEqual(AppTileStyle.accent(forName: "Forza Horizon 5").argb, 0xFFE11D48)
        XCTAssertEqual(AppTileStyle.accent(forName: "Baldur's Gate 3").argb, 0xFF8B5CF6)
        // A negative hash still lands in the list
        XCTAssertLessThan(JavaCompat.hashCode("Hades II".lowercased()), 0)
        XCTAssertEqual(AppTileStyle.accent(forName: nil).argb, 0xFFE11D48)
        XCTAssertEqual(AppTileStyle.accent(forName: "").argb, 0xFFE11D48)
    }

    func testUsesIconFollowsTheCoverStyle() {
        XCTAssertTrue(AppTileStyle.usesIcon(name: "Steam"))
        XCTAssertFalse(AppTileStyle.usesIcon(name: "Elden Ring"))
        XCTAssertTrue(AppTileStyle.usesIcon(name: "Elden Ring", style: .always))
        XCTAssertFalse(AppTileStyle.usesIcon(name: "Steam", style: .never))
        XCTAssertEqual(CoverStyle(rawValue: "missing"), .missing)
        XCTAssertEqual(CoverStyle(rawValue: "always"), .always)
        XCTAssertEqual(CoverStyle(rawValue: "never"), .never)
    }

    func testCoverArtIsKeptForGames() {
        XCTAssertEqual(AppTileStyle.tile(forName: "Elden Ring", hasCoverArt: true), .coverArt)
        XCTAssertEqual(AppTileStyle.tile(forName: "Steamworld Dig", hasCoverArt: true), .coverArt)
        // "Never" keeps the PC's cover for built-in apps too
        XCTAssertEqual(AppTileStyle.tile(forName: "Steam", hasCoverArt: true, style: .never), .coverArt)
    }

    func testAGameWithNoCoverGetsTheGeneratedTile() {
        XCTAssertEqual(AppTileStyle.tile(forName: "Elden Ring", hasCoverArt: false),
                       .generated(GeneratedTileLook(name: "Elden Ring")))
        XCTAssertEqual(AppTileStyle.tile(forName: "Desktop", hasCoverArt: false, style: .never),
                       .generated(GeneratedTileLook(name: "Desktop")))
    }

    func testDesktopGetsTheGeneratedTileAndSteamAnIconTile() {
        // As on Android: Desktop and plain games share the Starwire tile, the launchers get icons
        XCTAssertEqual(AppTileStyle.tile(forName: "Desktop", hasCoverArt: true),
                       .generated(GeneratedTileLook(name: "Desktop")))
        XCTAssertEqual(AppTileStyle.tile(forName: "Elden Ring", hasCoverArt: true, style: .always),
                       .generated(GeneratedTileLook(name: "Elden Ring")))
        guard case .icon(let steam) = AppTileStyle.tile(forName: "Steam Big Picture", hasCoverArt: true) else {
            return XCTFail("Steam Big Picture should get an icon tile")
        }
        XCTAssertEqual(steam.kind, .launcher)
        XCTAssertEqual(steam.accent.argb, 0xFF06B6D4)
        for (name, kind) in [("Playnite", AppKind.library), ("RetroArch", .retro), ("YouTube", .media),
                             ("PowerShell", .terminal)] {
            guard case .icon(let look) = AppTileStyle.ownTile(forName: name) else {
                return XCTFail("\(name) should get an icon tile")
            }
            XCTAssertEqual(look.kind, kind)
        }
    }

    func testIconTileColours() {
        let look = IconTileLook(kind: .launcher, accent: RGBA(argb: 0xFF06B6D4))
        // 8 percent towards white and 62 percent towards black, rounded per channel
        XCTAssertEqual(look.gradientStart.argb, 0xFF1ABCD7)
        XCTAssertEqual(look.gradientEnd.argb, 0xFF024551)
        XCTAssertEqual(IconTileLook.gridStep(width: 120), 15)
        XCTAssertEqual(IconTileLook.gridStep(width: 40), 8, "the grid never gets finer than 8")
    }

    // MARK: Generated tiles

    private struct Expected {
        let name: String
        let accent: UInt32
        let ringTurn: Float
        let tilt: Float
        let moonAngle: Float
        let shiftX: Float
        let shiftY: Float
        let size: Float
        let glowCorner: Int
        let starCount: Int
        let secondColour: UInt32
        let spaceTop: UInt32
        let firstStar: (Float, Float, Float, Float)
        let lastStar: (Float, Float, Float, Float)
    }

    func testGeneratedTilesMatchWhatAndroidsCodeGives() {
        let cases = [
            // The second colour came out the same as the accent here, so another one was drawn
            Expected(name: "Cyberpunk 2077", accent: 0xFF22C55E, ringTurn: 58.65581, tilt: -14.292484,
                     moonAngle: 312.55795, shiftX: 0.02427634, shiftY: 0.021898938, size: 0.9950278,
                     glowCorner: 1, starCount: 29, secondColour: 0xFFF97316, spaceTop: 0xFF243952,
                     firstStar: (0.5856983, 0.25919437, 0.0048143873, 0.69180363),
                     lastStar: (0.059207916, 0.91142887, 0.0082874, 0.8064329)),
            Expected(name: "Elden Ring", accent: 0xFFEAB308, ringTurn: 190.35287, tilt: -19.064678,
                     moonAngle: 334.84842, shiftX: 0.045243144, shiftY: -0.015475548, size: 0.9565268,
                     glowCorner: 1, starCount: 24, secondColour: 0xFF14B8A6, spaceTop: 0xFF482F42,
                     firstStar: (0.6993937, 0.07816607, 0.0046021026, 0.36072704),
                     lastStar: (0.15953231, 0.6365042, 0.0069420305, 0.5972208)),
            Expected(name: "Hades II", accent: 0xFFEC4899, ringTurn: 186.31982, tilt: -15.649612,
                     moonAngle: 297.74826, shiftX: 0.00831573, shiftY: -0.017656337, size: 0.9284361,
                     glowCorner: 0, starCount: 33, secondColour: 0xFF8B5CF6, spaceTop: 0xFF3F1959,
                     firstStar: (0.62529975, 0.0032361746, 0.0040347558, 0.6876524),
                     lastStar: (0.1545052, 0.021932602, 0.005113905, 0.60508406)),
            Expected(name: "Forza Horizon 5", accent: 0xFFE11D48, ringTurn: 47.54754, tilt: -18.249622,
                     moonAngle: 82.001785, shiftX: 0.014948892, shiftY: -0.022224804, size: 0.9776427,
                     glowCorner: 3, starCount: 22, secondColour: 0xFF14B8A6, spaceTop: 0xFF4D144D,
                     firstStar: (0.5296671, 0.87575245, 0.0045257453, 0.86575276),
                     lastStar: (0.71772474, 0.71600753, 0.0056219613, 0.512238)),
            // Desktop's colour is its kind's; its look still comes from its name's hash
            Expected(name: "Desktop", accent: 0xFF3B82F6, ringTurn: 212.48645, tilt: -35.217827,
                     moonAngle: 138.88657, shiftX: -0.020552326, shiftY: 0.019279275, size: 1.0267859,
                     glowCorner: 0, starCount: 33, secondColour: 0xFFE11D48, spaceTop: 0xFF292B74,
                     firstStar: (0.34307647, 0.30491215, 0.006752099, 0.688349),
                     lastStar: (0.7366075, 0.4976126, 0.008691136, 0.88714343)),
        ]
        for c in cases {
            let look = GeneratedTileLook(name: c.name)
            XCTAssertEqual(look.accent.argb, c.accent, c.name)
            XCTAssertEqual(look.ringTurn, c.ringTurn, c.name)
            XCTAssertEqual(look.tilt, c.tilt, c.name)
            XCTAssertEqual(look.moonAngle, c.moonAngle, c.name)
            XCTAssertEqual(look.shiftX, c.shiftX, c.name)
            XCTAssertEqual(look.shiftY, c.shiftY, c.name)
            XCTAssertEqual(look.size, c.size, c.name)
            XCTAssertEqual(look.glowCorner, c.glowCorner, c.name)
            XCTAssertEqual(look.stars.count, c.starCount, c.name)
            XCTAssertEqual(look.secondColour.argb, c.secondColour, c.name)
            XCTAssertEqual(look.spaceTop.argb, c.spaceTop, c.name)
            let first = look.stars[0]
            XCTAssertEqual([first.x, first.y, first.radiusFraction, first.alpha],
                           [c.firstStar.0, c.firstStar.1, c.firstStar.2, c.firstStar.3], c.name)
            let last = look.stars[look.stars.count - 1]
            XCTAssertEqual([last.x, last.y, last.radiusFraction, last.alpha],
                           [c.lastStar.0, c.lastStar.1, c.lastStar.2, c.lastStar.3], c.name)
        }
    }

    func testTheSecondColourRuleKeepsAndroidsQuirk() {
        // "Game 12" has the last colour in the list as its accent; the "take another one" rule
        // can land on that same colour again, and Android's tile has it twice, so ours does too.
        let look = GeneratedTileLook(name: "Game 12")
        XCTAssertEqual(look.accent.argb, 0xFFEC4899)
        XCTAssertEqual(look.secondColour.argb, 0xFFEC4899)
        XCTAssertEqual(look.spaceTop.argb, 0xFF3A1857)
    }

    func testNoNameLooksLikeTheEmptyName() {
        // Android hashes a null name as 0, which is also the empty name's hash
        let none = GeneratedTileLook(name: nil)
        XCTAssertEqual(none, GeneratedTileLook(name: ""))
        XCTAssertEqual(none.ringTurn, 263.63214)
        XCTAssertEqual(none.glowCorner, 3)
        XCTAssertEqual(none.stars.count, 29)
        XCTAssertEqual(none.secondColour.argb, 0xFFEAB308)
        XCTAssertEqual(none.spaceTop.argb, 0xFF3E144E)
    }

    func testATilesLookIsTheSameEveryTimeAndDiffersByName() {
        XCTAssertEqual(GeneratedTileLook(name: "Hades II"), GeneratedTileLook(name: "Hades II"))
        XCTAssertNotEqual(GeneratedTileLook(name: "Hades II"), GeneratedTileLook(name: "Hades"))
        // The look uses the name's own case (Android's seed is name.hashCode(), not the lower case's)
        XCTAssertNotEqual(GeneratedTileLook(name: "Hades II").ringTurn, GeneratedTileLook(name: "HADES II").ringTurn)
        // ...while the colour does not
        XCTAssertEqual(GeneratedTileLook(name: "Hades II").accent, GeneratedTileLook(name: "HADES II").accent)
    }

    func testStarsStayInsideTheTileAndAreNeverTooSmall() {
        for name in ["Cyberpunk 2077", "Elden Ring", "Desktop", "", "Game 12"] {
            let look = GeneratedTileLook(name: name)
            XCTAssertTrue((20...33).contains(look.stars.count), name)
            for star in look.stars {
                XCTAssertTrue((0..<1).contains(star.x) && (0..<1).contains(star.y), name)
                XCTAssertTrue((0.3..<0.9).contains(star.alpha), name)
                // 300 wide, as Android's covers are: 0.003 to 0.009 of that is 0.9 to 2.7
                XCTAssertTrue((0.9..<2.8).contains(star.radius(tileWidth: 300)), name)
                XCTAssertEqual(star.radius(tileWidth: 10), Double(TileStar.minimumRadius), accuracy: 1e-6)
            }
        }
    }

    func testLogoPlacement() {
        // Cyberpunk 2077 on a 300 by 400 cover: the look's numbers worked into the tile
        let look = GeneratedTileLook(name: "Cyberpunk 2077")
        let logo = look.logo(width: 300, height: 400)
        XCTAssertEqual(logo.scale, 300 * 0.5 * Double(look.size), accuracy: 1e-9)
        XCTAssertEqual(logo.centerX, 150 + 300 * Double(look.shiftX), accuracy: 1e-9)
        XCTAssertEqual(logo.centerY, 400 * (0.42 + Double(look.shiftY)), accuracy: 1e-9)
        XCTAssertEqual(logo.voidRadius, logo.scale * 0.34, accuracy: 1e-9)
        XCTAssertEqual(logo.ringRadius, logo.scale * 0.39, accuracy: 1e-9)
        XCTAssertEqual(logo.orbitRadiusX, logo.scale * 0.6, accuracy: 1e-9)
        XCTAssertEqual(logo.starX - logo.centerX, logo.scale * 0.27, accuracy: 1e-9)
        XCTAssertEqual(logo.centerY - logo.starY, logo.scale * 0.27, accuracy: 1e-9)
        // The orbit's stroke is at least one unit wide, however small the tile
        XCTAssertEqual(look.logo(width: 20, height: 20).orbitStroke, 1)
        // Its moon at 312 degrees is in the upper half of the orbit, so behind the void
        XCTAssertFalse(logo.moonInFront)
        XCTAssertTrue(GeneratedTileLook(name: "Forza Horizon 5").logo(width: 300, height: 400).moonInFront)
        XCTAssertEqual(logo.ringTurn, Double(look.ringTurn))
        XCTAssertEqual(logo.tilt, Double(look.tilt))
    }

    func testGlowCornersOppositeTheHaze() {
        var look = GeneratedTileLook(name: "Desktop")
        for (corner, glow) in [(0, (0.8, 0.12)), (1, (0.2, 0.12)), (2, (0.8, 0.88)), (3, (0.2, 0.88))] {
            look.glowCorner = corner
            XCTAssertEqual(look.glowCentre.x, glow.0, accuracy: 1e-12)
            XCTAssertEqual(look.glowCentre.y, glow.1, accuracy: 1e-12)
            XCTAssertEqual(look.hazeCentre.x, 1 - glow.0, accuracy: 1e-12)
            XCTAssertEqual(look.hazeCentre.y, 1 - glow.1, accuracy: 1e-12)
        }
    }

    // MARK: Cover colours (CoverGlowTest)

    private func flat(_ red: UInt8, _ green: UInt8, _ blue: UInt8, width: Int = 24, height: Int = 32) -> [UInt8] {
        var bytes: [UInt8] = []
        for _ in 0..<(width * height) {
            bytes += [red, green, blue, 255]
        }
        return bytes
    }

    private func hue(_ colour: RGBA) -> Float {
        let c = colour.bytes
        return CoverPalette.rgbToHSV(red: c.red, green: c.green, blue: c.blue).h
    }

    func testARedCoverTintsRed() {
        let tint = CoverPalette.tintColour(width: 24, height: 32, rgba: flat(200, 30, 40))
        let h = hue(tint)
        XCTAssertTrue(h < 10 || h > 350, "hue \(h)")
        // Worked by hand: hue 356.47, saturation 0.85 (inside 0.55 to 0.9), brightness 0.85
        XCTAssertEqual(tint.argb, 0xFFD9212B)
    }

    func testTheVividPartOfADarkCoverWins() {
        // Mostly near-black with a blue logo
        var bytes = flat(12, 12, 14)
        for pixel in 0..<115 {
            bytes[pixel * 4] = 30
            bytes[pixel * 4 + 1] = 90
            bytes[pixel * 4 + 2] = 230
        }
        let h = hue(CoverPalette.tintColour(width: 24, height: 32, rgba: bytes))
        XCTAssertTrue(h > 210 && h < 235, "hue \(h)")
    }

    func testAGreyCoverKeepsTheDefault() {
        XCTAssertEqual(CoverPalette.tintColour(width: 24, height: 32, rgba: flat(128, 128, 128)), CoverPalette.defaultTint)
        XCTAssertEqual(CoverPalette.from(width: 24, height: 32, rgba: flat(0, 0, 0)), CoverPalette.fallback)
        XCTAssertEqual(CoverPalette.defaultTint.argb, 0xFF7C3AED)
    }

    func testTheFallbackPalette() {
        // Worked by hand from deep() and panel(): 124 * 0.16 + 8, and so on
        XCTAssertEqual(CoverPalette.fallback.tint.argb, 0xFF7C3AED)
        XCTAssertEqual(CoverPalette.fallback.deep.argb, 0xFF1C112E)
        XCTAssertEqual(CoverPalette.fallback.panel.argb, 0xF425173E)
    }

    func testABiggerCoverIsAveragedDown() {
        // The same red at 96 by 128 and at 24 by 32
        XCTAssertEqual(CoverPalette.from(width: 96, height: 128, rgba: flat(200, 30, 40, width: 96, height: 128)),
                       CoverPalette.from(width: 24, height: 32, rgba: flat(200, 30, 40)))
        // A cover that is blue on its left half and grey on its right is blue
        var bytes: [UInt8] = []
        for _ in 0..<64 {
            for x in 0..<48 {
                bytes += x < 24 ? [20, 60, 220, 255] : [120, 120, 120, 255]
            }
        }
        let h = hue(CoverPalette.tintColour(width: 48, height: 64, rgba: bytes))
        XCTAssertTrue(h > 215 && h < 235, "hue \(h)")
        // A small cover is stretched, not skipped
        XCTAssertEqual(CoverPalette.samplePixels(width: 2, height: 2, rgba: flat(1, 2, 3, width: 2, height: 2))?.count, 768)
        XCTAssertEqual(CoverPalette.samplePixels(width: 2, height: 2, rgba: flat(1, 2, 3, width: 2, height: 2))?.first, 0x010203)
    }

    func testABadBufferGetsTheFallback() {
        XCTAssertEqual(CoverPalette.from(width: 0, height: 0, rgba: []), CoverPalette.fallback)
        XCTAssertEqual(CoverPalette.from(width: 24, height: 32, rgba: [1, 2, 3]), CoverPalette.fallback)
        XCTAssertEqual(CoverPalette.from(width: -4, height: 32, rgba: flat(200, 30, 40)), CoverPalette.fallback)
    }

    func testWhiteTextStaysReadableOnTheBackground() {
        func luminance(_ c: RGBA) -> Double {
            func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
        }
        for tint in [0xFF7C3AED, 0xFFFFFF00, 0xFFFFFFFF, 0xFFA3E635] as [UInt32] {
            let deep = CoverPalette(tint: RGBA(argb: tint)).deep
            let contrast = 1.05 / (luminance(deep) + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, 7, "tint \(String(tint, radix: 16)) gives contrast \(contrast)")
        }
    }

    // MARK: Starfield

    func testTheSkyIsTheSameEveryTime() {
        XCTAssertEqual(StarfieldModel(width: 1180, height: 820), StarfieldModel(width: 1180, height: 820))
    }

    func testStarCounts() {
        XCTAssertEqual(StarfieldModel.starCount(width: 1180, height: 820), 106)
        XCTAssertEqual(StarfieldModel.starCount(width: 100, height: 100), 40, "never fewer than 40")
        XCTAssertEqual(StarfieldModel.starCount(width: 1000, height: 1020), 112)
        XCTAssertEqual(StarfieldModel(width: 1180, height: 820).stars.count, 106)
    }

    func testTheFirstStarsAreTheSameAtAnySize() {
        let small = StarfieldModel(width: 300, height: 400)
        let big = StarfieldModel(width: 1180, height: 820)
        XCTAssertEqual(Array(big.stars.prefix(small.stars.count)), small.stars)
    }

    func testStarsMatchWhatAndroidsLoopGives() {
        let stars = StarfieldModel(width: 1000, height: 1020).stars
        XCTAssertEqual(stars.count, 112)
        XCTAssertEqual(stars[0].x, 0.8973274)
        XCTAssertEqual(stars[0].y, 0.6519021)
        XCTAssertEqual(stars[0].radius, 0.7252929)
        XCTAssertEqual(stars[0].phase, 1.3278226)
        XCTAssertEqual(stars[0].colour.argb, 0xFFFFFFFF)
        XCTAssertTrue(stars[0].twinkles)
        XCTAssertEqual(stars[1].x, 0.040545523)
        XCTAssertEqual(stars[1].radius, 0.46827888)
        XCTAssertEqual(stars[1].phase, 4.264155)
        XCTAssertEqual(stars[1].colour.argb, 0xFFFDE68A)
        XCTAssertFalse(stars[1].twinkles)
        XCTAssertEqual(stars[2].y, 0.7873378)
        XCTAssertEqual(stars[2].phase, 6.008598)
        // Of the 112 stars, 24 twinkle
        XCTAssertEqual(stars.filter { $0.twinkles }.count, 24)
        for star in stars {
            XCTAssertTrue(star.radius >= 0.35 && star.radius <= 1.75)
            XCTAssertTrue(StarfieldModel.starColours.contains(star.colour))
        }
    }

    func testOnlyTheTwinklingStarsChange() {
        let model = StarfieldModel(width: 1000, height: 1020)
        let steady = model.stars[1]
        let twinkler = model.stars[0]
        for time in [0.0, 1.0, 3.5, 6.9] {
            XCTAssertEqual(StarfieldModel.alpha(of: steady, at: time), 0.55)
            let alpha = StarfieldModel.alpha(of: twinkler, at: time)
            XCTAssertTrue(alpha >= 0.35 && alpha <= 0.95, "alpha \(alpha) at \(time)")
        }
        // At angle 0 the twinkle is 0.35 + 0.6 * (0.5 + 0.5 * sin(phase))
        XCTAssertEqual(StarfieldModel.alpha(of: twinkler, angle: 0), 0.35 + 0.6 * (0.5 + 0.5 * sin(Double(twinkler.phase))),
                       accuracy: 1e-12)
        XCTAssertEqual(StarfieldModel.alpha(of: twinkler, at: 0), StarfieldModel.alpha(of: twinkler, angle: 0))
    }

    func testTheTwinkleRepeatsEverySevenSeconds() {
        let star = StarfieldModel(width: 1000, height: 1020).stars[0]
        XCTAssertEqual(StarfieldModel.alpha(of: star, at: 2.5), StarfieldModel.alpha(of: star, at: 9.5), accuracy: 1e-9)
        XCTAssertEqual(StarfieldModel.twinkleAngle(at: 3.5), Double.pi, accuracy: 1e-12)
        XCTAssertEqual(StarfieldModel.twinkleAngle(at: 7), 0, accuracy: 1e-12)
        XCTAssertEqual(StarfieldModel.twinkleAngle(at: -3.5), Double.pi, accuracy: 1e-12)
    }

    func testTheGlowDriftsOutAndBack() {
        XCTAssertEqual(StarfieldModel.glowDrift(at: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(StarfieldModel.glowDrift(at: 2.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(StarfieldModel.glowDrift(at: 4.5), 1, accuracy: 1e-12)
        XCTAssertEqual(StarfieldModel.glowDrift(at: 6.75), 0.5, accuracy: 1e-12)
        XCTAssertEqual(StarfieldModel.glowDrift(at: 9), 0, accuracy: 1e-12)
        XCTAssertEqual(StarfieldModel.glowDrift(at: 11.25), 0.5, accuracy: 1e-12)
    }

    func testNebulaCloudsAreTheThreeOnAndroid() {
        XCTAssertEqual(StarfieldModel.clouds.map { $0.colour.argb }, [0x387C3AED, 0x26C026D3, 0x1A2563EB])
        XCTAssertEqual(StarfieldModel.clouds.map { $0.radius }, [0.55, 0.50, 0.40])
    }

    // MARK: Rainbow

    func testTheRainbowLoopsWithoutASeam() {
        XCTAssertEqual(RainbowPalette.stops.count, 5)
        XCTAssertEqual(RainbowPalette.stops.first, RainbowPalette.stops.last)
        XCTAssertEqual(RainbowPalette.stops.map { $0.argb },
                       [0xFF0894FF, 0xFFC959DD, 0xFFFF2E54, 0xFFFF9004, 0xFF0894FF])
        XCTAssertEqual(RainbowPalette.colour(at: 0), RainbowPalette.stops[0])
        XCTAssertEqual(RainbowPalette.colour(at: 0.25).argb, 0xFFC959DD)
        XCTAssertEqual(RainbowPalette.colour(at: 0.5).argb, 0xFFFF2E54)
        XCTAssertEqual(RainbowPalette.colour(at: 0.75).argb, 0xFFFF9004)
        XCTAssertEqual(RainbowPalette.colour(at: 1), RainbowPalette.colour(at: 0))
        XCTAssertEqual(RainbowPalette.colour(at: -0.75).argb, 0xFFC959DD, "positions wrap")
        XCTAssertEqual(RainbowPalette.colour(at: 2.5).argb, 0xFFFF2E54)
    }

    func testTheRainbowBlendsBetweenStops() {
        let middle = RainbowPalette.colour(at: 0.125)
        XCTAssertEqual(middle.r, (RainbowPalette.stops[0].r + RainbowPalette.stops[1].r) / 2, accuracy: 1e-12)
        XCTAssertEqual(middle.g, (RainbowPalette.stops[0].g + RainbowPalette.stops[1].g) / 2, accuracy: 1e-12)
        XCTAssertEqual(middle.a, 1)
    }

    func testTheRainbowsPhaseFollowsTime() {
        XCTAssertEqual(RainbowPalette.textPhase(at: 0), 0)
        XCTAssertEqual(RainbowPalette.textPhase(at: 3), 0.5, accuracy: 1e-12)
        XCTAssertEqual(RainbowPalette.textPhase(at: 6), 0, accuracy: 1e-12)
        XCTAssertEqual(RainbowPalette.textPhase(at: 7.5), 0.25, accuracy: 1e-12)
        XCTAssertEqual(RainbowPalette.ringAngle(at: 0), 0)
        XCTAssertEqual(RainbowPalette.ringAngle(at: 1), 90, accuracy: 1e-12)
        XCTAssertEqual(RainbowPalette.ringAngle(at: 4), 0, accuracy: 1e-12)
        XCTAssertEqual(RainbowPalette.ringAngle(at: 5), 90, accuracy: 1e-12)
        XCTAssertEqual(RainbowPalette.ringAngle(at: -1), 270, accuracy: 1e-12)
    }
}
