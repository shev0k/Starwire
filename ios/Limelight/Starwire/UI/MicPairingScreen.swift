//
//  MicPairingScreen.swift
//  Starwire
//
//  Pairing with StarwireMicReceiver on a PC (docs/dev/mic-protocol.md, "Pairing"): pick the PC,
//  type the 16-character code its receiver shows under "Pair a device...", and Starwire and the
//  PC agree a key that's kept in this device's Keychain. Also shows and removes pairings.
//

import Network
import StarwireKit
import SwiftUI
import UIKit

/// Runs one pairing over UDP to each of the PC's home-network addresses.
enum MicPairingRunner {
    static func pair(code: String, host: PCItem, port: UInt16, deviceName: String) async -> Result<MicPairing, MicPairingFailure> {
        let addresses = [host.activeAddress, host.localAddress, host.manualAddress, host.ipv6Address]
            .compactMap { $0 }
            .compactMap { StarwireMicrophone.resolve($0) }
            .filter { HomeNetwork.contains($0) }
        let unique = Array(NSOrderedSet(array: addresses)) as? [String] ?? addresses
        guard !unique.isEmpty else { return .failure(.noAddress) }
        let client: MicPairingClient
        do {
            client = try MicPairingClient(typedCode: code, deviceName: deviceName,
                                          knownDeviceId: MicPairingStore.pairing(for: host.id)?.deviceId,
                                          computerUUID: host.id, computerName: host.name,
                                          pairedAt: Date().timeIntervalSince1970)
        } catch {
            return .failure(.badCode)
        }
        let queue = DispatchQueue(label: "io.github.shev0k.starwire.mic-pairing")
        let start = Date()
        return await withCheckedContinuation { continuation in
            var finished = false
            var connections: [NWConnection] = []
            func finish(_ outcome: MicPairingClient.Outcome) {
                guard !finished else { return }
                finished = true
                connections.forEach { $0.cancel() }
                switch outcome {
                case .paired(let pairing): continuation.resume(returning: .success(pairing))
                case .wrongCode: continuation.resume(returning: .failure(.wrongCode))
                case .notPairing: continuation.resume(returning: .failure(.notPairing))
                case .expired: continuation.resume(returning: .failure(.expired))
                case .noAnswer: continuation.resume(returning: .failure(.noAnswer))
                case .failed: continuation.resume(returning: .failure(.failed))
                }
            }
            func receive(_ connection: NWConnection) {
                connection.receiveMessage { data, _, _, error in
                    guard !finished else { return }
                    if let data, let outcome = client.receive(Array(data), now: Date().timeIntervalSince(start)) {
                        finish(outcome)
                        return
                    }
                    if error == nil {
                        receive(connection)
                    }
                }
            }
            func tick() {
                guard !finished else { return }
                let step = client.poll(now: Date().timeIntervalSince(start))
                if let outcome = step.outcome {
                    finish(outcome)
                    return
                }
                if step.send {
                    for connection in connections {
                        connection.send(content: Data(client.request), completion: .idempotent)
                    }
                }
                queue.asyncAfter(deadline: .now() + max(0.005, min(step.wait, 0.1))) { tick() }
            }
            queue.async {
                for address in unique {
                    guard let port = NWEndpoint.Port(rawValue: port) else { continue }
                    let connection = NWConnection(host: NWEndpoint.Host(address), port: port, using: .udp)
                    connection.start(queue: queue)
                    connections.append(connection)
                    receive(connection)
                }
                tick()
            }
        }
    }
}

enum MicPairingFailure: Error {
    case badCode, wrongCode, notPairing, expired, noAnswer, failed, noAddress

    var messageKey: String {
        switch self {
        case .badCode: return "ios_mic_pair_bad_code"
        case .wrongCode: return "ios_mic_pair_wrong_code"
        case .notPairing: return "ios_mic_pair_not_pairing"
        case .expired: return "ios_mic_pair_expired"
        case .noAnswer: return "ios_mic_pair_no_answer"
        case .failed: return "ios_mic_pair_failed"
        case .noAddress: return "ios_mic_pair_no_address"
        }
    }
}

struct MicPairingScreen: View {
    let hostID: String?
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var pairings: [MicPairing] = []
    @State private var code = ""

    var body: some View {
        ZStack {
            StarfieldBackground(paused: state.isStreaming)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: L("title_mic_pairing"))
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L("ios_mic_pair_help"))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(library.hosts.filter { hostID == nil || $0.id == hostID }) { host in
                            hostRow(host)
                        }
                        if library.hosts.isEmpty {
                            Text(L("ios_mic_pair_no_pcs"))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        Text(L("ios_mic_pair_security"))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .controllerBack("mic-pairing") { dismiss() }
        .onAppear { pairings = MicPairingStore.all() }
    }

    private func hostRow(_ host: PCItem) -> some View {
        let pairing = pairings.first { $0.computerUUID == host.id }
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.name)
                    .font(.headline)
                Text(pairing.map { L("ios_mic_paired_with", $0.receiverName.isEmpty ? host.name : $0.receiverName) }
                     ?? L("ios_mic_not_paired"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
            }
            Spacer()
            Button(pairing == nil ? L("ios_mic_pair") : L("ios_mic_pair_again")) { askCode(host) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("mic-pair-\(host.name)")
                .controllerFocusable("mic-pair-\(host.id)") { askCode(host) }
            if pairing != nil {
                Button(L("ios_mic_unpair"), role: .destructive) { unpair(host) }
                    .buttonStyle(.bordered)
                    .controllerFocusable("mic-unpair-\(host.id)") { unpair(host) }
            }
        }
        .padding(16)
        .frostedCard(cornerRadius: 18, padding: 0)
    }

    private func askCode(_ host: PCItem) {
        code = ""
        state.show(PanelContent(title: L("ios_mic_pair_with", host.name), message: L("ios_mic_pair_code_help"),
                                textField: ("2491-650N-2RBH-G690", Binding(get: { code }, set: { code = PairingCode.format($0) }),
                                            .asciiCapable),
                                buttons: [
                                    PanelButton(title: L("ios_mic_pair"), identifier: "mic-pair-confirm") { pair(host) },
                                    PanelButton(title: L("applist_menu_cancel"), role: .cancel),
                                ]))
    }

    private func pair(_ host: PCItem) {
        let store = StarwireSettings.store
        let portText: String = { if case .string(let v)? = store.value("text_vban_port") { return v } else { return "6980" } }()
        let port = UInt16(portText) ?? 6980
        state.busy = L("ios_mic_pairing")
        Task {
            let result = await MicPairingRunner.pair(code: code, host: host, port: port, deviceName: StarwireSettings.clientName)
            state.busy = nil
            switch result {
            case .success(let pairing):
                if MicPairingStore.save(pairing) {
                    pairings = MicPairingStore.all()
                    state.message(L("title_mic_pairing"), L("ios_mic_paired_with", pairing.receiverName.isEmpty ? host.name : pairing.receiverName))
                } else {
                    state.message(L("title_mic_pairing"), L("ios_mic_pair_not_saved"))
                }
            case .failure(let failure):
                state.message(L("title_mic_pairing"), L(failure.messageKey))
            }
        }
    }

    private func unpair(_ host: PCItem) {
        state.show(PanelContent(title: L("ios_mic_unpair"), message: L("ios_mic_unpair_help"), buttons: [
            PanelButton(title: L("ios_mic_unpair"), role: .destructive) {
                MicPairingStore.remove(host.id)
                pairings = MicPairingStore.all()
            },
            PanelButton(title: L("applist_menu_cancel"), role: .cancel),
        ]))
    }
}
