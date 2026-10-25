//
//  StarwireSettings.swift
//  Starwire
//
//  The app's settings store (StarwireKit's SettingsStore, with Android's keys) and what the ObjC
//  code reads from it. Since phase 3 the app's own settings screen writes the store. The old
//  places (moonlight-ios's Core Data record, and the "Starwire..." user defaults that batches 1
//  and 2 kept in the iOS Settings app) are copied into the store once. From then on they get the
//  store's values written back before every stream, because moonlight-ios's code still reads them.
//
//  Launch arguments from the device runs (-StarwireVirtualDisplayMode virtual, ...) are applied
//  on top for that launch only and never saved. A game's own settings are on top while it streams.
//

import Foundation
import StarwireKit
import UIKit

/// Reads from the overrides first, writes only to the saved settings.
final class LayeredSettingsStorage: SettingsStorage {
    let overrides: SettingsStorage
    let saved: SettingsStorage

    init(overrides: SettingsStorage, saved: SettingsStorage) {
        self.overrides = overrides
        self.saved = saved
    }

    func object(forKey key: String) -> Any? { overrides.object(forKey: key) ?? saved.object(forKey: key) }
    func set(_ value: Any?, forKey key: String) { saved.set(value, forKey: key) }
    func removeObject(forKey key: String) { saved.removeObject(forKey: key) }
}

@objc(StarwireSettings)
final class StarwireSettings: NSObject {
    static let suiteName = "io.github.shev0k.starwire.settings"
    /// Set once the old settings have been copied into the store
    static let migratedKey = "starwire_legacy_settings_migrated"

    private static let lock = NSLock()
    private static var current: SettingsStore?
    /// The streaming game's own settings, on top of the saved ones while it streams
    private static var gameLayer = MemorySettingsStorage()

    static var saved: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    private static var smallScreen: Bool {
        UIScreen.main.bounds.width < 500 || UIScreen.main.bounds.height < 500
    }

    /// The store: the saved settings, with the streaming game's settings and this launch's
    /// arguments on top. Writes go to the saved settings.
    static var store: SettingsStore {
        lock.lock()
        defer { lock.unlock() }
        if let current {
            return current
        }
        let arguments = MemorySettingsStorage()
        let fromArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            .filter { SettingsMigration.iosSettingsKeys.contains($0.key) }
        if !fromArguments.isEmpty {
            SettingsMigration.apply(LegacySettings(coreData: nil, iosSettings: fromArguments),
                                    to: SettingsStore(storage: arguments))
        }
        let onTop = LayeredSettingsStorage(overrides: arguments, saved: gameLayer)
        let store = SettingsStore(storage: LayeredSettingsStorage(overrides: onTop, saved: saved), smallScreen: smallScreen)
        current = store
        return store
    }

    /// The saved settings alone, for the settings screen: no launch arguments, no game's settings.
    static var savedStore: SettingsStore {
        SettingsStore(storage: saved, smallScreen: smallScreen)
    }

    /// Per-game settings, saved next to the global ones as Android does.
    static var gameSettings: GameSettingsStore {
        GameSettingsStore(storage: saved)
    }

    /// The overrides bar on the game screen, saved with the settings as on Android.
    static var overrides: StreamOverridesStore {
        StreamOverridesStore(storage: saved)
    }

    /// Quick Launch's entries, in their own suite (Android keeps them in their own file).
    static var quickLaunch: QuickLaunchStore {
        QuickLaunchStore(storage: UserDefaults(suiteName: suiteName + ".quicklaunch") ?? .standard,
                         nowMillis: { Int64(Date().timeIntervalSince1970 * 1000) })
    }

    /// Reads the saved settings and the launch arguments again on next use.
    @objc static func reload() {
        lock.lock()
        current = nil
        lock.unlock()
    }

    /// Copies moonlight-ios's settings and the iOS Settings app's into the store, once. `coreData`
    /// is a TemporarySettings, or nil when the app has none yet.
    @objc static func migrateLegacySettingsOnce(_ coreData: NSObject?) {
        guard !saved.bool(forKey: migratedKey) else { return }
        var legacy = LegacySettings(coreData: nil, iosSettings: [:])
        if let settings = coreData {
            legacy.coreData = Self.coreData(from: settings)
        }
        // Only what the user set in iOS Settings, not the registered defaults
        let appDomain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        legacy.iosSettings = appDomain.filter { SettingsMigration.iosSettingsKeys.contains($0.key) }
        let applied = SettingsMigration.apply(legacy, to: savedStore)
        saved.set(true, forKey: migratedKey)
        reload()
        StarwireLog.info("Settings: \(applied.count) copied once from the old settings")
    }

    /// Before a stream: the game's own settings on top (or none), then every value written where
    /// moonlight-ios's code reads it. Launch arguments still win there: UserDefaults reads them
    /// first, and the stream screen applies them to the Core Data record again.
    /// `displayMode` replaces "Display on the PC" for this stream only (the app menu's Start in
    /// Virtual Display or Primary Display).
    /// `quickLaunchKey` is the Quick Launch entry it was started from, whose own settings come
    /// before the game's. The overrides bar applies unless `applyOverrides` is false (a resumed
    /// session, as on Android).
    static func prepareForStream(hostUUID: String?, appID: String?, displayMode: VirtualDisplayMode? = nil,
                                 quickLaunchKey: String? = nil, applyOverrides: Bool = true) {
        var game = GameSettings()
        if let hostUUID, let appID {
            game = gameSettings.settings(hostUUID: hostUUID, appID: appID)
        }
        let quick = quickLaunchKey.map { gameSettings.settings(forKey: $0) }
        let global = savedStore
        let layer = MemorySettingsStorage()
        var effective = global.launchValues(game: game, quickLaunch: quick, overrides: overrides.overrides,
                                            applyOverrides: applyOverrides)
        if let displayMode {
            effective["virtual_display_mode"] = .string(displayMode.rawValue)
        }
        for (key, value) in effective where global.value(key) != value {
            layer.set(value.propertyListValue, forKey: key)
        }
        lock.lock()
        gameLayer = layer
        current = nil
        lock.unlock()
        if !layer.values.isEmpty {
            StarwireLog.info("Settings: this game changes \(layer.values.keys.sorted().joined(separator: ", "))")
        }
        writeLegacySettings(SettingsStore(storage: LayeredSettingsStorage(overrides: layer, saved: saved),
                                          smallScreen: smallScreen))
    }

    /// The game last started on a PC, for the game screen's hero.
    static func lastPlayed(hostUUID: String) -> String? {
        saved.string(forKey: "last_played:" + hostUUID)
    }

    static func rememberLastPlayed(hostUUID: String, appID: String) {
        saved.set(appID, forKey: "last_played:" + hostUUID)
    }

    /// After a stream: the game's settings come off again.
    static func streamEnded() {
        lock.lock()
        gameLayer = MemorySettingsStorage()
        current = nil
        lock.unlock()
    }

    private static func writeLegacySettings(_ from: SettingsStore) {
        let legacy = SettingsMigration.export(from)
        if let c = legacy.coreData {
            StarwireHostLibraryFacade.saveLegacyCoreDataSettingsBitrate(
                c.bitrateKbps, framerate: c.framerate, height: c.height, width: c.width, audioConfig: c.audioConfig,
                spatialAudio: c.spatialAudio, onscreenControls: c.onscreenControls, optimizeGames: c.optimizeGames,
                multiController: c.multiController, swapABXYButtons: c.swapABXYButtons, audioOnPC: c.playAudioOnPC,
                preferredCodec: c.preferredCodec, frameQueueSize: c.frameQueueSize, enableHdr: c.enableHdr,
                enableYUV444: c.enableYUV444, btMouseSupport: c.btMouseSupport, absoluteTouchMode: c.absoluteTouchMode,
                statsOverlay: c.statsOverlay, enableGraphs: c.enableGraphs, graphOpacity: c.graphOpacity)
        }
        for (key, value) in legacy.iosSettings {
            UserDefaults.standard.set(value, forKey: key)
        }
    }


    private static func coreData(from settings: NSObject) -> LegacySettings.CoreData {
        func int(_ key: String) -> Int { (settings.value(forKey: key) as? NSNumber)?.intValue ?? 0 }
        func bool(_ key: String) -> Bool { (settings.value(forKey: key) as? NSNumber)?.boolValue ?? false }
        return LegacySettings.CoreData(
            bitrateKbps: int("bitrate"), framerate: int("framerate"), width: int("width"), height: int("height"),
            audioConfig: int("audioConfig"), preferredCodec: int("preferredCodec"), frameQueueSize: int("frameQueueSize"),
            multiController: bool("multiController"), swapABXYButtons: bool("swapABXYButtons"),
            playAudioOnPC: bool("playAudioOnPC"), optimizeGames: bool("optimizeGames"), enableHdr: bool("enableHdr"),
            enableYUV444: bool("enableYUV444"), btMouseSupport: bool("btMouseSupport"),
            absoluteTouchMode: bool("absoluteTouchMode"), statsOverlay: bool("statsOverlay"),
            enableGraphs: bool("enableGraphs"), graphOpacity: int("graphOpacity"),
            onscreenControls: int("onscreenControls"), spatialAudio: int("spatialAudio"))
    }

    /// The name this device gives the PC: the setting, or the device's own name.
    @objc static var clientName: String {
        let name = store[.clientName].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? defaultClientName : name
    }

    /// Since iOS 16 UIDevice.name is "iPad" without a special entitlement, so the default says
    /// which iPad or iPhone it is.
    static var defaultClientName: String {
        let device = UIDevice.current
        return device.userInterfaceIdiom == .pad ? "Starwire on iPad" : "Starwire on iPhone"
    }

    /// The launch options for a stream of this size, from the settings.
    static func launchOptions(width: Int, height: Int, frameRate: Int) -> LaunchOptions {
        var options = LaunchOptions(settings: store, width: width, height: height, deviceName: clientName)
        // An exact rate is only used when it rounds to the stream's own frame rate, so a stale
        // 119.88 can't ask for 120 Hz when the stream was set to 60
        if options.streamFrameRate != frameRate {
            options.refreshRate = Double(frameRate)
        }
        return options
    }

    /// `mode` for the launch request: WIDTHxHEIGHTxRATE, where the rate may be fractional.
    @objc static func launchMode(width: Int, height: Int, frameRate: Int) -> String {
        launchOptions(width: width, height: height, frameRate: frameRate).mode
    }

    /// Vibeshine's launch options as a query string that starts with "&", or "".
    @objc static func launchQueryExtras(width: Int, height: Int, frameRate: Int) -> String {
        launchOptions(width: width, height: height, frameRate: frameRate).extraQueryString
    }

    /// For the log: what the launch asks for.
    @objc static func launchSummary(width: Int, height: Int, frameRate: Int) -> String {
        let options = launchOptions(width: width, height: height, frameRate: frameRate)
        return "mode \(options.mode), display \(options.virtualDisplay.rawValue), scale \(options.scalePercent)%, VRR \(options.requestVRR ? "on" : "off")"
    }

    /// The demo mode: a PC and streams with nothing behind them (StarwireKit's DemoMode).
    @objc static var demoModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "StarwireDemoMode")
    }
}
