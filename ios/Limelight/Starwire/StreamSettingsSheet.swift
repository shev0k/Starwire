//
//  StreamSettingsSheet.swift
//  Starwire
//
//  The stream menu's More settings: the settings screen over the stream, with only the sections
//  that take effect during a stream (touch, keyboard, the menu and its button, the on-screen
//  controls). The rest wait for the next stream, so they aren't offered here.
//

import StarwireKit
import SwiftUI
import UIKit

enum StreamSettingsSheet {
    static let sections = ["touch", "keyboard", "menu", "onscreen"]

    @MainActor
    static func make(onChange: @escaping () -> Void) -> UIViewController {
        let state = AppState.current ?? AppState(library: Library(backend: DemoLibraryBackend()))
        weak var controller: UIViewController?
        let screen = NavigationStack {
            SettingsScreen(initialSection: sections[0], only: sections) {
                onChange()
                controller?.dismiss(animated: true)
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .environmentObject(state)
        .environmentObject(state.library)
        .environmentObject(state.focus)
        let host = UIHostingController(rootView: screen)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        controller = host
        return host
    }
}
