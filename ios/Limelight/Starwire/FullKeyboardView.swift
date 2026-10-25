//
//  FullKeyboardView.swift
//  Starwire
//
//  The on-screen full keyboard: 6 rows, 80 keys, drawn over the bottom of the stream. From Starwire
//  for Android's KeyBoardLayoutController (GPL-3.0); the layout is from Artemide. The key layout
//  and the sticky modifier rules live in StarwireKit (FullKeyboardLayout, StickyModifiers); this
//  view only draws the keys, turns touches into press and release calls, and sends the events.
//
//  Batch 4.5 added the layouts, remapped keys, size and placement from StarwireKit's
//  KeyboardCustomization: docked along the bottom, or floating where it was dragged by the handle
//  on its top edge.
//

import StarwireKit
import UIKit

/// Fill the stream's screen with this view. It draws the keyboard panel at the bottom and lets
/// every touch outside the panel through to the views behind it.
///
/// The panel is 42% of the view's height in landscape and 32% in portrait (at most 380 points),
/// above the bottom safe area and between the side safe areas. Android uses a fixed 200 dp, which
/// is too tall for a phone held upright and too short for a big iPad.
@objc(StarwireFullKeyboardView)
final class FullKeyboardView: UIView {
    /// The Hide key was pressed and lifted.
    var onHide: (() -> Void)?

    static let landscapeHeightShare: CGFloat = 0.42
    static let portraitHeightShare: CGFloat = 0.32
    static let maxPanelHeight: CGFloat = 380

    private struct Slot {
        let key: FullKeyboardKey
        let label: UILabel
        let element: UIAccessibilityElement
        var frame: CGRect = .zero
    }

    private let send: (InputEvent) -> Void
    private let panel = UIView()
    private let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let handle = UIView()
    private var placement = KeyboardPlacement.docked
    private var sizeShare: CGFloat = 1
    /// The floating keyboard's spot, as fractions of the room it can move in
    private var floatingFraction = CGPoint(x: 0.5, y: 1)
    private var dragTouch: UITouch?
    private var dragStart: (finger: CGPoint, origin: CGPoint) = (.zero, .zero)
    private let defaults = UserDefaults(suiteName: StarwireSettings.suiteName) ?? .standard
    /// Height of the floating keyboard's handle
    static let handleHeight: CGFloat = 22
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private var model = StickyModifiers()
    private var slots: [Slot] = []
    /// The key each finger went down on, by touch.
    private var touchKeys: [ObjectIdentifier: String] = [:]
    private var bubbles: [ObjectIdentifier: UILabel] = [:]
    private var timer: Timer?

    private let padding: CGFloat = 3
    private let keyGap: CGFloat = 2

    init(send: @escaping (InputEvent) -> Void) {
        self.send = send
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        send = { _ in }
        super.init(coder: coder)
        setUp()
    }

    deinit {
        timer?.invalidate()
    }

    private static func readModel() -> StickyModifiers {
        let store = StarwireSettings.store
        return StickyModifiers(layout: KeyboardCustomization.layout(from: store),
                               sticky: store.bool("checkbox_sticky_modifier_keys"),
                               vibrate: store.bool("checkbox_keyboard_vibrate"))
    }

    private func setUp() {
        model = Self.readModel()
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let store = StarwireSettings.store
        let opacity = min(max(store.int("seekbar_keyboard_opacity"), 20), 100)
        placement = KeyboardPlacement(rawValue: store.string(KeyboardCustomization.placementKey) ?? "") ?? .docked
        sizeShare = CGFloat(min(max(store.int(KeyboardCustomization.sizeKey), KeyboardCustomization.sizeRange.lowerBound),
                                KeyboardCustomization.sizeRange.upperBound)) / 100
        if defaults.object(forKey: KeyboardCustomization.floatingXKey) != nil {
            floatingFraction = CGPoint(x: defaults.double(forKey: KeyboardCustomization.floatingXKey),
                                       y: defaults.double(forKey: KeyboardCustomization.floatingYKey))
        }
        panel.alpha = CGFloat(opacity) / 100
        panel.backgroundColor = .clear
        panel.layer.cornerRadius = 16
        panel.layer.cornerCurve = .continuous
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        panel.clipsToBounds = true
        panel.isUserInteractionEnabled = false
        panel.accessibilityIdentifier = "FullKeyboard"
        backdrop.isUserInteractionEnabled = false
        backdrop.contentView.backgroundColor = UIColor(red: 0.06, green: 0.04, blue: 0.13, alpha: 0.72)
        panel.addSubview(backdrop)
        handle.backgroundColor = UIColor(white: 1, alpha: 0.45)
        handle.layer.cornerRadius = 2.5
        handle.isUserInteractionEnabled = false
        panel.addSubview(handle)
        addSubview(panel)

        var elements: [UIAccessibilityElement] = []
        for key in model.layout.keys {
            let label = UILabel()
            label.textAlignment = .center
            label.numberOfLines = 0
            label.textColor = .white
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
            label.layer.cornerRadius = 7
            label.layer.cornerCurve = .continuous
            label.layer.masksToBounds = true
            label.isUserInteractionEnabled = false
            panel.addSubview(label)
            let element = UIAccessibilityElement(accessibilityContainer: panel)
            element.accessibilityIdentifier = "key_\(key.id)"
            element.accessibilityLabel = key.label.replacingOccurrences(of: "\n", with: " ")
            element.accessibilityTraits = .button
            elements.append(element)
            slots.append(Slot(key: key, label: label, element: element))
        }
        panel.accessibilityElements = elements
        refresh()
    }

    // MARK: Public

    /// Sends key ups for every finger and every locked modifier, and starts again from a clean
    /// state with the current settings. Call it when the keyboard is hidden or the stream ends.
    func releaseAll() {
        let now = ProcessInfo.processInfo.systemUptime
        let held = Array(touchKeys.values)
        touchKeys.removeAll()
        for id in held {
            apply(model.release(keyID: id, now: now), vibrate: false)
        }
        for id in model.lockedKeyIDs.sorted() {
            // Touching a locked key unlocks it without sending anything; lifting sends the key up
            _ = model.press(keyID: id, now: now)
            apply(model.release(keyID: id, now: now), vibrate: false)
        }
        bubbles.values.forEach { $0.removeFromSuperview() }
        bubbles.removeAll()
        model = Self.readModel()
        refresh()
        scheduleTimer()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        panel.frame = panelFrame()
        backdrop.frame = panel.bounds
        let floating = placement == .floating
        handle.isHidden = !floating
        handle.frame = CGRect(x: (panel.bounds.width - 44) / 2, y: (Self.handleHeight - 5) / 2, width: 44, height: 5)
        layoutKeys()
    }

    /// Docked: the whole width above the bottom safe area. Floating: narrower, where it was left.
    private func panelFrame() -> CGRect {
        let landscape = bounds.width > bounds.height
        let share = landscape ? Self.landscapeHeightShare : Self.portraitHeightShare
        let insets = safeAreaInsets
        let available = CGSize(width: bounds.width - insets.left - insets.right, height: bounds.height - insets.top - insets.bottom)
        let keyRows = CGFloat(model.layout.rows.count) / 6
        var height = min(bounds.height * share * keyRows, Self.maxPanelHeight * keyRows) * sizeShare
        height = min(height, available.height)
        guard placement == .floating else {
            return CGRect(x: insets.left, y: bounds.height - insets.bottom - height, width: available.width, height: height)
        }
        // About as wide as the keys need: Android's rows are about 15 keys wide
        let widest = model.layout.rows.map { row in row.reduce(0) { $0 + $1.weight } }.max() ?? 1500
        let rowHeight = height / CGFloat(max(model.layout.rows.count, 1))
        var width = min(CGFloat(widest) / 100 * rowHeight * 1.25, available.width)
        width = max(width, min(320, available.width))
        height += Self.handleHeight
        let room = CGSize(width: max(available.width - width, 0), height: max(available.height - height, 0))
        let x = insets.left + min(max(floatingFraction.x, 0), 1) * room.width
        let y = insets.top + min(max(floatingFraction.y, 0), 1) * room.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Sizes each key from its weight, as Android's layout weights do. A row's margins (in points
    /// here, dp on Android) are taken off first and the rest is shared out by weight.
    private func layoutKeys() {
        var inner = panel.bounds.insetBy(dx: padding + 2, dy: padding + 2)
        if placement == .floating {
            inner.origin.y += Self.handleHeight - 2
            inner.size.height -= Self.handleHeight - 2
        }
        let rows = model.layout.rows
        guard !rows.isEmpty else { return }
        let rowHeight = inner.height / CGFloat(rows.count)
        let fontSize = min(max(rowHeight * 0.38, 9), 20)
        var index = 0
        for (rowIndex, row) in rows.enumerated() {
            let margins = row.reduce(0) { $0 + $1.marginBefore + $1.marginAfter }
            let weights = row.reduce(0) { $0 + $1.weight }
            let unit = (inner.width - CGFloat(margins)) / CGFloat(max(weights, 1))
            var x = inner.minX
            for key in row {
                x += CGFloat(key.marginBefore)
                let slot = CGRect(x: x, y: inner.minY + CGFloat(rowIndex) * rowHeight,
                                  width: CGFloat(key.weight) * unit, height: rowHeight)
                x += slot.width + CGFloat(key.marginAfter)
                guard index < slots.count else { continue }
                let frame = slot.insetBy(dx: keyGap / 2, dy: keyGap / 2)
                slots[index].frame = frame
                slots[index].label.frame = frame
                slots[index].label.font = .systemFont(ofSize: fontSize, weight: .medium)
                slots[index].element.accessibilityFrameInContainerSpace = frame
                index += 1
            }
        }
    }

    // MARK: Drawing state

    /// Updates every key's text and colour from the model and the fingers that are down.
    private func refresh() {
        let shiftOn = model.activeModifiers & KeyModifier.shift != 0
        let held = Set(touchKeys.values)
        for slot in slots {
            let key = slot.key
            slot.label.text = shiftOn ? (key.shiftedLabel ?? key.label) : key.label
            let on = model.lockedKeyIDs.contains(key.id)
                || (key.modifierMask != 0 && model.activeModifiers & key.modifierMask != 0)
            if on {
                // Starwire's violet, as the menu's switches
                slot.label.backgroundColor = UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 0.95)
            } else if held.contains(key.id) {
                slot.label.backgroundColor = UIColor(white: 1, alpha: 0.42)
            } else {
                slot.label.backgroundColor = UIColor(white: 1, alpha: key.isSpecial ? 0.10 : 0.17)
            }
        }
    }

    // MARK: Touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        panel.frame.contains(point)
    }

    private func slot(at point: CGPoint) -> Slot? {
        let grow = -(keyGap / 2 + 0.5)
        return slots.first { $0.frame.insetBy(dx: grow, dy: grow).contains(point) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // The floating keyboard's handle moves it
            if placement == .floating, dragTouch == nil, touch.location(in: panel).y < Self.handleHeight {
                dragTouch = touch
                dragStart = (touch.location(in: self), panel.frame.origin)
                continue
            }
            guard let slot = slot(at: touch.location(in: panel)) else { continue }
            touchKeys[ObjectIdentifier(touch)] = slot.key.id
            let output = model.press(keyID: slot.key.id, now: touch.timestamp)
            apply(output)
            if output.showsPopup { showBubble(for: slot, touch: touch) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let drag = dragTouch, touches.contains(drag) else { return }
        let point = drag.location(in: self)
        let insets = safeAreaInsets
        let room = CGSize(width: max(bounds.width - insets.left - insets.right - panel.frame.width, 1),
                          height: max(bounds.height - insets.top - insets.bottom - panel.frame.height, 1))
        let origin = CGPoint(x: dragStart.origin.x + point.x - dragStart.finger.x, y: dragStart.origin.y + point.y - dragStart.finger.y)
        floatingFraction = CGPoint(x: min(max((origin.x - insets.left) / room.width, 0), 1),
                                   y: min(max((origin.y - insets.top) / room.height, 0), 1))
        setNeedsLayout()
    }

    // A finger that slides off its key stays on that key until it lifts, as on Android
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, cancelled: true) }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        if let drag = dragTouch, touches.contains(drag) {
            dragTouch = nil
            defaults.set(Double(floatingFraction.x), forKey: KeyboardCustomization.floatingXKey)
            defaults.set(Double(floatingFraction.y), forKey: KeyboardCustomization.floatingYKey)
        }
        for touch in touches {
            guard let id = touchKeys.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            apply(model.release(keyID: id, now: touch.timestamp))
            hideBubble(for: touch)
            if !cancelled && model.layout.key(id: id)?.kind == .hide { onHide?() }
        }
    }

    // MARK: Output, timer and popups

    private func apply(_ output: StickyModifiers.Output, vibrate: Bool = true) {
        output.events.forEach(send)
        if vibrate && output.shouldVibrate {
            haptics.impactOccurred()
            haptics.prepare()
        }
        refresh()
        scheduleTimer()
    }

    /// Sets a one-shot timer for the model's next lock deadline, if there is one. Touch times and
    /// `systemUptime` are on the same clock.
    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard let deadline = model.nextDeadline else { return }
        let delay = max(deadline - ProcessInfo.processInfo.systemUptime, 0)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.apply(self.model.tick(now: ProcessInfo.processInfo.systemUptime))
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// A small bubble with the key's label above the key, as Android's popup does.
    private func showBubble(for slot: Slot, touch: UITouch) {
        let id = ObjectIdentifier(touch)
        bubbles[id]?.removeFromSuperview()
        let shiftOn = model.activeModifiers & KeyModifier.shift != 0
        let bubble = UILabel()
        bubble.text = shiftOn ? (slot.key.shiftedLabel ?? slot.key.label) : slot.key.label
        bubble.font = .systemFont(ofSize: 26, weight: .semibold)
        bubble.textAlignment = .center
        bubble.textColor = .black
        bubble.backgroundColor = UIColor(white: 0.96, alpha: 1)
        bubble.layer.cornerRadius = 8
        bubble.layer.masksToBounds = true
        bubble.isUserInteractionEnabled = false
        let size = CGSize(width: max(slot.frame.width + 8, 48), height: 52)
        let center = CGPoint(x: slot.frame.midX + panel.frame.minX, y: slot.frame.minY + panel.frame.minY)
        let x = min(max(center.x - size.width / 2, 0), max(bounds.width - size.width, 0))
        bubble.frame = CGRect(x: x, y: max(center.y - size.height - 4, 0), width: size.width, height: size.height)
        addSubview(bubble)
        bubbles[id] = bubble
    }

    private func hideBubble(for touch: UITouch) {
        guard let bubble = bubbles.removeValue(forKey: ObjectIdentifier(touch)) else { return }
        UIView.animate(withDuration: 0.12, delay: 0.1, options: [.allowUserInteraction],
                       animations: { bubble.alpha = 0 },
                       completion: { _ in bubble.removeFromSuperview() })
    }
}
