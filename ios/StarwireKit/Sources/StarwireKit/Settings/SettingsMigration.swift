import Foundation

/// The settings the app kept before StarwireKit: moonlight-ios's Core Data `Settings` record,
/// edited on the app's own settings screen, and the choices batch 1 added to the iOS Settings
/// app (Settings.bundle, "Starwire..." keys in UserDefaults).
public struct LegacySettings: Equatable {
    /// Core Data `Settings`, nil when the app has none yet (first start).
    public struct CoreData: Equatable {
        public var bitrateKbps: Int
        public var framerate: Int
        public var width: Int
        public var height: Int
        /// Channels: 2, 6 or 8.
        public var audioConfig: Int
        /// 0 auto, 1 H.264, 2 HEVC, 3 AV1.
        public var preferredCodec: Int
        public var frameQueueSize: Int
        public var multiController: Bool
        public var swapABXYButtons: Bool
        public var playAudioOnPC: Bool
        public var optimizeGames: Bool
        public var enableHdr: Bool
        public var enableYUV444: Bool
        public var btMouseSupport: Bool
        public var absoluteTouchMode: Bool
        public var statsOverlay: Bool
        public var enableGraphs: Bool
        public var graphOpacity: Int
        /// OnScreenControlsLevel: 0 off, 1 auto, 2 simple, 3 full.
        public var onscreenControls: Int
        /// 0 fixed, 1 head tracked, 2 off.
        public var spatialAudio: Int

        public init(bitrateKbps: Int = 10000, framerate: Int = 60, width: Int = 1280, height: Int = 720,
                    audioConfig: Int = 2, preferredCodec: Int = 0, frameQueueSize: Int = 2,
                    multiController: Bool = true, swapABXYButtons: Bool = false, playAudioOnPC: Bool = false,
                    optimizeGames: Bool = true, enableHdr: Bool = false, enableYUV444: Bool = false,
                    btMouseSupport: Bool = false, absoluteTouchMode: Bool = false, statsOverlay: Bool = false,
                    enableGraphs: Bool = false, graphOpacity: Int = 50, onscreenControls: Int = 1, spatialAudio: Int = 0) {
            self.bitrateKbps = bitrateKbps
            self.framerate = framerate
            self.width = width
            self.height = height
            self.audioConfig = audioConfig
            self.preferredCodec = preferredCodec
            self.frameQueueSize = frameQueueSize
            self.multiController = multiController
            self.swapABXYButtons = swapABXYButtons
            self.playAudioOnPC = playAudioOnPC
            self.optimizeGames = optimizeGames
            self.enableHdr = enableHdr
            self.enableYUV444 = enableYUV444
            self.btMouseSupport = btMouseSupport
            self.absoluteTouchMode = absoluteTouchMode
            self.statsOverlay = statsOverlay
            self.enableGraphs = enableGraphs
            self.graphOpacity = graphOpacity
            self.onscreenControls = onscreenControls
            self.spatialAudio = spatialAudio
        }
    }

    public var coreData: CoreData?
    /// Only the iOS Settings values the user has set (UserDefaults' app domain, not the
    /// registered defaults), so an untouched choice leaves the store's own default alone.
    public var iosSettings: [String: Any]

    public init(coreData: CoreData?, iosSettings: [String: Any]) {
        self.coreData = coreData
        self.iosSettings = iosSettings
    }

    public static func == (lhs: LegacySettings, rhs: LegacySettings) -> Bool {
        lhs.coreData == rhs.coreData && NSDictionary(dictionary: lhs.iosSettings).isEqual(to: rhs.iosSettings)
    }
}

/// Copies the old settings into the store, with nothing lost: every old value has a key.
///
/// Until phase 3 replaces the old settings screens, they stay where the owner changes settings,
/// so this runs at every launch and the old values win. Settings only the store has (the
/// Vibeshine launch options) are left alone unless the iOS Settings app sets them.
public enum SettingsMigration {
    /// Applies the old values. Returns the keys it set, sorted.
    @discardableResult
    public static func apply(_ legacy: LegacySettings, to store: SettingsStore) -> [String] {
        var values: [String: SettingValue] = [:]

        if let old = legacy.coreData {
            values["seekbar_bitrate_kbps"] = .int(old.bitrateKbps)
            values["list_fps"] = .string(String(old.framerate))
            values["list_resolution"] = .string("\(old.width)x\(old.height)")
            values["list_audio_config"] = .string(old.audioConfig == 8 ? "71" : old.audioConfig == 6 ? "51" : "2")
            values["video_format"] = .string(["auto", "neverh265", "forceh265", "forceav1"][min(max(old.preferredCodec, 0), 3)])
            values["seekbar_frames_to_buffer"] = .int(min(max(old.frameQueueSize, 1), 5))
            values["checkbox_multi_controller"] = .bool(old.multiController)
            values["checkbox_flip_face_buttons"] = .bool(old.swapABXYButtons)
            values["checkbox_host_audio"] = .bool(old.playAudioOnPC)
            values["checkbox_enable_sops"] = .bool(old.optimizeGames)
            values["checkbox_enable_hdr"] = .bool(old.enableHdr)
            values["checkbox_enable_yuv444"] = .bool(old.enableYUV444)
            values["checkbox_bt_mouse_support"] = .bool(old.btMouseSupport)
            // moonlight-ios's "absolute touch mode" is Android's direct touch
            values["checkbox_touchscreen_trackpad"] = .bool(!old.absoluteTouchMode)
            values["checkbox_enable_perf_overlay"] = .bool(old.statsOverlay)
            values["checkbox_enable_graphs"] = .bool(old.enableGraphs)
            values["seekbar_graph_opacity"] = .int(min(max(old.graphOpacity, 0), 100))
            let level = ["off", "auto", "simple", "full"][min(max(old.onscreenControls, 0), 3)]
            values["list_onscreen_controls"] = .string(level)
            values["checkbox_show_onscreen_controls"] = .bool(old.onscreenControls != 0)
            values["list_spatial_audio"] = .string(["fixed", "head-tracked", "off"][min(max(old.spatialAudio, 0), 2)])
        }

        let ios = legacy.iosSettings
        func bool(_ key: String) -> Bool? {
            SettingValue.coerce(ios[key], to: .bool).flatMap { if case .bool(let v) = $0 { return v } else { return nil } }
        }
        func string(_ key: String) -> String? {
            (ios[key] as? String) ?? (ios[key] as? NSNumber)?.stringValue
        }
        func int(_ key: String) -> Int? {
            SettingValue.coerce(ios[key], to: .int).flatMap { if case .int(let v) = $0 { return v } else { return nil } }
        }

        // Batch 1 had an on/off switch; batch 2 has host default, virtual or primary
        if let mode = string("StarwireVirtualDisplayMode") {
            values["virtual_display_mode"] = .string(mode)
        } else if let on = bool("StarwireVirtualDisplay") {
            values["virtual_display_mode"] = .string(on ? "virtual" : "host")
        }
        if let exact = string("StarwireExactFrameRate"), !exact.isEmpty, Double(exact) != nil {
            values["list_fps"] = .string(exact)
        }
        if let scale = int("StarwireScaleFactor") { values["seekbar_virtual_display_scale"] = .int(scale) }
        if let vrr = bool("StarwireRequestVRR") { values["checkbox_vrr_request"] = .bool(vrr) }
        if let name = string("StarwireClientName") { values["text_client_name"] = .string(name.trimmingCharacters(in: .whitespaces)) }
        if let reduce = bool("StarwireReduceRefreshRate") { values["checkbox_reduce_refresh_rate"] = .bool(reduce) }
        if let external = string("StarwireExternalDisplay") { values["list_external_display"] = .string(external) }
        if let interpolation = bool("StarwireFrameInterpolation") { values["checkbox_frame_interpolation"] = .bool(interpolation) }
        if let pip = bool("StarwirePictureInPicture") { values["checkbox_enable_pip"] = .bool(pip) }
        if let fullRange = bool("StarwireFullRange") { values["checkbox_full_range"] = .bool(fullRange) }
        if let overlay = string("StarwireOverlay") { values["checkbox_enable_perf_overlay_lite"] = .bool(overlay == "lite") }
        if let presenter = string("StarwirePresenter") { values["video_renderer"] = .string(presenter) }
        if let jitter = string("StarwireJitterBuffer") { values["jitter_buffer"] = .string(jitter) }
        if let timing = string("StarwirePresentTiming") { values["list_present_timing"] = .string(timing) }
        if let drop = string("StarwireDropPolicy") { values["list_drop_policy"] = .string(drop) }
        if let frames = int("StarwireFramesToBuffer") { values["seekbar_pacing_frames_to_buffer"] = .int(frames) }
        if let verbose = bool("StarwireVerboseLogging") { values["checkbox_verbose_logging"] = .bool(verbose) }

        var applied: [String] = []
        for (key, value) in values {
            if (try? store.set(value, for: key)) != nil {
                applied.append(key)
            }
        }
        return applied.sorted()
    }

    /// The iOS Settings keys this migration reads, for the app to pick out of UserDefaults.
    public static let iosSettingsKeys = [
        "StarwireVirtualDisplayMode", "StarwireVirtualDisplay", "StarwireExactFrameRate", "StarwireScaleFactor",
        "StarwireRequestVRR", "StarwireClientName", "StarwireReduceRefreshRate", "StarwireExternalDisplay",
        "StarwireFrameInterpolation", "StarwirePictureInPicture", "StarwireFullRange", "StarwireOverlay",
        "StarwirePresenter", "StarwireJitterBuffer", "StarwirePresentTiming", "StarwireDropPolicy",
        "StarwireFramesToBuffer", "StarwireVerboseLogging",
    ]
}
