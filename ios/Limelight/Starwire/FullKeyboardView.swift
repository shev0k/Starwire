//
//  FullKeyboardView.swift
//  Starwire
//
//  The on-screen full keyboard: 6 rows, 80 keys, drawn over the bottom of the stream. From Starwire
//  for Android's KeyBoardLayoutController (GPL-3.0); the layout is from Artemide. The key layout
//  and the sticky modifier rules live in StarwireKit (FullKeyboardLayout, StickyModifiers); this
//  view only draws the keys, turns touches into press and release calls, and sends the events.
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
        return StickyModifiers(sticky: store.bool("checkbox_sticky_modifier_keys"),
                               vibrate: store.bool("checkbox_keyboard_vibrate"))
    }

    private func setUp() {
        model = Self.readModel()
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let opacity = min(max(StarwireSettings.store.int("seekbar_keyboard_opacity"), 20), 100)
        panel.alpha = CGFloat(opacity) / 100
        panel.backgroundColor = UIColor(white: 0.13, alpha: 0.92)
        panel.layer.cornerRadius = 8
        panel.isUserInteractionEnabled = false
        panel.accessibilityIdentifier = "FullKeyboard"
        addSubview(panel)

        var elements: [UIAccessibilityElement] = []
        for key in model.layout.keys {
            let label = UILabel()
            label.textAlignment = .center
            label.numberOfLines = 0
            label.textColor = .white
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
            label.layer.cornerRadius = 5
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
        let landscape = bounds.width > bounds.height
        let share = landscape ? Self.landscapeHeightShare : Self.portraitHeightShare
        let height = min(bounds.height * share, Self.maxPanelHeight)
        let insets = safeAreaInsets
        panel.frame = CGRect(x: insets.left, y: bounds.height - insets.bottom - height,
                             width: bounds.width - insets.left - insets.right, height: height)
        layoutKeys()
    }

    /// Sizes each key from its weight, as Android's layout weights do. A row's margins (in points
    /// here, dp on Android) are taken off first and the rest is shared out by weight.
    private func layoutKeys() {
        let inner = panel.bounds.insetBy(dx: padding, dy: padding)
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
                slot.label.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
            } else if held.contains(key.id) {
                slot.label.backgroundColor = UIColor(white: 1, alpha: 0.38)
            } else {
                slot.label.backgroundColor = UIColor(white: 1, alpha: 0.16)
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
            guard let slot = slot(at: touch.location(in: panel)) else { continue }
            touchKeys[ObjectIdentifier(touch)] = slot.key.id
            let output = model.press(keyID: slot.key.id, now: touch.timestamp)
            apply(output)
            if output.showsPopup { showBubble(for: slot, touch: touch) }
        }
    }

    // A finger that slides off its key stays on that key until it lifts, as on Android
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, cancelled: true) }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
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
