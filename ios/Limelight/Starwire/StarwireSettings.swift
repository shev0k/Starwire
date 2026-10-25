//
//  StarwireSettings.swift
//  Starwire
//
//  The app's settings store (StarwireKit's SettingsStore, with Android's keys) and what the ObjC
//  code reads from it. Until phase 3 replaces moonlight-ios's settings screen, that screen and the
//  iOS Settings app stay where settings are changed: their values are copied into the store at
//  every launch and whenever the app becomes active (SettingsMigration).
//
//  Launch arguments from the device runs (-StarwireVirtualDisplayMode virtual, ...) are applied
//  on top for that launch only and never saved.
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

    private static let lock = NSLock()
    private static var current: SettingsStore?

    /// The store. Built on first use from the saved settings and this launch's arguments.
    static var store: SettingsStore {
        lock.lock()
        defer { lock.unlock() }
        if let current {
            return current
        }
        let saved = UserDefaults(suiteName: suiteName) ?? .standard
        let overrides = MemorySettingsStorage()
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let fromArguments = arguments.filter { SettingsMigration.iosSettingsKeys.contains($0.key) }
        if !fromArguments.isEmpty {
            SettingsMigration.apply(LegacySettings(coreData: nil, iosSettings: fromArguments),
                                    to: SettingsStore(storage: overrides))
        }
        let store = SettingsStore(storage: LayeredSettingsStorage(overrides: overrides, saved: saved),
                                  smallScreen: UIScreen.main.bounds.width < 500 || UIScreen.main.bounds.height < 500)
        current = store
        return store
    }

    /// Reads the saved settings and the launch arguments again on next use.
    @objc static func reload() {
        lock.lock()
        current = nil
        lock.unlock()
    }

    /// Copies moonlight-ios's settings and the iOS Settings app's into the store. `coreData` is
    /// a TemporarySettings, or nil when the app has none yet.
    @objc static func syncLegacySettings(_ coreData: NSObject?) {
        var legacy = LegacySettings(coreData: nil, iosSettings: [:])
        if let settings = coreData {
            legacy.coreData = Self.coreData(from: settings)
        }
        // Only what the user set in iOS Settings, not the registered defaults
        let appDomain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        legacy.iosSettings = appDomain.filter { SettingsMigration.iosSettingsKeys.contains($0.key) }
        let applied = SettingsMigration.apply(legacy, to: store)
        StarwireLog.info("Settings: \(applied.count) copied from the old settings")
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
