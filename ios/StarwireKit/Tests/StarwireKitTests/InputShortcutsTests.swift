import XCTest
@testable import StarwireKit

// Shortcuts, imported shortcuts, custom commands and monitor switching, against what Starwire for
// Android sends (OverlayMenuView.java, Game.java, ImportedShortcuts.java, CustomCommand.java).

// A key going down or up with the given modifier flags
private func down(_ code: Int, _ modifiers: Int = 0) -> InputEvent { .key(code: code, down: true, modifiers: modifiers) }
private func up(_ code: Int, _ modifiers: Int = 0) -> InputEvent { .key(code: code, down: false, modifiers: modifiers) }

private let shift = KeyModifier.shift
private let ctrl = KeyModifier.ctrl
private let alt = KeyModifier.alt
private let meta = KeyModifier.meta

final class InputShortcutsBuiltInTests: XCTestCase {
    // Every shortcut on Android's Shortcuts page: its name, its keys, and the exact events. Each
    // key goes down carrying the modifiers pressed before it; they come up in reverse order, each
    // carrying the modifiers still held after it is let go.
    private let expected: [(id: String, name: String, keys: [Int], events: [InputEvent])] = [
        ("esc", "Esc", [0x1B], [down(0x1B), up(0x1B)]),
        ("f11", "F11", [0x7A], [down(0x7A), up(0x7A)]),
        ("alt-f4", "Alt+F4", [0xA4, 0x73],
         [down(0xA4), down(0x73, alt), up(0x73, alt), up(0xA4)]),
        ("alt-enter", "Alt+Enter", [0xA4, 0x0D],
         [down(0xA4), down(0x0D, alt), up(0x0D, alt), up(0xA4)]),
        ("ctrl-v", "Ctrl+V", [0xA2, 0x56],
         [down(0xA2), down(0x56, ctrl), up(0x56, ctrl), up(0xA2)]),
        ("win", "Win", [0x5B], [down(0x5B), up(0x5B)]),
        ("win-d", "Win+D", [0x5B, 0x44],
         [down(0x5B), down(0x44, meta), up(0x44, meta), up(0x5B)]),
        ("win-g", "Win+G", [0x5B, 0x47],
         [down(0x5B), down(0x47, meta), up(0x47, meta), up(0x5B)]),
        ("ctrl-alt-tab", "Ctrl+Alt+Tab", [0xA2, 0xA4, 0x09],
         [down(0xA2), down(0xA4, ctrl), down(0x09, ctrl | alt),
          up(0x09, ctrl | alt), up(0xA4, ctrl), up(0xA2)]),
        ("shift-tab", "Shift+Tab", [0xA0, 0x09],
         [down(0xA0), down(0x09, shift), up(0x09, shift), up(0xA0)]),
        ("win-shift-left", "Win+Shift+Left", [0x5B, 0xA0, 0x25],
         [down(0x5B), down(0xA0, meta), down(0x25, meta | shift),
          up(0x25, meta | shift), up(0xA0, meta), up(0x5B)]),
        ("ctrl-alt-shift-f1", "Ctrl+Alt+Shift+F1", [0xA2, 0xA4, 0xA0, 0x70],
         [down(0xA2), down(0xA4, ctrl), down(0xA0, ctrl | alt), down(0x70, ctrl | alt | shift),
          up(0x70, ctrl | alt | shift), up(0xA0, ctrl | alt), up(0xA4, ctrl), up(0xA2)]),
        ("ctrl-alt-shift-f12", "Ctrl+Alt+Shift+F12", [0xA2, 0xA4, 0xA0, 0x7B],
         [down(0xA2), down(0xA4, ctrl), down(0xA0, ctrl | alt), down(0x7B, ctrl | alt | shift),
          up(0x7B, ctrl | alt | shift), up(0xA0, ctrl | alt), up(0xA4, ctrl), up(0xA2)]),
        ("win-alt-b", "Win+Alt+B", [0x5B, 0xA4, 0x42],
         [down(0x5B), down(0xA4, meta), down(0x42, meta | alt),
          up(0x42, meta | alt), up(0xA4, meta), up(0x5B)]),
    ]

    func testThereAreFourteenOnTheShortcutsPageInAndroidsOrder() {
        XCTAssertEqual(BuiltInShortcuts.all.count, 14)
        XCTAssertEqual(BuiltInShortcuts.all.map(\.name), expected.map(\.name))
        XCTAssertEqual(BuiltInShortcuts.all.map(\.id), expected.map(\.id))
        XCTAssertEqual(Set(BuiltInShortcuts.all.map(\.id)).count, 14)
    }

    func testEveryBuiltInShortcutSendsTheExactEvents() {
        for (index, row) in expected.enumerated() {
            let shortcut = BuiltInShortcuts.all[index]
            XCTAssertEqual(shortcut.keys, row.keys, row.name)
            XCTAssertEqual(shortcut.events(), row.events, row.name)
        }
    }

    func testTaskManagerIsCtrlShiftEscape() {
        let task = BuiltInShortcuts.taskManager
        XCTAssertEqual(task.name, "Task Manager")
        XCTAssertEqual(task.keys, [0xA2, 0xA0, 0x1B])
        XCTAssertEqual(task.events(), [down(0xA2), down(0xA0, ctrl), down(0x1B, ctrl | shift),
                                       up(0x1B, ctrl | shift), up(0xA0, ctrl), up(0xA2)])
        XCTAssertFalse(BuiltInShortcuts.all.contains(task), "Android has it on the main page, not the Shortcuts page")
    }

    func testTheReleasesComeTwentyFiveMillisecondsAfterThePresses() {
        let steps = BuiltInShortcuts.all[2].steps()
        XCTAssertEqual(steps, [
            ShortcutStep(pauseBeforeMilliseconds: 0, events: [down(0xA4), down(0x73, alt)]),
            ShortcutStep(pauseBeforeMilliseconds: 25, events: [up(0x73, alt), up(0xA4)]),
        ])
    }

    func testOnlyTheLeftModifiersAndTheLeftWindowsKeyAddFlags() {
        XCTAssertEqual(Shortcut.modifierFlag(forKey: 0xA0), shift)
        XCTAssertEqual(Shortcut.modifierFlag(forKey: 0xA2), ctrl)
        XCTAssertEqual(Shortcut.modifierFlag(forKey: 0xA4), alt)
        XCTAssertEqual(Shortcut.modifierFlag(forKey: 0x5B), meta)
        for general in [0x10, 0x11, 0x12, 0xA1, 0xA3, 0xA5, 0x5C, 0x41] {
            XCTAssertEqual(Shortcut.modifierFlag(forKey: general), 0, String(general, radix: 16))
        }
        // So a file that says VK_CONTROL sends no Ctrl flag, as on Android
        let general = Shortcut(id: "x", name: "x", keys: [0x11, 0x12, 0x2E])
        XCTAssertEqual(general.events(), [down(0x11), down(0x12), down(0x2E), up(0x2E), up(0x12), up(0x11)])
    }

    func testSendingStepsWaitsForTheReleasePause() {
        let sink = RecordingInputSink()
        var waits: [Int] = []
        var pending: [() -> Void] = []
        BuiltInShortcuts.all[0].steps().send(to: sink) { milliseconds, next in
            waits.append(milliseconds)
            pending.append(next)
        }
        XCTAssertEqual(sink.events, [down(0x1B)], "the presses go out at once")
        XCTAssertEqual(waits, [25])
        pending.removeFirst()()
        XCTAssertEqual(sink.events, [down(0x1B), up(0x1B)])
    }
}

final class InputShortcutsMonitorTests: XCTestCase {
    func testMonitorOneIsCtrlAltShiftF1() {
        let monitor = MonitorSwitch.shortcut(monitor: 1)
        XCTAssertEqual(monitor?.name, "Monitor 1")
        XCTAssertEqual(monitor?.events(), [down(0xA2), down(0xA4, ctrl), down(0xA0, ctrl | alt), down(0x70, ctrl | alt | shift),
                                           up(0x70, ctrl | alt | shift), up(0xA0, ctrl | alt), up(0xA4, ctrl), up(0xA2)])
    }

    func testMonitorSixIsCtrlAltShiftF6() {
        let monitor = MonitorSwitch.shortcut(monitor: 6)
        XCTAssertEqual(monitor?.name, "Monitor 6")
        XCTAssertEqual(monitor?.events(), [down(0xA2), down(0xA4, ctrl), down(0xA0, ctrl | alt), down(0x75, ctrl | alt | shift),
                                           up(0x75, ctrl | alt | shift), up(0xA0, ctrl | alt), up(0xA4, ctrl), up(0xA2)])
    }

    func testThereAreSixAndNoOthers() {
        XCTAssertEqual(MonitorSwitch.all.map(\.name), (1...6).map { "Monitor \($0)" })
        XCTAssertEqual(MonitorSwitch.all.map { $0.keys.last }, [0x70, 0x71, 0x72, 0x73, 0x74, 0x75])
        XCTAssertNil(MonitorSwitch.shortcut(monitor: 0))
        XCTAssertNil(MonitorSwitch.shortcut(monitor: 7))
    }
}

final class InputShortcutsImportTests: XCTestCase {
    // docs/shortcuts-example.json
    private let exampleFile = """
    {
      "data": [
        { "name": "Snipping tool", "keys": ["VK_LWIN", "VK_LSHIFT", "VK_S"] },
        { "name": "Ctrl+Alt+Del", "keys": ["VK_LCONTROL", "VK_LMENU", "VK_DELETE"] },
        { "name": "Steam overlay", "keys": ["VK_LSHIFT", "VK_TAB"] },
        { "name": "Game Bar record", "keys": ["VK_LWIN", "VK_LMENU", "VK_R"] },
        { "name": "Mute", "keys": ["0xAD"] }
      ]
    }
    """

    func testReadsTheExampleFile() throws {
        let shortcuts = try ShortcutImport.parse(exampleFile)
        XCTAssertEqual(shortcuts.map(\.name), ["Snipping tool", "Ctrl+Alt+Del", "Steam overlay", "Game Bar record", "Mute"])
        XCTAssertEqual(shortcuts.map(\.keys), [[0x5B, 0xA0, 0x53], [0xA2, 0xA4, 0x2E], [0xA0, 0x09], [0x5B, 0xA4, 0x52], [0xAD]])
        XCTAssertEqual(shortcuts[0].events(), [down(0x5B), down(0xA0, meta), down(0x53, meta | shift),
                                               up(0x53, meta | shift), up(0xA0, meta), up(0x5B)])
        XCTAssertEqual(shortcuts[1].events(), [down(0xA2), down(0xA4, ctrl), down(0x2E, ctrl | alt),
                                               up(0x2E, ctrl | alt), up(0xA4, ctrl), up(0xA2)])
        XCTAssertEqual(shortcuts[4].events(), [down(0xAD), up(0xAD)])
        XCTAssertEqual(Set(shortcuts.map(\.id)).count, 5)
    }

    func testTheExampleFileInDocsStaysImportable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("docs").appendingPathComponent("shortcuts-example.json")
        guard let data = try? Data(contentsOf: file) else {
            throw XCTSkip("docs/shortcuts-example.json is not next to this package")
        }
        let shortcuts = try ShortcutImport.parse(data)
        XCTAssertEqual(shortcuts.count, 5)
        XCTAssertEqual(shortcuts, try ShortcutImport.parse(exampleFile))
    }

    func testAcceptsHexInAnyCaseNumbersABareListAndShortNames() throws {
        let shortcuts = try ShortcutImport.parse(
            "[{\"name\": \" Task view \", \"keys\": [\"0x11\", \"0X12\", \"0x2e\"]},"
            + "{\"name\": \"Save\", \"keys\": [\"vk_ctrl\", \"VK_S\"]}, {\"name\": \"F13\", \"keys\": [124, \"91\"]}]")
        XCTAssertEqual(shortcuts.map(\.name), ["Task view", "Save", "F13"], "spaces around a name are dropped")
        XCTAssertEqual(shortcuts.map(\.keys), [[0x11, 0x12, 0x2E], [0x11, 0x53], [0x7C, 0x5B]])
    }

    func testKeyCodesInEveryForm() {
        XCTAssertEqual(ShortcutImport.keyCode(named: "vk_lwin"), 0x5B)
        XCTAssertEqual(ShortcutImport.keyCode(named: " VK_LWIN "), 0x5B)
        XCTAssertEqual(ShortcutImport.keyCode(named: "0x5b"), 0x5B)
        XCTAssertEqual(ShortcutImport.keyCode(named: "0X5B"), 0x5B)
        XCTAssertEqual(ShortcutImport.keyCode(named: "91"), 0x5B)
        XCTAssertEqual(ShortcutImport.keyCode(.int(91)), 0x5B)
        XCTAssertEqual(ShortcutImport.keyCode(.double(91.9)), 0x5B, "the whole part, as Android")
        XCTAssertEqual(ShortcutImport.keyCode(named: "VK_F1"), 0x70)
        XCTAssertEqual(ShortcutImport.keyCode(named: "VK_F24"), 0x87)
        XCTAssertEqual(ShortcutImport.keyCode(named: "VK_NUMPAD9"), 0x69)
        XCTAssertEqual(ShortcutImport.keyCode(named: "VK_0"), 0x30)
        XCTAssertEqual(ShortcutImport.keyCode(named: "VK_Z"), 0x5A)
        XCTAssertEqual(ShortcutImport.keyCode(named: "VK_VOLUME_MUTE"), 0xAD)
        XCTAssertEqual(ShortcutImport.keyCode(named: "VK_OEM_7"), 0xDE)
        XCTAssertEqual(ShortcutImport.keyCode(named: "VK_PRINTSCREEN"), 0x2C)
        XCTAssertNil(ShortcutImport.keyCode(named: "VK_NOPE"))
        XCTAssertNil(ShortcutImport.keyCode(named: "0xZZ"))
        XCTAssertNil(ShortcutImport.keyCode(named: ""))
        XCTAssertNil(ShortcutImport.keyCode(.bool(true)), "true is not the key number 1")
        XCTAssertNil(ShortcutImport.keyCode(.null))
        XCTAssertNil(ShortcutImport.keyCode(nil))
    }

    func testTheNameTableHasAndroidsEntries() {
        // 26 letters, 10 digits, 10 numpad digits, F1 to F24, and 71 named keys and short names
        XCTAssertEqual(ShortcutImport.vkNames.count, 26 + 10 + 10 + 24 + 71)
        for (name, code) in ShortcutImport.vkNames {
            XCTAssertTrue((0x01...0xFE).contains(code), name)
        }
    }

    // Windows virtual keys run from 0x01 to 0xFE
    func testKeyCodesOutsideTheWindowsRangeAreRefused() {
        XCTAssertEqual(ShortcutImport.keyCode(named: "0x01"), 0x01)
        XCTAssertEqual(ShortcutImport.keyCode(.int(254)), 0xFE)
        XCTAssertNil(ShortcutImport.keyCode(.int(0)))
        XCTAssertNil(ShortcutImport.keyCode(.int(0xFF)))
        XCTAssertNil(ShortcutImport.keyCode(named: "0x1FF"))
        XCTAssertNil(ShortcutImport.keyCode(.int(-5)))
        XCTAssertNil(ShortcutImport.keyCode(named: "99999999999"))
        XCTAssertNil(ShortcutImport.keyCode(.double(1e300)))
    }

    private func assertRefused(_ text: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ShortcutImport.parse(text), text, file: file, line: line) { error in
            XCTAssertEqual((error as? ShortcutImportError)?.message, message, text, file: file, line: line)
        }
    }

    func testSaysWhatIsWrongWithABadFile() {
        let cases: [(String, String)] = [
            ("hello", "not a JSON file"),
            ("not json at all", "not a JSON file"),
            ("", "not a JSON file"),
            ("42", "not a JSON file"),
            ("null", "not a JSON file"),
            ("{\"data\": [", "not a JSON file"),
            ("[] []", "not a JSON file"),
            ("{}", "no \"data\" list of shortcuts"),
            ("{\"shortcuts\": []}", "no \"data\" list of shortcuts"),
            ("{\"data\": 5}", "no \"data\" list of shortcuts"),
            ("[]", "the \"data\" list is empty"),
            ("{\"data\": []}", "the \"data\" list is empty"),
            ("[{\"keys\":[\"VK_A\"]}]", "shortcut 1 has no name"),
            ("[{\"name\":\"  \",\"keys\":[\"VK_A\"]}]", "shortcut 1 has no name"),
            ("[{\"name\":\"X\"}]", "\"X\" has no keys"),
            ("[{\"name\":\"X\",\"keys\":[]}]", "\"X\" has no keys"),
            ("[{\"name\":\"X\",\"keys\":\"VK_A\"}]", "\"X\" has no keys"),
            ("[{\"name\":\"X\",\"keys\":[\"VK_NOPE\"]}]", "\"X\" has an unknown key: VK_NOPE"),
            ("[{\"name\":\"X\",\"keys\":[\"0x1FF\"]}]", "\"X\" has an unknown key: 0x1FF"),
            ("[{\"name\":\"X\",\"keys\":[\"VK_A\", 0]}]", "\"X\" has an unknown key: 0"),
            ("[{\"name\":\"X\",\"keys\":[true]}]", "\"X\" has an unknown key: true"),
            ("[{\"name\":\"X\",\"keys\":[null]}]", "\"X\" has an unknown key: null"),
            ("[1]", "shortcut 1 is not an object"),
            ("[{\"name\":\"A\",\"keys\":[\"VK_A\"]}, \"B\"]", "shortcut 2 is not an object"),
        ]
        for (text, message) in cases {
            assertRefused(text, message)
        }
    }

    private func shortcuts(_ count: Int, keys: Int) -> String {
        let key = Array(repeating: "\"VK_A\"", count: keys).joined(separator: ",")
        return "[" + (1...count).map { "{\"name\":\"S\($0)\",\"keys\":[\(key)]}" }.joined(separator: ",") + "]"
    }

    func testLimitsOnShortcutsAndKeys() throws {
        XCTAssertEqual(ShortcutImport.maxShortcuts, 50)
        XCTAssertEqual(ShortcutImport.maxKeys, 8)
        XCTAssertEqual(try ShortcutImport.parse(shortcuts(50, keys: 1)).count, 50)
        assertRefused(shortcuts(51, keys: 1), "more than 50 shortcuts")
        XCTAssertEqual(try ShortcutImport.parse(shortcuts(1, keys: 8))[0].keys.count, 8)
        assertRefused(shortcuts(1, keys: 9), "\"S1\" has more than 8 keys")
    }

    func testDuplicateNamesAndKeysAreAllowed() throws {
        let both = try ShortcutImport.parse("[{\"name\":\"A\",\"keys\":[\"VK_A\"]},{\"name\":\"A\",\"keys\":[\"VK_A\"]}]")
        XCTAssertEqual(both.count, 2)
    }

    func testAFileOver256KiBIsTooBigAndOneAtTheLimitIsNot() throws {
        XCTAssertEqual(ShortcutImport.maxFileBytes, 262_144)
        XCTAssertThrowsError(try ShortcutImport.parse(Data(count: 262_145))) { error in
            XCTAssertEqual((error as? ShortcutImportError)?.message, "the file is too big to be a shortcuts file")
        }
        var atLimit = Data("[{\"name\":\"A\",\"keys\":[\"VK_A\"]}]".utf8)
        atLimit.append(Data(repeating: 0x20, count: 262_144 - atLimit.count))
        XCTAssertEqual(try ShortcutImport.parse(atLimit).count, 1)
    }

    func testAByteOrderMarkAndNewlinesAroundTheFileAreIgnored() throws {
        XCTAssertEqual(try ShortcutImport.parse("\u{FEFF}\n[{\"name\":\"A\",\"keys\":[\"VK_A\"]}]\n").count, 1)
    }

    func testDeeplyNestedJSONIsRefusedNotCrashed() {
        assertRefused(String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000), "not a JSON file")
    }

    func testTheSummaryNamesFourAndAnEllipsis() throws {
        let five = try ShortcutImport.parse(shortcuts(5, keys: 1))
        XCTAssertEqual(ShortcutImport.summaryNames(Array(five.prefix(2))), "S1, S2")
        XCTAssertEqual(ShortcutImport.summaryNames(Array(five.prefix(4))), "S1, S2, S3, S4")
        XCTAssertEqual(ShortcutImport.summaryNames(five), "S1, S2, S3, S4, \u{2026}")
    }

    // MARK: Saving and removing

    func testSavingReplacesTheEarlierImportAndRemovingClearsIt() throws {
        let storage = MemorySettingsStorage()
        let store = ImportedShortcutsStore(storage: storage)
        XCTAssertEqual(store.load(), [])

        XCTAssertEqual(try store.save(exampleFile), 5)
        XCTAssertEqual(storage.object(forKey: "overlay_imported_shortcuts") as? String, exampleFile)
        XCTAssertEqual(ImportedShortcutsStore(storage: storage).load().count, 5, "a new store reads what was saved")

        XCTAssertEqual(try store.save("[{\"name\":\"Only\",\"keys\":[\"VK_A\"]}]"), 1)
        XCTAssertEqual(store.load().map(\.name), ["Only"])

        store.clear()
        XCTAssertEqual(store.load(), [])
        XCTAssertNil(storage.object(forKey: "overlay_imported_shortcuts"))
    }

    func testAFileThatFailsKeepsTheEarlierImport() throws {
        let store = ImportedShortcutsStore(storage: MemorySettingsStorage())
        try store.save(exampleFile)
        XCTAssertThrowsError(try store.save("{\"data\": []}"))
        XCTAssertThrowsError(try store.save(Data(count: 300_000)))
        XCTAssertEqual(store.load().count, 5)
    }

    func testSavingBytesKeepsTheText() throws {
        let storage = MemorySettingsStorage()
        XCTAssertEqual(try ImportedShortcutsStore(storage: storage).save(Data(exampleFile.utf8)), 5)
        XCTAssertEqual(storage.object(forKey: "overlay_imported_shortcuts") as? String, exampleFile)
    }

    func testSavedTextThatNoLongerReadsLoadsAsNone() {
        let storage = MemorySettingsStorage(["overlay_imported_shortcuts": "garbage"])
        XCTAssertEqual(ImportedShortcutsStore(storage: storage).load(), [])
        storage.set("", forKey: "overlay_imported_shortcuts")
        XCTAssertEqual(ImportedShortcutsStore(storage: storage).load(), [])
    }
}

final class InputShortcutsCustomCommandTests: XCTestCase {
    // Android's KeyEvent codes
    private let keyEscape = 111
    private let keyS = 47
    private let keyF11 = 141
    private let keyTab = 61

    private func command(_ keys: KeyCombination, after: CommandAfterAction = .none) -> CustomCommand {
        CustomCommand(id: "id-1", name: "Task Manager", iconName: "Task Manager", keys: keys, after: after)
    }

    private let taskManagerKeys = KeyCombination(ctrl: true, shift: true, androidKeyCode: 111)

    private let taskManagerSteps = [
        ShortcutStep(events: [down(0x11), down(0x10)]),
        ShortcutStep(pauseBeforeMilliseconds: 50, events: [down(0x1B, ctrl | shift)]),
        ShortcutStep(pauseBeforeMilliseconds: 50, events: [up(0x1B, ctrl | shift)]),
        ShortcutStep(pauseBeforeMilliseconds: 50, events: [up(0x10), up(0x11)]),
    ]

    func testTheKeysGoOutAsAndroidSendsThem() {
        let run = command(taskManagerKeys).run()
        XCTAssertEqual(run.steps, taskManagerSteps)
        XCTAssertEqual(run.events, [down(0x11), down(0x10), down(0x1B, ctrl | shift), up(0x1B, ctrl | shift), up(0x10), up(0x11)])
    }

    func testAllFourModifiersGoDownInOrderAndUpInReverse() {
        let run = command(KeyCombination(ctrl: true, alt: true, shift: true, meta: true, androidKeyCode: keyS)).run()
        let all = ctrl | alt | shift | meta
        XCTAssertEqual(run.events, [down(0x11), down(0x12), down(0x10), down(0x5B),
                                    down(0x53, all), up(0x53, all),
                                    up(0x5B), up(0x10), up(0x12), up(0x11)])
    }

    func testAKeyWithNoModifiersKeepsTheTiming() {
        let run = command(KeyCombination(androidKeyCode: keyF11)).run()
        XCTAssertEqual(run.steps, [
            ShortcutStep(events: []),
            ShortcutStep(pauseBeforeMilliseconds: 50, events: [down(0x7A)]),
            ShortcutStep(pauseBeforeMilliseconds: 50, events: [up(0x7A)]),
            ShortcutStep(pauseBeforeMilliseconds: 50, events: []),
        ])
    }

    func testNothingAfterTheKeysByDefault() {
        let run = command(taskManagerKeys, after: .none).run()
        XCTAssertEqual(run.after, .none)
        XCTAssertEqual(run.afterTiming, .none)
        XCTAssertTrue(run.afterIsSupported)
    }

    func testCloseMenuClosesItBeforeTheKeysAreSent() {
        let run = command(taskManagerKeys, after: .closeMenu).run()
        XCTAssertEqual(run.steps, taskManagerSteps)
        XCTAssertEqual(run.after, .closeMenu)
        XCTAssertEqual(run.afterTiming, .beforeKeys)
        XCTAssertTrue(run.afterIsSupported)
    }

    func testDisconnectAndQuitComeTwoHundredMillisecondsAfterTheKeys() {
        for action in [CommandAfterAction.disconnect, .quit] {
            let run = command(taskManagerKeys, after: action).run()
            XCTAssertEqual(run.steps, taskManagerSteps)
            XCTAssertEqual(run.after, action)
            XCTAssertEqual(run.afterTiming, .afterKeys(delayMilliseconds: 200))
            XCTAssertTrue(run.afterIsSupported)
        }
    }

    func testSleepIsReadButMarkedUnsupported() {
        let run = command(taskManagerKeys, after: .sleep).run()
        XCTAssertEqual(run.steps, taskManagerSteps, "the keys still go out")
        XCTAssertEqual(run.after, .sleep)
        XCTAssertEqual(run.afterTiming, .afterKeys(delayMilliseconds: 200))
        XCTAssertFalse(run.afterIsSupported)
        XCTAssertFalse(CommandAfterAction.sleep.isSupported)
        XCTAssertEqual(CommandAfterAction.allCases.filter { !$0.isSupported }, [.sleep])
    }

    func testAKeyAndroidCantTranslateSendsNothingAndTakesNoAction() {
        let unknown = KeyCombination(ctrl: true, androidKeyCode: 9999)
        XCTAssertNil(unknown.windowsKey)
        for action in [CommandAfterAction.none, .disconnect, .quit, .sleep] {
            let run = command(unknown, after: action).run()
            XCTAssertEqual(run.steps, [])
            XCTAssertEqual(run.after, .none)
        }
        // The menu is already closed by the time Android finds out
        let close = command(unknown, after: .closeMenu).run()
        XCTAssertEqual(close.steps, [])
        XCTAssertEqual(close.after, .closeMenu)
        XCTAssertEqual(close.afterTiming, .beforeKeys)
    }

    func testTheNameIsTheKeysWhenThereIsNone() {
        XCTAssertEqual(command(taskManagerKeys).displayName, "Task Manager")
        var unnamed = command(taskManagerKeys)
        unnamed.name = "  "
        XCTAssertEqual(unnamed.displayName, "Ctrl+Shift+Escape")
        unnamed.keys = KeyCombination(ctrl: true, alt: true, shift: true, meta: true, androidKeyCode: keyF11)
        XCTAssertEqual(unnamed.displayName, "Ctrl+Alt+Shift+Win/Cmd+F11")
    }

    // MARK: Format

    private let androidSaved = "[{\"id\":\"id-1\",\"name\":\"Task Manager\",\"iconName\":\"Task Manager\","
        + "\"keyCombination\":{\"ctrl\":true,\"alt\":false,\"shift\":true,\"meta\":false,\"keyCode\":111},\"postAction\":1},"
        + "{\"id\":\"x\",\"name\":\"Old\",\"iconName\":\"Gone\","
        + "\"keyCombination\":{\"ctrl\":false,\"alt\":true,\"shift\":false,\"meta\":false,\"keyCode\":61}}]"

    func testReadsWhatAndroidSaves() throws {
        let commands = try XCTUnwrap(CustomCommandsFormat.decode(androidSaved))
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0], command(taskManagerKeys, after: .closeMenu))
        // Saved before post-actions existed, with an icon a later version removed
        XCTAssertEqual(commands[1].after, .none)
        XCTAssertEqual(commands[1].iconName, "Gone")
        XCTAssertEqual(commands[1].keys, KeyCombination(alt: true, androidKeyCode: keyTab))
    }

    func testWritingAndReadingBackKeepsEverything() throws {
        let list = [command(taskManagerKeys, after: .quit),
                    CustomCommand(id: "b", name: "Quote \" and \\ and \u{00E9}", iconName: "Close",
                                  keys: KeyCombination(meta: true, androidKeyCode: 117), after: .sleep)]
        let text = CustomCommandsFormat.encode(list)
        XCTAssertEqual(CustomCommandsFormat.decode(text), list)
        XCTAssertEqual(CustomCommandsFormat.decode(CustomCommandsFormat.encode([])), [])
    }

    func testTheSavedTextIsAndroidsFormat() {
        XCTAssertEqual(CustomCommandsFormat.encode([command(taskManagerKeys, after: .closeMenu)]),
                       "[{\"id\":\"id-1\",\"name\":\"Task Manager\",\"iconName\":\"Task Manager\","
                       + "\"keyCombination\":{\"ctrl\":true,\"alt\":false,\"shift\":true,\"meta\":false,\"keyCode\":111},"
                       + "\"postAction\":1}]")
    }

    func testAnUnknownAfterActionIsNone() throws {
        let text = androidSaved.replacingOccurrences(of: "\"postAction\":1", with: "\"postAction\":9")
        XCTAssertEqual(try XCTUnwrap(CustomCommandsFormat.decode(text))[0].after, .none)
    }

    func testACommandWithoutItsPartsRefusesTheWholeList() {
        let ok = "{\"id\":\"x\",\"name\":\"N\",\"iconName\":\"Close\","
            + "\"keyCombination\":{\"ctrl\":false,\"alt\":false,\"shift\":false,\"meta\":false,\"keyCode\":61}}"
        XCTAssertNotNil(CustomCommandsFormat.decode("[\(ok)]"))
        let broken = [
            "{\"id\":\"x\",\"name\":\"N\",\"iconName\":\"Close\"}",
            "{\"name\":\"N\",\"iconName\":\"Close\",\"keyCombination\":{\"ctrl\":false,\"alt\":false,"
                + "\"shift\":false,\"meta\":false,\"keyCode\":61}}",
            "{\"id\":\"x\",\"name\":\"N\",\"iconName\":\"Close\",\"keyCombination\":{\"keyCode\":61}}",
            "5",
        ]
        for item in broken {
            XCTAssertNil(CustomCommandsFormat.decode("[\(ok),\(item)]"), item)
        }
        XCTAssertNil(CustomCommandsFormat.decode("not json"))
        XCTAssertNil(CustomCommandsFormat.decode("{}"))
    }

    // MARK: Store

    func testTheStoreSavesAfterEveryChange() throws {
        let storage = MemorySettingsStorage()
        let store = CustomCommandsStore(storage: storage)
        XCTAssertEqual(store.commands, [])

        let a = CustomCommand(id: "a", name: "A", iconName: "Close", keys: KeyCombination(androidKeyCode: keyS))
        let b = CustomCommand(id: "b", name: "B", iconName: "Close", keys: KeyCombination(androidKeyCode: keyF11))
        let c = CustomCommand(id: "c", name: "C", iconName: "Close", keys: KeyCombination(androidKeyCode: keyTab))
        store.add(a)
        store.add(b)
        store.add(c)
        XCTAssertEqual(CustomCommandsStore(storage: storage).commands, [a, b, c])

        store.move(from: 2, to: 0)
        XCTAssertEqual(CustomCommandsStore(storage: storage).commands.map(\.id), ["c", "a", "b"])
        store.move(from: 0, to: 5)
        store.move(from: -1, to: 0)
        XCTAssertEqual(store.commands.map(\.id), ["c", "a", "b"], "places outside the list do nothing")

        var renamed = a
        renamed.name = "Renamed"
        store.update(id: "a", with: renamed)
        store.update(id: "missing", with: renamed)
        XCTAssertEqual(store.command(withID: "a")?.name, "Renamed")
        XCTAssertEqual(store.commands.count, 3)

        store.remove(id: "c")
        XCTAssertEqual(CustomCommandsStore(storage: storage).commands.map(\.id), ["a", "b"])

        store.removeAll()
        XCTAssertEqual(CustomCommandsStore(storage: storage).commands, [])
    }

    func testASavedListThatDoesNotReadShowsAsEmptyUntilTheNextChange() {
        let storage = MemorySettingsStorage(["overlay_custom_commands": "[{\"id\":1}]"])
        let store = CustomCommandsStore(storage: storage)
        XCTAssertEqual(store.commands, [])
        XCTAssertEqual(storage.object(forKey: "overlay_custom_commands") as? String, "[{\"id\":1}]")
        store.add(command(taskManagerKeys))
        XCTAssertEqual(CustomCommandsStore(storage: storage).commands.count, 1)
    }

    func testReloadSeesAChangeMadeElsewhere() {
        let storage = MemorySettingsStorage()
        let store = CustomCommandsStore(storage: storage)
        CustomCommandsStore(storage: storage).add(command(taskManagerKeys))
        XCTAssertEqual(store.commands, [])
        store.reload()
        XCTAssertEqual(store.commands.count, 1)
    }

    // MARK: Keys

    func testTheKeyListHasAndroidsSixtySixKeysAndEachHasAWindowsKey() throws {
        let keys = AndroidKeyCode.pickableKeys
        XCTAssertEqual(keys.count, 66)
        XCTAssertEqual(Set(keys.map(\.androidKeyCode)).count, 66)
        for key in keys {
            XCTAssertNotNil(AndroidKeyCode.windowsKey(forAndroid: key.androidKeyCode), key.name)
        }
        XCTAssertEqual(keys.first?.name, "A")
        XCTAssertEqual(keys.last?.name, "Pause/Break")
    }

    func testAndroidKeysBecomeWindowsKeys() {
        let table: [(Int, Int)] = [
            (29, 0x41), (54, 0x5A), (7, 0x30), (16, 0x39), (131, 0x70), (142, 0x7B), (117, 0x5B), (62, 0x20),
            (66, 0x0D), (61, 0x09), (111, 0x1B), (67, 0x08), (112, 0x2E), (21, 0x25), (22, 0x27), (19, 0x26),
            (20, 0x28), (124, 0x2D), (122, 0x24), (123, 0x23), (92, 0x21), (93, 0x22), (120, 0x2C), (121, 0x13),
            (144, 0x60), (153, 0x69), (59, 0xA0), (113, 0xA2), (57, 0xA4),
        ]
        for (android, windows) in table {
            XCTAssertEqual(AndroidKeyCode.windowsKey(forAndroid: android), windows, "Android key \(android)")
        }
        XCTAssertNil(AndroidKeyCode.windowsKey(forAndroid: 0))
        XCTAssertEqual(AndroidKeyCode.name(forAndroid: 117), "Win/Cmd")
        XCTAssertNil(AndroidKeyCode.name(forAndroid: 113))
    }
}
