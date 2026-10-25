// Ported from Starwire for Android's OverridesView (com.limelight.ui) and the way
// AppPreferences.applyPreferenceOverrides uses it at launch (GPL-3.0, Starwire; built on Moonlight X).
import Foundation

/// What the overrides bar can force on every stream: the bitrate, the stats overlay and the codec.
/// Android keeps them in the same preferences as the settings, under these keys.
public enum OverrideKeys {
    /// Bool, false: whether the bar is shown and its choices are used.
    public static let enabled = "overrides_enabled"
    /// Int, 0: kbps for the current codec. 0 means no override.
    public static let bitrate = "bitrate_override"
    /// Int, 0: 0 = default, 1 = force on, 2 = force off.
    public static let statsOverlay = "perf_overlay_override"
    /// Int, 0: 0 = default, 1 = HEVC, 2 = AV1, 3 = PyroWave.
    public static let codec = "codec_override"
    /// Int, 0: the bitrate remembered for a codec while another is selected. The codec's number
    /// follows the prefix: `bitrate_override_codec_2`.
    public static let bitrateForCodecPrefix = "bitrate_override_codec_"

    public static func bitrateForCodec(_ codec: Int) -> String { bitrateForCodecPrefix + String(codec) }

    /// Every key, for a settings export. The per-codec keys are the four Android can write.
    public static var all: [String] {
        [enabled, bitrate, statsOverlay, codec] + CodecOverride.allCases.map { bitrateForCodec($0.rawValue) }
    }
}

/// The codec button's choices, in the order it cycles through them.
public enum CodecOverride: Int, CaseIterable, Sendable {
    case useDefault = 0
    case hevc = 1
    case av1 = 2
    case pyroWave = 3

    /// The value of the `video_format` setting this forces, or nil to leave the setting alone.
    public var videoFormat: String? {
        switch self {
        case .useDefault: return nil
        case .hevc: return "forceh265"
        case .av1: return "forceav1"
        case .pyroWave: return "forcepyrowave"
        }
    }

    /// Android shows a saved number it doesn't know as the default.
    public init(saved: Int) {
        self = CodecOverride(rawValue: saved) ?? .useDefault
    }
}

/// The stats overlay button's choices.
public enum StatsOverlayOverride: Int, CaseIterable, Sendable {
    case useDefault = 0
    case forceOn = 1
    case forceOff = 2

    /// Android shows a saved number it doesn't know as the default.
    public init(saved: Int) {
        self = StatsOverlayOverride(rawValue: saved) ?? .useDefault
    }
}

/// The overrides bar's choices as saved, and how they combine with a stream's settings.
public struct StreamOverrides: Equatable, Sendable {
    public var enabled: Bool
    /// kbps. 0 means no override.
    public var bitrateKbps: Int
    /// The saved number: 0, 1 or 2. See `statsOverlay`.
    public var statsOverlayRaw: Int
    /// The saved number: 0 to 3. See `codec`.
    public var codecRaw: Int

    public init(enabled: Bool = false, bitrateKbps: Int = 0, statsOverlayRaw: Int = 0, codecRaw: Int = 0) {
        self.enabled = enabled
        self.bitrateKbps = bitrateKbps
        self.statsOverlayRaw = statsOverlayRaw
        self.codecRaw = codecRaw
    }

    public var statsOverlay: StatsOverlayOverride { StatsOverlayOverride(saved: statsOverlayRaw) }
    public var codec: CodecOverride { CodecOverride(saved: codecRaw) }

    /// Puts the overrides on top of a stream's settings, as Android does at launch
    /// (`AppPreferences.applyPreferenceOverrides`). Nothing changes when they are off. When on:
    /// a bitrate above 0 sets `seekbar_bitrate_kbps`, a stats overlay choice of on or off sets
    /// `checkbox_enable_perf_overlay`, and HEVC, AV1 or PyroWave sets `video_format`. A choice left
    /// at its default leaves the setting as it was.
    ///
    /// Apply this last, after the game's and the Quick Launch entry's own settings: the overrides
    /// win over all of them. Android skips them for streams started from a home screen shortcut or
    /// resumed after a restart (`applyPreferenceOverrides` false in `Game`'s intent).
    public func applied(to values: [String: SettingValue]) -> [String: SettingValue] {
        guard enabled else { return values }
        var result = values
        if bitrateKbps > 0 {
            result["seekbar_bitrate_kbps"] = .int(bitrateKbps)
        }
        switch statsOverlay {
        case .forceOn: result["checkbox_enable_perf_overlay"] = .bool(true)
        case .forceOff: result["checkbox_enable_perf_overlay"] = .bool(false)
        case .useDefault: break
        }
        if codecRaw >= 1, let format = codec.videoFormat {
            result["video_format"] = .string(format)
        }
        return result
    }
}

extension SettingsStore {
    /// The settings a stream uses, in Android's order (`AppPreferences.getEffectivePreferences`):
    /// the global settings, then for each setting the Quick Launch entry's own value if it has one,
    /// else the game's (unless the game uses the global settings), then the overrides bar on top
    /// if `applyOverrides` is true. The overrides are left out for streams started from a home
    /// screen shortcut and for resumed sessions.
    public func launchValues(game: GameSettings, quickLaunch: GameSettings? = nil,
                             overrides: StreamOverrides? = nil, applyOverrides: Bool = true) -> [String: SettingValue] {
        var values: [String: SettingValue]
        if (quickLaunch == nil || quickLaunch?.useGlobalSettings == true) && game.useGlobalSettings {
            values = effectiveValues(for: GameSettings())
        } else {
            values = effectiveValues(for: Self.layered(quickLaunch: quickLaunch, game: game))
        }
        if applyOverrides, let overrides {
            values = overrides.applied(to: values)
        }
        return values
    }

    /// One set of overrides from the Quick Launch entry's and the game's. Android takes each field
    /// from the entry if the entry sets it, even when the entry says "use global settings".
    static func layered(quickLaunch: GameSettings?, game: GameSettings) -> GameSettings {
        let own = game.useGlobalSettings ? GameSettings() : game
        guard let quick = quickLaunch else {
            return GameSettings(resolution: own.resolution, fps: own.fps, framePacing: own.framePacing,
                                bitrate: own.bitrate, actualDisplayRefreshRate: own.actualDisplayRefreshRate,
                                enableHdr: own.enableHdr, enablePerfOverlay: own.enablePerfOverlay,
                                useGlobalSettings: false, gameOptions: own.gameOptions)
        }
        var options = own.gameOptions
        for (key, value) in quick.gameOptions {
            options[key] = value
        }
        return GameSettings(
            resolution: quick.resolution ?? own.resolution,
            fps: quick.fps > 0 ? quick.fps : own.fps,
            framePacing: quick.framePacing ?? own.framePacing,
            bitrate: quick.bitrate > 0 ? quick.bitrate : own.bitrate,
            actualDisplayRefreshRate: quick.actualDisplayRefreshRate > 0
                ? quick.actualDisplayRefreshRate : own.actualDisplayRefreshRate,
            enableHdr: quick.enableHdr ?? own.enableHdr,
            enablePerfOverlay: quick.enablePerfOverlay ?? own.enablePerfOverlay,
            useGlobalSettings: false, gameOptions: options)
    }
}

/// What happened to a bitrate typed into the box.
public enum BitrateInputResult: Equatable, Sendable {
    /// The box was empty: nothing changes.
    case ignored
    /// Saved this many kbps (0 for the default).
    case saved(kbps: Int)
    /// Saved, but the number was above the maximum and was lowered. Android tells the user
    /// "Maximum bitrate is 2500 Mbps".
    case clamped(kbps: Int)
    /// Not a whole number: "Invalid number".
    case invalid
}

/// The overrides bar's choices, saved under Android's keys. What the buttons and the slider do is
/// here, so the screen only shows the result.
public final class StreamOverridesStore {
    /// Slider steps are 10 Mbps.
    public static let bitrateStepKbps = 10_000
    /// The slider has 50 steps: 0 is the default, 50 is 500 Mbps.
    public static let sliderMaximum = 50
    /// The largest bitrate the box takes, in Mbps. Above the slider's range on purpose.
    public static let maximumBitrateMbps = 2500

    private let storage: SettingsStorage

    public init(storage: SettingsStorage) {
        self.storage = storage
    }

    /// The saved choices.
    public var overrides: StreamOverrides {
        StreamOverrides(enabled: bool(OverrideKeys.enabled), bitrateKbps: int(OverrideKeys.bitrate),
                        statsOverlayRaw: int(OverrideKeys.statsOverlay), codecRaw: int(OverrideKeys.codec))
    }

    public var isEnabled: Bool { bool(OverrideKeys.enabled) }

    /// Shows or hides the bar. Returns the new state.
    @discardableResult
    public func toggleEnabled() -> Bool {
        let enabled = !isEnabled
        storage.set(enabled, forKey: OverrideKeys.enabled)
        return enabled
    }

    // MARK: - Bitrate

    /// kbps for the codec that is selected. 0 means the default.
    public var bitrateKbps: Int { int(OverrideKeys.bitrate) }

    /// Where the slider sits for the saved bitrate: 0 for the default, else the bitrate in steps,
    /// held to the slider's range.
    public var sliderPosition: Int {
        Self.sliderPosition(forKbps: bitrateKbps)
    }

    public static func sliderPosition(forKbps kbps: Int) -> Int {
        min(max(kbps > 0 ? kbps / bitrateStepKbps : 0, 0), sliderMaximum)
    }

    /// The slider was let go, or a key moved it: saves that position.
    public func setSliderPosition(_ position: Int) {
        let position = min(max(position, 0), Self.sliderMaximum)
        storage.set(position == 0 ? 0 : position * Self.bitrateStepKbps, forKey: OverrideKeys.bitrate)
    }

    /// A plus or minus key (or a d-pad press while adjusting) moved the slider by whole steps.
    /// Saves the new position and returns it; nothing is saved at either end.
    @discardableResult
    public func stepSlider(by steps: Int) -> Int {
        let current = sliderPosition
        let next = min(max(current + steps, 0), Self.sliderMaximum)
        if next != current {
            setSliderPosition(next)
        }
        return next
    }

    /// The text from the "Set Bitrate Override" box, in Mbps.
    @discardableResult
    public func setBitrate(fromText text: String) -> BitrateInputResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .ignored
        }
        // Java's Integer.parseInt: a whole number that fits an Int32
        guard let typed = Int(trimmed), typed >= Int(Int32.min), typed <= Int(Int32.max) else {
            return .invalid
        }
        var mbps = typed
        var clamped = false
        if mbps < 0 {
            mbps = 0
        } else if mbps > Self.maximumBitrateMbps {
            mbps = Self.maximumBitrateMbps
            clamped = true
        }
        storage.set(mbps * 1000, forKey: OverrideKeys.bitrate)
        return clamped ? .clamped(kbps: mbps * 1000) : .saved(kbps: mbps * 1000)
    }

    /// What the box shows when it opens: the saved Mbps, or empty for the default.
    public var bitrateInputText: String {
        let kbps = bitrateKbps
        return kbps > 0 ? String(kbps / 1000) : ""
    }

    // MARK: - Stats overlay and codec

    public var statsOverlay: StatsOverlayOverride { StatsOverlayOverride(saved: int(OverrideKeys.statsOverlay)) }

    /// The stats button: default, then on, then off, then default again.
    @discardableResult
    public func cycleStatsOverlay() -> StatsOverlayOverride {
        // Java's remainder, as Android does it on whatever number is saved
        let next = (int(OverrideKeys.statsOverlay) + 1) % 3
        storage.set(next, forKey: OverrideKeys.statsOverlay)
        return StatsOverlayOverride(saved: next)
    }

    public var codec: CodecOverride { CodecOverride(saved: int(OverrideKeys.codec)) }

    /// The codec button: default, HEVC, AV1, PyroWave, then default again. Each codec keeps its own
    /// bitrate: the one on the slider is filed under the codec being left, and the one filed under
    /// the new codec (0 if none) comes onto the slider.
    @discardableResult
    public func cycleCodec() -> CodecOverride {
        let current = int(OverrideKeys.codec)
        let next = (current + 1) % CodecOverride.allCases.count
        let active = int(OverrideKeys.bitrate)
        let remembered = int(OverrideKeys.bitrateForCodec(next))
        storage.set(active, forKey: OverrideKeys.bitrateForCodec(current))
        storage.set(next, forKey: OverrideKeys.codec)
        storage.set(remembered, forKey: OverrideKeys.bitrate)
        return CodecOverride(saved: next)
    }

    // MARK: - Export

    /// The saved values under Android's keys, for a settings export.
    public func exportValues() -> [String: SettingValue] {
        var values: [String: SettingValue] = [:]
        for key in OverrideKeys.all {
            if key == OverrideKeys.enabled {
                if let value = SettingValue.coerce(storage.object(forKey: key), to: .bool) { values[key] = value }
            } else if let value = SettingValue.coerce(storage.object(forKey: key), to: .int) {
                values[key] = value
            }
        }
        return values
    }

    /// Saves values from an export. Keys that aren't override keys and values of the wrong type
    /// are skipped.
    public func importValues(_ values: [String: SettingValue]) {
        for key in OverrideKeys.all {
            switch (key == OverrideKeys.enabled, values[key]) {
            case (true, .bool(let value)?): storage.set(value, forKey: key)
            case (false, .int(let value)?): storage.set(value, forKey: key)
            default: break
            }
        }
    }

    private func int(_ key: String) -> Int {
        if case .int(let value)? = SettingValue.coerce(storage.object(forKey: key), to: .int) { return value }
        return 0
    }

    private func bool(_ key: String) -> Bool {
        if case .bool(let value)? = SettingValue.coerce(storage.object(forKey: key), to: .bool) { return value }
        return false
    }
}

/// The overrides bar's texts, by the names Android gives them in `strings.xml`. Some of Android's
/// texts are written in its code and have no resource; those are marked, and the name is one
/// proposed here.
public enum OverrideText: String, CaseIterable, Sendable {
    case sectionTitle = "overrides_section_title"
    case toggleDescription = "cg_a11y_overrides"
    case bitrateTitle = "title_bitrate_override"
    case bitrateSummary = "summary_bitrate_override"
    case bitrateDefault = "bitrate_use_default"
    // Written in Android's code, not in strings.xml
    case bitrateMbps = "overrides_bitrate_mbps"
    case statsDefault = "overrides_stats_default"
    case statsEnabled = "overrides_stats_enabled"
    case statsDisabled = "overrides_stats_disabled"
    case codecDefault = "overrides_codec_default"
    case codecHEVC = "overrides_codec_hevc"
    case codecAV1 = "overrides_codec_av1"
    case codecPyroWave = "overrides_codec_pyrowave"
    case bitrateDialogTitle = "overrides_bitrate_dialog_title"
    case bitrateDialogMessage = "overrides_bitrate_dialog_message"
    case bitrateMaximum = "overrides_bitrate_maximum"
    case invalidNumber = "overrides_invalid_number"

    public var resourceName: String { rawValue }

    /// Whether Android has this name in `strings.xml`. If not, the name is new.
    public var isAndroidResource: Bool {
        switch self {
        case .sectionTitle, .toggleDescription, .bitrateTitle, .bitrateSummary, .bitrateDefault: return true
        default: return false
        }
    }

    /// Android's wording. "%d" stands for a number.
    public var english: String {
        switch self {
        case .sectionTitle: return "Overrides"
        case .toggleDescription: return "Turn overrides on or off"
        case .bitrateTitle: return "Bitrate Override"
        case .bitrateSummary: return "Override all bitrate settings. Set to left for default behavior."
        case .bitrateDefault: return "Bitrate: (Default)"
        case .bitrateMbps: return "Bitrate: %d Mbps"
        case .statsDefault: return "Stats overlay: Default"
        case .statsEnabled: return "Stats overlay: Enabled"
        case .statsDisabled: return "Stats overlay: Disabled"
        case .codecDefault: return "Codec: Default"
        case .codecHEVC: return "Codec: HEVC"
        case .codecAV1: return "Codec: AV1"
        case .codecPyroWave: return "Codec: PyroWave"
        case .bitrateDialogTitle: return "Set Bitrate Override"
        case .bitrateDialogMessage: return "Enter bitrate in Mbps (0 for default, max %d)"
        case .bitrateMaximum: return "Maximum bitrate is %d Mbps"
        case .invalidNumber: return "Invalid number"
        }
    }
}

/// A text with its number, if it takes one.
public struct OverrideLabel: Equatable, Sendable {
    public let text: OverrideText
    public let number: Int?

    public init(_ text: OverrideText, number: Int? = nil) {
        self.text = text
        self.number = number
    }

    public var resourceName: String { text.resourceName }

    /// Android's wording with the number in.
    public var english: String {
        guard let number else { return text.english }
        return text.english.replacingOccurrences(of: "%d", with: String(number))
    }
}

extension StreamOverrides {
    /// The bitrate label for the saved bitrate: "Bitrate: (Default)" or "Bitrate: 40 Mbps". It
    /// shows the bitrate itself, not the slider's position, so a typed 800 Mbps reads right.
    public var bitrateLabel: OverrideLabel {
        bitrateKbps <= 0 ? OverrideLabel(.bitrateDefault) : OverrideLabel(.bitrateMbps, number: bitrateKbps / 1000)
    }

    /// The label while the slider is being dragged: its position in 10 Mbps steps.
    public static func sliderLabel(position: Int) -> OverrideLabel {
        position == 0 ? OverrideLabel(.bitrateDefault)
            : OverrideLabel(.bitrateMbps, number: position * (StreamOverridesStore.bitrateStepKbps / 1000))
    }

    public var statsOverlayLabel: OverrideLabel {
        switch statsOverlay {
        case .forceOn: return OverrideLabel(.statsEnabled)
        case .forceOff: return OverrideLabel(.statsDisabled)
        case .useDefault: return OverrideLabel(.statsDefault)
        }
    }

    public var codecLabel: OverrideLabel {
        switch codec {
        case .useDefault: return OverrideLabel(.codecDefault)
        case .hevc: return OverrideLabel(.codecHEVC)
        case .av1: return OverrideLabel(.codecAV1)
        case .pyroWave: return OverrideLabel(.codecPyroWave)
        }
    }
}
