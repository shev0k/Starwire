//
//  Library.swift
//  Starwire
//
//  The PCs and their games as the SwiftUI screens see them. The screens talk only to `Library`,
//  which talks to a backend: the real one over moonlight-ios's core (StarwireHostLibraryFacade),
//  or the demo one built on StarwireKit's DemoMode, which the snapshot tests and the demo mode
//  use. Nothing in a view knows which it has.
//

import Foundation
import StarwireKit
import SwiftUI
import UIKit

/// One app on a PC.
struct GameItem: Identifiable, Equatable {
    var id: String
    var name: String
    var hdrSupported: Bool
    var hidden: Bool
    /// The cover art's file, when the PC sent one
    var coverPath: String?
    var kind: HostApp.Kind

    var isControlTile: Bool { kind != .game }
}

/// One saved PC.
struct PCItem: Identifiable, Equatable {
    enum Status: Equatable {
        case unknown, online, offline
    }

    enum Pairing: Equatable {
        case unknown, paired, unpaired
    }

    var id: String
    var name: String
    var status: Status
    var pairing: Pairing
    var activeAddress: String?
    var localAddress: String?
    var externalAddress: String?
    var ipv6Address: String?
    var manualAddress: String?
    var macAddress: String?
    var runningAppID: String?
    var httpsPort: Int
    var canSleep: Bool
    var games: [GameItem]

    var runningGame: GameItem? {
        guard let runningAppID else { return nil }
        return games.first { $0.id == runningAppID }
    }

    var isPaired: Bool { pairing == .paired }
}

/// What a PC refresh found.
enum RefreshResult: Equatable {
    case ok
    case needsPairing
    case failed(String)
}

/// Where the library's PCs come from.
protocol LibraryBackend: AnyObject {
    /// Called on the main queue when anything changes
    var onChange: (() -> Void)? { get set }
    var isDemo: Bool { get }
    func hosts() -> [PCItem]
    func startDiscovery()
    func stopDiscovery()
    func addHost(address: String) async -> String?
    func removeHost(_ id: String)
    func refresh(_ id: String) async -> RefreshResult
    func pair(_ id: String, showPIN: @escaping (String) -> Void) async -> String?
    func cancelPairing()
    func quitApp(on id: String) async -> String?
    func setHidden(_ hidden: Bool, appID: String, on id: String)
    func wake(_ id: String) -> String
    /// The ports the network blocks: "" for none, nil when the test couldn't run
    func testNetwork() async -> String?
    func sleepPC(_ id: String) async -> String?
    /// The stream screen. `onFinished` runs when it closes.
    func streamViewController(appID: String, on id: String, onFinished: @escaping () -> Void) -> UIViewController?
    func takePendingShortcutHost() -> String?
}

@MainActor
final class Library: ObservableObject {
    @Published private(set) var hosts: [PCItem] = []
    let backend: LibraryBackend

    init(backend: LibraryBackend) {
        self.backend = backend
        hosts = backend.hosts()
        backend.onChange = { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        let fresh = backend.hosts()
        if fresh != hosts {
            hosts = fresh
        }
    }

    func host(_ id: String) -> PCItem? {
        hosts.first { $0.id == id }
    }
}

// MARK: - The real PCs

final class LiveLibraryBackend: LibraryBackend {
    private let facade = StarwireHostLibraryFacade()
    var isDemo: Bool { false }

    var onChange: (() -> Void)? {
        didSet { facade.onChange = onChange }
    }

    func hosts() -> [PCItem] {
        facade.hosts().map { snapshot in
            PCItem(id: snapshot.uuid, name: snapshot.name,
                   status: snapshot.status == .online ? .online : snapshot.status == .offline ? .offline : .unknown,
                   pairing: snapshot.pairing == .paired ? .paired : snapshot.pairing == .unpaired ? .unpaired : .unknown,
                   activeAddress: snapshot.activeAddress, localAddress: snapshot.localAddress,
                   externalAddress: snapshot.externalAddress, ipv6Address: snapshot.ipv6Address,
                   manualAddress: snapshot.manualAddress, macAddress: snapshot.macAddress,
                   runningAppID: snapshot.runningAppID, httpsPort: Int(snapshot.httpsPort), canSleep: snapshot.canSleep,
                   games: snapshot.apps.map { app in
                       GameItem(id: app.appID, name: app.name, hdrSupported: app.hdrSupported, hidden: app.hidden,
                                coverPath: app.boxArtPath, kind: HostApp.kind(id: app.appID, uuid: nil))
                   })
        }
    }

    func startDiscovery() { facade.startDiscovery() }
    func stopDiscovery() { facade.stopDiscovery() }

    func addHost(address: String) async -> String? {
        await withCheckedContinuation { continuation in
            facade.addHost(withAddress: address) { continuation.resume(returning: $0) }
        }
    }

    func removeHost(_ id: String) { facade.removeHost(id) }

    func refresh(_ id: String) async -> RefreshResult {
        await withCheckedContinuation { continuation in
            facade.refreshHost(id) { error, needsPairing in
                if let error {
                    continuation.resume(returning: .failed(error))
                } else {
                    continuation.resume(returning: needsPairing ? .needsPairing : .ok)
                }
            }
        }
    }

    func pair(_ id: String, showPIN: @escaping (String) -> Void) async -> String? {
        await withCheckedContinuation { continuation in
            facade.pairHost(id, showPIN: showPIN) { continuation.resume(returning: $0) }
        }
    }

    func cancelPairing() { facade.cancelPairing() }

    func quitApp(on id: String) async -> String? {
        await withCheckedContinuation { continuation in
            facade.quitApp(onHost: id) { continuation.resume(returning: $0) }
        }
    }

    func setHidden(_ hidden: Bool, appID: String, on id: String) {
        facade.setApp(appID, hidden: hidden, onHost: id)
    }

    func wake(_ id: String) -> String { facade.wakeHost(id) }

    func testNetwork() async -> String? {
        await withCheckedContinuation { continuation in
            StarwireHostLibraryFacade.testNetwork { continuation.resume(returning: $0) }
        }
    }

    func sleepPC(_ id: String) async -> String? {
        guard let host = facade.hosts().first(where: { $0.uuid == id }), let address = host.activeAddress,
              let actions = StarwireHostActions(address: address, httpsPort: Int(host.httpsPort), serverCert: host.serverCert) else {
            return L("ios_pc_sleep_failed")
        }
        return await withCheckedContinuation { continuation in
            actions.sleepPC { continuation.resume(returning: $0) }
        }
    }

    func streamViewController(appID: String, on id: String, onFinished: @escaping () -> Void) -> UIViewController? {
        facade.streamViewController(forApp: appID, onHost: id, onFinished: onFinished)
    }

    func takePendingShortcutHost() -> String? { facade.takePendingShortcutHost() }
}

// MARK: - The demo PC

/// StarwireKit's demo PC, for the demo mode and the snapshot tests. Streams show the demo's
/// moving test picture.
final class DemoLibraryBackend: LibraryBackend {
    var onChange: (() -> Void)?
    var isDemo: Bool { true }
    private var removed = false
    private var hiddenApps: Set<String> = []
    private var running: String?

    /// `running` starts the demo with that app running on its PC (for the snapshot tests).
    init(running: String? = nil) {
        self.running = running
    }

    func hosts() -> [PCItem] {
        guard !removed else { return [] }
        let games = DemoMode.apps().map { app in
            GameItem(id: app.id, name: app.name, hdrSupported: app.hdrSupported, hidden: hiddenApps.contains(app.id),
                     coverPath: nil, kind: app.kind)
        }
        return [PCItem(id: DemoMode.hostUUID, name: DemoMode.hostName, status: .online, pairing: .paired,
                       activeAddress: "demo", localAddress: nil, externalAddress: nil, ipv6Address: nil,
                       manualAddress: nil, macAddress: nil, runningAppID: running, httpsPort: 47984, canSleep: false,
                       games: games)]
    }

    func startDiscovery() {}
    func stopDiscovery() {}
    func addHost(address: String) async -> String? { L("ios_demo_no_pc") }
    func removeHost(_ id: String) {
        removed = true
        onChange?()
    }
    func refresh(_ id: String) async -> RefreshResult { .ok }
    func pair(_ id: String, showPIN: @escaping (String) -> Void) async -> String? { nil }
    func cancelPairing() {}
    func quitApp(on id: String) async -> String? {
        running = nil
        onChange?()
        return nil
    }
    func setHidden(_ hidden: Bool, appID: String, on id: String) {
        if hidden { hiddenApps.insert(appID) } else { hiddenApps.remove(appID) }
        onChange?()
    }
    func wake(_ id: String) -> String { L("ios_demo_no_pc") }
    func testNetwork() async -> String? { "" }
    func sleepPC(_ id: String) async -> String? { L("ios_demo_no_pc") }

    func streamViewController(appID: String, on id: String, onFinished: @escaping () -> Void) -> UIViewController? {
        guard let app = DemoMode.apps().first(where: { $0.id == appID }) else { return nil }
        running = app.isControl ? running : app.id
        let controller = UIHostingController(rootView: DemoStreamScreen(host: DemoMode.hostService(), app: app,
                                                                       onClose: onFinished))
        controller.modalPresentationStyle = .fullScreen
        return controller
    }

    func takePendingShortcutHost() -> String? { nil }
}

/// A string from the String Catalog, by Android's resource name (or an iOS-only `ios_` name from
/// ios/Strings/strings-ios.xml). The catalog is made from those files by
/// ios/scripts/strings-to-xcstrings.py.
func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
}

/// The same with `%@` / `%d` values put in.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: arguments)
}
