// Ported from Starwire for Android's app_preferences.xml and AppStreamSettings.java (GPL-3.0).

import Foundation

/// Android's per-game settings screen (an app's or a Quick Launch item's own settings) as data.
/// Each row after the first overrides a global setting (`SettingsItem.overrides`), and every
/// list has one more choice at the start that leaves the setting to the global one
/// (`defaultEntryKey`). The rows are enabled only while `useGlobalKey` is off, and what is saved
/// is `GameSettings`.
public enum GameSettingsLayout {
    /// The switch at the top. On means none of the rows below are used.
    public static let useGlobalKey = "checkbox_use_global_settings"

    /// The name of the choice that leaves a setting to the global one. Android writes
    /// "[Use global default]" in code.
    public static let defaultEntryKey = "ios_use_global_default"

    /// For a Quick Launch item the switch and the default choice say "app" where a game's say
    /// "global", because a Quick Launch item falls back to the app's own settings first.
    public static let quickLaunchUseGlobalTitleKey = "ios_title_use_app_settings"
    public static let quickLaunchUseGlobalSummaryKey = "ios_summary_use_app_settings"
    public static let quickLaunchDefaultEntryKey = "ios_use_app_default"

    public static let groups: [SettingsGroup] = [
        SettingsGroup(id: "game_use_global", titleKey: nil, showWhen: nil, items: [
            .make(useGlobalKey, .toggle, "ios_title_use_global_settings", summary: "ios_summary_use_global_settings"),
        ]),
        SettingsGroup(id: "category_app_specific", titleKey: "ios_category_app_specific", showWhen: nil, items: [
            .list("list_app_resolution", "title_resolution_list", array: "resolution",
                  values: ["1280x720", "1920x1080", "2560x1440", "3840x2160"], custom: true,
                  summary: "summary_resolution_list", overrides: "list_resolution"),
            .list("list_app_fps", "title_fps_list", array: "fps", values: ["30", "60", "90", "120"], custom: true,
                  summary: "summary_fps_list", overrides: "list_fps"),
            // Entered in Mbps, where the global slider is in kbps
            .make("text_app_bitrate_kbps", .text(.number, maxLength: nil), "title_seekbar_bitrate",
                  summary: "summary_seekbar_bitrate", overrides: "seekbar_bitrate_kbps"),
            .list("list_app_frame_pacing", "title_frame_pacing", array: "video_frame_pacing",
                  values: SettingsCatalog.framePacing, summary: "summary_frame_pacing", overrides: "frame_pacing"),
            .list("game_jitter_buffer", "title_jitter_buffer", array: "jitter_buffer",
                  values: SettingsCatalog.jitterBuffers, overrides: "jitter_buffer"),
            .make("text_app_actual_display_refresh_rate", .text(.decimal, maxLength: nil),
                  "title_actual_display_refresh_rate", summary: "summary_actual_display_refresh_rate",
                  overrides: "text_actual_display_refresh_rate"),
            .list("list_app_enable_hdr", "title_enable_hdr", array: "hdr_setting", values: ["true", "false"],
                  overrides: "checkbox_enable_hdr"),
            .list("list_app_enable_perf_overlay", "title_enable_perf_overlay", array: "perf_overlay_setting",
                  values: ["true", "false"], overrides: "checkbox_enable_perf_overlay"),
            // Starwire's options: "game_" plus the global key (AppStreamSettings.GAME_OPTIONS)
            .list("game_video_format", "title_video_format", array: "video_format",
                  values: SettingsCatalog.videoFormats, overrides: "video_format"),
            .list("game_vsync_mode", "title_vsync_mode", array: "vsync_mode", values: ["off", "vsync", "fast"],
                  overrides: "vsync_mode"),
            .list("game_checkbox_sync_lfr", "title_checkbox_sync_lfr", array: "hdr_setting",
                  values: ["true", "false"], overrides: "checkbox_sync_lfr"),
            .list("game_checkbox_async_decode", "title_checkbox_async_decode", array: "hdr_setting",
                  values: ["true", "false"], overrides: "checkbox_async_decode"),
            .list("game_checkbox_async_lfr", "title_checkbox_async_lfr", array: "hdr_setting",
                  values: ["true", "false"], overrides: "checkbox_async_lfr"),
            .list("game_virtual_display_mode", "title_virtual_display_mode", array: "virtual_display_mode",
                  values: ["host", "virtual", "primary"], overrides: "virtual_display_mode"),
            .list("game_checkbox_touchscreen_trackpad", "title_game_touch_mode", array: "game_touch_mode",
                  values: ["true", "false"], overrides: "checkbox_touchscreen_trackpad"),
            .list("game_hide_cursor_mode", "title_hide_cursor_mode", array: "hide_cursor_mode",
                  values: ["never", "touching", "always"], overrides: "hide_cursor_mode"),
            .list("game_list_audio_haptics", "title_audio_haptics", array: "audio_haptics",
                  values: ["off", "device", "controller", "both"], overrides: "list_audio_haptics"),
        ]),
    ]

    public static let items: [SettingsItem] = groups.flatMap(\.items)

    public static func item(_ id: String) -> SettingsItem? {
        items.first { $0.id == id }
    }
}
