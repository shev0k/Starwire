import XCTest
@testable import StarwireKit

/// The input choices in the iOS Settings app (Settings.bundle/Root.plist) and where they land.
final class InputSettingsMigrationTests: XCTestCase {
    /// Each new iOS key and the key the settings store saves it under.
    private static let mapping: [String: String] = [
        "StarwireTouchscreenTrackpad": "checkbox_touchscreen_trackpad",
        "StarwireTouchSensitivity": "seekbar_touch_sensitivity",
        "StarwireLongPressRightClick": "checkbox_long_press_right_click",
        "StarwirePinchToZoom": "checkbox_pinch_to_zoom",
        "StarwireHideCursor": "hide_cursor_mode",
        "StarwireAbsoluteMouse": "checkbox_absolute_mouse_mode",
        "StarwireMouseNavButtons": "checkbox_mouse_nav_buttons",
        "StarwireStickyModifiers": "checkbox_sticky_modifier_keys",
        "StarwireKeyboardOpacity": "seekbar_keyboard_opacity",
        "StarwireFloatingButton": "checkbox_enable_floating_button",
        "StarwireMenuTrigger": "overlay_trigger_button",
        "StarwireMenuHold": "overlay_hold_duration",
        "StarwireShowOnScreenControls": "checkbox_show_onscreen_controls",
        "StarwireOnScreenOpacity": "seekbar_osc_opacity",
        "StarwireOnlyL3R3": "checkbox_only_show_L3R3",
        "StarwireShowGuide": "checkbox_show_guide_button",
        "StarwireDeadzone": "seekbar_deadzone",
        "StarwireFlipFaceButtons": "checkbox_flip_face_buttons",
        "StarwireAnalogScrolling": "analog_scrolling",
        "StarwireTouchpadAsMouse": "checkbox_gamepad_touchpad_as_mouse",
        "StarwireMotionSensors": "checkbox_gamepad_motion_sensors",
        "StarwireMotionFallback": "checkbox_gamepad_motion_fallback",
        "StarwireVibrateFallback": "checkbox_vibrate_fallback",
        "StarwireMultiController": "checkbox_multi_controller",
        "StarwirePencilCurve": "list_pencil_pressure_curve",
    ]

    private static let rootPlist = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Limelight/Settings.bundle/Root.plist")

    /// The plist's specifiers, in order.
    private func plistSpecifiers() throws -> [[String: Any]] {
        let data = try Data(contentsOf: Self.rootPlist)
        let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return try XCTUnwrap(root?["PreferenceSpecifiers"] as? [[String: Any]])
    }

    private func migrate(_ ios: [String: Any]) -> [String: SettingValue] {
        let store = SettingsStore(storage: MemorySettingsStorage())
        SettingsMigration.apply(LegacySettings(coreData: nil, iosSettings: ios), to: store)
        return store.savedValues()
    }

    func testEveryNewKeyIsReadByTheApp() {
        for key in Self.mapping.keys {
            XCTAssertTrue(SettingsMigration.iosSettingsKeys.contains(key), key)
        }
    }

    func testEveryNewKeyGoesToItsAndroidKeyWithTheRightType() throws {
        for (iosKey, androidKey) in Self.mapping.sorted(by: { $0.key < $1.key }) {
            let definition = try XCTUnwrap(SettingsCatalog.definition(androidKey), "\(androidKey) is not in the catalog")
            // A value that is not the default, in the form the iOS Settings app stores it
            let sample: Any
            switch definition.defaultValue {
            case .bool(let value)?:
                sample = !value
            case .int(let value)?:
                let low = try XCTUnwrap(definition.range?.lowerBound)
                sample = low == value ? low + 1 : low
            default:
                sample = try XCTUnwrap(definition.allowedValues?.last)
            }
            let saved = migrate([iosKey: sample])
            XCTAssertEqual(Array(saved.keys), [androidKey], iosKey)
            let value = try XCTUnwrap(saved[androidKey], iosKey)
            XCTAssertEqual(value.kind, definition.kind, iosKey)
            XCTAssertTrue(definition.accepts(value), "\(iosKey) saved \(value)")
        }
    }

    func testAListANumberAndASwitchLandWithTheirValues() {
        let saved = migrate([
            "StarwireHideCursor": "touching", "StarwireTouchSensitivity": 150, "StarwireStickyModifiers": false,
            "StarwireMenuHold": "2500", "StarwireMenuTrigger": "lb_rb", "StarwirePencilCurve": "firm",
            "StarwireDeadzone": NSNumber(value: 12), "StarwireKeyboardOpacity": 40,
        ])
        XCTAssertEqual(saved, [
            "hide_cursor_mode": .string("touching"), "seekbar_touch_sensitivity": .int(150),
            "checkbox_sticky_modifier_keys": .bool(false), "overlay_hold_duration": .string("2500"),
            "overlay_trigger_button": .string("lb_rb"), "list_pencil_pressure_curve": .string("firm"),
            "seekbar_deadzone": .int(12), "seekbar_keyboard_opacity": .int(40),
        ])
    }

    func testTheHoldDurationAlsoReadsAsANumber() {
        XCTAssertEqual(migrate(["StarwireMenuHold": 3000]), ["overlay_hold_duration": .string("3000")])
    }

    func testAValueTheCatalogRefusesIsNotSaved() {
        XCTAssertEqual(migrate(["StarwireHideCursor": "sometimes", "StarwireDeadzone": 99]), [:])
    }

    func testUntouchedInputChoicesLeaveTheStoreAlone() {
        XCTAssertEqual(migrate([:]), [:])
    }

    func testThePencilCurveIsAnIOSOnlySetting() throws {
        let definition = try XCTUnwrap(SettingsCatalog.definition("list_pencil_pressure_curve"))
        XCTAssertEqual(definition.availability, .iosOnly)
        XCTAssertEqual(definition.defaultValue, .string("linear"))
        XCTAssertEqual(definition.allowedValues, ["linear", "soft", "firm"])
    }

    func testThePlistHasEveryNewKeyWithTheCatalogsDefault() throws {
        var specifiers: [String: [String: Any]] = [:]
        for item in try plistSpecifiers() {
            if let key = item["Key"] as? String { specifiers[key] = item }
        }
        for (iosKey, androidKey) in Self.mapping.sorted(by: { $0.key < $1.key }) {
            let spec = try XCTUnwrap(specifiers[iosKey], "\(iosKey) is not in Root.plist")
            let definition = try XCTUnwrap(SettingsCatalog.definition(androidKey))
            let type = spec["Type"] as? String
            XCTAssertEqual(SettingValue.coerce(spec["DefaultValue"], to: definition.kind), definition.defaultValue,
                           "\(iosKey) default")
            if definition.kind == .bool {
                XCTAssertEqual(type, "PSToggleSwitchSpecifier", iosKey)
                continue
            }
            XCTAssertEqual(type, "PSMultiValueSpecifier", iosKey)
            let titles = try XCTUnwrap(spec["Titles"] as? [String], iosKey)
            let values = try XCTUnwrap(spec["Values"] as? [Any], iosKey)
            XCTAssertEqual(titles.count, values.count, iosKey)
            // Every choice is one the catalog accepts, and the default is one of them
            let choices = values.compactMap { SettingValue.coerce($0, to: definition.kind) }
            XCTAssertEqual(choices.count, values.count, iosKey)
            for choice in choices {
                XCTAssertTrue(definition.accepts(choice), "\(iosKey) offers \(choice)")
            }
            XCTAssertTrue(choices.contains(definition.defaultValue!), "\(iosKey) offers its default")
        }
    }

    func testEveryKeyInThePlistIsUnique() throws {
        let keys = try plistSpecifiers().compactMap { $0["Key"] as? String }
        XCTAssertEqual(keys.count, Set(keys).count)
    }
}
