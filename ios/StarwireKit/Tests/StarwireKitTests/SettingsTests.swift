import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import StarwireKit

/// Reads every `android:key` and `android:defaultValue` from Android's preferences.xml.
private final class PreferenceXMLReader: NSObject, XMLParserDelegate {
    var keys: [String: String?] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if let key = attributes["android:key"] {
            keys[key] = attributes["android:defaultValue"]
        }
    }

    static func read(_ url: URL) throws -> [String: String?] {
        let reader = PreferenceXMLReader()
        let parser = XMLParser(data: try Data(contentsOf: url))
        parser.delegate = reader
        XCTAssertTrue(parser.parse(), "\(url.lastPathComponent) didn't parse")
        return reader.keys
    }
}

final class SettingsCatalogTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Keys in preferences.xml that save nothing: headings, buttons and links, and the rows whose
    /// keys hold device state rather than a setting.
    private let notSettings: Set<String> = [
        "microphone_host_info", "vban_setup_info", "mic_pairing", "import_shortcuts_file",
        "clear_imported_shortcuts", "remove_custom_vulkan_driver", "overlay_custom_commands",
        "text_custom_vulkan_driver_path",
    ]

    func testEveryAndroidSettingIsInTheCatalogWithItsDefault() throws {
        let xml = Self.repo.appendingPathComponent("app/src/main/res/xml/preferences.xml")
        let keys = try PreferenceXMLReader.read(xml)
        XCTAssertGreaterThan(keys.count, 60)

        for (key, xmlDefault) in keys.sorted(by: { $0.key < $1.key }) {
            if key.hasPrefix("category_") || key.hasPrefix("about_") || notSettings.contains(key) {
                continue
            }
            guard let definition = SettingsCatalog.definition(key) else {
                XCTFail("\(key) is in preferences.xml but not in SettingsCatalog")
                continue
            }
            guard let xmlDefault else {
                XCTAssertNil(definition.defaultValue, "\(key) has no default in the XML, so it's computed")
                continue
            }
            switch definition.defaultValue {
            case .bool(let value)?: XCTAssertEqual(String(value), xmlDefault, key)
            case .int(let value)?: XCTAssertEqual(String(value), xmlDefault, key)
            case .string(let value)?: XCTAssertEqual(value, xmlDefault, key)
            case nil: XCTFail("\(key) has a default in the XML but not in the catalog")
            }
        }
    }

    func testDefaultsAreValuesTheirListsAccept() {
        for definition in SettingsCatalog.all {
            if let value = definition.defaultValue {
                XCTAssertTrue(definition.accepts(value), definition.key)
            }
        }
    }

    func testKeysAreUnique() {
        XCTAssertEqual(Set(SettingsCatalog.all.map(\.key)).count, SettingsCatalog.all.count)
    }

    func testGameOptionsAreFlaggedInTheCatalog() {
        for key in SettingsCatalog.gameOptionKeys {
            XCTAssertEqual(SettingsCatalog.definition(key)?.gameOption, true, key)
        }
    }
}

final class SettingsStoreTests: XCTestCase {
    private let storage = MemorySettingsStorage()
    private lazy var store = SettingsStore(storage: storage)

    func testUnsetSettingsReadTheirDefaults() {
        XCTAssertEqual(store[.virtualDisplayMode], .host)
        XCTAssertEqual(store[.frameRate], "60")
        XCTAssertEqual(store.value("seekbar_deadzone"), .int(7))
        XCTAssertEqual(store[.vrrRequest], false)
    }

    func testValuesAreSavedWithAndroidsTypes() {
        store[.virtualDisplayMode] = .virtual
        store[.bitrateKbps] = 50000
        store[.enableHDR] = true
        XCTAssertEqual(storage.values["virtual_display_mode"] as? String, "virtual")
        XCTAssertEqual(storage.values["seekbar_bitrate_kbps"] as? Int, 50000)
        XCTAssertEqual(storage.values["checkbox_enable_hdr"] as? Bool, true)
    }

    func testTheWrongKindOrAnUnknownListValueIsRefused() {
        XCTAssertThrowsError(try store.set(.int(1), for: "virtual_display_mode"))
        XCTAssertThrowsError(try store.set(.string("sideways"), for: "virtual_display_mode"))
        XCTAssertThrowsError(try store.set(.bool(true), for: "no_such_key"))
    }

    func testABadSavedValueFallsBackToTheDefault() {
        storage.set("sideways", forKey: "virtual_display_mode")
        storage.set("seven", forKey: "seekbar_deadzone")
        XCTAssertEqual(store[.virtualDisplayMode], .host)
        XCTAssertEqual(store.value("seekbar_deadzone"), .int(7))
    }

    func testTheBitrateDefaultFollowsResolutionAndFrameRateAsOnAndroid() {
        XCTAssertEqual(SettingsStore.defaultBitrate(width: 1280, height: 720, fps: 60), 10000)
        XCTAssertEqual(SettingsStore.defaultBitrate(width: 1920, height: 1080, fps: 60), 20000)
        XCTAssertEqual(SettingsStore.defaultBitrate(width: 3840, height: 2160, fps: 60), 80000)
        XCTAssertEqual(SettingsStore.defaultBitrate(width: 1280, height: 720, fps: 30), 5000)
        XCTAssertEqual(SettingsStore.defaultBitrate(width: 1920, height: 1080, fps: 120), 28000)

        store[.resolution] = "1920x1080"
        XCTAssertEqual(store[.bitrateKbps], 20000)
        store[.bitrateKbps] = 70000
        XCTAssertEqual(store[.bitrateKbps], 70000)
    }

    func testSmallIconModeFollowsTheScreen() {
        XCTAssertEqual(SettingsStore(storage: storage, smallScreen: true).value("checkbox_small_icon_mode"), .bool(true))
        XCTAssertEqual(SettingsStore(storage: storage, smallScreen: false).value("checkbox_small_icon_mode"), .bool(false))
    }
}

final class GameSettingsTests: XCTestCase {
    private let storage = MemorySettingsStorage()
    private lazy var store = SettingsStore(storage: storage)
    private lazy var games = GameSettingsStore(storage: storage)

    func testAndroidsJSONReadsAndWritesTheSame() throws {
        let android = """
        {"resolution":"1920x1080","fps":120,"framePacing":"smoothness","bitrate":45000,"actualDisplayRefreshRate":119.88,\
        "enableHdr":"true","useGlobalSettings":false,"gameOptions":{"video_format":"forceav1","virtual_display_mode":"virtual"}}
        """
        let game = GameSettings(jsonData: Data(android.utf8))
        XCTAssertEqual(game.resolution, "1920x1080")
        XCTAssertEqual(game.fps, 120)
        XCTAssertEqual(game.bitrate, 45000)
        XCTAssertEqual(game.actualDisplayRefreshRate, 119.88)
        XCTAssertEqual(game.enableHdr, "true")
        XCTAssertNil(game.enablePerfOverlay)
        XCTAssertFalse(game.useGlobalSettings)
        XCTAssertEqual(game.gameOptions, ["video_format": "forceav1", "virtual_display_mode": "virtual"])

        XCTAssertEqual(GameSettings(jsonData: try game.jsonData()), game)
        let written = try JSONSerialization.jsonObject(with: game.jsonData()) as! [String: Any]
        XCTAssertNil(written["enablePerfOverlay"], "unset strings stay out, as on Android")
    }

    func testMissingOrBrokenJSONIsAllUnset() {
        XCTAssertEqual(GameSettings(jsonData: Data("not json".utf8)), GameSettings())
        XCTAssertTrue(GameSettings(jsonData: Data("{}".utf8)).useGlobalSettings)
    }

    func testAGameUsingGlobalSettingsKeepsItsOverridesButIgnoresThem() {
        store[.frameRate] = "60"
        let game = GameSettings(fps: 120, useGlobalSettings: true)
        XCTAssertEqual(store.effectiveValues(for: game)["list_fps"], .string("60"))
        var own = game
        own.useGlobalSettings = false
        XCTAssertEqual(store.effectiveValues(for: own)["list_fps"], .string("120"))
    }

    func testOverridesApplyOnTopOfTheGlobalSettings() {
        store[.virtualDisplayMode] = .host
        let game = GameSettings(bitrate: 30000, enablePerfOverlay: "true", useGlobalSettings: false,
                                gameOptions: ["virtual_display_mode": "primary", "jitter_buffer": "nonsense"])
        let values = store.effectiveValues(for: game)
        XCTAssertEqual(values["seekbar_bitrate_kbps"], .int(30000))
        XCTAssertEqual(values["checkbox_enable_perf_overlay"], .bool(true))
        XCTAssertEqual(values["virtual_display_mode"], .string("primary"))
        XCTAssertEqual(values["jitter_buffer"], .string("balanced"), "an unknown option is ignored")
    }

    func testAsyncLowFrameRateNeedsAsyncDecode() {
        let game = GameSettings(useGlobalSettings: false, gameOptions: ["checkbox_async_lfr": "true"])
        XCTAssertEqual(store.effectiveValues(for: game)["checkbox_async_lfr"], .bool(false))
        let both = GameSettings(useGlobalSettings: false, gameOptions: ["checkbox_async_lfr": "true", "checkbox_async_decode": "true"])
        XCTAssertEqual(store.effectiveValues(for: both)["checkbox_async_lfr"], .bool(true))
    }

    func testGamesAreSavedUnderAndroidsKeys() {
        let key = GameSettings.key(hostUUID: "6B1C3A4E-0000-4000-8000-00000000F1C5", appID: "881448767")
        XCTAssertEqual(key, "6B1C3A4E-0000-4000-8000-00000000F1C5:881448767")
        games.set(GameSettings(fps: 90, useGlobalSettings: false), forKey: key)
        XCTAssertEqual(games.settings(forKey: key).fps, 90)
        games.set(GameSettings(), forKey: key)
        XCTAssertNil(storage.values["game:" + key], "a game with nothing set leaves nothing behind")
    }
}

final class SettingsJSONTests: XCTestCase {
    func testExportThenImportGivesTheSameSettings() throws {
        let from = SettingsStore(storage: MemorySettingsStorage())
        let fromGames = GameSettingsStore(storage: from.storage)
        from[.virtualDisplayMode] = .virtual
        from[.frameRate] = "119.88"
        from[.bitrateKbps] = 70000
        try from.set(.int(12), for: "seekbar_deadzone")
        try from.set(.bool(true), for: "checkbox_enable_yuv444")
        fromGames.set(GameSettings(fps: 60, useGlobalSettings: false), forKey: "PC:1")

        let data = try SettingsJSON.export(from, games: fromGames, gameKeys: ["PC:1"])

        let to = SettingsStore(storage: MemorySettingsStorage())
        let toGames = GameSettingsStore(storage: to.storage)
        let report = try SettingsJSON.import(data, into: to, games: toGames)
        XCTAssertTrue(report.skipped.isEmpty, "\(report.skipped)")
        XCTAssertEqual(to.savedValues(), from.savedValues())
        XCTAssertEqual(toGames.settings(forKey: "PC:1"), fromGames.settings(forKey: "PC:1"))
    }

    func testTheFileUsesAndroidsTypes() throws {
        let store = SettingsStore(storage: MemorySettingsStorage())
        store[.frameRate] = "120"
        store[.enableHDR] = true
        let root = try JSONSerialization.jsonObject(with: SettingsJSON.export(store)) as! [String: Any]
        XCTAssertEqual(root["format"] as? String, "starwire-settings")
        XCTAssertEqual(root["version"] as? Int, 1)
        let settings = root["settings"] as! [String: Any]
        XCTAssertEqual(settings["list_fps"] as? String, "120")
        XCTAssertEqual(settings["checkbox_enable_hdr"] as? Bool, true)
    }

    func testAHandWrittenFileIsReadLeniently() throws {
        let file = """
        {"format":"starwire-settings","version":1,"settings":{
          "list_fps": 120, "seekbar_deadzone": "10", "checkbox_enable_hdr": "true",
          "virtual_display_mode": "sideways", "made_up_key": true, "video_renderer": "vulkan",
          "seekbar_bitrate_kbps": 1.5
        }}
        """
        let store = SettingsStore(storage: MemorySettingsStorage())
        let report = try SettingsJSON.import(Data(file.utf8), into: store)
        XCTAssertEqual(store[.frameRate], "120")
        XCTAssertEqual(store.value("seekbar_deadzone"), .int(10))
        XCTAssertEqual(store[.enableHDR], true)
        XCTAssertEqual(store.value("video_renderer"), .string("auto"), "Android's renderers mean the default here")
        XCTAssertEqual(Set(report.skipped.keys), ["virtual_display_mode", "made_up_key", "seekbar_bitrate_kbps"])
    }

    func testOtherFilesAreRefused() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        XCTAssertThrowsError(try SettingsJSON.import(Data("[1]".utf8), into: store)) {
            XCTAssertEqual($0 as? SettingsJSON.ImportError, .notStarwireSettings)
        }
        XCTAssertThrowsError(try SettingsJSON.import(Data("nope".utf8), into: store)) {
            XCTAssertEqual($0 as? SettingsJSON.ImportError, .notJSON)
        }
        XCTAssertThrowsError(try SettingsJSON.import(Data(#"{"format":"starwire-settings","version":2,"settings":{}}"#.utf8), into: store)) {
            XCTAssertEqual($0 as? SettingsJSON.ImportError, .newerVersion(2))
        }
    }
}

final class SettingsMigrationTests: XCTestCase {
    func testEveryOldValueLandsInTheStore() {
        // The owner's settings after batch 1: Safe Area 2420x1668, 120 FPS, HEVC, 70 Mbps, frames
        // to buffer 2, statistics overlay on, and the batch 1 iOS Settings choices.
        let legacy = LegacySettings(
            coreData: .init(bitrateKbps: 70000, framerate: 120, width: 2420, height: 1668, audioConfig: 6,
                            preferredCodec: 2, frameQueueSize: 2, multiController: true, swapABXYButtons: true,
                            playAudioOnPC: false, optimizeGames: false, enableHdr: true, enableYUV444: true,
                            btMouseSupport: true, absoluteTouchMode: true, statsOverlay: true, enableGraphs: true,
                            graphOpacity: 70, onscreenControls: 3, spatialAudio: 1),
            iosSettings: [
                "StarwireVirtualDisplay": true, "StarwireReduceRefreshRate": true, "StarwireExternalDisplay": "video",
                "StarwireFrameInterpolation": true, "StarwirePictureInPicture": true, "StarwireFullRange": true,
                "StarwireOverlay": "lite", "StarwirePresenter": "display", "StarwireJitterBuffer": "smooth",
                "StarwirePresentTiming": "frame", "StarwireDropPolicy": "newest", "StarwireFramesToBuffer": 3,
                "StarwireVerboseLogging": true,
            ])
        let store = SettingsStore(storage: MemorySettingsStorage())
        let applied = SettingsMigration.apply(legacy, to: store)

        let expected: [String: SettingValue] = [
            "seekbar_bitrate_kbps": .int(70000), "list_fps": .string("120"), "list_resolution": .string("2420x1668"),
            "list_audio_config": .string("51"), "video_format": .string("forceh265"), "seekbar_frames_to_buffer": .int(2),
            "checkbox_multi_controller": .bool(true), "checkbox_flip_face_buttons": .bool(true),
            "checkbox_host_audio": .bool(false), "checkbox_enable_sops": .bool(false), "checkbox_enable_hdr": .bool(true),
            "checkbox_enable_yuv444": .bool(true), "checkbox_bt_mouse_support": .bool(true),
            "checkbox_touchscreen_trackpad": .bool(false), "checkbox_enable_perf_overlay": .bool(true),
            "checkbox_enable_graphs": .bool(true), "seekbar_graph_opacity": .int(70),
            "list_onscreen_controls": .string("full"), "checkbox_show_onscreen_controls": .bool(true),
            "list_spatial_audio": .string("head-tracked"),
            "virtual_display_mode": .string("virtual"), "checkbox_reduce_refresh_rate": .bool(true),
            "list_external_display": .string("video"), "checkbox_frame_interpolation": .bool(true),
            "checkbox_enable_pip": .bool(true), "checkbox_full_range": .bool(true),
            "checkbox_enable_perf_overlay_lite": .bool(true), "video_renderer": .string("display"),
            "jitter_buffer": .string("smooth"), "list_present_timing": .string("frame"), "list_drop_policy": .string("newest"),
            "seekbar_pacing_frames_to_buffer": .int(3), "checkbox_verbose_logging": .bool(true),
        ]
        XCTAssertEqual(store.savedValues(), expected)
        XCTAssertEqual(applied, expected.keys.sorted())
    }

    func testUntouchedIOSSettingsLeaveTheStoreAlone() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        store[.vrrRequest] = true
        store[.virtualDisplayMode] = .primary
        SettingsMigration.apply(LegacySettings(coreData: nil, iosSettings: [:]), to: store)
        XCTAssertEqual(store[.vrrRequest], true)
        XCTAssertEqual(store[.virtualDisplayMode], .primary)
    }

    func testTheNewVirtualDisplayChoiceWinsOverBatch1sSwitch() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        SettingsMigration.apply(LegacySettings(coreData: nil, iosSettings: [
            "StarwireVirtualDisplay": true, "StarwireVirtualDisplayMode": "primary",
        ]), to: store)
        XCTAssertEqual(store[.virtualDisplayMode], .primary)
    }

    func testAnExactFrameRateReplacesTheWholeNumberOne() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        SettingsMigration.apply(LegacySettings(coreData: .init(framerate: 120), iosSettings: [
            "StarwireExactFrameRate": "119.88", "StarwireScaleFactor": 150, "StarwireRequestVRR": true,
            "StarwireClientName": "  iPad Pro  ",
        ]), to: store)
        XCTAssertEqual(store[.frameRate], "119.88")
        XCTAssertEqual(store[.virtualDisplayScale], 150)
        XCTAssertEqual(store[.vrrRequest], true)
        XCTAssertEqual(store[.clientName], "iPad Pro")
    }

    func testRunningAgainChangesNothing() {
        let legacy = LegacySettings(coreData: .init(), iosSettings: ["StarwireJitterBuffer": "balanced"])
        let store = SettingsStore(storage: MemorySettingsStorage())
        SettingsMigration.apply(legacy, to: store)
        let first = store.savedValues()
        SettingsMigration.apply(legacy, to: store)
        XCTAssertEqual(store.savedValues(), first)
    }
}
