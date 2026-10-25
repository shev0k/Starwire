import Foundation

/// Settings as a JSON file, to move them between devices and between Starwire for Android and
/// iOS. Android has no export of its own yet, so this is the format both should use:
///
///     {
///       "format": "starwire-settings",
///       "version": 1,
///       "settings": { "list_fps": "120", "checkbox_enable_hdr": true, "seekbar_deadzone": 7 },
///       "games": { "<PC UUID>:<app ID>": { ...Android's per-game JSON... } }
///     }
///
/// Keys and value types are Android's (lists as strings, check boxes as booleans, sliders as
/// numbers). Only saved values go out, so the other app's defaults still apply to the rest.
/// Secrets (the microphone's pairing keys) and device state are never in it.
public enum SettingsJSON {
    public static let format = "starwire-settings"
    public static let version = 1

    public struct ImportReport: Equatable {
        /// Keys that were set.
        public var applied: [String] = []
        /// Keys left out, with why.
        public var skipped: [String: String] = [:]
        /// Games whose settings were set.
        public var games: [String] = []
    }

    public enum ImportError: Error, Equatable {
        case notJSON
        case notStarwireSettings
        case newerVersion(Int)
    }

    public static func export(_ store: SettingsStore, games: GameSettingsStore? = nil, gameKeys: [String] = []) throws -> Data {
        var settings: [String: Any] = [:]
        for (key, value) in store.savedValues() {
            settings[key] = value.jsonValue
        }
        var root: [String: Any] = ["format": format, "version": version, "settings": settings]
        if let games {
            var gameObjects: [String: Any] = [:]
            for key in gameKeys {
                let game = games.settings(forKey: key)
                if game != GameSettings() {
                    gameObjects[key] = game.jsonObject
                }
            }
            root["games"] = gameObjects
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Imports a file over the current settings. Unknown keys, wrong types and values a list
    /// doesn't have are skipped and reported; the rest is applied. A setting that isn't in the
    /// file keeps its current value.
    @discardableResult
    public static func `import`(_ data: Data, into store: SettingsStore, games: GameSettingsStore? = nil) throws -> ImportReport {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw ImportError.notJSON
        }
        guard let root = object as? [String: Any], root["format"] as? String == format, let settings = root["settings"] as? [String: Any] else {
            throw ImportError.notStarwireSettings
        }
        let fileVersion = (root["version"] as? NSNumber)?.intValue ?? 1
        guard fileVersion <= version else {
            throw ImportError.newerVersion(fileVersion)
        }

        var report = ImportReport()
        for key in settings.keys.sorted() {
            guard let definition = SettingsCatalog.definition(key) else {
                report.skipped[key] = "not a setting this version knows"
                continue
            }
            guard var value = SettingValue.coerce(settings[key], to: definition.kind) else {
                report.skipped[key] = "not a \(definition.kind.rawValue)"
                continue
            }
            if key == "video_renderer", value == .string("direct") || value == .string("vulkan") {
                value = .string("auto")
            }
            do {
                try store.set(value, for: key)
                report.applied.append(key)
            } catch {
                report.skipped[key] = "value not allowed"
            }
        }

        if let games, let gameObjects = root["games"] as? [String: Any] {
            for key in gameObjects.keys.sorted() {
                guard let object = gameObjects[key] as? [String: Any], key.split(separator: ":").count >= 2 else {
                    report.skipped["games." + key] = "not a game's settings"
                    continue
                }
                games.set(GameSettings(jsonObject: object), forKey: key)
                report.games.append(key)
            }
        }
        return report
    }
}
