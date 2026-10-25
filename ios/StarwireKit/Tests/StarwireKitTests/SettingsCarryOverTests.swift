import XCTest
@testable import StarwireKit

/// Batch 4.5's settings start from what the owner already chose, so nothing changes on update.
final class SettingsCarryOverTests: XCTestCase {
    private func store(_ values: [String: SettingValue] = [:]) throws -> SettingsStore {
        let store = SettingsStore(storage: MemorySettingsStorage())
        for (key, value) in values { try store.set(value, for: key) }
        return store
    }

    func testTheTouchModeFollowsAndroidsTrackpadSwitchUntilChosen() throws {
        XCTAssertEqual(try store().value("list_touch_mode"), .string("gaming_trackpad"), "Android's default is the trackpad")
        let direct = try store(["checkbox_touchscreen_trackpad": .bool(false)])
        XCTAssertEqual(direct.value("list_touch_mode"), .string("direct"))
        XCTAssertNil(direct.savedValue("list_touch_mode"), "nothing is written: the switch still decides")

        try direct.set(.string("multi_touch"), for: "list_touch_mode")
        XCTAssertEqual(direct.value("list_touch_mode"), .string("multi_touch"))
        XCTAssertEqual(TouchMode(settingValue: "multi_touch"), .multiTouch)
    }

    func testThePictureFollowsAndroidsStretchSwitchUntilChosen() throws {
        XCTAssertEqual(try store().value("list_video_scaling"), .string("fit"))
        XCTAssertEqual(try store(["checkbox_stretch_video": .bool(true)]).value("list_video_scaling"), .string("stretch"))
        let chosen = try store(["checkbox_stretch_video": .bool(true), "list_video_scaling": .string("fill")])
        XCTAssertEqual(chosen.value("list_video_scaling"), .string("fill"))
    }

    func testEveryNewSettingKeepsTodaysBehaviourByDefault() throws {
        let store = try store()
        XCTAssertEqual(store.value("checkbox_enable_floating_button"), .bool(true))
        XCTAssertEqual(MenuButtonOptions(store: store).autoHide, nil, "the button doesn't tuck away by itself")
        XCTAssertEqual(GestureSettings(store: store).threeFingerTap, .menu, "three fingers still open the menu")
        XCTAssertEqual(KeyboardCustomization.layout(from: store), FullKeyboardLayout.android, "the same keyboard")
        XCTAssertEqual(store.value("seekbar_keyboard_size"), .int(100))
        XCTAssertEqual(store.value("list_keyboard_placement"), .string("docked"))
    }

    func testAGamesTrackpadChoiceStillPicksItsTouchMode() throws {
        let store = try store(["list_touch_mode": .string("natural_trackpad")])
        let android = GameSettings(useGlobalSettings: false, gameOptions: ["checkbox_touchscreen_trackpad": "false"])
        XCTAssertEqual(store.effectiveValues(for: android)["list_touch_mode"], .string("direct"))

        let own = GameSettings(useGlobalSettings: false, gameOptions: ["checkbox_touchscreen_trackpad": "false",
                                                                       "list_touch_mode": "multi_touch"])
        XCTAssertEqual(store.effectiveValues(for: own)["list_touch_mode"], .string("multi_touch"))

        let unused = GameSettings(useGlobalSettings: true, gameOptions: ["list_touch_mode": "multi_touch"])
        XCTAssertEqual(store.effectiveValues(for: unused)["list_touch_mode"], .string("natural_trackpad"))
    }

    func testAGameCanPickItsPicture() throws {
        let game = GameSettings(useGlobalSettings: false, gameOptions: ["list_video_scaling": "fill"])
        XCTAssertEqual(try store().effectiveValues(for: game)["list_video_scaling"], .string("fill"))
    }

    func testTheNewSettingsRoundTripThroughTheSettingsFile() throws {
        let store = try store(["list_touch_mode": .string("multi_touch"), "list_menu_button_style": .string("edge"),
                               "keyboard_remapped_keys": .string(#"{"full":{"caps":"esc"}}"#)])
        let data = try SettingsJSON.export(store)
        let copy = try self.store()
        _ = try SettingsJSON.import(data, into: copy)
        for key in ["list_touch_mode", "list_menu_button_style", "keyboard_remapped_keys"] {
            XCTAssertEqual(copy.savedValue(key), store.savedValue(key), key)
        }
    }
}
