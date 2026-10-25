import XCTest
@testable import StarwireKit

// Tests for the keyboard input in StarwireKit/Input/Keyboard. Time is passed in; nothing here
// reads a clock.

private func down(_ code: Int, _ modifiers: Int = 0) -> InputEvent {
    .key(code: code, down: true, modifiers: modifiers)
}

private func up(_ code: Int, _ modifiers: Int = 0) -> InputEvent {
    .key(code: code, down: false, modifiers: modifiers)
}

final class InputKeyboardLayoutTests: XCTestCase {
    private let layout = FullKeyboardLayout.android

    func testEveryRowHasAndroidsKeyCount() {
        XCTAssertEqual(layout.rows.map(\.count), [15, 14, 14, 13, 13, 11])
    }

    /// Android's layout holds 80 keys, one of them Hide. The task brief said 82; the two extra
    /// are a second Alt and Ctrl that Android's file has commented out.
    func testTheKeyboardHasEightyKeysAndSeventyNineSendOne() {
        XCTAssertEqual(layout.keys.count, 80)
        XCTAssertEqual(layout.sendingKeys.count, 79)
        XCTAssertEqual(layout.keys.filter { $0.kind == .hide }.map(\.id), ["hide"])
    }

    func testKeysAreInAndroidsOrder() {
        let ids = layout.rows.map { $0.map(\.id) }
        XCTAssertEqual(ids[0], ["esc", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "ins", "del"])
        XCTAssertEqual(ids[1], ["grave", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "minus", "equals", "backspace"])
        XCTAssertEqual(ids[2], ["tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "lbracket", "rbracket", "backslash"])
        XCTAssertEqual(ids[3], ["caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", "semicolon", "quote", "enter"])
        XCTAssertEqual(ids[4], ["shift", "z", "x", "c", "v", "b", "n", "m", "comma", "period", "slash", "up", "hide"])
        XCTAssertEqual(ids[5], ["ctrl", "win", "alt", "space", "home", "end", "pgup", "pgdn", "left", "down", "right"])
    }

    func testIdsAndCodesAreUnique() {
        let keys = layout.keys
        XCTAssertEqual(Set(keys.map(\.id)).count, keys.count)
        XCTAssertEqual(Set(layout.sendingKeys.map(\.virtualKey)).count, 79)
        XCTAssertEqual(Set(layout.sendingKeys.map(\.androidKeyCode)).count, 79)
    }

    func testRowNumbersMatchTheRows() {
        for (index, row) in layout.rows.enumerated() {
            XCTAssertTrue(row.allSatisfy { $0.row == index }, "row \(index)")
        }
    }

    func testModifiersAndToggle() {
        let modifiers = layout.keys.filter { $0.kind == .modifier }
        XCTAssertEqual(modifiers.map(\.id), ["shift", "ctrl", "win", "alt"])
        XCTAssertEqual(modifiers.map(\.modifierMask),
                       [KeyModifier.shift, KeyModifier.ctrl, KeyModifier.meta, KeyModifier.alt])
        XCTAssertEqual(modifiers.map(\.virtualKey), [0xA0, 0xA2, 0x5B, 0xA4])
        XCTAssertEqual(layout.keys.filter { $0.kind == .toggle }.map(\.id), ["caps"])
        XCTAssertEqual(layout.key(id: "caps")?.virtualKey, 0x14)
        XCTAssertEqual(layout.keys.filter { $0.modifierMask != 0 }.count, 4)
    }

    func testLabelsWidthsAndMargins() {
        XCTAssertEqual(layout.key(id: "grave")?.label, "`")
        XCTAssertEqual(layout.key(id: "grave")?.shiftedLabel, "~")
        XCTAssertEqual(layout.key(id: "quote")?.shiftedLabel, "\"")
        XCTAssertNil(layout.key(id: "a")?.shiftedLabel)
        XCTAssertEqual(layout.key(id: "space")?.weight, 310)
        XCTAssertEqual(layout.key(id: "space")?.marginBefore, 5)
        XCTAssertEqual(layout.key(id: "space")?.marginAfter, 5)
        XCTAssertEqual(layout.key(id: "esc")?.marginAfter, 5)
        XCTAssertEqual(layout.key(id: "ins")?.marginBefore, 5)
        XCTAssertEqual(layout.key(id: "backspace")?.relativeWidth, 1.5)
        XCTAssertEqual(layout.key(id: "up")?.label, "\u{2191}")
    }

    func testWindowsKeyCodesOfASample() {
        let expected: [String: Int] = [
            "esc": 0x1B, "f1": 0x70, "f12": 0x7B, "a": 0x41, "z": 0x5A, "0": 0x30, "1": 0x31,
            "enter": 0x0D, "backspace": 0x08, "del": 0x2E, "space": 0x20, "up": 0x26, "left": 0x25,
            "home": 0x24, "pgdn": 0x22, "semicolon": 0xBA, "quote": 0xDE, "slash": 0xBF,
        ]
        for (id, code) in expected {
            XCTAssertEqual(layout.key(id: id)?.virtualKey, code, id)
        }
    }

    func testSpecialKeysGetNoPopup() {
        for id in ["tab", "enter", "space", "backspace", "del", "esc", "caps", "ins", "up", "down", "left", "right",
                   "pgup", "pgdn", "home", "end", "shift", "ctrl", "alt", "win"] {
            XCTAssertEqual(layout.key(id: id)?.isSpecial, true, id)
        }
        for id in ["a", "1", "f1", "grave", "slash"] {
            XCTAssertEqual(layout.key(id: id)?.isSpecial, false, id)
        }
    }

    func testEveryKeyHasAHardwareKeyThatMapsToIt() {
        let mapped = Set((0...700).compactMap { KeyCodeMap.virtualKey(forHIDUsage: $0) })
        for key in layout.sendingKeys {
            XCTAssertTrue(mapped.contains(key.virtualKey), key.id)
        }
    }
}

final class InputKeyboardStickyTests: XCTestCase {
    func testAPlainKeyTap() {
        var keyboard = StickyModifiers()
        let pressed = keyboard.press(keyID: "a", now: 0)
        XCTAssertEqual(pressed, StickyModifiers.Output(events: [down(0x41)], shouldVibrate: true, showsPopup: true))
        let released = keyboard.release(keyID: "a", now: 0.05)
        XCTAssertEqual(released, StickyModifiers.Output(events: [up(0x41)], shouldVibrate: true, showsPopup: false))
        XCTAssertNil(keyboard.nextDeadline)
        XCTAssertEqual(keyboard.lockedModifiers, 0)
    }

    func testVibrationFollowsTheSetting() {
        var keyboard = StickyModifiers(vibrate: false)
        XCTAssertFalse(keyboard.press(keyID: "a", now: 0).shouldVibrate)
        XCTAssertFalse(keyboard.release(keyID: "a", now: 0.1).shouldVibrate)
        _ = keyboard.press(keyID: "shift", now: 1)
        XCTAssertFalse(keyboard.tick(now: 2).shouldVibrate)
        XCTAssertEqual(keyboard.lockedKeyIDs, ["shift"])
    }

    func testSpecialKeysShowNoPopup() {
        var keyboard = StickyModifiers()
        XCTAssertFalse(keyboard.press(keyID: "enter", now: 0).showsPopup)
        XCTAssertFalse(keyboard.press(keyID: "shift", now: 0).showsPopup)
    }

    func testCapsLockIsAnOrdinaryTapEvenWhenSticky() {
        var keyboard = StickyModifiers(sticky: true)
        XCTAssertEqual(keyboard.press(keyID: "caps", now: 0).events, [down(0x14)])
        XCTAssertNil(keyboard.nextDeadline)
        XCTAssertEqual(keyboard.release(keyID: "caps", now: 1).events, [up(0x14)])
        XCTAssertEqual(keyboard.lockedKeyIDs, [])
        XCTAssertEqual(keyboard.activeModifiers, 0)
    }

    func testAQuickShiftTapWithStickyOnSendsDownThenUpAndDoesNotLatch() {
        var keyboard = StickyModifiers(sticky: true)
        XCTAssertEqual(keyboard.press(keyID: "shift", now: 0).events, [down(0xA0, KeyModifier.shift)])
        XCTAssertEqual(keyboard.nextDeadline, 0.3)
        XCTAssertEqual(keyboard.release(keyID: "shift", now: 0.1).events, [up(0xA0, 0)])
        XCTAssertNil(keyboard.nextDeadline)
        // The next key carries no Shift
        XCTAssertEqual(keyboard.press(keyID: "a", now: 1).events, [down(0x41, 0)])
    }

    func testShiftLockedByALongPressThenAThenUnlocked() {
        var keyboard = StickyModifiers(sticky: true)
        XCTAssertEqual(keyboard.press(keyID: "shift", now: 10).events, [down(0xA0, KeyModifier.shift)])
        XCTAssertEqual(keyboard.nextDeadline, 10.3)

        // Not due yet
        XCTAssertEqual(keyboard.tick(now: 10.29), StickyModifiers.Output())
        XCTAssertEqual(keyboard.lockedKeyIDs, [])

        // Locked at 0.3 seconds, with a tap of feedback
        XCTAssertEqual(keyboard.tick(now: 10.3), StickyModifiers.Output(events: [], shouldVibrate: true, showsPopup: false))
        XCTAssertEqual(keyboard.lockedKeyIDs, ["shift"])
        XCTAssertEqual(keyboard.lockedModifiers, KeyModifier.shift)
        XCTAssertNil(keyboard.nextDeadline)

        // Lifting the finger sends nothing: the PC still sees Shift down
        XCTAssertEqual(keyboard.release(keyID: "shift", now: 10.6), StickyModifiers.Output())

        // Letters carry Shift
        XCTAssertEqual(keyboard.press(keyID: "a", now: 11).events, [down(0x41, KeyModifier.shift)])
        XCTAssertEqual(keyboard.release(keyID: "a", now: 11.05).events, [up(0x41, KeyModifier.shift)])
        XCTAssertEqual(keyboard.lockedKeyIDs, ["shift"], "a letter does not release the lock")

        // Touching Shift again: nothing on touch, key up on lift
        XCTAssertEqual(keyboard.press(keyID: "shift", now: 12), StickyModifiers.Output())
        XCTAssertEqual(keyboard.lockedKeyIDs, [])
        XCTAssertEqual(keyboard.release(keyID: "shift", now: 12.1),
                       StickyModifiers.Output(events: [up(0xA0, 0)], shouldVibrate: true, showsPopup: false))
        XCTAssertEqual(keyboard.activeModifiers, 0)
        XCTAssertEqual(keyboard.press(keyID: "a", now: 13).events, [down(0x41, 0)])
    }

    func testAReleaseAfterTheDeadlineLocksEvenIfNobodyCalledTick() {
        var keyboard = StickyModifiers(sticky: true)
        _ = keyboard.press(keyID: "ctrl", now: 0)
        XCTAssertEqual(keyboard.release(keyID: "ctrl", now: 0.4).events, [])
        XCTAssertEqual(keyboard.lockedModifiers, KeyModifier.ctrl)
    }

    func testAReleaseJustBeforeTheDeadlineDoesNotLock() {
        var keyboard = StickyModifiers(sticky: true)
        _ = keyboard.press(keyID: "ctrl", now: 0)
        XCTAssertEqual(keyboard.release(keyID: "ctrl", now: 0.299).events, [up(0xA2, 0)])
        XCTAssertEqual(keyboard.lockedKeyIDs, [])
        XCTAssertNil(keyboard.nextDeadline)
    }

    func testSeveralLockedModifiersCombine() {
        var keyboard = StickyModifiers(sticky: true)
        for (index, id) in ["ctrl", "alt", "win"].enumerated() {
            _ = keyboard.press(keyID: id, now: Double(index))
            _ = keyboard.release(keyID: id, now: Double(index) + 0.5)
        }
        XCTAssertEqual(keyboard.lockedKeyIDs, ["ctrl", "alt", "win"])
        XCTAssertEqual(keyboard.lockedModifiers, KeyModifier.ctrl | KeyModifier.alt | KeyModifier.meta)
        let mask = KeyModifier.ctrl | KeyModifier.alt | KeyModifier.meta
        XCTAssertEqual(keyboard.press(keyID: "del", now: 10).events, [down(0x2E, mask)])
    }

    func testStickyOffHoldingShiftWithOneFingerWhileTappingA() {
        var keyboard = StickyModifiers(sticky: false)
        XCTAssertEqual(keyboard.press(keyID: "shift", now: 0).events, [down(0xA0, KeyModifier.shift)])
        XCTAssertNil(keyboard.nextDeadline, "no timer without sticky keys")
        XCTAssertEqual(keyboard.press(keyID: "a", now: 1).events, [down(0x41, KeyModifier.shift)])
        XCTAssertEqual(keyboard.release(keyID: "a", now: 1.05).events, [up(0x41, KeyModifier.shift)])
        XCTAssertEqual(keyboard.release(keyID: "shift", now: 5).events, [up(0xA0, 0)])
        XCTAssertEqual(keyboard.lockedKeyIDs, [], "a long hold does not lock")
        XCTAssertEqual(keyboard.press(keyID: "a", now: 6).events, [down(0x41, 0)])
    }

    func testStickyOffATapOnShiftIsJustDownAndUp() {
        var keyboard = StickyModifiers(sticky: false)
        XCTAssertEqual(keyboard.press(keyID: "alt", now: 0).events, [down(0xA4, KeyModifier.alt)])
        XCTAssertEqual(keyboard.tick(now: 100), StickyModifiers.Output())
        XCTAssertEqual(keyboard.release(keyID: "alt", now: 100).events, [up(0xA4, 0)])
    }

    func testTheHideKeySendsNothing() {
        var keyboard = StickyModifiers()
        XCTAssertEqual(keyboard.press(keyID: "hide", now: 0), StickyModifiers.Output())
        XCTAssertEqual(keyboard.release(keyID: "hide", now: 0.1), StickyModifiers.Output())
        XCTAssertEqual(keyboard.press(keyID: "nonsense", now: 0), StickyModifiers.Output())
    }
}

final class InputKeyboardCodeMapTests: XCTestCase {
    func testASampleOfHIDUsagesToWindowsKeys() {
        let expected: [(usage: Int, vk: Int, name: String)] = [
            (0x04, 0x41, "A"), (0x1D, 0x5A, "Z"), (0x1E, 0x31, "1"), (0x26, 0x39, "9"), (0x27, 0x30, "0"),
            (0x45, 0x7B, "F12"), (0x3A, 0x70, "F1"), (0x68, 0x7C, "F13"), (0x73, 0x87, "F24"),
            (0x5D, 0x65, "numpad 5"), (0x62, 0x60, "numpad 0"), (0x59, 0x61, "numpad 1"),
            (0xE0, 0xA2, "left Ctrl"), (0xE4, 0xA3, "right Ctrl"), (0xE1, 0xA0, "left Shift"),
            (0xE5, 0xA1, "right Shift"), (0xE2, 0xA4, "left Alt"), (0xE6, 0xA5, "right Alt"),
            (0xE3, 0x5B, "left Windows"), (0xE7, 0x5C, "right Windows"),
            (0x50, 0x25, "left"), (0x4F, 0x27, "right"), (0x52, 0x26, "up"), (0x51, 0x28, "down"),
            (0x4C, 0x2E, "Delete"), (0x2A, 0x08, "Backspace"), (0x28, 0x0D, "Return"), (0x29, 0x1B, "Escape"),
            (0x2B, 0x09, "Tab"), (0x2C, 0x20, "Space"), (0x39, 0x14, "Caps Lock"), (0x49, 0x2D, "Insert"),
            (0x4A, 0x24, "Home"), (0x4D, 0x23, "End"), (0x4B, 0x21, "Page Up"), (0x4E, 0x22, "Page Down"),
            (0x53, 0x90, "Num Lock"), (0x47, 0x91, "Scroll Lock"), (0x48, 0x13, "Pause"), (0x65, 0x5D, "Menu"),
        ]
        for item in expected {
            XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: item.usage), item.vk, item.name)
        }
    }

    func testPunctuationMatchesAndroid() {
        let expected: [Int: Int] = [
            0x2D: 0xBD, 0x2E: 0xBB, 0x2F: 0xDB, 0x30: 0xDD, 0x31: 0xDC, 0x33: 0xBA, 0x34: 0xDE,
            0x35: 0xC0, 0x36: 0xBC, 0x37: 0xBE, 0x38: 0xBF,
            0x54: 0x6F, 0x55: 0x6A, 0x56: 0x6D, 0x57: 0x6B, 0x63: 0x6E,
        ]
        for (usage, vk) in expected {
            XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: usage), vk, String(usage, radix: 16))
        }
    }

    func testEveryRangeIsComplete() {
        for offset in 0..<26 { XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: 0x04 + offset), 0x41 + offset) }
        for offset in 0..<9 { XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: 0x1E + offset), 0x31 + offset) }
        for offset in 0..<12 { XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: 0x3A + offset), 0x70 + offset) }
        for offset in 0..<12 { XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: 0x68 + offset), 0x7C + offset) }
        for offset in 0..<9 { XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: 0x59 + offset), 0x61 + offset) }
    }

    func testNumpadEnterIsExtended() {
        XCTAssertEqual(KeyCodeMap.entry(forHIDUsage: 0x58), KeyCodeMap.Entry(0x0D, extended: true))
        XCTAssertEqual(KeyCodeMap.entry(forHIDUsage: 0x28), KeyCodeMap.Entry(0x0D, extended: false))
        XCTAssertEqual(KeyCodeMap.extendedModifier, 0x10)
    }

    func testKeysFromKeyboardSupportAreAllMapped() {
        // Every value ios/Limelight/Input/KeyboardSupport.m handles, except PrintScreen (see below)
        let usages = [0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
                      0x39, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55,
                      0x56, 0x57, 0x58, 0x63, 0x64, 0x85, 0x9B, 0x9C, 0xA3, 0xA4, 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5,
                      0xE6, 0xE7, 669]
        for usage in usages {
            XCTAssertNotNil(KeyCodeMap.virtualKey(forHIDUsage: usage), String(usage, radix: 16))
        }
        XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: 0x64), 0xE2)
        XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: 669), 0x1B)
        XCTAssertEqual(KeyCodeMap.virtualKey(forHIDUsage: 0x46), 0x2C, "Print Screen is VK_SNAPSHOT")
    }

    func testUnknownUsagesHaveNoKey() {
        XCTAssertNil(KeyCodeMap.virtualKey(forHIDUsage: 0x00))
        XCTAssertNil(KeyCodeMap.virtualKey(forHIDUsage: 0x03))
        XCTAssertNil(KeyCodeMap.virtualKey(forHIDUsage: 0xFFFF))
    }

    func testUSCharacters() {
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "a"), KeyCodeMap.KeyStroke(virtualKey: 0x41, needsShift: false))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "A"), KeyCodeMap.KeyStroke(virtualKey: 0x41, needsShift: true))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "!"), KeyCodeMap.KeyStroke(virtualKey: 0x31, needsShift: true))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "?"), KeyCodeMap.KeyStroke(virtualKey: 0xBF, needsShift: true))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "~"), KeyCodeMap.KeyStroke(virtualKey: 0xC0, needsShift: true))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "`"), KeyCodeMap.KeyStroke(virtualKey: 0xC0, needsShift: false))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "0"), KeyCodeMap.KeyStroke(virtualKey: 0x30, needsShift: false))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: ")"), KeyCodeMap.KeyStroke(virtualKey: 0x30, needsShift: true))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: " "), KeyCodeMap.KeyStroke(virtualKey: 0x20, needsShift: false))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "\""), KeyCodeMap.KeyStroke(virtualKey: 0xDE, needsShift: true))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "|"), KeyCodeMap.KeyStroke(virtualKey: 0xDC, needsShift: true))
        XCTAssertEqual(KeyCodeMap.keyStroke(for: "\t"), KeyCodeMap.KeyStroke(virtualKey: 0x09, needsShift: false))
        XCTAssertNil(KeyCodeMap.keyStroke(for: "\u{00E9}"))
        XCTAssertNil(KeyCodeMap.keyStroke(for: "\u{1F600}"))
    }

    func testEveryPrintableASCIICharacterHasAKey() {
        for value in 0x20...0x7E {
            let character = Character(Unicode.Scalar(UInt8(value)))
            XCTAssertNotNil(KeyCodeMap.keyStroke(for: character), "\(character)")
        }
    }

    func testCharactersAsKeyEvents() {
        XCTAssertEqual(KeyCodeMap.keyEvents(for: "a"), [down(0x41), up(0x41)])
        XCTAssertEqual(KeyCodeMap.keyEvents(for: "A"),
                       [down(0xA0, KeyModifier.shift), down(0x41, KeyModifier.shift), up(0x41, KeyModifier.shift), up(0xA0, 0)])
        XCTAssertNil(KeyCodeMap.keyEvents(for: "\u{00E9}"))
    }
}

final class InputKeyboardSystemTextTests: XCTestCase {
    private let backspace: [InputEvent] = [down(0x08), up(0x08)]
    private let enter: [InputEvent] = [down(0x0D), up(0x0D)]

    func testInsertedTextGoesAsOneTextPacket() {
        XCTAssertEqual(SystemKeyboardText.events(inserted: "hello world"), [.text("hello world")])
        XCTAssertEqual(SystemKeyboardText.events(inserted: "caf\u{00E9}"), [.text("caf\u{00E9}")])
    }

    func testEmojiGoesAsText() {
        XCTAssertEqual(SystemKeyboardText.events(inserted: "\u{1F44D}\u{1F3FD}"), [.text("\u{1F44D}\u{1F3FD}")])
    }

    func testThreeBackspaces() {
        XCTAssertEqual(SystemKeyboardText.events(inserted: "", deleted: 3), backspace + backspace + backspace)
    }

    func testNothingInsertedOrDeletedSendsNothing() {
        XCTAssertEqual(SystemKeyboardText.events(inserted: ""), [])
        XCTAssertEqual(SystemKeyboardText.events(inserted: "", deleted: -2), [])
        XCTAssertEqual(SystemKeyboardText.events(old: "same", new: "same"), [])
    }

    func testEnterIsAKeyTapNotText() {
        XCTAssertEqual(SystemKeyboardText.events(inserted: "\n"), enter)
        XCTAssertEqual(SystemKeyboardText.events(inserted: "\r"), enter)
        XCTAssertEqual(SystemKeyboardText.events(inserted: "\r\n"), enter)
    }

    func testTextWithANewlineInTheMiddleIsSplit() {
        XCTAssertEqual(SystemKeyboardText.events(inserted: "ab\ncd"), [.text("ab")] + enter + [.text("cd")])
        XCTAssertEqual(SystemKeyboardText.events(inserted: "ab\n"), [.text("ab")] + enter)
        XCTAssertEqual(SystemKeyboardText.events(inserted: "\n\nx"), enter + enter + [.text("x")])
    }

    func testDeletionsComeBeforeTheInsertion() {
        XCTAssertEqual(SystemKeyboardText.events(inserted: "p!", deleted: 2), backspace + backspace + [.text("p!")])
    }

    func testChangingTheTextFieldFindsTheDifference() {
        XCTAssertEqual(SystemKeyboardText.events(old: "hello", new: "help!"), backspace + backspace + [.text("p!")])
        XCTAssertEqual(SystemKeyboardText.events(old: "", new: "hi"), [.text("hi")])
        XCTAssertEqual(SystemKeyboardText.events(old: "abc", new: "ab"), backspace)
        XCTAssertEqual(SystemKeyboardText.events(old: "abc", new: ""), backspace + backspace + backspace)
        XCTAssertEqual(SystemKeyboardText.events(old: "line", new: "line\n"), enter)
    }

    func testAnEmojiWithAModifierIsOneBackspace() {
        XCTAssertEqual(SystemKeyboardText.events(old: "a\u{1F44D}\u{1F3FD}", new: "a"), backspace)
    }
}
