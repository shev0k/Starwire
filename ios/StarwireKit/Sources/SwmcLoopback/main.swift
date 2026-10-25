// swmc-loopback: StarwireKit's microphone code against the real Windows receiver, on this PC's
// loopback. It pairs with the code the receiver printed (MicPairingClient), starts a session
// (SwmcSender), streams a quiet tone in real time in 256-sample VBAN packets (VbanPacketizer),
// then sends a replayed packet and a plain VBAN packet, which must both be refused. Last it
// prints one SENT line with what the receiver's summary should say. ios/scripts/mic-loopback.ps1
// builds the receiver into a temporary folder and runs this against it on a test port.
//
//   swmc-loopback <port> <code> <packets>
//
// Not part of the app: only the StarwireKit library is linked into it.

import Foundation
import StarwireKit
#if os(Windows)
import WinSDK
#elseif canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// A UDP socket bound to 127.0.0.1, sending to one port there.
final class LoopbackSocket {
    #if os(Windows)
    private var socketHandle: SOCKET
    #else
    private var socketHandle: Int32
    #endif
    private var peer = sockaddr_in()

    init(port: UInt16) {
        #if os(Windows)
        var data = WSADATA()
        _ = WSAStartup(0x0202, &data)
        socketHandle = socket(AF_INET, Int32(SOCK_DGRAM), Int32(IPPROTO_UDP.rawValue))
        #else
        socketHandle = socket(AF_INET, Int32(SOCK_DGRAM), Int32(IPPROTO_UDP))
        #endif
        var local = sockaddr_in()
        local.sin_family = ADDRESS_FAMILY(AF_INET)
        local.sin_port = 0
        local.sin_addr = Self.loopback()
        _ = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketHandle, $0, Int32(MemoryLayout<sockaddr_in>.size)) }
        }
        peer.sin_family = ADDRESS_FAMILY(AF_INET)
        peer.sin_port = port.bigEndian
        peer.sin_addr = Self.loopback()
    }

    private static func loopback() -> in_addr {
        var address = in_addr()
        _ = inet_pton(AF_INET, "127.0.0.1", &address)
        return address
    }

    func send(_ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) { pointer in
                _ = withUnsafePointer(to: &peer) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(socketHandle, pointer, Int32(bytes.count), 0, $0, Int32(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    /// One datagram within `milliseconds`, or nil.
    func receive(milliseconds: Int) -> [UInt8]? {
        #if os(Windows)
        var timeout = DWORD(max(1, milliseconds))
        _ = withUnsafePointer(to: &timeout) {
            $0.withMemoryRebound(to: CChar.self, capacity: 4) {
                setsockopt(socketHandle, SOL_SOCKET, SO_RCVTIMEO, $0, Int32(MemoryLayout<DWORD>.size))
            }
        }
        #else
        var timeout = timeval(tv_sec: milliseconds / 1000, tv_usec: Int32(milliseconds % 1000) * 1000)
        _ = setsockopt(socketHandle, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        #endif
        var buffer = [CChar](repeating: 0, count: 2048)
        let count = buffer.withUnsafeMutableBufferPointer { recv(socketHandle, $0.baseAddress, Int32($0.count), 0) }
        guard count > 0 else { return nil }
        return buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }
    }
}

func fail(_ message: String) -> Never {
    print("FAIL \(message)")
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let port = UInt16(arguments[1]), let packets = Int(arguments[3]) else {
    fail("usage: swmc-loopback <port> <code> <packets>")
}
let udp = LoopbackSocket(port: port)
let start = Date()
func now() -> TimeInterval { Date().timeIntervalSince(start) }

// Pairing, exactly as the app does it
let client: MicPairingClient
do {
    client = try MicPairingClient(typedCode: arguments[2], deviceName: "StarwireKit loopback", knownDeviceId: nil,
                                  computerUUID: "loopback", computerName: "This PC", pairedAt: 0)
} catch {
    fail("the code doesn't read as 16 characters")
}
var pairing: MicPairing?
pairingLoop: while true {
    let step = client.poll(now: now())
    if let outcome = step.outcome {
        guard case .paired(let made) = outcome else { fail("pairing: \(outcome)") }
        pairing = made
        break
    }
    if step.send { udp.send(client.request) }
    if let datagram = udp.receive(milliseconds: Int(step.wait * 1000)), let outcome = client.receive(datagram, now: now()) {
        guard case .paired(let made) = outcome else { fail("pairing: \(outcome)") }
        pairing = made
        break pairingLoop
    }
}
guard let pairing else { fail("no pairing") }
print("PASS paired with \(pairing.receiverName)")

// A session
let sender = SwmcSender(deviceId: pairing.deviceId, pairKey: pairing.key)
var statuses: [SwmcSender.Status] = []
sender.onStatus = { statuses.append($0) }
sender.start(now: now())
while statuses.last == nil || statuses.last == .connecting {
    if now() > 10 { fail("no HELLO_ACK: \(statuses)") }
    let (out, wait) = sender.poll(now: now())
    out.forEach(udp.send)
    if let datagram = udp.receive(milliseconds: max(5, Int(wait * 1000))) {
        sender.receive(datagram, now: now())
    }
}
print("PASS session started, status \(statuses.last!)")

// The stream, in real time: 256 samples at 48 kHz every 5.333 ms
var packetizer = VbanPacketizer(streamName: "Stream1")
var hash: UInt64 = 0xcbf2_9ce4_8422_2325
var sealedPackets: [[UInt8]] = []
let streamStart = now()
for i in 0..<packets {
    // A quiet 1 kHz tone
    let samples = (0..<256).map { n -> Int16 in
        Int16(200 * sin(2 * Double.pi * 1000 * Double(i * 256 + n) / 48_000))
    }
    for vban in packetizer.write(samples) {
        for byte in vban[28...] {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        guard let sealed = sender.seal(vban: vban) else { fail("packet \(i) wasn't sealed") }
        udp.send(sealed)
        sealedPackets.append(sealed)
    }
    let (out, _) = sender.poll(now: now())
    out.forEach(udp.send)
    while now() < streamStart + Double(i + 1) * 256 / 48_000 {
        if let datagram = udp.receive(milliseconds: 1) {
            sender.receive(datagram, now: now())
        }
    }
}
// Must not play: an old packet sent again, and plain VBAN
udp.send(sealedPackets[5])
udp.send(packetizer.write([Int16](repeating: 100, count: 256)).first!)
print("INFO sent \(sealedPackets.count) audio packets, then a replay and a plain VBAN packet")
print(String(format: "SENT played=%d pcm=%016llx replayed_or_late=1 unencrypted=1", sealedPackets.count, hash))
exit(0)
