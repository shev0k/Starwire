import Foundation

/// Where settings are saved: UserDefaults in the app, a dictionary in tests.
public protocol SettingsStorage: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: SettingsStorage {}

public final class MemorySettingsStorage: SettingsStorage {
    public private(set) var values: [String: Any] = [:]

    public init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    public func object(forKey key: String) -> Any? { values[key] }
    public func set(_ value: Any?, forKey key: String) { values[key] = value }
    public func removeObject(forKey key: String) { values[key] = nil }
}

public enum SettingsError: Error, Equatable {
    case unknownKey(String)
    case wrongKind(String, expected: SettingKind)
    case notAllowed(String, String)
}

/// A setting with a Swift type. The key and default come from `SettingsCatalog`.
public struct Setting<Value>: @unchecked Sendable {
    public let key: String
    let decode: (SettingValue) -> Value?
    let encode: (Value) -> SettingValue
}

extension Setting where Value == Bool {
    public init(bool key: String) {
        self.init(key: key, decode: { if case .bool(let v) = $0 { return v } else { return nil } }, encode: { .bool($0) })
    }
}

extension Setting where Value == Int {
    public init(int key: String) {
        self.init(key: key, decode: { if case .int(let v) = $0 { return v } else { return nil } }, encode: { .int($0) })
    }
}

extension Setting where Value == String {
    public init(string key: String) {
        self.init(key: key, decode: { if case .string(let v) = $0 { return v } else { return nil } }, encode: { .string($0) })
    }
}

extension Setting where Value: RawRepresentable, Value.RawValue == String {
    public init(list key: String) {
        self.init(key: key, decode: { if case .string(let v) = $0 { return Value(rawValue: v) } else { return nil } },
                  encode: { .string($0.rawValue) })
    }
}

/// What the PC should stream to: Android's "Display on the PC".
public enum VirtualDisplayMode: String, Sendable, CaseIterable {
    /// Let the host decide (send no `virtualDisplay`).
    case host
    /// Ask for a virtual display (`virtualDisplay=1`).
    case virtual
    /// Ask for the PC's own monitor (`virtualDisplay=0`).
    case primary
}

extension Setting {
    public static var resolution: Setting<String> { Setting<String>(string: "list_resolution") }
    public static var frameRate: Setting<String> { Setting<String>(string: "list_fps") }
    public static var bitrateKbps: Setting<Int> { Setting<Int>(int: "seekbar_bitrate_kbps") }
    public static var virtualDisplayMode: Setting<VirtualDisplayMode> { Setting<VirtualDisplayMode>(list: "virtual_display_mode") }
    public static var virtualDisplayScale: Setting<Int> { Setting<Int>(int: "seekbar_virtual_display_scale") }
    public static var vrrRequest: Setting<Bool> { Setting<Bool>(bool: "checkbox_vrr_request") }
    public static var clientName: Setting<String> { Setting<String>(string: "text_client_name") }
    public static var hostAudio: Setting<Bool> { Setting<Bool>(bool: "checkbox_host_audio") }
    public static var optimizeGameSettings: Setting<Bool> { Setting<Bool>(bool: "checkbox_enable_sops") }
    public static var perfOverlay: Setting<Bool> { Setting<Bool>(bool: "checkbox_enable_perf_overlay") }
    public static var enableHDR: Setting<Bool> { Setting<Bool>(bool: "checkbox_enable_hdr") }
}

/// The app's settings, in one store, typed. Values are saved under Android's keys with Android's
/// types, so `SettingsJSON` can move them between the two apps.
///
/// A saved value that is the wrong kind or not one of a list's values is ignored and the default
/// used, as Android does for unknown list values.
public final class SettingsStore {
    public let storage: SettingsStorage
    /// For `checkbox_small_icon_mode`: true on screens narrower than 500 points, as Android.
    public let smallScreen: Bool

    public init(storage: SettingsStorage, smallScreen: Bool = false) {
        self.storage = storage
        self.smallScreen = smallScreen
    }

    /// The saved value, or nil if none is saved or it isn't valid for the key.
    public func savedValue(_ key: String) -> SettingValue? {
        guard let definition = SettingsCatalog.definition(key),
              let value = SettingValue.coerce(storage.object(forKey: key), to: definition.kind),
              definition.accepts(value) else {
            return nil
        }
        return value
    }

    /// The saved value, or the default.
    public func value(_ key: String) -> SettingValue? {
        if let saved = savedValue(key) {
            return saved
        }
        return defaultValue(key)
    }

    public func defaultValue(_ key: String) -> SettingValue? {
        switch key {
        case "seekbar_bitrate_kbps":
            let (width, height) = Self.parseResolution(stringValue("list_resolution")) ?? (1280, 720)
            return .int(Self.defaultBitrate(width: width, height: height, fps: Double(stringValue("list_fps")) ?? 60))
        case "checkbox_small_icon_mode":
            return .bool(smallScreen)
        case "list_touch_mode":
            let trackpad = value("checkbox_touchscreen_trackpad") == .bool(true)
            return .string(TouchMode.initial(touchscreenTrackpad: trackpad).settingValue)
        case "list_video_scaling":
            return .string(value("checkbox_stretch_video") == .bool(true) ? PictureScaling.stretch.rawValue : PictureScaling.fit.rawValue)
        default:
            return SettingsCatalog.definition(key)?.defaultValue
        }
    }

    public func set(_ value: SettingValue, for key: String) throws {
        guard let definition = SettingsCatalog.definition(key) else {
            throw SettingsError.unknownKey(key)
        }
        guard value.kind == definition.kind else {
            throw SettingsError.wrongKind(key, expected: definition.kind)
        }
        guard definition.accepts(value) else {
            if case .string(let string) = value {
                throw SettingsError.notAllowed(key, string)
            }
            throw SettingsError.notAllowed(key, "\(value)")
        }
        storage.set(value.propertyListValue, forKey: key)
    }

    /// Back to the default.
    public func reset(_ key: String) {
        storage.removeObject(forKey: key)
    }

    /// Every key with a saved, valid value.
    public func savedValues() -> [String: SettingValue] {
        var values: [String: SettingValue] = [:]
        for definition in SettingsCatalog.all {
            if let value = savedValue(definition.key) {
                values[definition.key] = value
            }
        }
        return values
    }

    public subscript<Value>(setting: Setting<Value>) -> Value {
        get {
            if let saved = savedValue(setting.key), let value = setting.decode(saved) {
                return value
            }
            return setting.decode(defaultValue(setting.key)!)!
        }
        set {
            try? set(setting.encode(newValue), for: setting.key)
        }
    }

    private func stringValue(_ key: String) -> String {
        if case .string(let string)? = value(key) {
            return string
        }
        return ""
    }

    // MARK: - Helpers shared with the launch request

    /// "1920x1080" as numbers, or nil.
    public static func parseResolution(_ text: String) -> (Int, Int)? {
        let parts = text.lowercased().split(separator: "x")
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]), width > 0, height > 0 else {
            return nil
        }
        return (width, height)
    }

    /// Android's default bitrate for a resolution and frame rate, from Moonlight Qt
    /// (PreferenceConfiguration.getDefaultBitrate): 10 Mbps at 720p60, 20 at 1080p60.
    public static func defaultBitrate(width: Int, height: Int, fps: Double) -> Int {
        let frameRateFactor = (fps <= 60 ? fps : (fps / 60).squareRoot() * 60) / 30
        let pixels: [Double] = [640 * 360, 854 * 480, 1280 * 720, 1920 * 1080, 2560 * 1440, 3840 * 2160]
        let factors: [Double] = [1, 2, 5, 10, 20, 40]
        let target = Double(width * height)
        var resolutionFactor = factors.last!
        if target <= pixels[0] {
            resolutionFactor = factors[0]
        } else {
            for i in 1..<pixels.count where target <= pixels[i] {
                let fraction = (target - pixels[i - 1]) / (pixels[i] - pixels[i - 1])
                resolutionFactor = factors[i - 1] + fraction * (factors[i] - factors[i - 1])
                break
            }
        }
        // Android keeps the resolution factor in a float and rounds half up (Math.round)
        return Int((Double(Float(resolutionFactor)) * frameRateFactor + 0.5).rounded(.down)) * 1000
    }
}
