import Foundation

// Ported from Starwire for Android's VirtualControllerConfigurationLoader.java and
// VirtualControllerElement.java (GPL-3.0; Moonlight for Android, Karim Mreisi and contributors).
// The default positions and sizes are Android's. The saved layout is not Android's format.
//
// Coordinates. Android works in pixels: the default layout is a grid of 128 x 72 cells at 16:9,
// one cell being a 72nd of the screen height, and the controls on the right are pushed over by
// however much wider than 16:9 the screen is. This port keeps Android's arithmetic, including
// its whole-number rounding, to place the default controls on the screen it is given, and then
// stores every frame as fractions, so that a saved layout survives a change of screen.
// `OnScreenFrame` says which fraction is which. Android has one layout for every orientation
// (it does not use the controls in portrait), so there is one here.

/// A size in points.
public struct OnScreenSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A point on the screen, in points, y down.
public struct OnScreenPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle on the screen, in points, y down.
public struct OnScreenRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    /// As Android's `View.pointInView`: the left and top edges are inside, the right and bottom
    /// edges are not.
    public func contains(_ point: OnScreenPoint) -> Bool {
        point.x >= x && point.x < maxX && point.y >= y && point.y < maxY
    }
}

/// The ids of Android's on-screen elements (`VirtualControllerElement.EID_*`). The raw values
/// are Android's.
public enum OnScreenElementID: Int, CaseIterable, Sendable, Comparable {
    case dpad = 1
    case leftTrigger = 2
    case rightTrigger = 3
    case leftBumper = 4
    case rightBumper = 5
    case a = 6
    case b = 7
    case x = 8
    case y = 9
    case back = 10
    case start = 11
    case leftStick = 12
    case rightStick = 13
    case leftStickButton = 14
    case rightStickButton = 15
    case guide = 16

    public static func < (lhs: OnScreenElementID, rhs: OnScreenElementID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum OnScreenElementKind: Equatable, Sendable {
    case dpad
    /// A round button that sets one `GamepadButton` flag
    case button
    /// A button that sets a trigger to 255
    case trigger(left: Bool)
    case stick(left: Bool)
}

/// One control: what it is and what it sends. Where it sits is in `OnScreenLayout.frames`.
public struct OnScreenElement: Equatable, Sendable {
    public let id: OnScreenElementID
    public let kind: OnScreenElementKind
    /// The text on it. With flipped face buttons the A control says "B" and sends B.
    public let label: String
    /// The `GamepadButton` flag a `.button` sets, else 0
    public let flag: Int
    /// Android's layer. A finger sliding across buttons only presses the ones in its own layer.
    public let layer: Int
}

/// The settings that decide which controls there are and how they look.
public struct OnScreenOptions: Equatable, Sendable {
    /// `checkbox_show_onscreen_controls`
    public var enabled = false
    /// `checkbox_only_show_L3R3`: only the L3 and R3 buttons, for playing with a real controller
    public var onlyL3R3 = false
    /// `checkbox_show_guide_button`
    public var showGuideButton = true
    /// `checkbox_flip_face_buttons`
    public var flipFaceButtons = false
    /// `seekbar_osc_opacity`, 0 to 100
    public var opacityPercent = 90
    /// `checkbox_vibrate_osc`
    public var vibrateOnHostRumble = true

    public init() {}

    public init(store: SettingsStore) {
        if case .bool(let value)? = store.value("checkbox_show_onscreen_controls") { enabled = value }
        if case .bool(let value)? = store.value("checkbox_only_show_L3R3") { onlyL3R3 = value }
        if case .bool(let value)? = store.value("checkbox_show_guide_button") { showGuideButton = value }
        if case .bool(let value)? = store.value("checkbox_flip_face_buttons") { flipFaceButtons = value }
        if case .int(let value)? = store.value("seekbar_osc_opacity") { opacityPercent = value }
        if case .bool(let value)? = store.value("checkbox_vibrate_osc") { vibrateOnHostRumble = value }
    }

    /// The controls' alpha, 0 to 255: `opacity * 255 / 100`, cut down, as Android does.
    public var alpha: Int { opacityPercent * 255 / 100 }

    /// Android never vibrates when a control is touched. It vibrates the device when the PC
    /// rumbles controller 0 and no real controller is there, if the on-screen controls are on,
    /// are not in L3/R3 only mode and `checkbox_vibrate_osc` is on. This is that condition.
    public var hostRumbleVibratesDevice: Bool { enabled && !onlyL3R3 && vibrateOnHostRumble }
}

/// Where one control is, as fractions of the screen so that it is the same on any screen.
///
/// `x` is the left edge as a fraction of the screen's width, `y` the top edge as a fraction of
/// its height, and `width` and `height` are fractions of the screen's HEIGHT. Sizes follow the
/// height because that is how Android sizes them (a 72nd of the height per cell), so a round
/// button stays round when the width changes.
public struct OnScreenFrame: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(rect: OnScreenRect, in screen: OnScreenSize) {
        self.init(x: rect.x / screen.width, y: rect.y / screen.height,
                  width: rect.width / screen.height, height: rect.height / screen.height)
    }

    public func rect(in screen: OnScreenSize) -> OnScreenRect {
        OnScreenRect(x: x * screen.width, y: y * screen.height, width: width * screen.height, height: height * screen.height)
    }

    var isValid: Bool {
        [x, y, width, height].allSatisfy { $0.isFinite } && width > 0 && height > 0
    }
}

/// The controls on screen and where they are.
public struct OnScreenLayout: Equatable, Sendable {
    public let options: OnScreenOptions
    /// Back to front: a control later in the list is drawn over, and touched before, an earlier one.
    public let elements: [OnScreenElement]
    public var frames: [OnScreenElementID: OnScreenFrame]

    /// The default layout, with a saved layout's frames over it for the controls that are shown.
    public init(options: OnScreenOptions, screen: OnScreenSize, saved: [OnScreenElementID: OnScreenFrame] = [:]) {
        self.options = options
        elements = Self.elements(for: options)
        var frames = Self.defaultFrames(options: options, screen: screen)
        for element in elements {
            if let frame = saved[element.id], frame.isValid {
                frames[element.id] = frame
            }
        }
        self.frames = frames
    }

    /// The layout the settings and the saved layout describe.
    public init(store: SettingsStore, screen: OnScreenSize) {
        self.init(options: OnScreenOptions(store: store), screen: screen, saved: OnScreenLayoutStore(store: store).load())
    }

    public func rect(of id: OnScreenElementID, in screen: OnScreenSize) -> OnScreenRect? {
        frames[id]?.rect(in: screen)
    }

    /// Every control with its rectangle, back to front.
    public func resolved(in screen: OnScreenSize) -> [(element: OnScreenElement, rect: OnScreenRect)] {
        elements.compactMap { element in
            frames[element.id].map { (element, $0.rect(in: screen)) }
        }
    }

    // MARK: - Android's default layout

    private static func element(_ id: OnScreenElementID, _ kind: OnScreenElementKind, _ label: String, flag: Int = 0,
                                layer: Int = 1) -> OnScreenElement {
        OnScreenElement(id: id, kind: kind, label: label, flag: flag, layer: layer)
    }

    /// The controls to show, in the order Android adds them (which is the order they stack in).
    public static func elements(for options: OnScreenOptions) -> [OnScreenElement] {
        var list: [OnScreenElement] = []
        if !options.onlyL3R3 {
            let flip = options.flipFaceButtons
            list = [
                element(.dpad, .dpad, ""),
                element(.a, .button, flip ? "B" : "A", flag: flip ? GamepadButton.b : GamepadButton.a),
                element(.b, .button, flip ? "A" : "B", flag: flip ? GamepadButton.a : GamepadButton.b),
                element(.x, .button, flip ? "Y" : "X", flag: flip ? GamepadButton.y : GamepadButton.x),
                element(.y, .button, flip ? "X" : "Y", flag: flip ? GamepadButton.x : GamepadButton.y),
                element(.leftTrigger, .trigger(left: true), "LT"),
                element(.rightTrigger, .trigger(left: false), "RT"),
                element(.leftBumper, .button, "LB", flag: GamepadButton.leftBumper),
                element(.rightBumper, .button, "RB", flag: GamepadButton.rightBumper),
                element(.leftStick, .stick(left: true), ""),
                element(.rightStick, .stick(left: false), ""),
                element(.back, .button, "BACK", flag: GamepadButton.back, layer: 2),
                element(.start, .button, "START", flag: GamepadButton.start, layer: 3),
            ]
        } else {
            list = [
                element(.leftStickButton, .button, "L3", flag: GamepadButton.leftStick),
                element(.rightStickButton, .button, "R3", flag: GamepadButton.rightStick),
            ]
        }
        if options.showGuideButton {
            list.append(element(.guide, .button, "GUIDE", flag: GamepadButton.guide))
        }
        return list
    }

    /// `screenScale`: cells of the 128 x 72 grid to pixels, `(int) ((float) height / 72 * units)`.
    static func screenScale(_ units: Int, height: Int) -> Int {
        Int(Float(height) / Float(72) * Float(units))
    }

    /// Android's `createDefaultLayout` for a screen. The pixels are worked out as Android works
    /// them out (whole numbers, from the screen's size cut down to whole points) and then stored
    /// as fractions.
    public static func defaultFrames(options: OnScreenOptions, screen: OnScreenSize) -> [OnScreenElementID: OnScreenFrame] {
        let width = Int(screen.width)
        let height = Int(screen.height)
        // Controls on the right move over by however much wider than 16:9 the screen is (or
        // back, when it is narrower)
        let rightDisplacement = width - height * 16 / 9

        func scale(_ units: Int) -> Int { screenScale(units, height: height) }
        var frames: [OnScreenElementID: OnScreenFrame] = [:]
        func place(_ id: OnScreenElementID, x: Int, y: Int, width w: Int, height h: Int, right: Bool = false) {
            let left = scale(x) + (right ? rightDisplacement : 0)
            let rect = OnScreenRect(x: Double(left), y: Double(scale(y)), width: Double(scale(w)), height: Double(scale(h)))
            frames[id] = OnScreenFrame(rect: rect, in: OnScreenSize(width: Double(width), height: Double(height)))
        }

        let triggerLeftX = 1, triggerRightX = 92, triggerDistance = 23, triggerY = 31, triggerWidth = 12, triggerHeight = 9
        let buttonX = 106, buttonY = 1, buttonSize = 10
        let startX = 83, backX = 34, startBackY = 64, startBackWidth = 12, startBackHeight = 7
        let l3r3Y = 60

        if !options.onlyL3R3 {
            place(.dpad, x: 4, y: 41, width: 30, height: 30)
            place(.a, x: buttonX, y: buttonY + 2 * buttonSize, width: buttonSize, height: buttonSize, right: true)
            place(.b, x: buttonX + buttonSize, y: buttonY + buttonSize, width: buttonSize, height: buttonSize, right: true)
            place(.x, x: buttonX - buttonSize, y: buttonY + buttonSize, width: buttonSize, height: buttonSize, right: true)
            place(.y, x: buttonX, y: buttonY, width: buttonSize, height: buttonSize, right: true)
            place(.leftTrigger, x: triggerLeftX, y: triggerY, width: triggerWidth, height: triggerHeight)
            place(.rightTrigger, x: triggerRightX + triggerDistance, y: triggerY, width: triggerWidth,
                  height: triggerHeight, right: true)
            place(.leftBumper, x: triggerLeftX + triggerDistance, y: triggerY, width: triggerWidth, height: triggerHeight)
            place(.rightBumper, x: triggerRightX, y: triggerY, width: triggerWidth, height: triggerHeight, right: true)
            place(.leftStick, x: 6, y: 4, width: 26, height: 26)
            place(.rightStick, x: 98, y: 42, width: 26, height: 26, right: true)
            place(.back, x: backX, y: startBackY, width: startBackWidth, height: startBackHeight)
            place(.start, x: startX, y: startBackY, width: startBackWidth, height: startBackHeight, right: true)
        } else {
            place(.leftStickButton, x: triggerLeftX, y: l3r3Y, width: triggerWidth, height: triggerHeight)
            place(.rightStickButton, x: triggerRightX + triggerDistance, y: l3r3Y, width: triggerWidth,
                  height: triggerHeight, right: true)
        }
        if options.showGuideButton {
            // Android's own comment says the Guide button sits between Back and Start, but the
            // code puts it 49 cells from the left edge (START_X - BACK_X) plus the right
            // displacement. That is kept.
            place(.guide, x: startX - backX, y: startBackY, width: startBackWidth, height: startBackHeight, right: true)
        }
        return frames
    }
}

/// The saved layout: control id to frame, as JSON, under one key in the settings storage.
///
/// Android keeps its layout in a preferences file of its own ("OSC"), not in the settings that
/// an export carries, and so does this: the key is not in `SettingsCatalog`, so a settings
/// export leaves it out, and this type reads and writes the storage directly.
public struct OnScreenLayoutStore {
    /// The key the JSON is saved under.
    public static let key = "osc_layout"
    static let version = 1

    public let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    /// The saved frames. A control whose entry is damaged is skipped and the others are kept.
    /// If the whole text is damaged it is removed, as Android removes a corrupt element.
    public func load() -> [OnScreenElementID: OnScreenFrame] {
        guard let text = store.storage.object(forKey: Self.key) as? String else { return [:] }
        guard let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["elements"] as? [String: Any] else {
            store.storage.removeObject(forKey: Self.key)
            return [:]
        }
        var frames: [OnScreenElementID: OnScreenFrame] = [:]
        for (name, value) in entries {
            guard let id = Int(name).flatMap(OnScreenElementID.init(rawValue:)),
                  let fields = value as? [String: Any],
                  let x = (fields["x"] as? NSNumber)?.doubleValue,
                  let y = (fields["y"] as? NSNumber)?.doubleValue,
                  let width = (fields["width"] as? NSNumber)?.doubleValue,
                  let height = (fields["height"] as? NSNumber)?.doubleValue else {
                continue
            }
            let frame = OnScreenFrame(x: x, y: y, width: width, height: height)
            if frame.isValid {
                frames[id] = frame
            }
        }
        return frames
    }

    /// Saves frames. Like Android, controls that are not in `frames` keep what was saved for them
    /// (the L3/R3 frames survive a session with the full controls).
    public func save(_ frames: [OnScreenElementID: OnScreenFrame]) {
        var all = load()
        for (id, frame) in frames where frame.isValid {
            all[id] = frame
        }
        let file = SavedFile(version: Self.version, elements: Dictionary(uniqueKeysWithValues: all.map { (String($0.key.rawValue), $0.value) }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(file), let text = String(data: data, encoding: .utf8) {
            store.storage.set(text, forKey: Self.key)
        }
    }

    /// "Clear saved on-screen controls layout": back to the defaults.
    public func reset() {
        store.storage.removeObject(forKey: Self.key)
    }

    public var hasSavedLayout: Bool {
        store.storage.object(forKey: Self.key) != nil
    }

    private struct SavedFile: Codable {
        var version: Int
        var elements: [String: OnScreenFrame]
    }
}
