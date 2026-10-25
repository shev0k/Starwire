import XCTest
@testable import StarwireKit

final class StreamShortcutsTests: XCTestCase {
    private let all = KeyModifier.ctrl | KeyModifier.alt | KeyModifier.shift

    func testCtrlAltShiftWithALetter() {
        XCTAssertEqual(StreamShortcuts.shortcut(hidUsage: 0x10, modifiers: all), .menu)
        XCTAssertEqual(StreamShortcuts.shortcut(hidUsage: 0x16, modifiers: all), .stats)
        XCTAssertEqual(StreamShortcuts.shortcut(hidUsage: 0x07, modifiers: all), .disconnect)
    }

    func testAnythingElseGoesToThePC() {
        XCTAssertNil(StreamShortcuts.shortcut(hidUsage: 0x10, modifiers: KeyModifier.ctrl | KeyModifier.alt))
        XCTAssertNil(StreamShortcuts.shortcut(hidUsage: 0x10, modifiers: all | KeyModifier.meta))
        XCTAssertNil(StreamShortcuts.shortcut(hidUsage: 0x04, modifiers: all), "Ctrl+Alt+Shift+A is the PC's")
    }

    func testTitles() {
        XCTAssertEqual(StreamShortcuts.title(.menu), "Ctrl+Alt+Shift+M")
    }
}
