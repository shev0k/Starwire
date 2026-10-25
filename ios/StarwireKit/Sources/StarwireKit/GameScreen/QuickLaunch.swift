// Ported from Starwire for Android's QuickLaunchManager (com.limelight.utils) and the rules of its
// QuickLaunchView (GPL-3.0, Starwire; built on Moonlight X).
import Foundation

/// A settings storage that can also list its keys. Quick Launch needs it to find entries that are
/// missing from the saved order, as Android does with `SharedPreferences.getAll()`.
public protocol KeyListingStorage: SettingsStorage {
    var allKeys: [String] { get }
}

extension MemorySettingsStorage: KeyListingStorage {
    public var allKeys: [String] { Array(values.keys) }
}

extension UserDefaults: KeyListingStorage {
    public var allKeys: [String] { Array(dictionaryRepresentation().keys) }
}

/// One pinned game on the PC list: a game on one PC, with the name the user gave it.
/// The same game can be pinned more than once.
public struct QuickLaunchEntry: Equatable, Hashable, Sendable {
    /// `<PC UUID>:<app ID>:<time added in milliseconds>`. It is also the key of this entry's own
    /// stream settings (`GameSettingsStore.settings(forKey:)`), as on Android.
    public let key: String
    public let computerUUID: String
    public let appID: Int
    public let computerName: String
    public let originalAppName: String
    public let customName: String

    public init(key: String, computerUUID: String, appID: Int, computerName: String,
                originalAppName: String, customName: String? = nil) {
        self.key = key
        self.computerUUID = computerUUID
        self.appID = appID
        self.computerName = computerName
        self.originalAppName = originalAppName
        self.customName = customName ?? originalAppName
    }

    /// The button's text.
    public var displayName: String { customName }

    /// The name with the game's own name after it when they differ: "Fast (Forza Horizon)".
    public var displayNameLong: String {
        customName + (customName != originalAppName ? " (\(originalAppName))" : "")
    }
}

/// The Quick Launch list, saved the way Android saves it in its "QuickLaunch" preferences file, so
/// a settings export carries it across: one string per entry under the entry's key
/// (`computer name|game name|custom name`), the order under `_sort_order` (keys joined with
/// commas), and the entry last started on each PC under `_last_started_<PC UUID>`.
///
/// Android has no limit on the number of entries. Time is passed in (`tick(now:)`), so nothing
/// here waits.
public final class QuickLaunchStore {
    public static let sortOrderKey = "_sort_order"
    public static let lastStartedKeyPrefix = "_last_started_"
    /// Android waits this long (seconds) before believing that a PC's game has stopped, because the
    /// host sometimes reports "nothing running" for a moment.
    public static let stopDebounce: TimeInterval = 1.0

    private let storage: SettingsStorage
    private let nowMillis: () -> Int64

    private var runningAppIDs: [String: Int] = [:]
    private var pendingStops: [String: TimeInterval] = [:]

    /// Called whenever the running state may have changed, so the buttons can be redrawn.
    public var onRunningStatusChanged: (() -> Void)?

    /// `nowMillis` gives the time in milliseconds since 1970; it only makes the keys unique.
    public init(storage: SettingsStorage,
                nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.storage = storage
        self.nowMillis = nowMillis
    }

    // MARK: - The list

    /// Every entry in the saved order. Entries missing from the order (old data) go to the end,
    /// oldest first, and the order is saved with them.
    public func entries() -> [QuickLaunchEntry] {
        var order = savedOrder()
        var found: [String: QuickLaunchEntry] = [:]
        var candidates = order
        if let listing = storage as? KeyListingStorage {
            candidates += listing.allKeys
        }
        for key in candidates where key != Self.sortOrderKey && found[key] == nil {
            if let value = storage.object(forKey: key) as? String, let entry = Self.parse(key: key, value: value) {
                found[key] = entry
            }
        }
        var result: [QuickLaunchEntry] = []
        for key in order {
            if let entry = found.removeValue(forKey: key) {
                result.append(entry)
            }
        }
        if !found.isEmpty {
            let orphans = found.values.sorted { ($0.timestamp, $0.key) < ($1.timestamp, $1.key) }
            for orphan in orphans {
                result.append(orphan)
                order.append(orphan.key)
            }
            saveOrder(order)
        }
        return result
    }

    public func entry(forKey key: String?) -> QuickLaunchEntry? {
        guard let key else { return nil }
        return entries().first { $0.key == key }
    }

    /// The entry whose custom name matches, ignoring case. This is how a home screen shortcut
    /// finds its entry.
    public func entry(named name: String?) -> QuickLaunchEntry? {
        guard let name, !name.isEmpty else { return nil }
        return entries().first { $0.customName.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Pins a game at the end of the list. Returns nil when the game has no name, because Android
    /// could not read such an entry back. A "|" in a name becomes "/", since "|" separates the
    /// names in the saved text.
    @discardableResult
    public func add(computerUUID: String, computerName: String, appID: Int, appName: String) -> QuickLaunchEntry? {
        let app = Self.clean(appName)
        guard !app.isEmpty else { return nil }
        let computer = Self.clean(computerName)
        var stamp = nowMillis()
        var key = "\(computerUUID):\(appID):\(stamp)"
        var order = savedOrder()
        while storage.object(forKey: key) != nil || order.contains(key) {
            stamp += 1
            key = "\(computerUUID):\(appID):\(stamp)"
        }
        order.append(key)
        saveOrder(order)
        storage.set("\(computer)|\(app)|\(app)", forKey: key)
        return QuickLaunchEntry(key: key, computerUUID: computerUUID, appID: appID, computerName: computer,
                                originalAppName: app, customName: app)
    }

    /// Takes an entry off the list.
    public func remove(key: String) {
        saveOrder(savedOrder().filter { $0 != key })
        storage.removeObject(forKey: key)
    }

    /// Gives an entry its own name. The name is trimmed; an empty name changes nothing, as in
    /// Android's rename box. Returns whether the name was changed.
    @discardableResult
    public func rename(key: String, to newName: String) -> Bool {
        let name = Self.clean(newName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let value = storage.object(forKey: key) as? String else { return false }
        let parts = Self.javaSplit(value, separator: "|")
        guard parts.count >= 2 else { return false }
        storage.set("\(parts[0])|\(parts[1])|\(name)", forKey: key)
        return true
    }

    /// Swaps the entry with the one before it. False if it is first or not on the list.
    @discardableResult
    public func moveLeft(key: String) -> Bool { move(key: key, by: -1) }

    /// Swaps the entry with the one after it. False if it is last or not on the list.
    @discardableResult
    public func moveRight(key: String) -> Bool { move(key: key, by: 1) }

    private func move(key: String, by offset: Int) -> Bool {
        var keys = entries().map(\.key)
        guard let index = keys.firstIndex(of: key), keys.indices.contains(index + offset) else { return false }
        keys.swapAt(index, index + offset)
        saveOrder(keys)
        return true
    }

    // MARK: - What is running

    /// The entries whose game is running, given each PC's running app IDs (0 means none). When a
    /// game is pinned twice only one entry counts as running: the one started last on that PC, or
    /// else the first in the list.
    public func runningKeys(runningAppIDs: [String: [Int]]) -> Set<String> {
        let all = entries()
        var keys: Set<String> = []
        for (uuid, ids) in runningAppIDs {
            for id in ids where id != 0 {
                if let lastStarted = lastStartedKey(on: uuid),
                   all.contains(where: { $0.key == lastStarted && $0.computerUUID == uuid && $0.appID == id }) {
                    keys.insert(lastStarted)
                } else if let first = all.first(where: { $0.computerUUID == uuid && $0.appID == id }) {
                    keys.insert(first.key)
                }
            }
        }
        return keys
    }

    /// The PC reported which game is running (0 for none), from its latest poll. A report of 0 is
    /// held for `stopDebounce` seconds first, and dropped if a game shows up before then.
    public func updateRunningAppID(_ appID: Int, onPC uuid: String, now: TimeInterval) {
        if appID == 0 {
            pendingStops[uuid] = now + Self.stopDebounce
        } else {
            pendingStops[uuid] = nil
            applyRunningAppID(appID, onPC: uuid)
        }
    }

    /// When `tick(now:)` next has something to do.
    public var nextDeadline: TimeInterval? { pendingStops.values.min() }

    /// Applies the held "nothing running" reports that are due.
    public func tick(now: TimeInterval) {
        for (uuid, due) in pendingStops.sorted(by: { $0.key < $1.key }) where due <= now {
            pendingStops[uuid] = nil
            applyRunningAppID(0, onPC: uuid)
        }
    }

    /// The user tapped this entry to start it: it is now the one running on its PC.
    public func markStarted(key: String) {
        guard let entry = entry(forKey: key) else { return }
        runningAppIDs[entry.computerUUID] = entry.appID
        storage.set(key, forKey: Self.lastStartedKeyPrefix + entry.computerUUID)
        onRunningStatusChanged?()
    }

    /// Whether this entry is the one running on its PC: it was the last started (or the first
    /// match for the running game) and the PC's running game is its game.
    public func isRunning(key: String?) -> Bool {
        guard let key, let entry = entry(forKey: key) else { return false }
        let lastStarted = lastStartedKey(on: entry.computerUUID)
        guard runningAppIDs[entry.computerUUID] != nil || lastStarted != nil else { return false }
        return key == lastStarted && (runningAppIDs[entry.computerUUID] ?? 0) == entry.appID
    }

    private func applyRunningAppID(_ appID: Int, onPC uuid: String) {
        runningAppIDs[uuid] = appID
        defer { onRunningStatusChanged?() }
        // The host sometimes says 0 for a moment, so the last started entry is kept
        if appID == 0 {
            return
        }
        if let lastStarted = lastStartedKey(on: uuid), let entry = entry(forKey: lastStarted),
           entry.appID == appID, entry.computerUUID == uuid {
            return
        }
        let match = entries().first { $0.appID == appID && $0.computerUUID == uuid }
        if let match {
            storage.set(match.key, forKey: Self.lastStartedKeyPrefix + uuid)
        } else {
            storage.removeObject(forKey: Self.lastStartedKeyPrefix + uuid)
        }
    }

    private func lastStartedKey(on uuid: String) -> String? {
        let key = storage.object(forKey: Self.lastStartedKeyPrefix + uuid) as? String
        return key?.isEmpty == false ? key : nil
    }

    // MARK: - Export

    /// What Android's QuickLaunch file holds for the entries and their order, as it would be in a
    /// settings export. What was last started is not included: it describes this device's session.
    public func exportValues() -> [String: String] {
        var values: [String: String] = [:]
        let all = entries()
        for entry in all {
            values[entry.key] = "\(entry.computerName)|\(entry.originalAppName)|\(entry.customName)"
        }
        values[Self.sortOrderKey] = all.map(\.key).joined(separator: ",")
        return values
    }

    /// Replaces the list with exported values. Entries that can't be read are left out.
    public func importValues(_ values: [String: String]) {
        for entry in entries() {
            storage.removeObject(forKey: entry.key)
        }
        var order: [String] = []
        for key in Self.javaSplit(values[Self.sortOrderKey] ?? "", separator: ",") where !key.isEmpty {
            order.append(key)
        }
        for key in values.keys.sorted() where key != Self.sortOrderKey && !key.hasPrefix(Self.lastStartedKeyPrefix) {
            if Self.parse(key: key, value: values[key] ?? "") != nil {
                storage.set(values[key], forKey: key)
                if !order.contains(key) {
                    order.append(key)
                }
            }
        }
        saveOrder(order)
    }

    // MARK: - Android's text format

    /// Reads one saved entry: key `uuid:appID:time`, value `computer|game|custom`. Nil when
    /// Android would not show it.
    static func parse(key: String, value: String) -> QuickLaunchEntry? {
        let keyParts = javaSplit(key, separator: ":")
        guard keyParts.count >= 3, let appID = javaInt(keyParts[1]) else { return nil }
        let valueParts = javaSplit(value, separator: "|")
        guard valueParts.count >= 3 else { return nil }
        return QuickLaunchEntry(key: key, computerUUID: keyParts[0], appID: appID, computerName: valueParts[0],
                                originalAppName: valueParts[1], customName: valueParts[2])
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "/")
    }

    /// Java's `String.split`: empty pieces at the end are dropped, and an empty string is one piece.
    static func javaSplit(_ text: String, separator: Character) -> [String] {
        var parts = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        while parts.count > 1, parts.last == "" {
            parts.removeLast()
        }
        return parts
    }

    /// Java's `Integer.parseInt` for the range Android's int has.
    private static func javaInt(_ text: String) -> Int? {
        guard let value = Int(text), value >= Int(Int32.min), value <= Int(Int32.max) else { return nil }
        return value
    }

    private func savedOrder() -> [String] {
        let text = storage.object(forKey: Self.sortOrderKey) as? String ?? ""
        return text.isEmpty ? [] : Self.javaSplit(text, separator: ",").filter { !$0.isEmpty }
    }

    private func saveOrder(_ order: [String]) {
        storage.set(order.joined(separator: ","), forKey: Self.sortOrderKey)
    }
}

extension QuickLaunchEntry {
    /// The time the entry was added, from the end of its key (0 if unreadable).
    fileprivate var timestamp: Int64 {
        Int64(key.split(separator: ":").last ?? "") ?? 0
    }
}

/// The texts of Quick Launch, by the names Android gives them in `strings.xml`. A String Catalog
/// keyed by these names has the same wording. Texts Android writes in its code (no resource) are
/// marked and have a name proposed here.
public enum QuickLaunchText: String, CaseIterable, Sendable {
    case sectionTitle = "quick_launch_section_title"
    case added = "quick_launch_added"
    case removed = "quick_launch_removed"
    case error = "quick_launch_error"
    case rename = "quick_launch_rename"
    case settings = "quick_launch_settings"
    case moveLeft = "quick_launch_move_left"
    case moveRight = "quick_launch_move_right"
    case delete = "quick_launch_delete"
    case renameTitle = "quick_launch_rename_title"
    case renameMessage = "quick_launch_rename_message"
    case renamed = "quick_launch_renamed"
    /// The menu item that quits the running game.
    case quit = "applist_menu_quit"
    // Written in Android's code, not in strings.xml
    case cannotMoveLeft = "quick_launch_cannot_move_left"
    case cannotMoveRight = "quick_launch_cannot_move_right"
    case removeTitle = "quick_launch_remove_title"
    case removeMessage = "quick_launch_remove_message"
    case pcNotFound = "quick_launch_pc_not_found"

    /// The resource name.
    public var resourceName: String { rawValue }

    /// Whether Android has this name in `strings.xml`. If not, the name is new.
    public var isAndroidResource: Bool {
        switch self {
        case .cannotMoveLeft, .cannotMoveRight, .removeTitle, .removeMessage, .pcNotFound: return false
        default: return true
        }
    }

    /// Android's wording. `removeMessage` has one argument, the entry's name.
    public var english: String {
        switch self {
        case .sectionTitle: return "Quick Launch"
        case .added: return "Added to Quick Launch"
        case .removed: return "Removed from Quick Launch"
        case .error: return "Error with Quick Launch"
        case .rename: return "Rename"
        case .settings: return "App Settings Override"
        case .moveLeft: return "Move Left"
        case .moveRight: return "Move Right"
        case .delete: return "Remove from Quick Launch"
        case .renameTitle: return "Rename Quick Launch"
        case .renameMessage: return "Enter a new name for this Quick Launch item:"
        case .renamed: return "Quick Launch renamed"
        case .quit: return "Quit Session"
        case .cannotMoveLeft: return "Cannot move left"
        case .cannotMoveRight: return "Cannot move right"
        case .removeTitle: return "Remove from Quick Launch"
        case .removeMessage: return "Remove \"%@\" from Quick Launch?"
        case .pcNotFound: return "PC not found"
        }
    }
}
