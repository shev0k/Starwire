import Foundation

// The on-screen full keyboard's choices beyond Android's: smaller layouts built from Android's
// keys, keys that send something else, a size, and docked or floating. Android has one layout
// (FullKeyboardLayout.android); the presets below take its keys and rows, so they look and behave
// the same. Saved in the settings store: the preset, size and placement as settings, the
// remapped keys as JSON in `keyboard_remapped_keys`.

/// The keyboards to choose from.
public enum KeyboardPreset: String, CaseIterable, Sendable {
    /// Android's 6 rows
    case full
    /// Without the function key row
    case compact
    /// The left hand's keys for games, with the arrows
    case gaming
    /// A number pad with the arrows and editing keys
    case numpad

    public var title: String {
        switch self {
        case .full: return "Full"
        case .compact: return "Compact"
        case .gaming: return "Gaming"
        case .numpad: return "Number pad"
        }
    }
}

/// Docked along the bottom of the screen, or floating where it was dragged.
public enum KeyboardPlacement: String, CaseIterable, Sendable {
    case docked, floating
}

/// Keys a key can be remapped to that Android's keyboard doesn't have.
public enum ExtraKeys {
    public static let all: [FullKeyboardKey] = [
        extra("num0", "0", vk: 0x60), extra("num1", "1", vk: 0x61), extra("num2", "2", vk: 0x62),
        extra("num3", "3", vk: 0x63), extra("num4", "4", vk: 0x64), extra("num5", "5", vk: 0x65),
        extra("num6", "6", vk: 0x66), extra("num7", "7", vk: 0x67), extra("num8", "8", vk: 0x68),
        extra("num9", "9", vk: 0x69), extra("numdiv", "/", vk: 0x6F), extra("nummul", "*", vk: 0x6A),
        extra("numsub", "-", vk: 0x6D), extra("numadd", "+", vk: 0x6B), extra("numdot", ".", vk: 0x6E),
        extra("numlock", "Num", vk: 0x90, special: true),
        extra("prtsc", "PrtSc", vk: 0x2C, special: true), extra("pause", "Pause", vk: 0x13, special: true),
        extra("rshift", "Shift", vk: 0xA1, special: true, kind: .modifier, mask: KeyModifier.shift),
        extra("rctrl", "Ctrl", vk: 0xA3, special: true, kind: .modifier, mask: KeyModifier.ctrl),
        extra("ralt", "Alt", vk: 0xA5, special: true, kind: .modifier, mask: KeyModifier.alt),
        extra("menu", "Menu", vk: 0x5D, special: true),
        extra("mute", "Mute", vk: 0xAD, special: true), extra("voldown", "Vol-", vk: 0xAE, special: true),
        extra("volup", "Vol+", vk: 0xAF, special: true), extra("playpause", "Play", vk: 0xB3, special: true),
    ]

    private static func extra(_ id: String, _ label: String, vk: Int, special: Bool = false,
                              kind: FullKeyboardKeyKind = .normal, mask: Int = 0) -> FullKeyboardKey {
        FullKeyboardKey(id: id, label: label, shiftedLabel: nil, virtualKey: vk, androidKeyCode: 0, weight: 100, kind: kind,
                        row: 0, marginBefore: 0, marginAfter: 0, modifierMask: mask, isSpecial: special || kind == .modifier)
    }
}

public enum KeyboardCustomization {
    public static let presetKey = "list_keyboard_preset"
    public static let sizeKey = "seekbar_keyboard_size"
    public static let placementKey = "list_keyboard_placement"
    public static let remapKey = "keyboard_remapped_keys"
    /// Where a floating keyboard sits, as fractions of the room it can move in (not settings)
    public static let floatingXKey = "keyboard_floating_x"
    public static let floatingYKey = "keyboard_floating_y"
    public static let sizeRange = 60...140

    /// Every key a key can send: Android's and the extras, by id.
    public static let targets: [FullKeyboardKey] = FullKeyboardLayout.android.keys + ExtraKeys.all

    public static func target(id: String) -> FullKeyboardKey? {
        targets.first { $0.id == id }
    }

    /// The preset's keys, before any remapping.
    public static func layout(_ preset: KeyboardPreset) -> FullKeyboardLayout {
        let android = FullKeyboardLayout.android
        func keys(_ ids: [String]) -> [FullKeyboardKey] {
            ids.compactMap { android.key(id: $0) ?? target(id: $0) }
        }
        let rows: [[FullKeyboardKey]]
        switch preset {
        case .full:
            return android
        case .compact:
            var rest = Array(android.rows.dropFirst())
            // Esc and Del lose their row: Esc starts the number row, Del ends the Tab row
            rest[0] = keys(["esc"]) + rest[0]
            rest[1] = rest[1] + keys(["del"])
            rows = rest
        case .gaming:
            rows = [
                keys(["esc", "1", "2", "3", "4", "5", "6"]),
                keys(["tab", "q", "w", "e", "r", "t", "y"]),
                keys(["caps", "a", "s", "d", "f", "g", "h"]),
                keys(["shift", "z", "x", "c", "v", "b", "up", "hide"]),
                keys(["ctrl", "alt", "space", "left", "down", "right"]),
            ]
        case .numpad:
            rows = [
                keys(["esc", "numlock", "numdiv", "nummul", "numsub", "backspace"]),
                keys(["num7", "num8", "num9", "numadd", "home", "pgup"]),
                keys(["num4", "num5", "num6", "tab", "end", "pgdn"]),
                keys(["num1", "num2", "num3", "enter", "up", "hide"]),
                keys(["num0", "numdot", "del", "left", "down", "right"]),
            ]
        }
        return FullKeyboardLayout(rows: rows.enumerated().map { index, row in
            row.map { $0.with(row: index, marginBefore: 0, marginAfter: 0) }
        })
    }

    /// The preset with its remapped keys: each remapped key keeps its place, id and width and
    /// takes the target's label and code. Unknown ids are skipped; Hide can't be remapped, so the
    /// keyboard can always be closed.
    public static func layout(_ preset: KeyboardPreset, remaps: [String: String]) -> FullKeyboardLayout {
        let base = layout(preset)
        return FullKeyboardLayout(rows: base.rows.map { row in
            row.map { key in
                guard key.kind != .hide, let targetID = remaps[key.id], let target = target(id: targetID),
                      target.kind != .hide else { return key }
                return FullKeyboardKey(id: key.id, label: target.label, shiftedLabel: target.shiftedLabel,
                                       virtualKey: target.virtualKey, androidKeyCode: target.androidKeyCode,
                                       weight: key.weight, kind: target.kind, row: key.row, marginBefore: key.marginBefore,
                                       marginAfter: key.marginAfter, modifierMask: target.modifierMask,
                                       isSpecial: target.isSpecial)
            }
        })
    }

    // MARK: Saved remaps

    /// Remaps per preset, as saved: `{"full":{"caps":"esc"}}`.
    public static func decodeRemaps(_ json: String) -> [KeyboardPreset: [String: String]] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return [:] }
        var result: [KeyboardPreset: [String: String]] = [:]
        for (name, map) in object {
            if let preset = KeyboardPreset(rawValue: name), !map.isEmpty {
                result[preset] = map
            }
        }
        return result
    }

    public static func encodeRemaps(_ remaps: [KeyboardPreset: [String: String]]) -> String {
        let object = Dictionary(uniqueKeysWithValues: remaps.filter { !$0.value.isEmpty }.map { ($0.key.rawValue, $0.value) })
        guard !object.isEmpty, let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// The keyboard to show, from the saved settings.
    public static func layout(from store: SettingsStore) -> FullKeyboardLayout {
        var preset = KeyboardPreset.full
        if case .string(let name)? = store.value(presetKey), let saved = KeyboardPreset(rawValue: name) {
            preset = saved
        }
        var remaps: [String: String] = [:]
        if case .string(let json)? = store.value(remapKey) {
            remaps = decodeRemaps(json)[preset] ?? [:]
        }
        return layout(preset, remaps: remaps)
    }
}

extension FullKeyboardKey {
    func with(row: Int, marginBefore: Int, marginAfter: Int) -> FullKeyboardKey {
        FullKeyboardKey(id: id, label: label, shiftedLabel: shiftedLabel, virtualKey: virtualKey, androidKeyCode: androidKeyCode,
                        weight: weight, kind: kind, row: row, marginBefore: marginBefore, marginAfter: marginAfter,
                        modifierMask: modifierMask, isSpecial: isSpecial)
    }
}
