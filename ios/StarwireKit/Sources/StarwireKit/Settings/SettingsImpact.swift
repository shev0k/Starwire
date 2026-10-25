// Ported from Starwire for Android's SettingsImpact.java and SettingsFeel.java (GPL-3.0): which
// settings get an "Impact:" line, and the "Predicted impact" panel.

import Foundation

/// A short "Impact:" line under the settings that change latency, smoothness, picture quality or
/// battery use, so it's clear what turning one on or up costs or gains. Settings with no such
/// effect get no line. The screen shows `labelKey` in bold and then the line's text.
public enum SettingsImpact {
    /// The string name of the "Impact:" label.
    public static let labelKey = "impact_label"

    /// Setting key to the string name of its line.
    public static let lines: [String: String] = [
        "list_resolution": "impact_resolution",
        "list_fps": "impact_fps",
        "seekbar_bitrate_kbps": "impact_bitrate",
        "frame_pacing": "impact_frame_pacing",
        "jitter_buffer": "impact_jitter_buffer",
        "vsync_mode": "impact_vsync",
        "checkbox_sync_lfr": "impact_sync_lfr",
        "checkbox_async_decode": "impact_async_decode",
        "checkbox_async_lfr": "impact_async_lfr",
        "checkbox_ultra_low_latency": "impact_ultra_low_latency",
        "checkbox_stretch_video": "impact_none",
        "list_audio_config": "impact_surround",
        "checkbox_enable_audiofx": "impact_audiofx",
        "checkbox_enable_microphone": "impact_microphone",
        "list_microphone_target": "impact_microphone_target",
        "list_audio_haptics": "impact_audio_haptics",
        "seekbar_deadzone": "impact_deadzone",
        "checkbox_prevent_packet_loss": "impact_prevent_packet_loss",
        "checkbox_reduce_refresh_rate": "impact_reduce_refresh_rate",
        "text_actual_display_refresh_rate": "impact_actual_refresh_rate",
        "video_format": "impact_video_format",
        "pyrowave_late_frames": "impact_pyrowave_late_frames",
        "video_renderer": "impact_video_renderer",
        "checkbox_custom_vulkan_driver": "impact_custom_vulkan_driver",
        "spatial_dithering": "impact_spatial_dithering",
        "checkbox_enable_hdr": "impact_hdr",
        "checkbox_full_range": "impact_none",
        "checkbox_enable_perf_overlay": "impact_perf_overlay",
    ]

    /// The per-game screen's own keys for the same settings. Its other options are "game_" plus
    /// the global key.
    public static let aliases: [String: String] = [
        "list_app_resolution": "list_resolution",
        "list_app_fps": "list_fps",
        "text_app_bitrate_kbps": "seekbar_bitrate_kbps",
        "list_app_frame_pacing": "frame_pacing",
        "text_app_actual_display_refresh_rate": "text_actual_display_refresh_rate",
        "list_app_enable_hdr": "checkbox_enable_hdr",
        "list_app_enable_perf_overlay": "checkbox_enable_perf_overlay",
    ]

    /// The string name of a setting's impact line, or nil when it has none. Only a leading
    /// "game_" is taken as the per-game prefix, and only once.
    public static func impactKey(for key: String?) -> String? {
        guard var key else { return nil }
        if let alias = aliases[key] {
            key = alias
        } else if key.hasPrefix("game_") {
            key = String(key.dropFirst("game_".count))
        }
        return lines[key]
    }
}

/// The settings screen's "Predicted impact" panel: where the frame pacing, V-Sync and Async LFR
/// choices put you between fastest response and smoothest motion, and which way each of them
/// pushes. These are rough comparisons between the choices, not measurements. Android shows the
/// panel on screens at least `panelMinWidth` points wide.
public struct SettingsFeel: Equatable, Sendable {
    public enum Level: Int, Equatable, Sendable {
        case lower = 0
        case medium = 1
        case higher = 2

        /// The string name for "Lower", "Medium" or "Higher".
        public var nameKey: String {
            switch self {
            case .lower: return "feel_level_lower"
            case .medium: return "feel_level_medium"
            case .higher: return "feel_level_higher"
            }
        }
    }

    public enum Effect: Int, Equatable, Sendable {
        case faster = -1
        case noEffect = 0
        case smoother = 1
        case notUsed = 2
        case balanced = 3

        /// The string name for the effect's label.
        public var nameKey: String {
            switch self {
            case .faster: return "feel_effect_faster"
            case .smoother: return "feel_effect_smoother"
            case .notUsed: return "feel_effect_not_used"
            case .balanced: return "feel_effect_balanced"
            case .noEffect: return "feel_effect_none"
            }
        }
    }

    /// What a row says the setting is now: a string name (`feel_on`, or item N of a list's names
    /// as `vsync_mode_names.1`), or the saved text itself when it isn't one of the list's values.
    public enum FactorValue: Equatable, Sendable {
        case label(String)
        case literal(String)
    }

    /// One setting that moves the marker: its name, its current value, and which way it pushes.
    public struct Factor: Equatable, Sendable {
        public let titleKey: String
        public let value: FactorValue
        public let effect: Effect
    }

    /// 0 is fastest response, 1 is smoothest motion.
    public let position: Float
    /// The string name of the sentence under the slider.
    public let descriptionKey: String
    public let delay: Level
    public let battery: Level
    public let factors: [Factor]

    /// The strings around the panel, in the order Android shows them: the title, the slider's two
    /// ends, "Input delay", "Battery use", the "What's moving it" heading, and a row's
    /// "%1$s: %2$s" format.
    public static let titleKey = "feel_title"
    public static let fastestKey = "feel_fastest"
    public static let smoothestKey = "feel_smoothest"
    public static let delayKey = "feel_delay"
    public static let batteryKey = "feel_battery"
    public static let movingItKey = "feel_moving_it"
    public static let factorRowKey = "feel_factor_row"

    /// The panel shows on screens at least this wide, in points (Android: 840 dp).
    public static let panelMinWidth = 840

    /// The settings the panel is built from, so the screen knows when to redraw it.
    public static let inputKeys = ["frame_pacing", "vsync_mode", "checkbox_async_decode", "checkbox_async_lfr"]

    /// The panel for the saved settings (Android reads them with their defaults).
    public static func describe(_ store: SettingsStore) -> SettingsFeel {
        func string(_ key: String) -> String {
            if case .string(let value)? = store.value(key) { return value }
            return ""
        }
        func bool(_ key: String) -> Bool {
            if case .bool(let value)? = store.value(key) { return value }
            return false
        }
        // Async LFR only counts with async decode on
        return describe(pacing: string("frame_pacing"), vsync: string("vsync_mode"),
                        asyncLfr: bool("checkbox_async_decode") && bool("checkbox_async_lfr"))
    }

    /// The panel for these choices. An unknown pacing is Balanced, as on Android.
    public static func describe(pacing requested: String, vsync: String, asyncLfr: Bool) -> SettingsFeel {
        var pacing = requested
        var position: Float
        let description: String
        var delay: Level
        var battery = Level.medium
        switch pacing {
        case "latency":
            position = 0.15
            description = "feel_latency"
            delay = .lower
        case "cap-fps":
            position = 0.5
            description = "feel_cap_fps"
            delay = .medium
        case "smoothness":
            position = 0.92
            description = "feel_smoothness"
            delay = .higher
        case "host-timed":
            position = 0.65
            description = "feel_host_timed"
            delay = .medium
        case "warp":
            position = 0.06
            description = "feel_warp"
            delay = .lower
            battery = .higher
        case "warp2":
            position = 0.02
            description = "feel_warp2"
            delay = .lower
            battery = .higher
        default:
            pacing = "balanced"
            position = 0.45
            description = "feel_balanced"
            delay = .medium
        }

        var factors: [Factor] = []
        let pacingEffect: Effect = position < 0.35 ? .faster : position > 0.6 ? .smoother : .balanced
        factors.append(Factor(titleKey: "feel_factor_pacing",
                              value: entry(names: "video_frame_pacing_names", values: SettingsCatalog.framePacing, value: pacing),
                              effect: pacingEffect))

        // V-Sync and Async LFR apply to the direct renderer, not host frame timing
        let direct = pacing != "host-timed"
        let vsyncValue = entry(names: "vsync_mode_names", values: ["off", "vsync", "fast"], value: vsync)
        let vsyncEffect: Effect
        if !direct {
            vsyncEffect = .notUsed
        } else if vsync == "vsync" {
            position += 0.15
            delay = Level(rawValue: min(Level.higher.rawValue, delay.rawValue + 1)) ?? .higher
            vsyncEffect = .smoother
        } else if vsync == "fast" {
            position += 0.05
            vsyncEffect = .smoother
        } else {
            vsyncEffect = .noEffect
        }
        factors.append(Factor(titleKey: "feel_factor_vsync", value: vsyncValue, effect: vsyncEffect))

        let lfrEffect: Effect
        if !direct {
            lfrEffect = .notUsed
        } else if asyncLfr {
            position -= 0.05
            lfrEffect = .faster
        } else {
            lfrEffect = .noEffect
        }
        factors.append(Factor(titleKey: "feel_factor_async_lfr", value: .label(asyncLfr ? "feel_on" : "feel_off"),
                              effect: lfrEffect))

        return SettingsFeel(position: max(0, min(1, position)), descriptionKey: description, delay: delay,
                            battery: battery, factors: factors)
    }

    // The name shown in settings for a list setting's value, or the value itself
    private static func entry(names: String, values: [String], value: String) -> FactorValue {
        guard let index = values.firstIndex(of: value) else {
            return .literal(value)
        }
        return .label("\(names).\(index)")
    }
}
