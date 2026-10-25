// Ported from Starwire for Android's preferences.xml and CoverGlowSettings.java (GPL-3.0): the
// sections, their order and the rows in them. The iOS-only settings are placed by hand.

import Foundation

/// One thing that decides whether a row shows or is enabled, other than another setting being on.
public enum SettingRequirement: Equatable, Sendable {
    /// The device has a feature (Android removes the row without it).
    case device(DeviceFeature)
    /// Another setting has one of these values (a list's saved value).
    case value(String, in: [String])
}

/// What Android's settings screen asks the device about before it shows a row. The app answers.
public enum DeviceFeature: String, Equatable, Sendable {
    /// A vibration motor (`Vibrator.hasVibrator`). iPads have none, so these rows may not show.
    case vibration
    /// A display that can show HDR10.
    case hdrDisplay
    /// An accelerometer or a gyroscope.
    case motionSensors
    /// Picture in picture.
    case pictureInPicture
    /// A touchscreen. Without one the whole on-screen controls group goes.
    case touchscreen
}

/// What a text field accepts.
public enum SettingTextInput: Equatable, Sendable {
    case plain
    case number
    case decimal
}

/// How a row is changed.
public enum SettingControl: Equatable, Sendable {
    case toggle
    /// A list. `entries` and `values` have the same length. An entry is a string name, or
    /// `arrayname.N` for item N of an Android string array. `allowsCustom` is for the resolution
    /// and frame rate lists, where any value can be typed in.
    case list(entries: [String], values: [String], allowsCustom: Bool)
    /// A list the app fills in when the screen opens (the microphone's input devices). The first
    /// entry is `defaultEntry`, with the value "0".
    case dynamicList(defaultEntry: String)
    /// A slider. The saved number is shown divided by `divisor` (the bitrate is saved in kbps and
    /// shown in Mbps). `unitKey` is a string name for the unit after the number. With
    /// `allowsCustom` a number outside the range can be typed in.
    case slider(range: ClosedRange<Int>, step: Int, divisor: Int, unitKey: String?, allowsCustom: Bool)
    case text(SettingTextInput, maxLength: Int?)
    /// A button. The text is a stable name for what it does, such as `pair_microphone`.
    case action(String)
    /// A link. The text is the address.
    case link(String)
}

/// Whether the screen should draw a row at all.
public enum SettingPresence: Equatable, Sendable {
    case shown
    /// Kept in the layout, so nothing is lost, but iOS can't do it or the PC lacks it.
    case hidden(SettingAvailability)
}

/// A question asked before an action runs (Android's "Reset Layout" dialog).
public struct SettingConfirmation: Equatable, Sendable {
    public let titleKey: String
    public let messageKey: String

    /// The buttons' string names.
    public static let yesKey = "yes"
    public static let noKey = "no"

    public init(titleKey: String, messageKey: String) {
        self.titleKey = titleKey
        self.messageKey = messageKey
    }
}

/// One row on the settings screen.
public struct SettingsItem: Identifiable, Equatable, Sendable {
    /// The preference key. Buttons and links that have no key on Android have a stable id here.
    public let id: String
    public let control: SettingControl
    /// Android string names. A summary may take arguments (`summary_about_version`).
    public let titleKey: String
    public let summaryKey: String?
    /// True when Android shows the chosen entry as the summary (`android:summary="%s"`).
    public let summaryShowsChoice: Bool
    /// The "Impact:" line (`impact_label` and then this string), or nil.
    public let impactKey: String?
    /// A setting that must be on for this row to be enabled.
    public let dependency: String?
    /// The row is only there while this holds.
    public let showWhen: SettingRequirement?
    /// The row is only enabled while this holds.
    public let enabledWhen: SettingRequirement?
    /// Where the setting came from, for the "From <fork>" line.
    public let credit: SettingCredit?
    public let presence: SettingPresence
    /// For the per-game screen: the global setting this row overrides.
    public let overrides: String?
    public let confirmation: SettingConfirmation?

    public var isShown: Bool { presence == .shown }
}

public struct SettingsGroup: Identifiable, Equatable, Sendable {
    /// Android's category key (`category_basic_settings`), or `ios_...` for a group of iOS-only rows.
    public let id: String
    /// nil for Android's own group in a section: its heading is the section's title, as the pills
    /// rename Android's headings. iOS-only groups have a title.
    public let titleKey: String?
    /// The group is only there while this holds.
    public let showWhen: SettingRequirement?
    public let items: [SettingsItem]

    /// The items the screen should draw (not the ones iOS can't do or the PC lacks).
    public var shownItems: [SettingsItem] { items.filter(\.isShown) }
}

public struct SettingsSection: Identifiable, Equatable, Sendable {
    public let id: String
    /// The section's name on its pill: Android's `cg_section_...` string.
    public let titleKey: String
    public let groups: [SettingsGroup]

    public var items: [SettingsItem] { groups.flatMap(\.items) }
}

/// Android's settings screen as data, in Android's order, for a SwiftUI screen to draw. Titles,
/// summaries and entries are Android string names (strings.xml, and arrays.xml as
/// `arrayname.N`) or `ios_` names (ios/Strings/strings-ios.xml). The sections are the pills at the
/// top of Android's screen, and each has Android's category followed by the iOS-only settings a
/// user would look for there.
public enum SettingsLayout {
    public static let sections: [SettingsSection] = [
        SettingsSection(id: "stream", titleKey: "cg_section_stream", groups: [
            SettingsGroup(id: "category_basic_settings", titleKey: nil, showWhen: nil, items: [
                .list("list_resolution", "title_resolution_list", array: "resolution",
                      values: ["1280x720", "1920x1080", "2560x1440", "3840x2160"], custom: true,
                      summary: "summary_resolution_list"),
                .list("list_fps", "title_fps_list", array: "fps", values: ["30", "60", "90", "120"], custom: true,
                      summary: "summary_fps_list"),
                .slider("seekbar_bitrate_kbps", "title_seekbar_bitrate", 500...150000, step: 500, divisor: 1000,
                        unit: "suffix_seekbar_bitrate_mbps", custom: true, summary: "summary_seekbar_bitrate"),
                .list("frame_pacing", "title_frame_pacing", array: "video_frame_pacing",
                      values: SettingsCatalog.framePacing, summary: "summary_frame_pacing"),
                // Android only uses it with host-timed pacing; on iOS it smooths every pacing mode
                // (batch 1), so it is never greyed out and has its own summary
                .list("jitter_buffer", "title_jitter_buffer", array: "jitter_buffer",
                      values: SettingsCatalog.jitterBuffers, summary: "ios_summary_jitter_buffer"),
                .list("vsync_mode", "title_vsync_mode", array: "vsync_mode", values: ["off", "vsync", "fast"],
                      summary: "summary_vsync_mode"),
                .toggle("checkbox_sync_lfr", "title_checkbox_sync_lfr", summary: "summary_checkbox_sync_lfr"),
                .toggle("checkbox_async_decode", "title_checkbox_async_decode", summary: "summary_checkbox_async_decode"),
                .toggle("checkbox_async_lfr", "title_checkbox_async_lfr", summary: "summary_checkbox_async_lfr",
                        dependency: "checkbox_async_decode"),
                .toggle("checkbox_ultra_low_latency", "title_checkbox_ultra_low_latency",
                        summary: "summary_checkbox_ultra_low_latency"),
                .toggle("checkbox_stretch_video", "title_checkbox_stretch_video"),
                .toggle("checkbox_auto_resume_stream", "title_checkbox_auto_resume_stream",
                        summary: "summary_checkbox_auto_resume_stream"),
            ]),
            SettingsGroup(id: "ios_stream", titleKey: "ios_group_this_device", showWhen: nil, items: [
                .toggle("checkbox_frame_interpolation", "ios_title_frame_interpolation",
                        summary: "ios_summary_frame_interpolation"),
                .list("list_external_display", "ios_title_external_display",
                      entries: ["ios_external_display_mirror", "ios_external_display_video"],
                      values: ["mirror", "video"], summary: "ios_summary_external_display"),
                .slider("seekbar_frames_to_buffer", "ios_title_frames_to_buffer", 1...5,
                        summary: "ios_summary_frames_to_buffer"),
            ]),
        ]),

        SettingsSection(id: "sound", titleKey: "cg_section_sound", groups: [
            SettingsGroup(id: "category_audio_settings", titleKey: nil, showWhen: nil, items: [
                .list("list_audio_config", "title_audio_config_list", array: "audio_config", values: ["2", "51", "71"],
                      summary: "summary_audio_config_list"),
                .toggle("checkbox_enable_audiofx", "title_checkbox_enable_audiofx",
                        summary: "summary_checkbox_enable_audiofx"),
                .toggle("checkbox_enable_microphone", "title_checkbox_enable_microphone",
                        summary: "summary_checkbox_enable_microphone"),
                .list("list_microphone_target", "title_microphone_target", array: "microphone_target",
                      values: ["starwire", "host", "vban"], summaryShowsChoice: true,
                      dependency: "checkbox_enable_microphone"),
                .dynamicList("list_microphone_device", "title_microphone_device_list",
                             defaultEntry: "microphone_device_default", summary: "summary_microphone_device_list",
                             dependency: "checkbox_enable_microphone"),
                // Only the rows for the chosen microphone destination show (StreamSettings.showMicrophoneTarget)
                .link("microphone_host_info", "title_microphone_host_info",
                      url: "https://github.com/logabell/apollo-microphone/releases",
                      summary: "summary_microphone_host_info", showWhen: .value("list_microphone_target", in: ["host"]),
                      presence: .hidden(.hostLacks)),
                .link("vban_setup_info", "title_vban_setup",
                      url: "https://github.com/SicarioGaming/Starwire/tree/main/windows#readme",
                      dependency: "checkbox_enable_microphone",
                      showWhen: .value("list_microphone_target", in: ["starwire", "vban"])),
                .action("mic_pairing", "title_mic_pairing", "pair_microphone", summary: "summary_mic_pairing_none",
                        dependency: "checkbox_enable_microphone",
                        showWhen: .value("list_microphone_target", in: ["starwire"])),
                .text("text_vban_stream_name", "title_vban_stream_name", .plain, maxLength: 16,
                      dependency: "checkbox_enable_microphone",
                      showWhen: .value("list_microphone_target", in: ["vban"])),
                .text("text_vban_port", "title_vban_port", .number, maxLength: 5,
                      dependency: "checkbox_enable_microphone",
                      showWhen: .value("list_microphone_target", in: ["starwire", "vban"])),
                .list("list_audio_haptics", "title_audio_haptics", array: "audio_haptics",
                      values: ["off", "device", "controller", "both"], summary: "summary_audio_haptics"),
                .slider("seekbar_audio_haptics_intensity", "title_audio_haptics_intensity", 25...200, step: 5,
                        unit: "suffix_seekbar_deadzone", summary: "summary_audio_haptics_intensity"),
            ]),
            SettingsGroup(id: "ios_sound", titleKey: "ios_group_this_device", showWhen: nil, items: [
                .list("list_spatial_audio", "ios_title_spatial_audio",
                      entries: ["ios_spatial_audio_fixed", "ios_spatial_audio_head_tracked", "ios_spatial_audio_off"],
                      values: ["fixed", "head-tracked", "off"], summary: "ios_summary_spatial_audio"),
            ]),
        ]),

        SettingsSection(id: "controllers", titleKey: "cg_section_controllers", groups: [
            SettingsGroup(id: "category_gamepad_settings", titleKey: nil, showWhen: nil, items: [
                .slider("seekbar_deadzone", "title_seekbar_deadzone", 1...20, unit: "suffix_seekbar_deadzone",
                        summary: "summary_seekbar_deadzone"),
                .toggle("checkbox_multi_controller", "title_checkbox_multi_controller",
                        summary: "summary_checkbox_multi_controller"),
                .toggle("checkbox_usb_driver", "title_checkbox_xb1_driver", summary: "summary_checkbox_xb1_driver"),
                .toggle("checkbox_usb_bind_all", "title_checkbox_usb_bind_all", summary: "summary_checkbox_usb_bind_all",
                        dependency: "checkbox_usb_driver"),
                .list("analog_scrolling", "title_analog_scrolling", array: "analog_scrolling",
                      values: ["none", "right", "left"], summary: "summary_analog_scrolling"),
                .toggle("checkbox_vibrate_fallback", "title_checkbox_vibrate_fallback",
                        summary: "summary_checkbox_vibrate_fallback", showWhen: .device(.vibration)),
                .slider("seekbar_vibrate_fallback_strength", "title_seekbar_vibrate_fallback_strength", 1...200,
                        unit: "suffix_seekbar_vibrate_fallback_strength",
                        summary: "summary_seekbar_vibrate_fallback_strength", dependency: "checkbox_vibrate_fallback",
                        showWhen: .device(.vibration)),
                .toggle("checkbox_flip_face_buttons", "title_checkbox_flip_face_buttons",
                        summary: "summary_checkbox_flip_face_buttons"),
                .toggle("checkbox_gamepad_touchpad_as_mouse", "title_checkbox_gamepad_touchpad_as_mouse",
                        summary: "summary_checkbox_gamepad_touchpad_as_mouse"),
                .toggle("checkbox_gamepad_motion_sensors", "title_checkbox_gamepad_motion_sensors",
                        summary: "summary_checkbox_gamepad_motion_sensors"),
                .toggle("checkbox_gamepad_motion_fallback", "title_checkbox_gamepad_motion_fallback",
                        summary: "summary_checkbox_gamepad_motion_fallback", showWhen: .device(.motionSensors)),
            ]),
        ]),

        SettingsSection(id: "menu", titleKey: "cg_section_menu", groups: [
            SettingsGroup(id: "category_overlay_menu", titleKey: nil, showWhen: nil, items: [
                .list("overlay_trigger_button", "title_overlay_trigger_button", array: "overlay_trigger_button",
                      values: ["select", "start", "guide", "lb_rb"], summary: "summary_overlay_trigger_button"),
                .list("overlay_hold_duration", "title_overlay_hold_duration", array: "overlay_hold_duration",
                      values: ["500", "1000", "1500", "2000", "2500", "3000"], summary: "summary_overlay_hold_duration"),
                .toggle("checkbox_enable_floating_button", "title_floating_button", summary: "summary_floating_button"),
                .action("overlay_custom_commands", "title_overlay_custom_commands", "open_custom_commands",
                        summary: "summary_overlay_custom_commands"),
                .action("import_shortcuts_file", "title_import_shortcuts", "import_shortcuts",
                        summary: "summary_import_shortcuts"),
                .action("clear_imported_shortcuts", "title_clear_imported_shortcuts", "clear_imported_shortcuts",
                        summary: "summary_clear_imported_shortcuts"),
            ]),
        ]),

        SettingsSection(id: "touch", titleKey: "cg_section_touch", groups: [
            SettingsGroup(id: "category_input_settings", titleKey: nil, showWhen: nil, items: [
                .toggle("checkbox_touchscreen_trackpad", "title_checkbox_touchscreen_trackpad",
                        summary: "summary_checkbox_touchscreen_trackpad"),
                .toggle("checkbox_long_press_right_click", "title_checkbox_long_press_right_click",
                        summary: "summary_checkbox_long_press_right_click"),
                .toggle("checkbox_pinch_to_zoom", "title_checkbox_pinch_to_zoom", summary: "summary_checkbox_pinch_to_zoom"),
                .list("hide_cursor_mode", "title_hide_cursor_mode", array: "hide_cursor_mode",
                      values: ["never", "touching", "always"], summary: "summary_hide_cursor_mode"),
                .slider("seekbar_touch_sensitivity", "title_seekbar_touch_sensitivity", 25...300, step: 5,
                        unit: "suffix_seekbar_deadzone", summary: "summary_seekbar_touch_sensitivity"),
                .toggle("checkbox_keyboard_vibrate", "title_checkbox_keyboard_vibrate",
                        summary: "summary_checkbox_keyboard_vibrate"),
                .toggle("checkbox_sticky_modifier_keys", "title_checkbox_sticky_modifier_keys",
                        summary: "summary_checkbox_sticky_modifier_keys"),
                .slider("seekbar_keyboard_opacity", "title_seekbar_keyboard_opacity", 20...100, step: 5,
                        unit: "suffix_seekbar_deadzone", summary: "summary_seekbar_keyboard_opacity"),
                .toggle("checkbox_mouse_nav_buttons", "title_checkbox_mouse_nav_buttons",
                        summary: "summary_checkbox_mouse_nav_buttons"),
                .toggle("checkbox_absolute_mouse_mode", "title_checkbox_absolute_mouse_mode",
                        summary: "summary_checkbox_absolute_mouse_mode"),
            ]),
            SettingsGroup(id: "ios_touch", titleKey: "ios_group_this_device", showWhen: nil, items: [
                .toggle("checkbox_bt_mouse_support", "ios_title_bt_mouse", summary: "ios_summary_bt_mouse"),
                .list("list_pencil_pressure_curve", "ios_title_pencil_curve",
                      entries: ["ios_pencil_curve_linear", "ios_pencil_curve_soft", "ios_pencil_curve_firm"],
                      values: ["linear", "soft", "firm"], summary: "ios_summary_pencil_curve"),
            ]),
        ]),

        SettingsSection(id: "onscreen", titleKey: "cg_section_onscreen", groups: [
            // Android removes the whole group on a device with no touchscreen
            SettingsGroup(id: "category_onscreen_controls", titleKey: nil, showWhen: .device(.touchscreen), items: [
                .toggle("checkbox_show_onscreen_controls", "title_checkbox_show_onscreen_controls",
                        summary: "summary_checkbox_show_onscreen_controls"),
                .toggle("checkbox_vibrate_osc", "title_checkbox_vibrate_osc", summary: "summary_checkbox_vibrate_osc",
                        dependency: "checkbox_show_onscreen_controls", showWhen: .device(.vibration)),
                .toggle("checkbox_only_show_L3R3", "title_only_l3r3", summary: "summary_only_l3r3",
                        dependency: "checkbox_show_onscreen_controls"),
                .toggle("checkbox_show_guide_button", "title_show_guide_button", summary: "summary_show_guide_button",
                        dependency: "checkbox_show_onscreen_controls"),
                .slider("seekbar_osc_opacity", "dialog_title_osc_opacity", 0...100, unit: "suffix_osc_opacity",
                        summary: "summary_osc_opacity", dependency: "checkbox_show_onscreen_controls"),
                // Android's ConfirmDeleteOscPreference has no key
                .action("reset_osc_layout", "title_reset_osc", "reset_onscreen_controls_layout",
                        summary: "summary_reset_osc",
                        confirmation: SettingConfirmation(titleKey: "dialog_title_reset_osc",
                                                          messageKey: "dialog_text_reset_osc")),
            ]),
            SettingsGroup(id: "ios_onscreen", titleKey: "ios_group_this_device", showWhen: .device(.touchscreen), items: [
                .list("list_onscreen_controls", "ios_title_onscreen_controls_level",
                      entries: ["ios_onscreen_controls_off", "ios_onscreen_controls_auto",
                                "ios_onscreen_controls_simple", "ios_onscreen_controls_full"],
                      values: ["off", "auto", "simple", "full"], summary: "ios_summary_onscreen_controls_level",
                      dependency: "checkbox_show_onscreen_controls"),
            ]),
        ]),

        SettingsSection(id: "pc", titleKey: "cg_section_pc", groups: [
            // This category has no key on Android
            SettingsGroup(id: "category_host_settings", titleKey: nil, showWhen: nil, items: [
                .toggle("checkbox_enable_sops", "title_checkbox_enable_sops", summary: "summary_checkbox_enable_sops"),
                .toggle("checkbox_host_audio", "title_checkbox_host_audio", summary: "summary_checkbox_host_audio"),
                .list("virtual_display_mode", "title_virtual_display_mode", array: "virtual_display_mode",
                      values: ["host", "virtual", "primary"], summary: "summary_virtual_display_mode"),
                .toggle("checkbox_prevent_packet_loss", "title_checkbox_prevent_packet_loss",
                        summary: "summary_checkbox_prevent_packet_loss"),
                .toggle("checkbox_smart_clipboard_sync", "title_checkbox_smart_clipboard_sync",
                        summary: "summary_checkbox_smart_clipboard_sync"),
                .toggle("checkbox_smart_clipboard_sync_toast", "title_checkbox_smart_clipboard_sync_toast",
                        summary: "summary_checkbox_smart_clipboard_sync_toast", dependency: "checkbox_smart_clipboard_sync"),
                .toggle("checkbox_hide_clipboard_content", "title_checkbox_hide_clipboard_content",
                        summary: "summary_checkbox_hide_clipboard_content"),
            ]),
            SettingsGroup(id: "ios_pc", titleKey: "ios_group_this_device", showWhen: nil, items: [
                .slider("seekbar_virtual_display_scale", "ios_title_virtual_display_scale", 0...400, step: 25,
                        unit: "suffix_seekbar_deadzone", summary: "ios_summary_virtual_display_scale"),
                .toggle("checkbox_vrr_request", "ios_title_vrr_request", summary: "ios_summary_vrr_request"),
                .text("text_client_name", "ios_title_client_name", .plain, summary: "ios_summary_client_name"),
            ]),
        ]),

        SettingsSection(id: "app", titleKey: "cg_section_app", groups: [
            SettingsGroup(id: "category_ui_settings", titleKey: nil, showWhen: nil, items: [
                .list("cover_style", "title_cover_style", array: "cover_style", values: ["missing", "always", "never"],
                      summaryShowsChoice: true),
                .toggle("checkbox_enable_pip", "title_checkbox_enable_pip", summary: "summary_checkbox_enable_pip",
                        showWhen: .device(.pictureInPicture)),
                .list("list_languages", "title_language_list", array: "language", values: languages,
                      summary: "summary_language_list"),
                .toggle("checkbox_small_icon_mode", "title_checkbox_small_icon_mode",
                        summary: "summary_checkbox_small_icon_mode"),
            ]),
        ]),

        SettingsSection(id: "advanced", titleKey: "cg_section_advanced", groups: [
            SettingsGroup(id: "category_advanced_settings", titleKey: nil, showWhen: nil, items: [
                .toggle("checkbox_reduce_refresh_rate", "title_checkbox_reduce_refresh_rate",
                        summary: "summary_checkbox_reduce_refresh_rate"),
                .text("text_actual_display_refresh_rate", "title_actual_display_refresh_rate", .decimal,
                      summary: "summary_actual_display_refresh_rate"),
                .toggle("checkbox_disable_warnings", "title_checkbox_disable_warnings",
                        summary: "summary_checkbox_disable_warnings"),
                .list("video_format", "title_video_format", array: "video_format", values: SettingsCatalog.videoFormats,
                      summary: "summary_video_format"),
                .list("pyrowave_late_frames", "title_pyrowave_late_frames", array: "pyrowave_late_frames",
                      values: ["off", "sharp", "balanced", "smooth", "smoothest"], summary: "summary_pyrowave_late_frames"),
                // Android's choices are Automatic, Direct Surface and Vulkan. iOS has the system
                // video layer (Automatic) and the two Metal presenters, and Android's impact line
                // talks about Vulkan, so this row has none. A saved "system" means Automatic
                // (`SettingsLayout.valueAliases`).
                .list("video_renderer", "title_video_renderer",
                      entries: ["ios_video_renderer_auto", "ios_video_renderer_display", "ios_video_renderer_loop"],
                      values: ["auto", "display", "loop"], summary: "ios_summary_video_renderer", impact: false),
                .toggle("checkbox_custom_vulkan_driver", "title_custom_vulkan_driver",
                        summary: "summary_custom_vulkan_driver"),
                .action("text_custom_vulkan_driver_path", "title_custom_vulkan_driver_path", "choose_vulkan_driver",
                        summary: "summary_custom_vulkan_driver_path", dependency: "checkbox_custom_vulkan_driver",
                        presence: .hidden(.notPossible)),
                .action("remove_custom_vulkan_driver", "title_remove_custom_vulkan_driver", "remove_vulkan_driver",
                        summary: "summary_remove_custom_vulkan_driver", dependency: "checkbox_custom_vulkan_driver",
                        presence: .hidden(.notPossible)),
                .toggle("checkbox_custom_vulkan_driver_toast", "title_custom_vulkan_driver_toast",
                        summary: "summary_custom_vulkan_driver_toast", dependency: "checkbox_custom_vulkan_driver"),
                .list("spatial_dithering", "title_spatial_dithering", array: "spatial_dithering",
                      values: ["off", "low", "high"], summary: "summary_spatial_dithering"),
                .toggle("checkbox_enable_hdr", "title_enable_hdr", summary: "summary_enable_hdr",
                        showWhen: .device(.hdrDisplay)),
                .toggle("checkbox_full_range", "title_full_range", summary: "summary_full_range"),
                .toggle("checkbox_enable_perf_overlay", "title_enable_perf_overlay",
                        summary: "summary_enable_perf_overlay"),
                .toggle("checkbox_enable_perf_overlay_lite", "title_checkbox_enable_perf_overlay_lite",
                        summary: "summary_checkbox_enable_perf_overlay_lite", dependency: "checkbox_enable_perf_overlay"),
                .toggle("checkbox_enable_post_stream_toast", "title_enable_post_stream_toast",
                        summary: "summary_enable_post_stream_toast"),
            ]),
            SettingsGroup(id: "ios_advanced", titleKey: "ios_group_this_device", showWhen: nil, items: [
                .toggle("checkbox_enable_yuv444", "ios_title_yuv444", summary: "ios_summary_yuv444"),
                .toggle("checkbox_enable_graphs", "ios_title_graphs", summary: "ios_summary_graphs"),
                .slider("seekbar_graph_opacity", "ios_title_graph_opacity", 0...100, step: 5,
                        unit: "suffix_seekbar_deadzone", summary: "ios_summary_graph_opacity",
                        dependency: "checkbox_enable_graphs"),
                .toggle("checkbox_verbose_logging", "ios_title_verbose_logging", summary: "ios_summary_verbose_logging"),
            ]),
            SettingsGroup(id: "ios_pacing_tests", titleKey: "ios_group_pacing_tests", showWhen: nil, items: [
                .list("list_present_timing", "ios_title_present_timing",
                      entries: ["ios_present_timing_nearest", "ios_present_timing_frame"],
                      values: ["nearest", "frame"], summary: "ios_summary_present_timing"),
                .list("list_drop_policy", "ios_title_drop_policy",
                      entries: ["ios_drop_policy_alternate", "ios_drop_policy_newest"],
                      values: ["alternate", "newest"], summary: "ios_summary_drop_policy"),
                .slider("seekbar_pacing_frames_to_buffer", "ios_title_pacing_frames_to_buffer", 0...4,
                        summary: "ios_summary_pacing_frames_to_buffer"),
            ]),
        ]),

        SettingsSection(id: "about", titleKey: "category_about", groups: [
            SettingsGroup(id: "category_about", titleKey: nil, showWhen: nil, items: [
                // The summary is filled in with the version, the build and the commit
                .action("about_version", "title_about_version", "copy_version", summary: "summary_about_version"),
                .link("about_github", "title_about_github", url: "https://github.com/SicarioGaming/Starwire",
                      summary: "summary_about_github"),
                .link("about_issues", "title_about_issues",
                      url: "https://github.com/SicarioGaming/Starwire/issues/new/choose", summary: "summary_about_issues"),
                // The summary is filled in with the version
                .action("about_source", "title_about_source", "open_source", summary: "summary_about_source"),
                .action("about_credits", "title_about_credits", "show_credits", summary: "summary_about_credits"),
                .action("about_licences", "title_about_licences", "show_licences", summary: "summary_about_licences"),
            ]),
        ]),
    ]

    /// The language codes in Android's language list (`language_values`).
    private static let languages = ["default", "en", "it", "ja", "ru", "nl", "zh-CN", "zh-TW", "ko", "es", "fr", "de",
                                    "ro", "uk", "nb-NO", "vi", "hu", "el", "pt-BR", "cs", "iw", "sv", "in", "eo", "lv", "ta"]

    /// Saved values that mean the same as one of a list's values. The Presenter choice in iOS
    /// Settings saved "system" for the system video layer, which is Automatic here.
    public static let valueAliases: [String: [String: String]] = [
        "video_renderer": ["system": "auto"],
    ]

    /// Settings in `SettingsCatalog` that have no row, and why. Android has no row for them either.
    public static let settingsWithoutRow: [String: String] = [
        "checkbox_mouse_emulation": "Android only toggles it from the stream menu (OverlayMenuView), never on the settings screen",
    ]

    /// Every row, in order.
    public static let items: [SettingsItem] = sections.flatMap(\.items)

    private static let byID: [String: SettingsItem] = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

    public static func item(_ id: String) -> SettingsItem? {
        byID[id]
    }

    public static func section(containing id: String) -> SettingsSection? {
        sections.first { $0.items.contains { $0.id == id } }
    }

    /// The saved list value as one of the list's own values (a saved "system" is "auto").
    public static func normalizedValue(_ value: String, for key: String) -> String {
        valueAliases[key]?[value] ?? value
    }
}

// MARK: - Building rows

extension SettingsItem {
    /// Where a row's impact line, credit and presence come from when the layout doesn't say: the
    /// setting's key (`SettingsImpact`, `SettingsCredits`, `SettingsCatalog`). A per-game row
    /// takes its impact line the way Android does (`overrides` is the global key) and has no credit.
    static func make(_ id: String, _ control: SettingControl, _ title: String, summary: String? = nil,
                     summaryShowsChoice: Bool = false, dependency: String? = nil, showWhen: SettingRequirement? = nil,
                     enabledWhen: SettingRequirement? = nil, impact: Bool = true, presence: SettingPresence? = nil,
                     confirmation: SettingConfirmation? = nil, overrides: String? = nil) -> SettingsItem {
        var presenceFromCatalog = SettingPresence.shown
        if let availability = SettingsCatalog.definition(overrides ?? id)?.availability,
           availability == .notPossible || availability == .hostLacks {
            presenceFromCatalog = .hidden(availability)
        }
        return SettingsItem(id: id, control: control, titleKey: title, summaryKey: summary,
                            summaryShowsChoice: summaryShowsChoice,
                            impactKey: impact ? SettingsImpact.impactKey(for: id) : nil, dependency: dependency,
                            showWhen: showWhen, enabledWhen: enabledWhen,
                            credit: overrides == nil ? SettingsCredits.credit(for: id) : nil,
                            presence: presence ?? presenceFromCatalog, overrides: overrides, confirmation: confirmation)
    }

    static func toggle(_ id: String, _ title: String, summary: String? = nil, dependency: String? = nil,
                       showWhen: SettingRequirement? = nil, enabledWhen: SettingRequirement? = nil,
                       presence: SettingPresence? = nil) -> SettingsItem {
        make(id, .toggle, title, summary: summary, dependency: dependency, showWhen: showWhen,
             enabledWhen: enabledWhen, presence: presence)
    }

    /// A list whose labels are item N of the Android array `<array>_names`.
    static func list(_ id: String, _ title: String, array: String, values: [String], custom: Bool = false,
                     summary: String? = nil, summaryShowsChoice: Bool = false, dependency: String? = nil,
                     showWhen: SettingRequirement? = nil, enabledWhen: SettingRequirement? = nil,
                     impact: Bool = true, overrides: String? = nil) -> SettingsItem {
        list(id, title, entries: values.indices.map { "\(array)_names.\($0)" }, values: values, custom: custom,
             summary: summary, summaryShowsChoice: summaryShowsChoice, dependency: dependency, showWhen: showWhen,
             enabledWhen: enabledWhen, impact: impact, overrides: overrides)
    }

    static func list(_ id: String, _ title: String, entries: [String], values: [String], custom: Bool = false,
                     summary: String? = nil, summaryShowsChoice: Bool = false, dependency: String? = nil,
                     showWhen: SettingRequirement? = nil, enabledWhen: SettingRequirement? = nil,
                     impact: Bool = true, overrides: String? = nil) -> SettingsItem {
        make(id, .list(entries: entries, values: values, allowsCustom: custom), title, summary: summary,
             summaryShowsChoice: summaryShowsChoice, dependency: dependency, showWhen: showWhen,
             enabledWhen: enabledWhen, impact: impact, overrides: overrides)
    }

    static func dynamicList(_ id: String, _ title: String, defaultEntry: String, summary: String? = nil,
                            dependency: String? = nil) -> SettingsItem {
        make(id, .dynamicList(defaultEntry: defaultEntry), title, summary: summary, dependency: dependency)
    }

    static func slider(_ id: String, _ title: String, _ range: ClosedRange<Int>, step: Int = 1, divisor: Int = 1,
                       unit: String? = nil, custom: Bool = false, summary: String? = nil,
                       dependency: String? = nil, showWhen: SettingRequirement? = nil) -> SettingsItem {
        make(id, .slider(range: range, step: step, divisor: divisor, unitKey: unit, allowsCustom: custom), title,
             summary: summary, dependency: dependency, showWhen: showWhen)
    }

    static func text(_ id: String, _ title: String, _ input: SettingTextInput, maxLength: Int? = nil,
                     summary: String? = nil, dependency: String? = nil, showWhen: SettingRequirement? = nil) -> SettingsItem {
        make(id, .text(input, maxLength: maxLength), title, summary: summary, dependency: dependency, showWhen: showWhen)
    }

    static func action(_ id: String, _ title: String, _ name: String, summary: String? = nil,
                       dependency: String? = nil, showWhen: SettingRequirement? = nil,
                       presence: SettingPresence? = nil, confirmation: SettingConfirmation? = nil) -> SettingsItem {
        make(id, .action(name), title, summary: summary, dependency: dependency, showWhen: showWhen,
             presence: presence, confirmation: confirmation)
    }

    static func link(_ id: String, _ title: String, url: String, summary: String? = nil,
                     dependency: String? = nil, showWhen: SettingRequirement? = nil,
                     presence: SettingPresence? = nil) -> SettingsItem {
        make(id, .link(url), title, summary: summary, dependency: dependency, showWhen: showWhen, presence: presence)
    }
}
