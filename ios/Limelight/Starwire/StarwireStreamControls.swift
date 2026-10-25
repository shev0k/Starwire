//
//  StarwireStreamControls.swift
//  Starwire
//
//  Everything Starwire puts over a stream for input: the stream menu and its floating button,
//  the on-screen controller, the full keyboard, and the input coordinator. The stream screen
//  (StreamFrameViewController, ObjC) makes one, forwards its life to it, and handles the few
//  menu actions only it can do (bitrate, stats, quit, disconnect, the system keyboard).
//

import StarwireKit
import UIKit

@objc(StarwireStreamControls)
final class StarwireStreamControls: NSObject {
    @objc let input: StarwireStreamInput
    private weak var view: UIView?
    private let title: String
    private let detail: String
    private var menu: StreamMenuView?
    private let floatingButton = FloatingMenuButton()
    private var floatingButtonShown: Bool
    private var onScreenControls: OnScreenControlsView?
    private var fullKeyboard: FullKeyboardView?

    // What only the stream screen can do
    @objc var onBitrate: (() -> Void)?
    @objc var onToggleStats: (() -> Void)?
    @objc var onSystemKeyboard: (() -> Void)?
    @objc var onQuit: (() -> Void)?
    @objc var onDisconnect: (() -> Void)?
    @objc var onNotice: ((String) -> Void)?
    @objc var present: ((UIViewController) -> Void)?
    /// Whether the statistics overlay shows, for the menu's switch
    @objc var statsShown = false

    /// The bitrate the PC applied, read out with the floating button ("70 Mbps")
    @objc var bitrateText: String? {
        get { floatingButton.accessibilityValue }
        set { floatingButton.accessibilityValue = newValue }
    }

    @objc static var bitrateChoicesMbps: [NSNumber] { StreamMenu.bitrateChoicesMbps.map { NSNumber(value: $0) } }

    @objc init(view: UIView, streamWidth: Int, streamHeight: Int, fps: Int, appName: String) {
        self.view = view
        title = appName
        detail = StreamMenu.detail(height: streamHeight, fps: fps)
        input = StarwireStreamInput(streamWidth: streamWidth, streamHeight: streamHeight, viewSize: view.bounds.size,
                                    scale: view.window?.screen.scale ?? UIScreen.main.scale)
        floatingButtonShown = StarwireSettings.store.bool("checkbox_enable_floating_button")
        super.init()
        input.onOpenMenu = { [weak self] in self?.openMenu() }
        input.onNotice = { [weak self] text in self?.onNotice?(text) }
        floatingButton.onTap = { [weak self] in self?.toggleMenu() }
        let gamepads = StarwireGamepads.shared
        gamepads.onOpenMenu = { [weak self] in self?.openMenu() }
        gamepads.onMenuButtons = { [weak self] buttons in self?.menu?.controllerPressed(buttons) }
        gamepads.onNotice = { [weak self] text in self?.onNotice?(text) }
    }

    /// The stream is up: show the controls the settings ask for.
    @objc func streamStarted(hostFeatureFlags: UInt32, pcUUID: String?, host: String, appID: Int) {
        input.streamStarted(hostFeatureFlags: hostFeatureFlags, pcUUID: pcUUID, host: host, appID: appID)
        guard let view else { return }
        if StarwireSettings.store.bool("checkbox_show_onscreen_controls") {
            setOnScreenControls(shown: true)
        }
        if floatingButtonShown {
            view.addSubview(floatingButton)
            floatingButton.place(in: view.bounds.size)
        }
        onNotice?("Hold \(StarwireGamepads.shared.menuTriggerTitle) to open menu")
    }

    /// The view changed size or turned.
    @objc func layout() {
        guard let view else { return }
        input.layout(viewSize: view.bounds.size, scale: view.window?.screen.scale ?? UIScreen.main.scale)
        floatingButton.place(in: view.bounds.size)
        if let osc = onScreenControls { osc.frame = view.bounds }
        if let keyboard = fullKeyboard { keyboard.frame = view.bounds }
        floatingButton.superview?.bringSubviewToFront(floatingButton)
    }

    /// Returns true when the PC's cursor was just shown again, so the caller waits a moment
    /// before stopping the connection.
    @objc func streamStopping() -> Bool {
        fullKeyboard?.releaseAll()
        menu?.removeFromSuperview()
        StarwireGamepads.shared.menuOpen = false
        return input.streamStopping()
    }

    // MARK: Menu

    @objc var menuShown: Bool { menu?.superview != nil }

    @objc func toggleMenu() {
        if menuShown { menu?.hide() } else { openMenu() }
    }

    @objc func openMenu() {
        guard let view, !menuShown else { return }
        let menu = StreamMenuView(title: title, detail: detail)
        menu.state = { [weak self] in self?.menuState() ?? StreamMenuState() }
        menu.onAction = { [weak self] action in self?.perform(action) }
        menu.onClose = { StarwireGamepads.shared.menuOpen = false }
        self.menu = menu
        menu.show(in: view)
        StarwireGamepads.shared.menuOpen = true
        // The floating button stays above the menu, so it can close it
        if floatingButton.superview != nil { view.bringSubviewToFront(floatingButton) }
        StarwireLog.info("Input: stream menu opened")
    }

    private func menuState() -> StreamMenuState {
        var state = StreamMenuState()
        state.fullKeyboardShown = fullKeyboard != nil
        state.mouseEmulation = StarwireGamepads.shared.mouseEmulationOn
        state.statsShown = statsShown
        state.panZoom = input.panZoomOn
        state.sensitivityOn = input.sensitivityOn
        state.sensitivityPercent = StarwireSettings.store.int("seekbar_touch_sensitivity")
        state.onScreenControlsShown = onScreenControls != nil
        state.floatingButtonShown = floatingButtonShown
        state.showFixHostCursor = input.offersHostCursorFix
        let storage = StarwireSettings.store.storage
        state.customCommands = CustomCommandsStore(storage: storage).commands
        state.importedShortcuts = ImportedShortcutsStore(storage: storage).load()
        return state
    }

    private func perform(_ action: StreamMenuAction) {
        StarwireLog.info("Input: menu \(action)")
        switch action {
        case .systemKeyboard: onSystemKeyboard?()
        case .toggleFullKeyboard: setFullKeyboard(shown: fullKeyboard == nil)
        case .toggleMouseEmulation: StarwireGamepads.shared.toggleMouseEmulation()
        case .toggleStats: onToggleStats?()
        case .guide: pressGuide()
        case .bitrate: onBitrate?()
        case .touchMode: chooseTouchMode()
        case .fixHostCursor: input.fixHostCursor()
        case .togglePanZoom: input.togglePanZoom()
        case .toggleSensitivity: input.toggleSensitivity()
        case .keys(let shortcut): input.send(shortcut)
        case .toggleOnScreenControls: setOnScreenControls(shown: onScreenControls == nil)
        case .editOnScreenControls:
            setOnScreenControls(shown: true)
            onScreenControls?.beginEditing()
        case .toggleFloatingButton: setFloatingButton(shown: !floatingButtonShown)
        case .customCommand(let command):
            input.run(command) { [weak self] after in self?.after(after) }
        case .manageShortcuts:
            if let presenter = topViewController() {
                presentShortcutsManager(from: presenter) { [weak self] in self?.menu?.reload() }
            }
        case .quit: onQuit?()
        case .disconnect: onDisconnect?()
        case .openPage, .back, .close: break
        }
    }

    private func after(_ action: CommandAfterAction) {
        switch action {
        case .none: break
        case .closeMenu: menu?.hide()
        case .disconnect: onDisconnect?()
        case .quit: onQuit?()
        case .sleep: onNotice?("Starwire can't put this device to sleep. iOS doesn't let apps do that.")
        }
    }

    /// Guide for 100 ms on the first controller, as Android's sendGuideButton
    private func pressGuide() {
        input.send([.controller(ControllerState(number: 0, activeMask: 1, buttons: GamepadButton.guide))])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.input.send([.controller(ControllerState(number: 0, activeMask: 1))])
        }
    }

    private func chooseTouchMode() {
        let sheet = UIAlertController(title: "Touch mode", message: nil, preferredStyle: .actionSheet)
        for (index, name) in StarwireStreamInput.touchModeTitles.enumerated() {
            let current = index == input.touchModeIndex
            sheet.addAction(UIAlertAction(title: current ? "\(name) (now)" : name, style: .default) { [weak self] _ in
                self?.input.touchModeIndex = index
                self?.onNotice?("Touch mode: \(name)")
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let view, let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.maxX - 240, y: view.bounds.midY, width: 1, height: 1)
        }
        present?(sheet)
    }

    /// The view controller on top, to present a sheet from
    private func topViewController() -> UIViewController? {
        var top = view?.window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: Overlays

    private func setOnScreenControls(shown: Bool) {
        guard let view else { return }
        if shown, onScreenControls == nil {
            let osc = OnScreenControlsView(frame: view.bounds) { [weak self] event in self?.input.send([event]) }
            view.addSubview(osc)
            onScreenControls = osc
        } else if !shown, let osc = onScreenControls {
            osc.endEditing(save: false)
            osc.removeFromSuperview()
            onScreenControls = nil
        }
        keepOnTop()
    }

    private func setFullKeyboard(shown: Bool) {
        guard let view else { return }
        if shown, fullKeyboard == nil {
            let keyboard = FullKeyboardView { [weak self] event in self?.input.send([event]) }
            keyboard.frame = view.bounds
            keyboard.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            keyboard.onHide = { [weak self] in self?.setFullKeyboard(shown: false) }
            view.addSubview(keyboard)
            fullKeyboard = keyboard
        } else if !shown, let keyboard = fullKeyboard {
            keyboard.releaseAll()
            keyboard.removeFromSuperview()
            fullKeyboard = nil
        }
        keepOnTop()
    }

    private func setFloatingButton(shown: Bool) {
        floatingButtonShown = shown
        if shown, let view {
            view.addSubview(floatingButton)
            floatingButton.place(in: view.bounds.size)
        } else {
            floatingButton.removeFromSuperview()
        }
    }

    /// The menu over everything, the floating button over the menu
    private func keepOnTop() {
        guard let view else { return }
        if let menu, menu.superview == view { view.bringSubviewToFront(menu) }
        if floatingButton.superview == view { view.bringSubviewToFront(floatingButton) }
    }
}
