import Foundation

/// One game's settings, the same JSON Starwire for Android keeps per game in its
/// `AppPreferences` file (AppPreferences.AppSettings): unset fields are absent, or 0 for the
/// numbers, and `gameOptions` holds only the options that are set.
public struct GameSettings: Equatable, Sendable {
    public var resolution: String?
    /// 0 is unset.
    public var fps: Int
    public var framePacing: String?
    /// kbps. 0 is unset.
    public var bitrate: Int
    /// 0 is unset.
    public var actualDisplayRefreshRate: Double
    /// "true", "false" or unset, as Android stores it.
    public var enableHdr: String?
    public var enablePerfOverlay: String?
    /// When true the overrides are kept but not used.
    public var useGlobalSettings: Bool
    /// Overrides for `SettingsCatalog.gameOptionKeys`, as strings.
    public var gameOptions: [String: String]

    public init(resolution: String? = nil, fps: Int = 0, framePacing: String? = nil, bitrate: Int = 0,
                actualDisplayRefreshRate: Double = 0, enableHdr: String? = nil, enablePerfOverlay: String? = nil,
                useGlobalSettings: Bool = true, gameOptions: [String: String] = [:]) {
        self.resolution = resolution
        self.fps = fps
        self.framePacing = framePacing
        self.bitrate = bitrate
        self.actualDisplayRefreshRate = actualDisplayRefreshRate
        self.enableHdr = enableHdr
        self.enablePerfOverlay = enablePerfOverlay
        self.useGlobalSettings = useGlobalSettings
        self.gameOptions = gameOptions
    }

    /// The key Android files a game's settings under: the PC's UUID and the app's ID.
    public static func key(hostUUID: String, appID: String) -> String {
        "\(hostUUID):\(appID)"
    }

    // MARK: - Android's JSON

    public var jsonObject: [String: Any] {
        var json: [String: Any] = [
            "fps": fps,
            "bitrate": bitrate,
            "actualDisplayRefreshRate": actualDisplayRefreshRate,
            "useGlobalSettings": useGlobalSettings,
            "gameOptions": gameOptions,
        ]
        json["resolution"] = resolution
        json["framePacing"] = framePacing
        json["enableHdr"] = enableHdr
        json["enablePerfOverlay"] = enablePerfOverlay
        return json
    }

    /// Reads Android's JSON. Like Android, anything missing or unreadable is unset.
    public init(jsonObject json: [String: Any]) {
        func string(_ key: String) -> String? {
            json[key] as? String
        }
        func number(_ key: String) -> Double {
            (json[key] as? NSNumber)?.doubleValue ?? (json[key] as? String).flatMap(Double.init) ?? 0
        }
        var options: [String: String] = [:]
        if let raw = json["gameOptions"] as? [String: Any] {
            for (key, value) in raw {
                if let value = value as? String, !value.isEmpty {
                    options[key] = value
                } else if let value = value as? Bool {
                    options[key] = value ? "true" : "false"
                }
            }
        }
        self.init(resolution: string("resolution"), fps: Int(number("fps")), framePacing: string("framePacing"),
                  bitrate: Int(number("bitrate")), actualDisplayRefreshRate: number("actualDisplayRefreshRate"),
                  enableHdr: string("enableHdr"), enablePerfOverlay: string("enablePerfOverlay"),
                  useGlobalSettings: (json["useGlobalSettings"] as? Bool) ?? true, gameOptions: options)
    }

    public func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
    }

    public init(jsonData: Data) {
        let object = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any]
        self.init(jsonObject: object ?? [:])
    }
}

/// Per-game settings, saved under Android's game keys as Android's JSON text.
public final class GameSettingsStore {
    public static let keyPrefix = "game:"
    let storage: SettingsStorage

    public init(storage: SettingsStorage) {
        self.storage = storage
    }

    public func settings(hostUUID: String, appID: String) -> GameSettings {
        settings(forKey: GameSettings.key(hostUUID: hostUUID, appID: appID))
    }

    public func settings(forKey key: String) -> GameSettings {
        guard let text = storage.object(forKey: Self.keyPrefix + key) as? String else {
            return GameSettings()
        }
        return GameSettings(jsonData: Data(text.utf8))
    }

    public func set(_ settings: GameSettings, forKey key: String) {
        if settings == GameSettings() {
            storage.removeObject(forKey: Self.keyPrefix + key)
        } else if let data = try? settings.jsonData() {
            storage.set(String(decoding: data, as: UTF8.self), forKey: Self.keyPrefix + key)
        }
    }

    /// The game keys with settings, for an export. The storage has to be able to list its keys.
    public func keys(in allKeys: [String]) -> [String] {
        allKeys.filter { $0.hasPrefix(Self.keyPrefix) }.map { String($0.dropFirst(Self.keyPrefix.count)) }.sorted()
    }
}

extension SettingsStore {
    /// The settings a stream of this game uses: the global ones, with the game's overrides on
    /// top unless it uses the global settings (AppPreferences.getEffectivePreferences).
    public func effectiveValues(for game: GameSettings) -> [String: SettingValue] {
        var values: [String: SettingValue] = [:]
        for definition in SettingsCatalog.all {
            if let value = value(definition.key) {
                values[definition.key] = value
            }
        }
        if !game.useGlobalSettings {
            applyOverrides(game, to: &values)
        }
        // Android: async LFR only counts with async decode on
        if values["checkbox_async_decode"] != .bool(true) {
            values["checkbox_async_lfr"] = .bool(false)
        }
        return values
    }

    private func applyOverrides(_ game: GameSettings, to values: inout [String: SettingValue]) {
        if let resolution = game.resolution, SettingsStore.parseResolution(resolution) != nil {
            values["list_resolution"] = .string(resolution)
        }
        if game.fps > 0 {
            values["list_fps"] = .string(String(game.fps))
        }
        if let pacing = game.framePacing, SettingsCatalog.framePacing.contains(pacing) {
            values["frame_pacing"] = .string(pacing)
        }
        if game.bitrate > 0 {
            values["seekbar_bitrate_kbps"] = .int(game.bitrate)
        }
        if game.actualDisplayRefreshRate > 0 {
            values["text_actual_display_refresh_rate"] = .string(String(game.actualDisplayRefreshRate))
        }
        if let hdr = game.enableHdr {
            values["checkbox_enable_hdr"] = .bool(hdr == "true")
        }
        if let overlay = game.enablePerfOverlay {
            values["checkbox_enable_perf_overlay"] = .bool(overlay == "true")
        }
        for key in SettingsCatalog.gameOptionKeys {
            guard let raw = game.gameOptions[key], let definition = SettingsCatalog.definition(key),
                  let value = SettingValue.coerce(raw, to: definition.kind), definition.accepts(value) else {
                continue
            }
            values[key] = value
        }
    }
}
