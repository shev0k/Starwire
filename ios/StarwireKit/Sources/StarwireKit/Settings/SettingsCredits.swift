// Ported from Starwire for Android's CoverGlowSettings.java (CREDITS) and AboutCredits.java
// (GPL-3.0): which settings came from which Moonlight version and author, and the credits list.

import Foundation

/// Where one setting came from, for a quiet "From <fork>" line under it.
public struct SettingCredit: Equatable, Sendable {
    /// The line, in English only, as Android writes it: "From Artemide by derflacco".
    public let text: String
    /// The projects it names, spelled as in `SettingsCredits.projects`.
    public let projects: [String]
}

/// One project or person Starwire is built on, for Settings > About > Credits.
public struct ProjectCredit: Identifiable, Equatable, Sendable {
    public var id: String { project }
    /// The heading it falls under: a `credits_section_...` string name.
    public let sectionKey: String
    public let project: String
    public let author: String
    /// A string name for what it was used for (`credit_...`, or `ios_credit_...`).
    public let usedForKey: String
    public let url: String
    /// True for a project only the iOS app uses. The Android credits and the README don't list it.
    public let iosOnly: Bool
}

public enum SettingsCredits {
    // MARK: - Settings

    private static func credit(_ text: String, _ projects: [String]) -> SettingCredit {
        SettingCredit(text: text, projects: projects)
    }

    /// Android's credit lines (CoverGlowSettings.CREDITS), by setting key. Moonlight's own
    /// settings and Starwire's new ones have none.
    public static let androidSettingCredits: [String: SettingCredit] = {
        let artemide = credit("From Artemide by derflacco", ["Artemide"])
        let artemis = credit("From Artemis by Yukino Song", ["Artemis"])
        let moonlightX = credit("From Moonlight X by MoreOrLessSoftware", ["Moonlight X"])
        let turnip = credit("From Moonlight X Turnip by NoCrypt", ["Moonlight X Turnip"])
        let keyboard = credit("Full keyboard from Axixi2233 and Artemis by Yukino Song",
                              ["Moonlight (Axixi2233 fork)", "Artemis"])
        let shortcuts = credit("File format from Axixi2233 and Artemis by Yukino Song",
                               ["Moonlight (Axixi2233 fork)", "Artemis"])
        let vplus = credit("Idea from Moonlight V+ by qiin2333", ["Moonlight V+"])

        var credits: [String: SettingCredit] = [:]
        for key in ["checkbox_sync_lfr", "checkbox_async_decode", "checkbox_async_lfr"] {
            credits[key] = artemide
        }
        credits["vsync_mode"] = credit("Fast V-Sync from Artemide by derflacco", ["Artemide"])
        credits["frame_pacing"] = credit("Warp Drive pacing from Artemis by Yukino Song", ["Artemis"])
        credits["checkbox_ultra_low_latency"] = credit("From Moonlight X by MoreOrLessSoftware, Artemis and Artemide",
                                                       ["Moonlight X", "Artemis", "Artemide"])
        credits["list_audio_haptics"] = vplus
        // logabell's work is credited as "Apollo microphone" in the project list
        credits["checkbox_enable_microphone"] = credit(
            "Capture from logabell's Artemis changes; the PC receiver is new in Starwire", ["Apollo microphone"])
        credits["list_microphone_device"] = credit("From logabell's Artemis changes", ["Apollo microphone"])
        credits["seekbar_audio_haptics_intensity"] = vplus
        for key in ["checkbox_enable_floating_button", "virtual_display_mode", "checkbox_smart_clipboard_sync",
                    "checkbox_smart_clipboard_sync_toast", "checkbox_hide_clipboard_content"] {
            credits[key] = artemis
        }
        credits["checkbox_prevent_packet_loss"] = credit("From Artemis by Yukino Song, via Artemide",
                                                         ["Artemis", "Artemide"])
        credits["seekbar_touch_sensitivity"] = credit("From Artemis by Yukino Song and Axixi2233",
                                                      ["Artemis", "Moonlight (Axixi2233 fork)"])
        for key in ["overlay_custom_commands", "overlay_trigger_button", "overlay_hold_duration", "video_format",
                    "video_renderer", "pyrowave_late_frames"] {
            credits[key] = moonlightX
        }
        // The settings are Moonlight's own; entering any value is from Moonlight X
        credits["list_resolution"] = credit("Custom resolutions from Moonlight X by MoreOrLessSoftware", ["Moonlight X"])
        credits["list_fps"] = credit("Custom frame rates from Moonlight X by MoreOrLessSoftware", ["Moonlight X"])
        credits["import_shortcuts_file"] = shortcuts
        credits["clear_imported_shortcuts"] = shortcuts
        credits["checkbox_pinch_to_zoom"] = credit("Idea from Moonlit Artemis by 4had45", ["Moonlit Artemis"])
        for key in ["checkbox_keyboard_vibrate", "checkbox_sticky_modifier_keys", "seekbar_keyboard_opacity"] {
            credits[key] = keyboard
        }
        for key in ["checkbox_custom_vulkan_driver", "text_custom_vulkan_driver_path",
                    "checkbox_custom_vulkan_driver_toast"] {
            credits[key] = turnip
        }
        credits["checkbox_enable_perf_overlay_lite"] = credit("From Axixi2233, via Artemis and Artemide",
                                                              ["Moonlight (Axixi2233 fork)", "Artemis", "Artemide"])
        return credits
    }()

    /// Credits for the iOS-only settings, from the notes in the code that was brought over.
    public static let iosSettingCredits: [String: SettingCredit] = [
        "list_pencil_pressure_curve": SettingCredit(text: "Pressure curves from VoidLink by The-Fried-Fish",
                                                    projects: ["VoidLink"]),
        "checkbox_frame_interpolation": SettingCredit(text: "Follows VoidLink by The-Fried-Fish",
                                                      projects: ["VoidLink"]),
    ]

    /// Where a setting came from, or nil for Moonlight's own and Starwire's new settings. A
    /// per-game key (`game_...`) has none, as on Android.
    public static func credit(for key: String?) -> SettingCredit? {
        guard let key else { return nil }
        return androidSettingCredits[key] ?? iosSettingCredits[key]
    }

    // MARK: - About > Credits

    /// The headings, in order: string names.
    public static let sectionKeys = [
        "credits_section_moonlight", "credits_section_microphone", "credits_section_video",
        "credits_section_hosts", "credits_section_tools",
    ]

    private static func project(_ section: Int, _ project: String, _ author: String, _ usedFor: String, _ url: String,
                                iosOnly: Bool = false) -> ProjectCredit {
        ProjectCredit(sectionKey: sectionKeys[section], project: project, author: author, usedForKey: usedFor,
                      url: url, iosOnly: iosOnly)
    }

    /// Android's list (AboutCredits.ALL), which is also the README's Credits table.
    public static let androidProjects: [ProjectCredit] = [
        project(0, "Moonlight Android", "Cameron Gutman and contributors", "credit_moonlight",
                "https://github.com/moonlight-stream/moonlight-android"),
        project(0, "Moonlight X", "MoreOrLessSoftware", "credit_moonlight_x",
                "https://github.com/MoreOrLessSoftware/moonlight-android"),
        project(0, "Artemis", "Yukino Song (ClassicOldSong)", "credit_artemis",
                "https://github.com/ClassicOldSong/moonlight-android"),
        project(0, "Artemide", "derflacco", "credit_artemide", "https://github.com/derflacco/moonlight-android"),
        project(0, "Moonlight (Axixi2233 fork)", "Axixi2233", "credit_axixi",
                "https://github.com/Axixi2233/moonlight-android"),
        project(0, "Moonlight X Turnip", "ncpt (NoCrypt)", "credit_turnip",
                "https://github.com/NoCrypt/moonlight-x-turnip"),
        project(0, "Moonlight V+", "qiin2333", "credit_vplus", "https://github.com/qiin2333/moonlight-vplus"),
        project(0, "Moonlit Artemis", "Mohammad Forhad (4had45)", "credit_moonlit",
                "https://github.com/4had45/moonlit-artemis"),
        project(0, "Moonlight Fold", "sblocktechnologies", "credit_fold",
                "https://github.com/sblocktechnologies/moonlight-fold"),

        project(1, "Apollo microphone", "logabell", "credit_apollo_microphone",
                "https://github.com/logabell/apollo-microphone"),
        project(1, "VBAN and VB-Cable", "VB-Audio (Vincent Burel)", "credit_vban", "https://vb-audio.com/Cable/"),

        project(2, "PyroWave", "Hans-Kristian Arntzen (Themaister)", "credit_pyrowave",
                "https://github.com/Themaister/pyrowave"),
        project(2, "libadrenotools", "Billy Laws (bylaws)", "credit_adrenotools",
                "https://github.com/bylaws/libadrenotools"),

        project(3, "Vibepollo", "Chase Payne (Nonary)", "credit_vibepollo", "https://github.com/Nonary/Vibepollo"),
        project(3, "Apollo", "ClassicOldSong", "credit_apollo_sunshine", "https://github.com/ClassicOldSong/Apollo"),
        project(3, "Sunshine", "LizardByte", "credit_apollo_sunshine", "https://github.com/LizardByte/Sunshine"),

        project(4, "Claude Code", "Anthropic", "credit_claude_code", "https://claude.com/claude-code"),
        project(4, "REA", "morluto", "credit_rea", "https://github.com/morluto/rea"),
    ]

    /// Projects only the iOS app uses, from the notes in the code that was brought over.
    public static let iosProjects: [ProjectCredit] = [
        project(0, "Moonlight iOS", "Diego Waxemberg, Cameron Gutman and contributors", "ios_credit_moonlight_ios",
                "https://github.com/moonlight-stream/moonlight-ios", iosOnly: true),
        project(0, "Moonlight iOS (Metal renderer)", "Andy Grundman", "ios_credit_andy_metal",
                "https://github.com/andygrundman/moonlight-ios", iosOnly: true),
        project(0, "VoidLink", "The-Fried-Fish", "ios_credit_voidlink",
                "https://github.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm", iosOnly: true),
        project(0, "Artemis iOS", "daniel-zn", "ios_credit_artemis_ios",
                "https://github.com/daniel-zn/danielzn-moonlight-ios", iosOnly: true),
        project(3, "Vibeshine and its moonlight-common-c", "Chase Payne (Nonary)", "ios_credit_vibeshine",
                "https://github.com/Nonary/moonlight-common-c", iosOnly: true),
        project(4, "swift-crypto", "Apple", "ios_credit_swift_crypto", "https://github.com/apple/swift-crypto",
                iosOnly: true),
    ]

    /// The list for the About page: Android's, with the iOS-only ones at the end of their heading.
    public static let projects: [ProjectCredit] = {
        var all = androidProjects
        for extra in iosProjects {
            let last = all.lastIndex { $0.sectionKey == extra.sectionKey } ?? all.count - 1
            all.insert(extra, at: last + 1)
        }
        return all
    }()

    public static func projects(inSection sectionKey: String) -> [ProjectCredit] {
        projects.filter { $0.sectionKey == sectionKey }
    }

    public static func project(named name: String) -> ProjectCredit? {
        projects.first { $0.project == name }
    }
}
