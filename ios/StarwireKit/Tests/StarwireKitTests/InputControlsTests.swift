import XCTest
@testable import StarwireKit

// Tests for the on-screen controller: Starwire for Android's VirtualController* classes, ported.
// The expected numbers are worked out from Android's code for a 1920 x 1080 screen, where one
// cell of its 128 x 72 grid is exactly 15 pixels and the controls on the right are not displaced.

private let screen = OnScreenSize(width: 1920, height: 1080)

private func point(_ x: Double, _ y: Double) -> OnScreenPoint {
    OnScreenPoint(x: x, y: y)
}

private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> OnScreenRect {
    OnScreenRect(x: x, y: y, width: width, height: height)
}

private func assertRect(_ actual: OnScreenRect?, _ expected: OnScreenRect, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let actual else { return XCTFail("no rectangle", file: file, line: line) }
    XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_001, "x \(message)", file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: 0.000_001, "y \(message)", file: file, line: line)
    XCTAssertEqual(actual.width, expected.width, accuracy: 0.000_001, "width \(message)", file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, accuracy: 0.000_001, "height \(message)", file: file, line: line)
}

private func state(buttons: Int = 0, leftTrigger: Int = 0, rightTrigger: Int = 0, leftX: Int = 0, leftY: Int = 0,
                   rightX: Int = 0, rightY: Int = 0) -> InputEvent {
    .controller(ControllerState(number: 0, activeMask: 1, buttons: buttons, leftTrigger: leftTrigger,
                                rightTrigger: rightTrigger, leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY))
}

private func makeOptions(_ configure: (inout OnScreenOptions) -> Void = { _ in }) -> OnScreenOptions {
    var options = OnScreenOptions()
    options.enabled = true
    configure(&options)
    return options
}

final class InputControlsLayoutTests: XCTestCase {
    func testTheDefaultLayoutHasAndroidsElementsInAndroidsOrder() {
        let layout = OnScreenLayout(options: makeOptions(), screen: screen)
        XCTAssertEqual(layout.elements.map(\.id), [.dpad, .a, .b, .x, .y, .leftTrigger, .rightTrigger, .leftBumper,
                                                   .rightBumper, .leftStick, .rightStick, .back, .start, .guide])
        XCTAssertEqual(layout.frames.count, 14)
        XCTAssertEqual(OnScreenElementID.a.rawValue, 6, "Android's EID_A")
        XCTAssertEqual(OnScreenElementID.guide.rawValue, 16, "Android's EID_GDB")
    }

    func testTheDefaultPositionsAreAndroids() {
        let layout = OnScreenLayout(options: makeOptions(), screen: screen)
        assertRect(layout.rect(of: .dpad, in: screen), rect(60, 615, 450, 450))
        assertRect(layout.rect(of: .a, in: screen), rect(1590, 315, 150, 150))
        assertRect(layout.rect(of: .b, in: screen), rect(1740, 165, 150, 150))
        assertRect(layout.rect(of: .x, in: screen), rect(1440, 165, 150, 150))
        assertRect(layout.rect(of: .y, in: screen), rect(1590, 15, 150, 150))
        assertRect(layout.rect(of: .leftTrigger, in: screen), rect(15, 465, 180, 135))
        assertRect(layout.rect(of: .rightTrigger, in: screen), rect(1725, 465, 180, 135))
        assertRect(layout.rect(of: .leftBumper, in: screen), rect(360, 465, 180, 135))
        assertRect(layout.rect(of: .rightBumper, in: screen), rect(1380, 465, 180, 135))
        assertRect(layout.rect(of: .leftStick, in: screen), rect(90, 60, 390, 390))
        assertRect(layout.rect(of: .rightStick, in: screen), rect(1470, 630, 390, 390))
        assertRect(layout.rect(of: .back, in: screen), rect(510, 960, 180, 105))
        assertRect(layout.rect(of: .start, in: screen), rect(1245, 960, 180, 105))
        assertRect(layout.rect(of: .guide, in: screen), rect(735, 960, 180, 105))
    }

    func testAWiderScreenPushesTheRightControlsOverAndANarrowerOneBack() {
        // 2400 wide at 1080 high is 480 wider than 16:9; 1440 is 480 narrower
        let wide = OnScreenSize(width: 2400, height: 1080)
        let wideLayout = OnScreenLayout(options: makeOptions(), screen: wide)
        assertRect(wideLayout.rect(of: .a, in: wide), rect(2070, 315, 150, 150))
        assertRect(wideLayout.rect(of: .dpad, in: wide), rect(60, 615, 450, 450))
        assertRect(wideLayout.rect(of: .guide, in: wide), rect(1215, 960, 180, 105))

        let narrow = OnScreenSize(width: 1440, height: 1080)
        let narrowLayout = OnScreenLayout(options: makeOptions(), screen: narrow)
        assertRect(narrowLayout.rect(of: .a, in: narrow), rect(1110, 315, 150, 150))
    }

    func testFramesAreFractionsSoTheyFollowTheScreen() {
        let layout = OnScreenLayout(options: makeOptions(), screen: screen)
        let frame = layout.frames[.a]!
        XCTAssertEqual(frame.x, 1590.0 / 1920.0, accuracy: 1e-12)
        XCTAssertEqual(frame.y, 315.0 / 1080.0, accuracy: 1e-12)
        XCTAssertEqual(frame.width, 150.0 / 1080.0, accuracy: 1e-12, "sizes are fractions of the height")
        let half = OnScreenSize(width: 960, height: 540)
        assertRect(frame.rect(in: half), rect(795, 157.5, 75, 75))
    }

    func testOnlyL3R3ShowsTwoButtonsAndTheGuideButton() {
        let layout = OnScreenLayout(options: makeOptions { $0.onlyL3R3 = true }, screen: screen)
        XCTAssertEqual(layout.elements.map(\.id), [.leftStickButton, .rightStickButton, .guide])
        assertRect(layout.rect(of: .leftStickButton, in: screen), rect(15, 900, 180, 135))
        assertRect(layout.rect(of: .rightStickButton, in: screen), rect(1725, 900, 180, 135))
        XCTAssertEqual(layout.elements.map(\.flag), [GamepadButton.leftStick, GamepadButton.rightStick, GamepadButton.guide])
        XCTAssertEqual(layout.elements.map(\.label), ["L3", "R3", "GUIDE"])
        XCTAssertNil(layout.frames[.a])
    }

    func testTheGuideButtonCanBeHidden() {
        let full = OnScreenLayout(options: makeOptions { $0.showGuideButton = false }, screen: screen)
        XCTAssertEqual(full.elements.count, 13)
        XCTAssertFalse(full.elements.contains { $0.id == .guide })
        let l3r3 = OnScreenLayout(options: makeOptions { $0.onlyL3R3 = true; $0.showGuideButton = false }, screen: screen)
        XCTAssertEqual(l3r3.elements.map(\.id), [.leftStickButton, .rightStickButton])
    }

    func testFlippedFaceButtonsSwapTheLabelAndTheFlagButNotThePlace() {
        let layout = OnScreenLayout(options: makeOptions { $0.flipFaceButtons = true }, screen: screen)
        func element(_ id: OnScreenElementID) -> OnScreenElement { layout.elements.first { $0.id == id }! }
        XCTAssertEqual(element(.a).label, "B")
        XCTAssertEqual(element(.a).flag, GamepadButton.b)
        XCTAssertEqual(element(.b).label, "A")
        XCTAssertEqual(element(.b).flag, GamepadButton.a)
        XCTAssertEqual(element(.x).label, "Y")
        XCTAssertEqual(element(.x).flag, GamepadButton.y)
        XCTAssertEqual(element(.y).label, "X")
        XCTAssertEqual(element(.y).flag, GamepadButton.x)
        assertRect(layout.rect(of: .a, in: screen), rect(1590, 315, 150, 150))
    }

    func testOpacityIsAndroidsAlpha() {
        XCTAssertEqual(makeOptions { $0.opacityPercent = 90 }.alpha, 229, "90 * 255 / 100, cut down")
        XCTAssertEqual(makeOptions { $0.opacityPercent = 0 }.alpha, 0)
        XCTAssertEqual(makeOptions { $0.opacityPercent = 100 }.alpha, 255)
    }

    func testTheOptionsComeFromTheSettings() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let defaults = OnScreenOptions(store: store)
        XCTAssertFalse(defaults.enabled)
        XCTAssertFalse(defaults.onlyL3R3)
        XCTAssertTrue(defaults.showGuideButton)
        XCTAssertFalse(defaults.flipFaceButtons)
        XCTAssertEqual(defaults.opacityPercent, 90)
        XCTAssertTrue(defaults.vibrateOnHostRumble)

        try? store.set(.bool(true), for: "checkbox_show_onscreen_controls")
        try? store.set(.bool(true), for: "checkbox_only_show_L3R3")
        try? store.set(.bool(false), for: "checkbox_show_guide_button")
        try? store.set(.bool(true), for: "checkbox_flip_face_buttons")
        try? store.set(.int(40), for: "seekbar_osc_opacity")
        let changed = OnScreenOptions(store: store)
        XCTAssertTrue(changed.enabled)
        XCTAssertTrue(changed.onlyL3R3)
        XCTAssertFalse(changed.showGuideButton)
        XCTAssertTrue(changed.flipFaceButtons)
        XCTAssertEqual(changed.opacityPercent, 40)
    }

    func testAndroidVibratesOnHostRumbleOnlyWithTheFullControlsOn() {
        XCTAssertTrue(makeOptions().hostRumbleVibratesDevice)
        XCTAssertFalse(makeOptions { $0.vibrateOnHostRumble = false }.hostRumbleVibratesDevice)
        XCTAssertFalse(makeOptions { $0.onlyL3R3 = true }.hostRumbleVibratesDevice)
        XCTAssertFalse(OnScreenOptions().hostRumbleVibratesDevice, "controls off")
    }

    // MARK: - The saved layout

    func testASavedLayoutRoundTripsThroughTheSettingsStorage() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let saved = OnScreenLayoutStore(store: store)
        XCTAssertEqual(OnScreenLayoutStore.key, "osc_layout")
        XCTAssertFalse(saved.hasSavedLayout)
        XCTAssertEqual(saved.load(), [:])

        let frames: [OnScreenElementID: OnScreenFrame] = [
            .a: OnScreenFrame(x: 0.5, y: 0.25, width: 0.125, height: 0.0625),
            .leftStick: OnScreenFrame(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
        ]
        saved.save(frames)
        XCTAssertTrue(saved.hasSavedLayout)
        XCTAssertTrue(store.storage.object(forKey: "osc_layout") is String)
        XCTAssertEqual(saved.load(), frames)

        // A new store over the same storage sees it
        XCTAssertEqual(OnScreenLayoutStore(store: SettingsStore(storage: store.storage)).load(), frames)
    }

    func testSavingKeepsTheFramesOfControlsThatWereNotShown() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let saved = OnScreenLayoutStore(store: store)
        let l3 = OnScreenFrame(x: 0.3, y: 0.4, width: 0.1, height: 0.1)
        let a = OnScreenFrame(x: 0.5, y: 0.5, width: 0.1, height: 0.1)
        saved.save([.leftStickButton: l3])
        saved.save([.a: a])
        XCTAssertEqual(saved.load(), [.leftStickButton: l3, .a: a])
    }

    func testASavedLayoutIsLaidOverTheDefaultsForTheControlsShown() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let moved = OnScreenFrame(x: 0.5, y: 0.25, width: 0.125, height: 0.0625)
        OnScreenLayoutStore(store: store).save([.a: moved, .leftStickButton: moved])

        let layout = OnScreenLayout(store: store, screen: screen)
        XCTAssertEqual(layout.frames[.a], moved)
        assertRect(layout.rect(of: .b, in: screen), rect(1740, 165, 150, 150))
        XCTAssertNil(layout.frames[.leftStickButton], "L3 is not shown in the full layout")
    }

    func testResetGoesBackToTheDefaults() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let saved = OnScreenLayoutStore(store: store)
        saved.save([.a: OnScreenFrame(x: 0.5, y: 0.25, width: 0.125, height: 0.0625)])
        saved.reset()
        XCTAssertFalse(saved.hasSavedLayout)
        XCTAssertNil(store.storage.object(forKey: "osc_layout"))
        let layout = OnScreenLayout(store: store, screen: screen)
        assertRect(layout.rect(of: .a, in: screen), rect(1590, 315, 150, 150))
    }

    func testADamagedEntryIsSkippedAndDamagedTextIsRemoved() {
        let storage = MemorySettingsStorage()
        let store = SettingsStore(storage: storage)
        let saved = OnScreenLayoutStore(store: store)

        storage.set("""
        {"version":1,"elements":{"6":{"x":0.5,"y":0.5,"width":0.1,"height":0.1},
        "7":{"x":0.5,"y":0.5,"width":-1,"height":0.1},"8":{"x":"left"},"99":{"x":0,"y":0,"width":1,"height":1}}}
        """, forKey: "osc_layout")
        XCTAssertEqual(saved.load(), [.a: OnScreenFrame(x: 0.5, y: 0.5, width: 0.1, height: 0.1)])

        storage.set("not json", forKey: "osc_layout")
        XCTAssertEqual(saved.load(), [:])
        XCTAssertNil(storage.object(forKey: "osc_layout"), "removed, as Android removes a corrupt element")
    }

    func testTheSavedLayoutIsNotAnExportedSetting() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        OnScreenLayoutStore(store: store).save([.a: OnScreenFrame(x: 0.5, y: 0.25, width: 0.125, height: 0.0625)])
        XCTAssertNil(SettingsCatalog.definition("osc_layout"))
        XCTAssertTrue(store.savedValues().isEmpty)
    }
}

final class InputControlsEditorTests: XCTestCase {
    private func editor() -> OnScreenEditor {
        OnScreenEditor(layout: OnScreenLayout(options: makeOptions(), screen: screen), screen: screen)
    }

    func testMovingFollowsTheFinger() {
        var editor = editor()
        editor.move(.a, dx: 100, dy: -50)
        assertRect(editor.rect(of: .a), rect(1690, 265, 150, 150))
    }

    func testMovingStaysOnTheScreen() {
        var editor = editor()
        editor.move(.a, dx: -5000, dy: -5000)
        assertRect(editor.rect(of: .a), rect(0, 0, 150, 150))
        editor.move(.a, dx: 9000, dy: 9000)
        assertRect(editor.rect(of: .a), rect(1770, 930, 150, 150), "the right and bottom edges stop at the screen too")
    }

    func testResizeMovesTheBottomRightCornerAndKeepsTheTopLeft() {
        var editor = editor()
        editor.resize(.a, dx: 30, dy: -20)
        assertRect(editor.rect(of: .a), rect(1590, 315, 180, 130), "width and height change on their own")
    }

    func testResizeStopsAt20AndAtTheScreen() {
        var editor = editor()
        editor.resize(.a, dx: -1000, dy: -1000)
        assertRect(editor.rect(of: .a), rect(1590, 315, 20, 20), "Android's smallest size")
        editor.resize(.a, dx: 5000, dy: 5000)
        assertRect(editor.rect(of: .a), rect(1590, 315, 330, 765))
    }

    func testADragMovesFromWhereItBeganSoItDoesNotDrift() {
        var editor = editor()
        XCTAssertEqual(editor.beginDrag(at: point(1650, 400), mode: .move), .a)
        editor.drag(to: point(1700, 420))
        editor.drag(to: point(1750, 440))
        editor.drag(to: point(1660, 410))
        editor.endDrag()
        assertRect(editor.rect(of: .a), rect(1600, 325, 150, 150))
        XCTAssertTrue(editor.canUndo)
    }

    func testADragThatMissesEveryControlDoesNothing() {
        var editor = editor()
        XCTAssertNil(editor.beginDrag(at: point(1000, 300), mode: .move))
        editor.drag(to: point(1100, 300))
        editor.endDrag()
        XCTAssertFalse(editor.canUndo)
    }

    func testAStickIsPickedUpAnywhereInItsRectangle() {
        let editor = editor()
        XCTAssertEqual(editor.hitTest(point(95, 65)), .leftStick, "a corner outside the stick's circle")
    }

    func testTheControlOnTopIsPickedUp() {
        var editor = editor()
        editor.move(.a, dx: 150, dy: -150)
        // A now sits on B (B was added after A, so B is on top)
        XCTAssertEqual(editor.hitTest(point(1800, 200)), .b)
    }

    func testUndoTakesBackOneChangeAtATime() {
        var editor = editor()
        editor.move(.a, dx: 10, dy: 0)
        editor.move(.a, dx: 10, dy: 0)
        assertRect(editor.rect(of: .a), rect(1610, 315, 150, 150))
        XCTAssertTrue(editor.undo())
        assertRect(editor.rect(of: .a), rect(1600, 315, 150, 150))
        XCTAssertTrue(editor.undo())
        assertRect(editor.rect(of: .a), rect(1590, 315, 150, 150))
        XCTAssertFalse(editor.undo())
    }

    func testResetToDefaultsIsOneStepOfUndo() {
        var editor = editor()
        editor.move(.a, dx: 10, dy: 0)
        editor.resetToDefaults()
        assertRect(editor.rect(of: .a), rect(1590, 315, 150, 150))
        XCTAssertTrue(editor.undo())
        assertRect(editor.rect(of: .a), rect(1600, 315, 150, 150))
    }

    func testSavingStoresEveryControlShownAndTheNextLayoutUsesIt() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        var editor = editor()
        editor.move(.a, dx: -100, dy: 0)
        editor.save(to: OnScreenLayoutStore(store: store))

        let saved = OnScreenLayoutStore(store: store).load()
        XCTAssertEqual(saved.count, 14)
        let layout = OnScreenLayout(options: makeOptions(), screen: screen, saved: saved)
        assertRect(layout.rect(of: .a, in: screen), rect(1490, 315, 150, 150))
        assertRect(layout.rect(of: .b, in: screen), rect(1740, 165, 150, 150))
    }
}

final class InputControlsControllerTests: XCTestCase {
    private func makeController(_ options: OnScreenOptions = makeOptions(), repeats: Bool = false,
                                edit: (inout OnScreenLayout) -> Void = { _ in }) -> OnScreenController {
        var layout = OnScreenLayout(options: options, screen: screen)
        edit(&layout)
        return OnScreenController(layout: layout, screen: screen, repeatsLikeAndroid: repeats)
    }

    // MARK: Buttons and triggers

    func testAButtonPressAndRelease() {
        let controller = makeController()
        let down = controller.touch(id: 1, at: point(1650, 400), phase: .began, now: 1)
        XCTAssertEqual(down.events, [state(buttons: GamepadButton.a)])
        XCTAssertTrue(down.captured)

        let up = controller.touch(id: 1, at: point(1650, 400), phase: .ended, now: 1.1)
        XCTAssertEqual(up.events, [state()])
        XCTAssertTrue(up.captured)
    }

    func testYIsOneFlagNotTheHigherFlagsToo() {
        // Android keeps the flags in a short, which turns 0x8000 into 0xFFFF8000. Not copied.
        let controller = makeController()
        let down = controller.touch(id: 1, at: point(1650, 90), phase: .began, now: 1)
        XCTAssertEqual(down.events, [state(buttons: 0x8000)])
    }

    func testEveryButtonSendsItsOwnFlag() {
        let taps: [(OnScreenElementID, OnScreenPoint, Int)] = [
            (.b, point(1800, 240), GamepadButton.b), (.x, point(1500, 240), GamepadButton.x),
            (.leftBumper, point(400, 500), GamepadButton.leftBumper), (.rightBumper, point(1400, 500), GamepadButton.rightBumper),
            (.back, point(550, 1000), GamepadButton.back), (.start, point(1300, 1000), GamepadButton.start),
            (.guide, point(800, 1000), GamepadButton.guide),
        ]
        for (id, at, flag) in taps {
            let controller = makeController()
            XCTAssertEqual(controller.touch(id: 1, at: at, phase: .began, now: 1).events, [state(buttons: flag)], "\(id)")
        }
    }

    func testFlippedFaceButtonsSendTheOtherFlag() {
        let controller = makeController(makeOptions { $0.flipFaceButtons = true })
        XCTAssertEqual(controller.touch(id: 1, at: point(1650, 400), phase: .began, now: 1).events,
                       [state(buttons: GamepadButton.b)], "the control in A's place says B and sends B")
    }

    func testTriggersAreZeroOr255() {
        let controller = makeController()
        XCTAssertEqual(controller.touch(id: 1, at: point(100, 500), phase: .began, now: 1).events, [state(leftTrigger: 255)])
        XCTAssertEqual(controller.touch(id: 1, at: point(100, 500), phase: .ended, now: 1.1).events, [state()])
        XCTAssertEqual(controller.touch(id: 2, at: point(1800, 500), phase: .began, now: 2).events, [state(rightTrigger: 255)])
        XCTAssertEqual(controller.touch(id: 2, at: point(1800, 500), phase: .ended, now: 2.1).events, [state()])
    }

    func testL3AndR3ButtonsInL3R3Mode() {
        let controller = makeController(makeOptions { $0.onlyL3R3 = true })
        XCTAssertEqual(controller.touch(id: 1, at: point(100, 950), phase: .began, now: 1).events,
                       [state(buttons: GamepadButton.leftStick)])
        XCTAssertEqual(controller.touch(id: 2, at: point(1800, 950), phase: .began, now: 1.1).events,
                       [state(buttons: GamepadButton.leftStick | GamepadButton.rightStick)])
    }

    func testAnEdgeIsNotInsideTheButton() {
        let controller = makeController()
        // A is x 1590..1740: the left edge is in, the right edge is out
        XCTAssertTrue(controller.touch(id: 1, at: point(1590, 400), phase: .began, now: 1).captured)
        XCTAssertFalse(controller.touch(id: 2, at: point(1740, 400), phase: .began, now: 1).captured)
    }

    // MARK: Sliding between buttons

    func testSlidingOntoAnotherButtonPressesItAndLiftingReleasesBoth() {
        let controller = makeController()
        XCTAssertEqual(controller.touch(id: 1, at: point(1650, 400), phase: .began, now: 1).events,
                       [state(buttons: GamepadButton.a)])
        // Over to B
        XCTAssertEqual(controller.touch(id: 1, at: point(1800, 240), phase: .moved, now: 1.05).events,
                       [state(buttons: GamepadButton.a | GamepadButton.b)])
        // Moving about on B changes nothing
        XCTAssertEqual(controller.touch(id: 1, at: point(1810, 250), phase: .moved, now: 1.06).events, [])
        // Lifting: A lets go, then B
        XCTAssertEqual(controller.touch(id: 1, at: point(1810, 250), phase: .ended, now: 1.1).events,
                       [state(buttons: GamepadButton.b), state()])
    }

    func testSlidingOffAButtonItPressedLetsGoOfIt() {
        let controller = makeController()
        _ = controller.touch(id: 1, at: point(1650, 400), phase: .began, now: 1)
        _ = controller.touch(id: 1, at: point(1800, 240), phase: .moved, now: 1.05)
        XCTAssertEqual(controller.touch(id: 1, at: point(1650, 400), phase: .moved, now: 1.1).events,
                       [state(buttons: GamepadButton.a)], "B is let go, A, where the finger started, stays down")
    }

    func testBackDoesNotSlideOntoButtonsInAnotherLayer() {
        let controller = makeController()
        XCTAssertEqual(controller.touch(id: 1, at: point(550, 1000), phase: .began, now: 1).events,
                       [state(buttons: GamepadButton.back)])
        // The Guide button is next door, in layer 1; Back is in layer 2
        XCTAssertEqual(controller.touch(id: 1, at: point(800, 1000), phase: .moved, now: 1.05).events, [])
    }

    // MARK: D-pad

    func testDpadUpRightIsTwoDirectionsAtOnce() {
        let controller = makeController()
        // The pad is x 60..510, y 615..1065. Right is past two thirds across, up is above a third.
        let down = controller.touch(id: 1, at: point(400, 650), phase: .began, now: 1)
        XCTAssertEqual(down.events, [state(buttons: GamepadButton.up | GamepadButton.right)])
        XCTAssertEqual(GamepadButton.up | GamepadButton.right, 9)
        XCTAssertEqual(controller.touch(id: 1, at: point(400, 650), phase: .ended, now: 1.1).events, [state()])
    }

    func testDpadFollowsTheFingerAroundTheCompass() {
        let controller = makeController()
        let steps: [(OnScreenPoint, Int)] = [
            (point(100, 800), GamepadButton.left),
            (point(100, 650), GamepadButton.left | GamepadButton.up),
            (point(285, 650), GamepadButton.up),
            (point(285, 840), 0),
            (point(285, 1050), GamepadButton.down),
            (point(450, 1050), GamepadButton.down | GamepadButton.right),
        ]
        var last = 0
        for (index, step) in steps.enumerated() {
            let phase: OnScreenTouchPhase = index == 0 ? .began : .moved
            let events = controller.touch(id: 1, at: step.0, phase: phase, now: 1 + Double(index) / 100).events
            XCTAssertEqual(events, step.1 == last ? [] : [state(buttons: step.1)], "step \(index)")
            last = step.1
        }
    }

    func testDpadKeepsWorkingWhenTheFingerLeavesIt() {
        let controller = makeController()
        _ = controller.touch(id: 1, at: point(285, 840), phase: .began, now: 1)
        // Dragged off the left of the pad: still the pad's finger, and now "left"
        XCTAssertEqual(controller.touch(id: 1, at: point(10, 840), phase: .moved, now: 1.1).events,
                       [state(buttons: GamepadButton.left)])
    }

    // MARK: Sticks

    // The left stick is x 90..480, y 60..450; its centre is (285, 255). Its half size is 195, so
    // the circle has radius 187 (195 less two 4-pixel strokes), the stick's own radius is 39
    // and full deflection is 148 from the centre. The dead circle has radius 58.5.

    func testAStickPushedToTheEdgeIsFullDeflectionAndReleaseBringsItBack() {
        let controller = makeController()
        let down = controller.touch(id: 1, at: point(285, 255), phase: .began, now: 1)
        XCTAssertEqual(down.events, [], "a touch in the dead circle does not move the stick yet")
        XCTAssertTrue(down.captured)

        let right = controller.touch(id: 1, at: point(285 + 300, 255), phase: .moved, now: 1.1)
        XCTAssertEqual(right.events, [state(leftX: 32766)], "full deflection is 0x7FFE, past the edge or not")

        let up = controller.touch(id: 1, at: point(585, 255), phase: .ended, now: 1.2)
        XCTAssertEqual(up.events, [state()])
    }

    func testAStickPushedInEachDirection() {
        let pushes: [(OnScreenPoint, Int, Int)] = [
            (point(285, 255 - 200), 0, 32766),      // up is positive
            (point(285, 255 + 200), 0, -32766),
            (point(285 - 200, 255), -32766, 0),
        ]
        for (target, x, y) in pushes {
            let controller = makeController()
            _ = controller.touch(id: 1, at: point(285, 255), phase: .began, now: 1)
            XCTAssertEqual(controller.touch(id: 1, at: target, phase: .moved, now: 1.1).events,
                           [state(leftX: x, leftY: y)], "\(target)")
        }
    }

    func testAStickHalfWayIsHalfDeflection() {
        let controller = makeController()
        _ = controller.touch(id: 1, at: point(285, 255), phase: .began, now: 1)
        // 74 is half of the 148 of full deflection
        XCTAssertEqual(controller.touch(id: 1, at: point(285 + 74, 255), phase: .moved, now: 1.1).events,
                       [state(leftX: 16383)])
    }

    func testADiagonalPushIsOnTheCircle() {
        let controller = makeController()
        _ = controller.touch(id: 1, at: point(285, 255), phase: .began, now: 1)
        let events = controller.touch(id: 1, at: point(285 + 300, 255 - 300), phase: .moved, now: 1.1).events
        guard case .controller(let sent)? = events.first else { return XCTFail("no packet") }
        XCTAssertEqual(Double(sent.leftX), 32766 * 0.7071067811865476, accuracy: 2)
        XCTAssertEqual(Double(sent.leftY), 32766 * 0.7071067811865476, accuracy: 2)
    }

    func testSmallMovementsInTheDeadCircleCountOnlyAfterTheFingerHasStayed() {
        let controller = makeController()
        _ = controller.touch(id: 1, at: point(285, 255), phase: .began, now: 1)
        XCTAssertEqual(controller.touch(id: 1, at: point(315, 255), phase: .moved, now: 1.1).events, [],
                       "30 pixels is inside the 58.5 dead circle, and the finger was down 100 ms ago")
        // Past 150 ms the dead circle is lifted: 30 / 148 of full
        let expected = Int(Float(30) / Float(148) * 32766)
        XCTAssertEqual(controller.touch(id: 1, at: point(315, 255), phase: .moved, now: 1.2).events,
                       [state(leftX: expected)])
        XCTAssertEqual(expected, 6641)
    }

    func testOnceActiveTheStickStaysActiveEvenBackInTheDeadCircle() {
        let controller = makeController()
        _ = controller.touch(id: 1, at: point(285, 255), phase: .began, now: 1)
        _ = controller.touch(id: 1, at: point(385, 255), phase: .moved, now: 1.01)
        XCTAssertEqual(controller.touch(id: 1, at: point(305, 255), phase: .moved, now: 1.02).events,
                       [state(leftX: Int(Float(20) / Float(148) * 32766))])
    }

    func testAFingerOutsideTheStickCircleIsNotCapturedByTheStick() {
        let controller = makeController()
        // The top left corner of the stick's rectangle is outside its circle
        let response = controller.touch(id: 1, at: point(95, 65), phase: .began, now: 1)
        XCTAssertFalse(response.captured)
        XCTAssertEqual(response.events, [])
        XCTAssertEqual(controller.capturedTouchIDs, [])
    }

    func testAFingerOutsideTheStickCircleFallsThroughToAControlUnderIt() {
        // Put the left trigger under the stick's top left corner
        let controller = makeController { layout in
            layout.frames[.leftTrigger] = OnScreenFrame(rect: rect(92, 62, 100, 80), in: screen)
        }
        let response = controller.touch(id: 1, at: point(95, 65), phase: .began, now: 1)
        XCTAssertTrue(response.captured)
        XCTAssertEqual(response.events, [state(leftTrigger: 255)])
    }

    func testTheRightStickDrivesTheRightAxes() {
        let controller = makeController()
        // Its rectangle is x 1470..1860, y 630..1020, so its centre is (1665, 825)
        _ = controller.touch(id: 1, at: point(1665, 825), phase: .began, now: 1)
        XCTAssertEqual(controller.touch(id: 1, at: point(1665 + 200, 825), phase: .moved, now: 1.1).events,
                       [state(rightX: 32766)])
    }

    func testDoubleTappingAStickClicksIt() {
        let controller = makeController()
        let centre = point(285, 255)
        XCTAssertEqual(controller.touch(id: 1, at: centre, phase: .began, now: 1.0).events, [])
        XCTAssertEqual(controller.touch(id: 1, at: centre, phase: .ended, now: 1.1).events, [])
        // The second tap, 300 ms after the first went down: L3 goes down
        XCTAssertEqual(controller.touch(id: 1, at: centre, phase: .began, now: 1.3).events,
                       [state(buttons: GamepadButton.leftStick)])
        // Lifting lets go of it
        XCTAssertEqual(controller.touch(id: 1, at: centre, phase: .ended, now: 1.4).events, [state()])
        // A third tap straight after is a single one again
        XCTAssertEqual(controller.touch(id: 1, at: centre, phase: .began, now: 1.5).events, [])
    }

    func testTheDoubleTapWindowIs350Milliseconds() {
        let inside = makeController()
        let centre = point(285, 255)
        _ = inside.touch(id: 1, at: centre, phase: .began, now: 2.0)
        _ = inside.touch(id: 1, at: centre, phase: .ended, now: 2.1)
        XCTAssertEqual(inside.touch(id: 1, at: centre, phase: .began, now: 2.35).events.count, 1, "350 ms is still a double tap")

        let outside = makeController()
        _ = outside.touch(id: 1, at: centre, phase: .began, now: 2.0)
        _ = outside.touch(id: 1, at: centre, phase: .ended, now: 2.1)
        XCTAssertEqual(outside.touch(id: 1, at: centre, phase: .began, now: 2.351).events, [], "351 ms is not")
    }

    func testRightStickDoubleTapIsR3() {
        let controller = makeController()
        let centre = point(1665, 825)
        _ = controller.touch(id: 1, at: centre, phase: .began, now: 1.0)
        _ = controller.touch(id: 1, at: centre, phase: .ended, now: 1.05)
        XCTAssertEqual(controller.touch(id: 1, at: centre, phase: .began, now: 1.2).events,
                       [state(buttons: GamepadButton.rightStick)])
    }

    // MARK: Two thumbs, and touches that no control has

    func testTwoThumbsAtOnce() {
        let controller = makeController()
        // Left thumb on the stick, pushed right; right thumb on A
        _ = controller.touch(id: 1, at: point(285, 255), phase: .began, now: 1)
        XCTAssertEqual(controller.touch(id: 1, at: point(485, 255), phase: .moved, now: 1.1).events,
                       [state(leftX: 32766)])
        XCTAssertEqual(controller.touch(id: 2, at: point(1650, 400), phase: .began, now: 1.2).events,
                       [state(buttons: GamepadButton.a, leftX: 32766)])
        XCTAssertEqual(controller.capturedTouchIDs, [1, 2])

        // Lifting the thumb on A leaves the stick alone
        XCTAssertEqual(controller.touch(id: 2, at: point(1650, 400), phase: .ended, now: 1.3).events,
                       [state(leftX: 32766)])
        XCTAssertEqual(controller.capturedTouchIDs, [1])
        XCTAssertEqual(controller.touch(id: 1, at: point(485, 255), phase: .ended, now: 1.4).events, [state()])
        XCTAssertEqual(controller.capturedTouchIDs, [])
    }

    func testTouchesNoControlHasAreLeftForTheTouchHandler() {
        let controller = makeController()
        let miss = controller.touch(id: 5, at: point(960, 300), phase: .began, now: 1)
        XCTAssertFalse(miss.captured)
        XCTAssertEqual(miss.events, [])
        XCTAssertFalse(controller.touch(id: 5, at: point(970, 300), phase: .moved, now: 1.1).captured)
        XCTAssertFalse(controller.touch(id: 5, at: point(970, 300), phase: .ended, now: 1.2).captured)
        XCTAssertEqual(controller.capturedTouchIDs, [])
    }

    func testASecondFingerOnTheSameControlIsHeldButDoesNothing() {
        let controller = makeController()
        _ = controller.touch(id: 1, at: point(1650, 400), phase: .began, now: 1)
        let second = controller.touch(id: 2, at: point(1660, 410), phase: .began, now: 1.1)
        XCTAssertTrue(second.captured)
        XCTAssertEqual(second.events, [])
        XCTAssertEqual(controller.capturedTouchIDs, [1, 2])
        XCTAssertEqual(controller.touch(id: 2, at: point(1660, 410), phase: .ended, now: 1.2).events, [])
        XCTAssertEqual(controller.state.buttons, GamepadButton.a, "A is still down")
    }

    func testCancellingAllLetsGoOfEverything() {
        let controller = makeController()
        _ = controller.touch(id: 1, at: point(285, 255), phase: .began, now: 1)
        _ = controller.touch(id: 1, at: point(485, 255), phase: .moved, now: 1.1)
        _ = controller.touch(id: 2, at: point(1650, 400), phase: .began, now: 1.2)
        let events = controller.cancelAll(now: 2)
        XCTAssertEqual(events.last, state())
        XCTAssertEqual(controller.state, ControllerState())
        XCTAssertEqual(controller.capturedTouchIDs, [])
    }

    func testThePacketsCarryTheControllerNumberAndMask() {
        let layout = OnScreenLayout(options: makeOptions(), screen: screen)
        let controller = OnScreenController(layout: layout, screen: screen, controllerNumber: 2, activeMask: 0b101)
        let events = controller.touch(id: 1, at: point(1650, 400), phase: .began, now: 1).events
        XCTAssertEqual(events, [.controller(ControllerState(number: 2, activeMask: 5, buttons: GamepadButton.a))])
    }

    // MARK: Android's repeats

    func testByDefaultAnUnchangedStateIsNotSentAgain() {
        let controller = makeController()
        _ = controller.touch(id: 1, at: point(285, 255), phase: .began, now: 1)
        _ = controller.touch(id: 1, at: point(485, 255), phase: .moved, now: 1.1)
        XCTAssertEqual(controller.touch(id: 1, at: point(490, 255), phase: .moved, now: 1.11).events, [])
        XCTAssertNil(controller.nextDeadline)
        XCTAssertEqual(controller.tick(now: 5), [])
    }

    func testLikeAndroidEveryEventSendsAndTheStateIsRepeated25_50_And75MillisecondsLater() {
        let controller = makeController(repeats: true)
        let down = controller.touch(id: 1, at: point(1650, 400), phase: .began, now: 10)
        XCTAssertEqual(down.events, [state(buttons: GamepadButton.a)])
        XCTAssertEqual(controller.nextDeadline ?? 0, 10.025, accuracy: 1e-9)
        XCTAssertEqual(controller.tick(now: 10.02), [])
        XCTAssertEqual(controller.tick(now: 10.03), [state(buttons: GamepadButton.a)])
        XCTAssertEqual(controller.tick(now: 10.08), [state(buttons: GamepadButton.a), state(buttons: GamepadButton.a)])
        XCTAssertNil(controller.nextDeadline)

        // A new input cancels the repeats that were still waiting
        _ = controller.touch(id: 1, at: point(1650, 400), phase: .ended, now: 11)
        _ = controller.touch(id: 1, at: point(1650, 400), phase: .began, now: 11.01)
        XCTAssertEqual(controller.nextDeadline ?? 0, 11.035, accuracy: 1e-9)

        let held = controller.touch(id: 1, at: point(1651, 400), phase: .moved, now: 11.02)
        XCTAssertEqual(held.events, [], "moving on a button sends nothing")
        let pad = makeController(repeats: true)
        _ = pad.touch(id: 1, at: point(285, 840), phase: .began, now: 1)
        XCTAssertEqual(pad.touch(id: 1, at: point(285, 841), phase: .moved, now: 1.01).events, [state()],
                       "the D-pad sends on every move, as Android does")
    }
}
