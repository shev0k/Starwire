//
//  SnapshotTests.swift
//  Starwire
//
//  Every screen of the SwiftUI app (phase 3), drawn on the simulator with the demo PC, in light
//  and dark, at the default and the largest text size, compared with the pictures in
//  ios/Tests/Snapshots/<iOS version>/<iPhone or iPad>/. They catch a screen that stops drawing or
//  whose layout breaks; small differences (the stars twinkle, the wordmark's colours move) are
//  allowed. The app keeps Starwire's dark look in light mode, as Android does, so the light
//  picture must match the dark one.
//
//  With no pictures for this iOS version (CI's simulator is older than the Mac's), the screens
//  are still drawn, so they must not crash, and the test is skipped rather than passed.
//  `mac.sh snapshots record` writes new pictures.
//

import StarwireKit
import SwiftUI
import UIKit
import XCTest
@testable import Starwire

@MainActor
final class SnapshotTests: XCTestCase {
    struct Size {
        let name: String
        let size: CGSize
        let horizontal: UIUserInterfaceSizeClass
    }

    private var record: Bool { ProcessInfo.processInfo.environment["STARWIRE_RECORD"] == "1" }
    private static let snapshots = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Snapshots")

    /// The sizes for this device: a full screen and, on iPad, a third of the screen in Split View
    private var sizes: [Size] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [Size(name: "landscape", size: CGSize(width: 1194, height: 834), horizontal: .regular),
                    Size(name: "split-third", size: CGSize(width: 375, height: 834), horizontal: .compact)]
        }
        return [Size(name: "portrait", size: CGSize(width: 393, height: 852), horizontal: .compact),
                Size(name: "landscape", size: CGSize(width: 852, height: 393), horizontal: .compact)]
    }

    private var folder: URL {
        let version = "iOS\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return Self.snapshots.appendingPathComponent(version).appendingPathComponent(device)
    }

    private func state() -> AppState {
        AppState(library: Library(backend: DemoLibraryBackend(running: "2")))
    }

    func testPCList() throws { try check("pc-list") { PCListView() } }
    func testGameScreen() throws { try check("game-screen") { GameScreenView(hostID: DemoMode.hostUUID) } }
    func testSettingsStream() throws { try check("settings-stream") { SettingsScreen(initialSection: "stream") } }
    func testSettingsSound() throws { try check("settings-sound") { SettingsScreen(initialSection: "sound") } }
    func testSettingsAbout() throws { try check("settings-about") { SettingsScreen(initialSection: "about") } }
    func testGameSettings() throws {
        try check("game-settings") { GameSettingsScreen(hostID: DemoMode.hostUUID, appID: DemoMode.apps()[0].id) }
    }
    func testAbout() throws { try check("about") { AboutScreen() } }
    func testLicences() throws { try check("licences") { LicencesScreen() } }
    func testMicPairing() throws { try check("mic-pairing") { MicPairingScreen(hostID: nil) } }
    func testAppMenuPanel() throws {
        try check("app-menu", panel: PanelContent(title: "Desktop", message: "Starfield Racer is running on the PC.", buttons: [
            PanelButton(title: L("applist_menu_resume")),
            PanelButton(title: L("applist_menu_quit_and_start"), role: .destructive),
            PanelButton(title: L("applist_menu_cancel"), role: .cancel),
        ])) { GameScreenView(hostID: DemoMode.hostUUID) }
    }

    // MARK: - Drawing and comparing

    private func check<Screen: View>(_ name: String, panel: PanelContent? = nil, @ViewBuilder _ screen: () -> Screen) throws {
        var missing: [String] = []
        for size in sizes {
            for large in [false, true] {
                var pictures: [UIImage] = []
                for style in [UIUserInterfaceStyle.dark, .light] {
                    let state = state()
                    state.panel = panel
                    let view = NavigationStack { screen() }
                        .overlay { if let panel = state.panel { PanelView(panel: panel) } }
                        .tint(.white)
                        .preferredColorScheme(.dark)
                        .environmentObject(state)
                        .environmentObject(state.library)
                        .environmentObject(state.focus)
                    pictures.append(draw(view, size: size, large: large, style: style))
                }
                let file = "\(name)-\(size.name)\(large ? "-largest-text" : "").jpg"
                let url = folder.appendingPathComponent(file)
                attach(pictures[0], name: file)
                // Starwire keeps its dark look in light mode
                XCTAssertLessThan(difference(pictures[0], pictures[1]), 0.02, "\(file): light differs from dark")
                if record {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try pictures[0].jpegData(compressionQuality: 0.7)!.write(to: url)
                    continue
                }
                guard let data = try? Data(contentsOf: url), let reference = UIImage(data: data) else {
                    missing.append(file)
                    continue
                }
                let diff = difference(pictures[0], reference)
                XCTAssertLessThan(diff, 0.02, "\(file) differs from its picture: \(Int(diff * 1000)) in 1000 pixels")
            }
        }
        if !missing.isEmpty {
            throw XCTSkip("no pictures for \(folder.lastPathComponent) \(folder.deletingLastPathComponent().lastPathComponent): \(missing.joined(separator: ", "))")
        }
    }

    /// The view at half size (the pictures in git stay small), after the screen settles
    private func draw<V: View>(_ view: V, size: Size, large: Bool, style: UIUserInterfaceStyle) -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.traitOverrides.horizontalSizeClass = size.horizontal
        controller.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
        let window = UIWindow(frame: CGRect(origin: .zero, size: size.size))
        // The system's appearance; the app's own preferredColorScheme decides over it, as in use
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.5
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size.size, format: format).image { _ in
            controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }

    /// The share of pixels whose colour differs by more than a little, 0 to 1
    private func difference(_ a: UIImage, _ b: UIImage) -> Double {
        guard let pa = pixels(a), let pb = pixels(b), pa.width == pb.width, pa.height == pb.height else { return 1 }
        var different = 0
        for i in stride(from: 0, to: pa.bytes.count, by: 4) {
            let d = max(abs(Int(pa.bytes[i]) - Int(pb.bytes[i])), abs(Int(pa.bytes[i + 1]) - Int(pb.bytes[i + 1])),
                        abs(Int(pa.bytes[i + 2]) - Int(pb.bytes[i + 2])))
            if d > 40 { different += 1 }
        }
        return Double(different) / Double(pa.bytes.count / 4)
    }

    private func pixels(_ image: UIImage) -> (width: Int, height: Int, bytes: [UInt8])? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, bytes)
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
