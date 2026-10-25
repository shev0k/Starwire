import XCTest
@testable import StarwireKit

final class KeyboardCustomizationTests: XCTestCase {
    func testFullIsAndroidsKeyboard() {
        XCTAssertEqual(KeyboardCustomization.layout(.full), FullKeyboardLayout.android)
    }

    func testEveryPresetHasUniqueKeysAndAHideKey() {
        for preset in KeyboardPreset.allCases {
            let layout = KeyboardCustomization.layout(preset)
            let ids = layout.keys.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(preset) repeats a key")
            XCTAssertNotNil(layout.key(id: "hide"), "\(preset) can't be closed")
            for (index, row) in layout.rows.enumerated() {
                XCTAssertTrue(row.allSatisfy { $0.row == index }, "\(preset) row \(index) has keys from another row")
            }
        }
    }

    func testCompactDropsTheFunctionRowButKeepsEscAndDelete() {
        let compact = KeyboardCustomization.layout(.compact)
        XCTAssertEqual(compact.rows.count, 5)
        XCTAssertNil(compact.key(id: "f1"))
        XCTAssertEqual(compact.rows[0].first?.id, "esc")
        XCTAssertEqual(compact.rows[1].last?.id, "del")
    }

    func testTheNumberPadSendsNumpadCodes() {
        let pad = KeyboardCustomization.layout(.numpad)
        XCTAssertEqual(pad.key(id: "num7")?.virtualKey, 0x67)
        XCTAssertEqual(pad.key(id: "numadd")?.virtualKey, 0x6B)
    }

    func testARemappedKeyKeepsItsPlaceAndSendsTheTarget() {
        let layout = KeyboardCustomization.layout(.full, remaps: ["caps": "esc", "hide": "a", "q": "nope"])
        let caps = layout.key(id: "caps")!
        XCTAssertEqual(caps.label, "ESC")
        XCTAssertEqual(caps.virtualKey, 0x1B)
        XCTAssertEqual(caps.kind, .normal)
        XCTAssertEqual(caps.weight, 160, "it keeps Caps Lock's width")
        XCTAssertEqual(caps.row, 3)
        XCTAssertEqual(layout.key(id: "hide")?.kind, .hide, "Hide can't be remapped")
        XCTAssertEqual(layout.key(id: "q")?.virtualKey, 0x51, "unknown targets are skipped")
    }

    func testARemappedModifierWorksAsAModifier() {
        let layout = KeyboardCustomization.layout(.gaming, remaps: ["caps": "ctrl"])
        var model = StickyModifiers(layout: layout, sticky: true, vibrate: false)
        let sink = RecordingInputSink()
        // Caps, now Ctrl, held while W is tapped
        model.press(keyID: "caps", now: 0).events.forEach(sink.send)
        model.press(keyID: "w", now: 0.1).events.forEach(sink.send)
        model.release(keyID: "w", now: 0.15).events.forEach(sink.send)
        model.release(keyID: "caps", now: 0.2).events.forEach(sink.send)
        XCTAssertEqual(sink.events.first, .key(code: 0xA2, down: true, modifiers: KeyModifier.ctrl))
        XCTAssertTrue(sink.events.contains(.key(code: 0x57, down: true, modifiers: KeyModifier.ctrl)), "\(sink.events)")
    }

    func testRemapsSaveAndLoadPerPreset() {
        let saved = KeyboardCustomization.encodeRemaps([.full: ["caps": "esc"], .gaming: [:]])
        XCTAssertEqual(saved, #"{"full":{"caps":"esc"}}"#)
        XCTAssertEqual(KeyboardCustomization.decodeRemaps(saved), [.full: ["caps": "esc"]])
        XCTAssertEqual(KeyboardCustomization.decodeRemaps("not json"), [:])
        XCTAssertEqual(KeyboardCustomization.decodeRemaps(#"{"other":{"a":"b"}}"#), [:])
        XCTAssertEqual(KeyboardCustomization.encodeRemaps([:]), "")
    }
}
