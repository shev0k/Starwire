//
//  StarwireMicrophone.swift
//  Starwire
//
//  The microphone to the PC (phase 6), as Starwire for Android sends it: to StarwireMicReceiver
//  on the PC (windows/), encrypted with SWMC (docs/dev/mic-protocol.md) or as plain VBAN when the
//  user chose "Not encrypted". Captured by AVAudioEngine with Apple's voice processing (echo and
//  noise cancelling), turned into 48 kHz mono 16-bit samples, packed into 256-sample VBAN packets
//  by StarwireKit's VbanPacketizer, sealed by StarwireKit's SwmcSender, and sent over UDP.
//
//  It only sends to a home-network or private VPN address (StarwireKit's HomeNetwork). That is
//  a filter; the security is the pairing and the encryption. Pairings are kept in the Keychain,
//  on this device only, and never exported.
//

import AVFoundation
import Foundation
import Network
import Security
import StarwireKit
import UIKit

/// The microphone pairings, one Keychain item per PC.
enum MicPairingStore {
    static let service = "io.github.shev0k.starwire.mic-pairing"

    private static func query(_ uuid: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let uuid {
            query[kSecAttrAccount as String] = uuid
        }
        return query
    }

    static func pairing(for uuid: String) -> MicPairing? {
        var query = query(uuid)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let pairing = try? JSONDecoder().decode(MicPairing.self, from: data), pairing.isValid else {
            return nil
        }
        return pairing
    }

    static func all() -> [MicPairing] {
        var query = query(nil)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [Data] else {
            return []
        }
        return items.compactMap { try? JSONDecoder().decode(MicPairing.self, from: $0) }.filter(\.isValid)
    }

    @discardableResult
    static func save(_ pairing: MicPairing) -> Bool {
        guard let data = try? JSONEncoder().encode(pairing) else { return false }
        SecItemDelete(query(pairing.computerUUID) as CFDictionary)
        var item = query(pairing.computerUUID)
        item[kSecValueData as String] = data
        // This device only: not in iCloud Keychain, not restored to another device
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove(_ uuid: String) {
        SecItemDelete(query(uuid) as CFDictionary)
    }
}

/// Sends the microphone during a stream. The app tells it the PC before the stream starts, then
/// starts and stops it with the stream.
@objc(StarwireMicrophone)
final class StarwireMicrophone: NSObject {
    @objc static let shared = StarwireMicrophone()

    private let queue = DispatchQueue(label: "io.github.shev0k.starwire.mic")
    private var hostUUID: String?
    private var address: String?
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var connection: NWConnection?
    private var sender: SwmcSender?
    private var packetizer = VbanPacketizer(streamName: "Stream1")
    private var timer: DispatchSourceTimer?
    private var shownStatuses: Set<String> = []
    private let clockStart = Date()
    private var running = false

    /// Status to show the user, told on the main queue
    var onMessage: ((String) -> Void)?

    private var now: TimeInterval { Date().timeIntervalSince(clockStart) }

    /// Before a stream: which PC it is and its address.
    func prepare(hostUUID: String, address: String?) {
        queue.async {
            self.hostUUID = hostUUID
            self.address = address
        }
    }

    /// The stream started: start the microphone if the settings ask for it.
    @objc func streamStarted() {
        let settings = StarwireSettings.store
        guard case .bool(true)? = settings.value("checkbox_enable_microphone") else { return }
        let target: String = { if case .string(let v)? = settings.value("list_microphone_target") { return v } else { return "starwire" } }()
        guard target == "starwire" || target == "vban" else {
            StarwireLog.info("Microphone: Vibeshine has no in-stream microphone; not sending")
            return
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            guard granted else {
                self.tell(L("ios_mic_no_permission"))
                return
            }
            self.queue.async { self.start(encrypted: target == "starwire", settings: settings) }
        }
    }

    /// The stream ended.
    @objc func streamStopped() {
        queue.async { self.stop() }
    }

    private func start(encrypted: Bool, settings: SettingsStore) {
        stop()
        shownStatuses = []
        guard let hostUUID, let address, let numeric = Self.resolve(address) else {
            tell(L("microphone_stream_start_failed"))
            return
        }
        guard HomeNetwork.contains(numeric) else {
            StarwireLog.info("Microphone: not sending to a PC that isn't on the home network")
            tell(L(encrypted ? "microphone_secure_not_home" : "microphone_vban_not_home"))
            return
        }
        let portText: String = { if case .string(let v)? = settings.value("text_vban_port") { return v } else { return "6980" } }()
        guard let port = NWEndpoint.Port(portText) else {
            tell(L("microphone_stream_start_failed"))
            return
        }
        if encrypted {
            guard let pairing = MicPairingStore.pairing(for: hostUUID) else {
                StarwireLog.info("Microphone: Starwire isn't paired with this PC's receiver")
                tell(L("microphone_secure_not_paired"))
                return
            }
            let sender = SwmcSender(deviceId: pairing.deviceId, pairKey: pairing.key)
            sender.onStatus = { [weak self] status in self?.statusChanged(status) }
            self.sender = sender
            // The receiver ignores the name inside: pairing says who sent it
            packetizer = VbanPacketizer(streamName: "Stream1")
        } else {
            sender = nil
            let name: String = { if case .string(let v)? = settings.value("text_vban_stream_name") { return v } else { return "Stream1" } }()
            packetizer = VbanPacketizer(streamName: name)
        }

        let connection = NWConnection(host: NWEndpoint.Host(numeric), port: port, using: .udp)
        self.connection = connection
        connection.start(queue: queue)
        if sender != nil {
            receive(on: connection)
            sender?.start(now: now)
            startTimer()
        }
        running = true
        let device: String = { if case .string(let v)? = settings.value("list_microphone_device") { return v } else { return "" } }()
        do {
            try startCapture(preferredInput: device)
            StarwireLog.info("Microphone: sending to the PC's receiver on port \(portText), \(encrypted ? "encrypted" : "not encrypted")")
        } catch {
            StarwireLog.info("Microphone: capture failed: \(error)")
            tell(L("microphone_stream_start_failed"))
            stop()
        }
    }

    private func stop() {
        guard running || engine != nil || connection != nil else { return }
        running = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        timer?.cancel()
        timer = nil
        connection?.cancel()
        connection = nil
        if let sender {
            StarwireLog.info("Microphone: sent \(sender.sent) packets, dropped \(sender.dropped) while waiting for the receiver")
        }
        sender = nil
    }

    // MARK: - Capture

    private func startCapture(preferredInput uid: String) throws {
        let session = AVAudioSession.sharedInstance()
        // The stream keeps playing: play and record, mixed with others as the stream's audio is
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
        try session.setPreferredSampleRate(48_000)
        if !uid.isEmpty, uid != "0", let input = session.availableInputs?.first(where: { $0.uid == uid }) {
            try session.setPreferredInput(input)
        }
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Apple's echo and noise cancelling
        try input.setVoiceProcessingEnabled(true)
        let inputFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw NSError(domain: "StarwireMicrophone", code: 1)
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.captured(buffer, target: target)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func captured(_ buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 48_000 / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var given = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let samples = out.int16ChannelData?[0] else { return }
        let pcm = Array(UnsafeBufferPointer(start: samples, count: Int(out.frameLength)))
        queue.async { self.send(pcm) }
    }

    private func send(_ pcm: [Int16]) {
        guard running, let connection else { return }
        for packet in packetizer.write(pcm) {
            if let sender {
                if let sealed = sender.seal(vban: packet) {
                    connection.send(content: Data(sealed), completion: .idempotent)
                }
            } else {
                connection.send(content: Data(packet), completion: .idempotent)
            }
        }
    }

    // MARK: - SWMC's handshake

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(25))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    private func poll() {
        guard let sender, let connection else { return }
        for packet in sender.poll(now: now).packets {
            connection.send(content: Data(packet), completion: .idempotent)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, self.connection === connection else { return }
            if let data {
                // Anyone can send here: the MACs decide what counts
                self.sender?.receive(Array(data), now: self.now)
                self.poll()
            }
            if error == nil {
                self.receive(on: connection)
            }
        }
    }

    private func statusChanged(_ status: SwmcSender.Status) {
        let key: String
        switch status {
        case .noAnswer: key = "microphone_secure_no_answer"
        case .busy: key = "microphone_secure_busy"
        case .noOutput: key = "microphone_secure_no_output"
        case .sending:
            StarwireLog.info("Microphone: encrypted session started")
            return
        case .connecting:
            return
        }
        StarwireLog.info("Microphone: \(status)")
        // Each problem once per stream, as on Android
        if shownStatuses.insert(key).inserted {
            tell(L(key))
        }
    }

    private func tell(_ text: String) {
        DispatchQueue.main.async {
            if let onMessage = self.onMessage {
                onMessage(text)
            } else {
                StarwireToast.show(text)
            }
        }
    }

    /// The PC's address as numbers, looked up if it's a name
    static func resolve(_ host: String) -> String? {
        let bare = host.hasPrefix("[") ? String(host.dropFirst().prefix { $0 != "]" }) : host
        if HomeNetwork.parseIPv4(bare) != nil || HomeNetwork.parseIPv6(bare) != nil {
            return bare
        }
        var hints = addrinfo()
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(bare, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0,
                          NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: buffer)
    }
}

/// A short message at the top of the screen, as Android's toasts.
enum StarwireToast {
    static func show(_ text: String) {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let label = PaddedToastLabel()
        label.text = text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.layer.cornerRadius = 14
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            label.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 16),
            label.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, multiplier: 0.8),
        ])
        UIAccessibility.post(notification: .announcement, argument: text)
        UIView.animate(withDuration: 0.3, delay: 3.5, options: []) {
            label.alpha = 0
        } completion: { _ in
            label.removeFromSuperview()
        }
    }

    private final class PaddedToastLabel: UILabel {
        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.insetBy(dx: 14, dy: 8))
        }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(width: size.width + 28, height: size.height + 16)
        }
    }
}
