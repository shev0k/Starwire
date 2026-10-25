//
//  ControllerFocus.swift
//  Starwire
//
//  Controller navigation of the app's screens: the d-pad or left stick moves a highlight between
//  buttons, A presses, B goes back, and Menu (or Y) opens a tile's menu. iOS has no public way to
//  move its own focus in a direction, so each button reports its frame and StarwireKit's
//  SpatialNavigation picks the next one. Controllers are read by polling while no stream runs,
//  so the stream's own controller handlers are never replaced.
//

import Combine
import GameController
import StarwireKit
import SwiftUI

@MainActor
final class ControllerFocus: ObservableObject {
    struct Target {
        var frame: CGRect
        var scope: String
        var action: () -> Void
        var menu: (() -> Void)?
    }

    @Published private(set) var focused: String?
    /// True once a controller has been used here: the highlight shows only then
    @Published private(set) var showsHighlight = false

    private var targets: [String: Target] = [:]
    /// Modal panels on top take the controller; the last one is active
    private var scopes: [String] = ["screen"]
    /// What B does on the current screen, newest last
    private var backActions: [(id: String, action: () -> Void)] = []
    private var timer: Timer?
    private var repeater = DirectionRepeater()
    private var wasPressed: [String: Bool] = [:]
    private var start = Date()
    var isPaused = false {
        didSet { updateTimer() }
    }

    init() {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateTimer() }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateTimer() }
        }
        updateTimer()
    }

    // MARK: - Targets

    func register(_ id: String, frame: CGRect, scope: String, action: @escaping () -> Void, menu: (() -> Void)?) {
        targets[id] = Target(frame: frame, scope: scope, action: action, menu: menu)
    }

    func unregister(_ id: String) {
        targets[id] = nil
        if focused == id {
            focused = nil
        }
    }

    func pushScope(_ scope: String) {
        scopes.append(scope)
        focused = nil
        if showsHighlight {
            move(.down)
        }
    }

    func popScope(_ scope: String) {
        scopes.removeAll { $0 == scope }
        focused = nil
    }

    func pushBack(id: String, _ action: @escaping () -> Void) {
        backActions.removeAll { $0.id == id }
        backActions.append((id, action))
    }

    func popBack(id: String) {
        backActions.removeAll { $0.id == id }
    }

    func focus(_ id: String) {
        focused = id
    }

    private var activeTargets: [(id: String, frame: SpatialNavigation.Rect)] {
        let scope = scopes.last ?? "screen"
        return targets.filter { $0.value.scope == scope }
            .sorted { $0.key < $1.key }
            .map { ($0.key, SpatialNavigation.Rect(x: $0.value.frame.minX, y: $0.value.frame.minY,
                                                   width: $0.value.frame.width, height: $0.value.frame.height)) }
    }

    func move(_ direction: SpatialNavigation.Direction) {
        showsHighlight = true
        let current = focused.flatMap { targets[$0] != nil ? $0 : nil }
        if let next = SpatialNavigation.next(from: current, direction: direction, targets: activeTargets) {
            focused = next
        }
    }

    func activate() {
        showsHighlight = true
        guard let focused, let target = targets[focused] else {
            move(.down)
            return
        }
        target.action()
    }

    func openMenu() {
        guard let focused, let menu = targets[focused]?.menu else { return }
        menu()
    }

    func back() {
        backActions.last?.action()
    }

    // MARK: - Reading the controller

    private func updateTimer() {
        let wanted = !isPaused && !GCController.controllers().isEmpty
        if wanted && timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
        } else if !wanted {
            timer?.invalidate()
            timer = nil
        }
    }

    private func pressed(_ name: String, _ isPressed: Bool) -> Bool {
        let was = wasPressed[name] ?? false
        wasPressed[name] = isPressed
        return isPressed && !was
    }

    private func poll() {
        guard !isPaused, let pad = (GCController.current ?? GCController.controllers().first)?.extendedGamepad else {
            return
        }
        let now = Date().timeIntervalSince(start)
        let dpad = pad.dpad
        let stick = pad.leftThumbstick
        let x = abs(dpad.xAxis.value) > abs(stick.xAxis.value) ? dpad.xAxis.value : stick.xAxis.value
        let y = abs(dpad.yAxis.value) > abs(stick.yAxis.value) ? dpad.yAxis.value : stick.yAxis.value
        if let direction = repeater.update(SpatialNavigation.direction(x: Double(x), y: Double(y)), now: now) {
            move(direction)
        }
        if pressed("a", pad.buttonA.isPressed) {
            activate()
        }
        if pressed("b", pad.buttonB.isPressed) {
            back()
        }
        if pressed("menu", pad.buttonMenu.isPressed) || pressed("y", pad.buttonY.isPressed) {
            openMenu()
        }
    }
}

private struct ControllerScopeKey: EnvironmentKey {
    static let defaultValue = "screen"
}

extension EnvironmentValues {
    /// The panel a button belongs to, for controller navigation
    var controllerScope: String {
        get { self[ControllerScopeKey.self] }
        set { self[ControllerScopeKey.self] = newValue }
    }
}

/// Makes a view reachable with a controller: it reports its frame, shows a ring when highlighted,
/// and runs `action` on A (and `menu` on Menu or Y).
struct ControllerFocusable: ViewModifier {
    let id: String
    var cornerRadius: CGFloat = 14
    let action: () -> Void
    var menu: (() -> Void)?
    @EnvironmentObject private var focus: ControllerFocus
    @Environment(\.controllerScope) private var scope

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius + 4)
                    .strokeBorder(Color.white, lineWidth: 3)
                    .padding(-5)
                    .opacity(focus.showsHighlight && focus.focused == id ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    Color.clear
                        .onAppear { focus.register(id, frame: frame, scope: scope, action: action, menu: menu) }
                        .onChange(of: frame) { _, new in
                            focus.register(id, frame: new, scope: scope, action: action, menu: menu)
                        }
                }
            }
            .onDisappear { focus.unregister(id) }
    }
}

extension View {
    func controllerFocusable(_ id: String, cornerRadius: CGFloat = 14, menu: (() -> Void)? = nil,
                             action: @escaping () -> Void) -> some View {
        modifier(ControllerFocusable(id: id, cornerRadius: cornerRadius, action: action, menu: menu))
    }

    /// B on a controller runs `action` while this view is showing.
    func controllerBack(_ id: String, _ action: @escaping () -> Void) -> some View {
        modifier(ControllerBack(id: id, action: action))
    }
}

private struct ControllerBack: ViewModifier {
    let id: String
    let action: () -> Void
    @EnvironmentObject private var focus: ControllerFocus

    func body(content: Content) -> some View {
        content
            .onAppear { focus.pushBack(id: id, action) }
            .onDisappear { focus.popBack(id: id) }
    }
}
