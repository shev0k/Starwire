import Foundation

// Ported from Starwire for Android (GPL-3.0): CustomCommand.java, CustomCommandsManager.java and
// CustomCommandEditorDialog.java (the format, the list of keys and what "Then" does), Game.java
// (sendCustomKeyCommand, buildPostActionRunnable, onCustomCommand) and KeyboardTranslator.java
// (Android key code to Windows virtual-key code).

/// What happens after a custom command's keys are sent (Android's "Then" list, in its order).
public enum CommandAfterAction: Int, Equatable, Sendable, CaseIterable {
    case none = 0
    case closeMenu = 1
    case disconnect = 2
    case quit = 3
    /// Android locks its own screen with a device admin. iOS has no way to do that, so the
    /// action is read and kept but the app has to say it can't.
    case sleep = 4

    /// False for the actions iOS can't do.
    public var isSupported: Bool { self != .sleep }
}

/// A key and the modifiers held with it, as the editor makes them.
public struct KeyCombination: Equatable, Sendable {
    public var ctrl: Bool
    public var alt: Bool
    public var shift: Bool
    /// The Windows key
    public var meta: Bool
    /// The key as Android's `KeyEvent` code. It is stored this way so a command file means the
    /// same on both apps; `windowsKey` is what is sent.
    public var androidKeyCode: Int

    public init(ctrl: Bool = false, alt: Bool = false, shift: Bool = false, meta: Bool = false, androidKeyCode: Int) {
        self.ctrl = ctrl
        self.alt = alt
        self.shift = shift
        self.meta = meta
        self.androidKeyCode = androidKeyCode
    }

    /// The Windows virtual-key code for the key, or nil if Android's table has none for it.
    public var windowsKey: Int? { AndroidKeyCode.windowsKey(forAndroid: androidKeyCode) }

    /// "Ctrl+Shift+S", "Win/Cmd+X", "F11": the name shown when a command has none.
    public var displayString: String {
        var text = ""
        if ctrl { text += "Ctrl+" }
        if alt { text += "Alt+" }
        if shift { text += "Shift+" }
        if meta { text += "Win/Cmd+" }
        return text + (AndroidKeyCode.name(forAndroid: androidKeyCode) ?? "Key \(androidKeyCode)")
    }
}

/// A key combination on the stream menu's main page, with the action to take after it.
public struct CustomCommand: Equatable, Sendable, Identifiable {
    /// How long Android waits after the last modifier is released before the "Then" action.
    public static let afterDelayMilliseconds = 200
    /// Android waits this long between the modifiers going down, the key down, the key up and
    /// the modifiers going up.
    public static let stepMilliseconds = 50

    public var id: String
    /// Empty means "show the key combination".
    public var name: String
    /// The icon's name in the app's icon list. The app picks the picture; an unknown name gets
    /// the default one.
    public var iconName: String
    public var keys: KeyCombination
    public var after: CommandAfterAction

    public init(id: String, name: String, iconName: String, keys: KeyCombination, after: CommandAfterAction = .none) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.keys = keys
        self.after = after
    }

    /// The name on the tile: the command's own name, or its keys if it has none.
    public var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? keys.displayString : name
    }

    /// What to do when the command is tapped.
    public func run() -> CustomCommandRun {
        // For a key it can't translate Android sends nothing and takes no "Then" action, except
        // that Close Menu has already closed the menu by then
        guard let key = keys.windowsKey else {
            return after == .closeMenu
                ? CustomCommandRun(steps: [], after: .closeMenu, afterTiming: .beforeKeys)
                : CustomCommandRun(steps: [], after: .none, afterTiming: .none)
        }

        var flags = 0
        var held: [Int] = []
        if keys.ctrl { flags |= KeyModifier.ctrl; held.append(0x11) }
        if keys.alt { flags |= KeyModifier.alt; held.append(0x12) }
        if keys.shift { flags |= KeyModifier.shift; held.append(0x10) }
        if keys.meta { flags |= KeyModifier.meta; held.append(0x5B) }

        // The modifiers go down without flags, the key carries all of them, then the modifiers
        // come up in reverse order
        let steps = [
            ShortcutStep(events: held.map { .key(code: $0, down: true, modifiers: 0) }),
            ShortcutStep(pauseBeforeMilliseconds: Self.stepMilliseconds,
                         events: [.key(code: key, down: true, modifiers: flags)]),
            ShortcutStep(pauseBeforeMilliseconds: Self.stepMilliseconds,
                         events: [.key(code: key, down: false, modifiers: flags)]),
            ShortcutStep(pauseBeforeMilliseconds: Self.stepMilliseconds,
                         events: held.reversed().map { .key(code: $0, down: false, modifiers: 0) }),
        ]

        switch after {
        case .none:
            return CustomCommandRun(steps: steps, after: .none, afterTiming: .none)
        case .closeMenu:
            // Android closes the menu first and then sends the keys
            return CustomCommandRun(steps: steps, after: .closeMenu, afterTiming: .beforeKeys)
        case .disconnect, .quit, .sleep:
            return CustomCommandRun(steps: steps, after: after,
                                    afterTiming: .afterKeys(delayMilliseconds: Self.afterDelayMilliseconds))
        }
    }
}

/// When a command's "Then" action happens.
public enum CommandAfterTiming: Equatable, Sendable {
    /// There is none.
    case none
    /// Before any key is sent (Close Menu).
    case beforeKeys
    /// This long after the last key event.
    case afterKeys(delayMilliseconds: Int)
}

/// What a tapped command asks the app to do: send the steps, and take the action.
public struct CustomCommandRun: Equatable, Sendable {
    public var steps: [ShortcutStep]
    public var after: CommandAfterAction
    public var afterTiming: CommandAfterTiming

    /// All the key events in order, without the pauses.
    public var events: [InputEvent] { steps.flatMap(\.events) }

    /// False when the action is one iOS can't do (Sleep). The app should say so instead of
    /// pretending.
    public var afterIsSupported: Bool { after.isSupported }
}

// MARK: - Saving and reading

/// The saved form, as Android's `overlay_custom_commands` setting has it: a JSON list of
///
///     {"id": "...", "name": "Task Manager", "iconName": "Task Manager",
///      "keyCombination": {"ctrl": true, "alt": false, "shift": true, "meta": false, "keyCode": 111},
///      "postAction": 1}
///
/// `keyCode` is an Android `KeyEvent` code and `postAction` is a `CommandAfterAction`.
/// A command needs its id, name, iconName and keyCombination with all five fields; one that is
/// missing any is refused, and Android then drops the whole list, so this does too. A missing
/// postAction means none, and one this version doesn't know is none.
public enum CustomCommandsFormat {
    public static let storageKey = "overlay_custom_commands"

    public static func encode(_ commands: [CustomCommand]) -> String {
        ShortcutJSONValue.array(commands.map(json)).serialized()
    }

    /// Reads a saved list, or returns nil if it isn't one.
    public static func decode(_ text: String) -> [CustomCommand]? {
        guard case .array(let items)? = ShortcutJSONValue.parse(text) else { return nil }
        var commands: [CustomCommand] = []
        for item in items {
            guard let command = command(from: item) else { return nil }
            commands.append(command)
        }
        return commands
    }

    static func json(_ command: CustomCommand) -> ShortcutJSONValue {
        .object([
            (key: "id", value: .string(command.id)),
            (key: "name", value: .string(command.name)),
            (key: "iconName", value: .string(command.iconName)),
            (key: "keyCombination", value: .object([
                (key: "ctrl", value: .bool(command.keys.ctrl)),
                (key: "alt", value: .bool(command.keys.alt)),
                (key: "shift", value: .bool(command.keys.shift)),
                (key: "meta", value: .bool(command.keys.meta)),
                (key: "keyCode", value: .int(command.keys.androidKeyCode)),
            ])),
            (key: "postAction", value: .int(command.after.rawValue)),
        ])
    }

    static func command(from item: ShortcutJSONValue) -> CustomCommand? {
        guard case .object = item,
              let id = text(item["id"]), let name = text(item["name"]), let iconName = text(item["iconName"]),
              let combination = item["keyCombination"], case .object = combination,
              let ctrl = flag(combination["ctrl"]), let alt = flag(combination["alt"]),
              let shift = flag(combination["shift"]), let meta = flag(combination["meta"]),
              let keyCode = number(combination["keyCode"]) else {
            return nil
        }
        var after = CommandAfterAction.none
        if let raw = number(item["postAction"]), let known = CommandAfterAction(rawValue: raw) {
            after = known
        }
        return CustomCommand(id: id, name: name, iconName: iconName,
                             keys: KeyCombination(ctrl: ctrl, alt: alt, shift: shift, meta: meta, androidKeyCode: keyCode),
                             after: after)
    }

    // The readers take what Android's getString, getBoolean and getInt take
    private static func text(_ value: ShortcutJSONValue?) -> String? {
        switch value {
        case .string(let text)?: return text
        case .int(let number)?: return String(number)
        case .double(let number)?: return String(number)
        case .bool(let flag)?: return flag ? "true" : "false"
        default: return nil
        }
    }

    private static func flag(_ value: ShortcutJSONValue?) -> Bool? {
        switch value {
        case .bool(let flag)?: return flag
        case .string(let text)?:
            switch text.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        default: return nil
        }
    }

    private static func number(_ value: ShortcutJSONValue?) -> Int? {
        switch value {
        case .int(let number)?: return number
        case .double(let number)?: return abs(number) < 1_000_000_000 ? Int(number) : nil
        case .string(let text)?: return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
}

/// The custom commands, kept as Android's manager keeps them: a list in the settings storage
/// under `overlay_custom_commands`, saved after every change. A saved list that doesn't read
/// shows as empty, and stays saved until the next change replaces it.
public final class CustomCommandsStore {
    private let storage: SettingsStorage
    public private(set) var commands: [CustomCommand] = []

    public init(storage: SettingsStorage) {
        self.storage = storage
        reload()
    }

    /// Reads the saved list again, after a change made somewhere else.
    public func reload() {
        commands = []
        if let text = storage.object(forKey: CustomCommandsFormat.storageKey) as? String, !text.isEmpty {
            commands = CustomCommandsFormat.decode(text) ?? []
        }
    }

    public func command(withID id: String) -> CustomCommand? {
        commands.first { $0.id == id }
    }

    public func add(_ command: CustomCommand) {
        commands.append(command)
        save()
    }

    /// Replaces the command with this id. Does nothing if there is none.
    public func update(id: String, with command: CustomCommand) {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[index] = command
        save()
    }

    public func remove(id: String) {
        commands.removeAll { $0.id == id }
        save()
    }

    /// Moves a command to a new place in the list. Does nothing for a place outside the list.
    public func move(from: Int, to: Int) {
        guard commands.indices.contains(from), commands.indices.contains(to) else { return }
        commands.insert(commands.remove(at: from), at: to)
        save()
    }

    public func removeAll() {
        commands = []
        save()
    }

    private func save() {
        storage.set(CustomCommandsFormat.encode(commands), forKey: CustomCommandsFormat.storageKey)
    }
}

// MARK: - Keys

/// Android's `KeyEvent` key codes, and the Windows virtual-key codes Android sends for them.
public enum AndroidKeyCode {
    /// A key the editor's key list offers.
    public struct Option: Equatable, Sendable {
        public let androidKeyCode: Int
        public let name: String
    }

    /// The editor's key list, in Android's order: letters, digits, F1 to F12, then the named keys.
    public static let pickableKeys: [Option] = {
        var keys: [Option] = []
        for (offset, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            keys.append(Option(androidKeyCode: 29 + offset, name: String(letter)))
        }
        for digit in 0...9 {
            keys.append(Option(androidKeyCode: 7 + digit, name: String(digit)))
        }
        for number in 1...12 {
            keys.append(Option(androidKeyCode: 130 + number, name: "F\(number)"))
        }
        let named: [(Int, String)] = [
            (117, "Win/Cmd"), (62, "Space"), (66, "Enter"), (61, "Tab"), (111, "Escape"), (67, "Backspace"),
            (112, "Delete"), (21, "Left"), (22, "Right"), (19, "Up"), (20, "Down"), (124, "Insert"),
            (122, "Home"), (123, "End"), (92, "Page Up"), (93, "Page Down"), (120, "Print Screen"),
            (121, "Pause/Break"),
        ]
        for (code, name) in named {
            keys.append(Option(androidKeyCode: code, name: name))
        }
        return keys
    }()

    /// The name of a key in the list, or nil for any other.
    public static func name(forAndroid code: Int) -> String? {
        pickableKeys.first { $0.androidKeyCode == code }?.name
    }

    /// Android's KeyboardTranslator, without its F13 to F24 (they have no `KeyEvent` code on the
    /// versions Starwire supports), PRINT and SCREENSHOT. Print Screen is 0x2C, the Windows
    /// code; Android sends 0x9A for it, which is Java's own constant and not a Windows key.
    public static func windowsKey(forAndroid code: Int) -> Int? {
        switch code {
        case 7...16: return 0x30 + (code - 7)
        case 29...54: return 0x41 + (code - 29)
        case 144...153: return 0x60 + (code - 144)
        case 131...142: return 0x70 + (code - 131)
        default: return singleKeys[code]
        }
    }

    private static let singleKeys: [Int: Int] = [
        57: 0xA4,   // ALT_LEFT
        58: 0xA5,   // ALT_RIGHT
        73: 0xDC,   // BACKSLASH
        115: 0x14,  // CAPS_LOCK
        28: 0x0C,   // CLEAR
        55: 0xBC,   // COMMA
        113: 0xA2,  // CTRL_LEFT
        114: 0xA3,  // CTRL_RIGHT
        67: 0x08,   // DEL (Backspace)
        66: 0x0D,   // ENTER
        81: 0xBB,   // PLUS
        70: 0xBB,   // EQUALS
        111: 0x1B,  // ESCAPE
        112: 0x2E,  // FORWARD_DEL (Delete)
        124: 0x2D,  // INSERT
        71: 0xDB,   // LEFT_BRACKET
        117: 0x5B,  // META_LEFT
        118: 0x5C,  // META_RIGHT
        82: 0x5D,   // MENU
        69: 0xBD,   // MINUS
        123: 0x23,  // MOVE_END
        122: 0x24,  // MOVE_HOME
        143: 0x90,  // NUM_LOCK
        93: 0x22,   // PAGE_DOWN
        92: 0x21,   // PAGE_UP
        56: 0xBE,   // PERIOD
        72: 0xDD,   // RIGHT_BRACKET
        116: 0x91,  // SCROLL_LOCK
        74: 0xBA,   // SEMICOLON
        59: 0xA0,   // SHIFT_LEFT
        60: 0xA1,   // SHIFT_RIGHT
        76: 0xBF,   // SLASH
        62: 0x20,   // SPACE
        120: 0x2C,  // SYSRQ (Print Screen)
        61: 0x09,   // TAB
        21: 0x25,   // DPAD_LEFT
        22: 0x27,   // DPAD_RIGHT
        19: 0x26,   // DPAD_UP
        20: 0x28,   // DPAD_DOWN
        68: 0xC0,   // GRAVE
        75: 0xDE,   // APOSTROPHE
        121: 0x13,  // BREAK (Pause)
        154: 0x6F,  // NUMPAD_DIVIDE
        155: 0x6A,  // NUMPAD_MULTIPLY
        156: 0x6D,  // NUMPAD_SUBTRACT
        157: 0x6B,  // NUMPAD_ADD
        158: 0x6E,  // NUMPAD_DOT
    ]
}
