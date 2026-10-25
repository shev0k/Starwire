import Foundation

/// Where a setting stands on iOS. Every Android key is listed, so a JSON file from Android or a
/// later version round-trips without losing anything, even the settings iOS can't use.
public enum SettingAvailability: String, Sendable {
    /// Used on iOS, now or in a later phase.
    case supported
    /// Kept and exported, but iOS can't do it (docs/ios/parity.md, "not possible").
    case notPossible
    /// Kept and exported, but Vibeshine doesn't have it (docs/ios/parity.md, "host lacks it").
    case hostLacks
    /// iOS only: Android has no such key. Android ignores it in an import.
    case iosOnly
}

/// One saved setting: its key, how it's stored and its default.
public struct SettingDefinition: Sendable {
    public let key: String
    public let kind: SettingKind
    /// The default as Android writes it, or nil when it is computed (`seekbar_bitrate_kbps`,
    /// `checkbox_small_icon_mode`).
    public let defaultValue: SettingValue?
    /// For lists, the values Android accepts. Nil when anything of the right kind goes.
    public let allowedValues: [String]?
    /// For sliders, the range Android's screen allows.
    public let range: ClosedRange<Int>?
    public let availability: SettingAvailability
    /// True if a game's settings can override it through `gameOptions`.
    public let gameOption: Bool

    init(_ key: String, _ defaultValue: SettingValue?, kind: SettingKind? = nil, allowed: [String]? = nil,
         range: ClosedRange<Int>? = nil, _ availability: SettingAvailability = .supported, gameOption: Bool = false) {
        self.key = key
        self.kind = kind ?? defaultValue!.kind
        self.defaultValue = defaultValue
        self.allowedValues = allowed
        self.range = range
        self.availability = availability
        self.gameOption = gameOption
    }

    /// True if the value is one Android would have saved for this key.
    public func accepts(_ value: SettingValue) -> Bool {
        guard value.kind == kind else { return false }
        switch value {
        case .string(let string):
            return allowedValues.map { $0.contains(string) } ?? true
        case .int(let int):
            return range.map { $0.contains(int) } ?? true
        case .bool:
            return true
        }
    }
}

/// Every setting Starwire for Android saves in its default preferences, with Android's keys,
/// types and defaults (app/src/main/res/xml/preferences.xml and PreferenceConfiguration.java),
/// plus the iOS-only settings. Per-game settings are in `GameSettings`.
///
/// Not here, because they aren't settings: Android's migration flags, the Vulkan driver's path
/// and hash, the floating button's position, custom commands, imported shortcuts, the overrides
/// bar's state, and the microphone's pairing secrets (never exported).
public enum SettingsCatalog {
    public static let resolutions = ["1280x720", "1920x1080", "2560x1440", "3840x2160"]
    public static let framePacing = ["latency", "balanced", "cap-fps", "smoothness", "host-timed", "warp", "warp2"]
    public static let jitterBuffers = ["lowest-latency", "low-latency", "balanced", "smooth"]
    public static let videoFormats = ["auto", "forceav1", "forceh265", "neverh265", "forcepyrowave"]
    public static let virtualDisplayModes = ["host", "virtual", "primary"]

    public static let all: [SettingDefinition] = [
        // Basic
        SettingDefinition("list_resolution", .string("1280x720")),
        SettingDefinition("list_fps", .string("60")),
        SettingDefinition("seekbar_bitrate_kbps", nil, kind: .int, range: 500...500_000),
        SettingDefinition("frame_pacing", .string("balanced"), allowed: framePacing),
        SettingDefinition("jitter_buffer", .string("balanced"), allowed: jitterBuffers, gameOption: true),
        SettingDefinition("vsync_mode", .string("off"), allowed: ["off", "vsync", "fast"], gameOption: true),
        SettingDefinition("checkbox_sync_lfr", .bool(false), gameOption: true),
        SettingDefinition("checkbox_async_decode", .bool(false), gameOption: true),
        SettingDefinition("checkbox_async_lfr", .bool(false), gameOption: true),
        SettingDefinition("checkbox_ultra_low_latency", .bool(false), .notPossible),
        SettingDefinition("checkbox_stretch_video", .bool(false)),
        SettingDefinition("checkbox_auto_resume_stream", .bool(false)),

        // Audio
        SettingDefinition("list_audio_config", .string("2"), allowed: ["2", "51", "71"]),
        SettingDefinition("checkbox_enable_audiofx", .bool(false), .notPossible),
        SettingDefinition("checkbox_enable_microphone", .bool(false)),
        SettingDefinition("list_microphone_target", .string("starwire"), allowed: ["starwire", "host", "vban"]),
        SettingDefinition("list_microphone_device", .string("0")),
        SettingDefinition("text_vban_stream_name", .string("Stream1")),
        SettingDefinition("text_vban_port", .string("6980")),
        SettingDefinition("list_audio_haptics", .string("off"), allowed: ["off", "device", "controller", "both"], gameOption: true),
        SettingDefinition("seekbar_audio_haptics_intensity", .int(100), range: 25...200),

        // Gamepad
        SettingDefinition("seekbar_deadzone", .int(7), range: 1...20),
        SettingDefinition("checkbox_multi_controller", .bool(true)),
        SettingDefinition("checkbox_usb_driver", .bool(true), .notPossible),
        SettingDefinition("checkbox_usb_bind_all", .bool(false), .notPossible),
        SettingDefinition("analog_scrolling", .string("right"), allowed: ["none", "right", "left"]),
        SettingDefinition("checkbox_vibrate_fallback", .bool(false)),
        SettingDefinition("seekbar_vibrate_fallback_strength", .int(100), range: 1...200),
        SettingDefinition("checkbox_flip_face_buttons", .bool(false)),
        SettingDefinition("checkbox_gamepad_touchpad_as_mouse", .bool(false)),
        SettingDefinition("checkbox_gamepad_motion_sensors", .bool(true)),
        SettingDefinition("checkbox_gamepad_motion_fallback", .bool(false)),

        // Overlay menu
        SettingDefinition("overlay_trigger_button", .string("select"), allowed: ["select", "start", "guide", "lb_rb"]),
        SettingDefinition("overlay_hold_duration", .string("1500"), allowed: ["500", "1000", "1500", "2000", "2500", "3000"]),
        SettingDefinition("checkbox_enable_floating_button", .bool(true)),

        // Input
        SettingDefinition("checkbox_touchscreen_trackpad", .bool(true), gameOption: true),
        SettingDefinition("checkbox_long_press_right_click", .bool(true)),
        SettingDefinition("checkbox_pinch_to_zoom", .bool(true)),
        SettingDefinition("hide_cursor_mode", .string("never"), allowed: ["never", "touching", "always"], gameOption: true),
        SettingDefinition("seekbar_touch_sensitivity", .int(100), range: 25...300),
        SettingDefinition("checkbox_keyboard_vibrate", .bool(true)),
        SettingDefinition("checkbox_sticky_modifier_keys", .bool(true)),
        SettingDefinition("seekbar_keyboard_opacity", .int(90), range: 20...100),
        SettingDefinition("checkbox_mouse_nav_buttons", .bool(false)),
        SettingDefinition("checkbox_absolute_mouse_mode", .bool(false)),
        SettingDefinition("checkbox_mouse_emulation", .bool(true)),

        // On-screen controls
        SettingDefinition("checkbox_show_onscreen_controls", .bool(false)),
        SettingDefinition("checkbox_vibrate_osc", .bool(true)),
        SettingDefinition("checkbox_only_show_L3R3", .bool(false)),
        SettingDefinition("checkbox_show_guide_button", .bool(true)),
        SettingDefinition("seekbar_osc_opacity", .int(90), range: 0...100),

        // Host
        SettingDefinition("checkbox_enable_sops", .bool(true)),
        SettingDefinition("checkbox_host_audio", .bool(false)),
        SettingDefinition("virtual_display_mode", .string("host"), allowed: virtualDisplayModes, gameOption: true),
        SettingDefinition("checkbox_prevent_packet_loss", .bool(false)),
        SettingDefinition("checkbox_smart_clipboard_sync", .bool(false), .hostLacks),
        SettingDefinition("checkbox_smart_clipboard_sync_toast", .bool(false), .hostLacks),
        SettingDefinition("checkbox_hide_clipboard_content", .bool(false), .hostLacks),

        // UI
        SettingDefinition("cover_style", .string("missing"), allowed: ["missing", "always", "never"]),
        SettingDefinition("checkbox_enable_pip", .bool(false)),
        SettingDefinition("list_languages", .string("default")),
        SettingDefinition("checkbox_small_icon_mode", nil, kind: .bool),

        // Advanced
        SettingDefinition("checkbox_reduce_refresh_rate", .bool(false)),
        SettingDefinition("text_actual_display_refresh_rate", .string("0")),
        SettingDefinition("checkbox_disable_warnings", .bool(false)),
        SettingDefinition("video_format", .string("auto"), allowed: videoFormats, gameOption: true),
        SettingDefinition("pyrowave_late_frames", .string("balanced"), allowed: ["off", "sharp", "balanced", "smooth", "smoothest"]),
        // Android: auto, direct, vulkan. iOS: auto (the system's video layer), display (Metal,
        // display driven) or loop (Metal render loop). Android's values import as auto.
        SettingDefinition("video_renderer", .string("auto"), allowed: ["auto", "direct", "vulkan", "system", "display", "loop"]),
        SettingDefinition("checkbox_custom_vulkan_driver", .bool(false), .notPossible),
        SettingDefinition("checkbox_custom_vulkan_driver_toast", .bool(true), .notPossible),
        SettingDefinition("spatial_dithering", .string("off"), allowed: ["off", "low", "high"]),
        SettingDefinition("checkbox_enable_hdr", .bool(false)),
        SettingDefinition("checkbox_full_range", .bool(false)),
        SettingDefinition("checkbox_enable_perf_overlay", .bool(false)),
        SettingDefinition("checkbox_enable_perf_overlay_lite", .bool(false)),
        SettingDefinition("checkbox_enable_post_stream_toast", .bool(false)),

        // iOS only. Named the Android way, so they sit with the rest in an export.
        SettingDefinition("checkbox_enable_yuv444", .bool(false), .iosOnly),
        SettingDefinition("list_spatial_audio", .string("fixed"), allowed: ["fixed", "head-tracked", "off"], .iosOnly),
        SettingDefinition("list_onscreen_controls", .string("auto"), allowed: ["off", "auto", "simple", "full"], .iosOnly),
        SettingDefinition("checkbox_bt_mouse_support", .bool(false), .iosOnly),
        SettingDefinition("checkbox_enable_graphs", .bool(false), .iosOnly),
        SettingDefinition("seekbar_graph_opacity", .int(50), range: 0...100, .iosOnly),
        SettingDefinition("seekbar_frames_to_buffer", .int(2), range: 1...5, .iosOnly),
        SettingDefinition("list_external_display", .string("mirror"), allowed: ["mirror", "video"], .iosOnly),
        SettingDefinition("checkbox_frame_interpolation", .bool(false), .iosOnly),
        SettingDefinition("list_present_timing", .string("nearest"), allowed: ["nearest", "frame"], .iosOnly),
        SettingDefinition("list_drop_policy", .string("alternate"), allowed: ["alternate", "newest"], .iosOnly),
        SettingDefinition("seekbar_pacing_frames_to_buffer", .int(0), range: 0...4, .iosOnly),
        SettingDefinition("checkbox_verbose_logging", .bool(false), .iosOnly),
        // Vibeshine launch options (phase 2): the virtual display's scale in percent (0 lets the
        // host decide), and asking for a variable refresh rate virtual display.
        SettingDefinition("seekbar_virtual_display_scale", .int(0), range: 0...400, .iosOnly),
        SettingDefinition("checkbox_vrr_request", .bool(false), .iosOnly),
        // The name this device gives the PC at launch (`clientName`). Empty uses the device's own.
        SettingDefinition("text_client_name", .string(""), .iosOnly),
        // The Apple Pencil's pressure curve (Android has no Pencil).
        SettingDefinition("list_pencil_pressure_curve", .string("linear"), allowed: ["linear", "soft", "firm"], .iosOnly),

        // Batch 4.5. The touch mode and the picture's fit default to what Android's switches say
        // (checkbox_touchscreen_trackpad, checkbox_stretch_video), so older settings carry over.
        SettingDefinition("list_touch_mode", nil, kind: .string, allowed: TouchMode.allCases.map(\.settingValue), .iosOnly,
                          gameOption: true),
        SettingDefinition("list_video_scaling", nil, kind: .string, allowed: PictureScaling.allCases.map(\.rawValue), .iosOnly,
                          gameOption: true),
        SettingDefinition("list_keyboard_preset", .string("full"), allowed: KeyboardPreset.allCases.map(\.rawValue), .iosOnly),
        SettingDefinition("seekbar_keyboard_size", .int(100), range: KeyboardCustomization.sizeRange, .iosOnly),
        SettingDefinition("list_keyboard_placement", .string("docked"), allowed: KeyboardPlacement.allCases.map(\.rawValue),
                          .iosOnly),
        // Remapped keys per keyboard, as JSON: {"full":{"caps":"esc"}}
        SettingDefinition("keyboard_remapped_keys", .string(""), .iosOnly),
        SettingDefinition("checkbox_controller_keyboard", .bool(true), .iosOnly),
        SettingDefinition("list_menu_button_style", .string("floating"), allowed: MenuButtonOptions.Style.allCases.map(\.rawValue),
                          .iosOnly),
        SettingDefinition("list_menu_button_size", .string("medium"), allowed: MenuButtonOptions.Size.allCases.map(\.rawValue),
                          .iosOnly),
        SettingDefinition("seekbar_menu_button_opacity", .int(60), range: 20...100, .iosOnly),
        SettingDefinition("list_menu_button_auto_hide", .string("off"), allowed: MenuButtonOptions.autoHideChoices, .iosOnly),
        SettingDefinition("list_gesture_three_finger_tap", .string("menu"), allowed: GestureAction.allCases.map(\.rawValue),
                          .iosOnly),
        SettingDefinition("list_gesture_four_finger_tap", .string("full_keyboard"), allowed: GestureAction.allCases.map(\.rawValue),
                          .iosOnly),
        SettingDefinition("list_gesture_five_finger_tap", .string("menu"), allowed: GestureAction.allCases.map(\.rawValue),
                          .iosOnly),
    ]

    private static let byKey: [String: SettingDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    public static func definition(_ key: String) -> SettingDefinition? {
        byKey[key]
    }

    /// The keys a game can override through its `gameOptions`, in Android's order
    /// (PreferenceConfiguration.GAME_OPTION_KEYS).
    public static let gameOptionKeys = [
        "video_format", "vsync_mode", "checkbox_sync_lfr", "checkbox_async_decode", "checkbox_async_lfr",
        "virtual_display_mode", "checkbox_touchscreen_trackpad", "hide_cursor_mode", "list_audio_haptics",
        "jitter_buffer",
    ]

    /// Per-game options iOS adds; Android keeps unknown options it is given and ignores them.
    public static let iosGameOptionKeys = ["list_touch_mode", "list_video_scaling"]
}
