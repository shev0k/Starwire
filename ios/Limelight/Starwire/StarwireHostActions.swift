//
//  StarwireHostActions.swift
//  Starwire
//
//  Vibeshine's own requests for the ObjC screens, through StarwireKit's VibeshineClient (the real
//  HostService) over the pinned transport: the bitrate during a stream, sleeping the PC, and the
//  host's CPU and GPU for the overlay. Completions run on the main queue.
//

import Foundation
import StarwireKit

@objc(StarwireHostActions)
final class StarwireHostActions: NSObject {
    let host: HostService
    private let transport: PinnedHostTransport?

    @objc init?(address: String, httpsPort: Int, serverCert: Data?) {
        guard let serverCert, let transport = PinnedHostTransport(address: address, httpsPort: httpsPort, certificate: serverCert) else {
            return nil
        }
        self.transport = transport
        host = VibeshineClient(transport: transport)
    }

    init(host: HostService) {
        self.host = host
        transport = nil
    }

    deinit {
        // The session keeps the transport otherwise
        transport?.close()
    }

    private func onMain(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    private static func message(_ error: Error) -> String {
        switch error {
        case VibeshineError.host(_, let message) where !message.isEmpty:
            return message
        case VibeshineError.host(let code, _):
            return "The PC answered with error \(code)."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Bitrate

    /// Asks the PC to change the running stream's bitrate. The completion gets the bitrate the
    /// PC applied (it may cap it), or 0 and why not.
    @objc func setBitrate(_ kbps: Int, completion: @escaping (Int, String?) -> Void) {
        Task {
            do {
                let applied = try await host.setBitrate(kbps: kbps)
                StarwireLog.info("Bitrate: asked \(kbps) kbps, the PC applied \(applied) kbps", StarwireLog.network)
                onMain { completion(applied, nil) }
            } catch {
                StarwireLog.warning("Bitrate: \(kbps) kbps refused: \(error)", StarwireLog.network)
                let message = Self.message(error)
                onMain { completion(0, message) }
            }
        }
    }

    // MARK: - What the PC offers this client

    /// From the PC's serverinfo: whether it lets this device sleep it, and whether it sends
    /// hardware metrics. Both off when it can't be asked.
    @objc func capabilities(_ completion: @escaping (_ sleep: Bool, _ metrics: Bool) -> Void) {
        Task {
            let info = try? await host.serverInfo()
            let sleep = (info?.powerActionVersion ?? 0) > 0 && info?.sleepSupported == true && info?.sleepAllowed == true
            let metrics = (info?.hardwareMetricsVersion ?? 0) > 0
            StarwireLog.info("PC offers: sleep \(sleep ? "yes" : "no"), hardware metrics \(metrics ? "yes" : "no")", StarwireLog.network)
            onMain { completion(sleep, metrics) }
        }
    }

    // MARK: - Sleep

    /// Puts the PC to sleep. The completion gets nil when the PC accepted, or why not.
    @objc func sleepPC(_ completion: @escaping (String?) -> Void) {
        Task {
            do {
                try await host.sleep()
                StarwireLog.info("Sleep: the PC accepted", StarwireLog.network)
                onMain { completion(nil) }
            } catch {
                StarwireLog.warning("Sleep: \(error)", StarwireLog.network)
                let message = Self.message(error)
                onMain { completion(message) }
            }
        }
    }

    // MARK: - Hardware metrics

    private let metricsLock = NSLock()
    private var metricsLine = ""
    private var metricsInFlight = false
    private var metricsStopped = false
    private var lastMetricsRequest: TimeInterval = 0
    private var metricsInterval: TimeInterval = 1

    /// The last host CPU and GPU line, or "" before the first answer or when the PC has none.
    @objc var hardwareMetricsLine: String {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        return metricsLine
    }

    /// Asks for new metrics if the last answer is old enough and none is on its way. Call it from
    /// the overlay's timer; it never waits. Stops for good after the PC says no (403 or 409),
    /// as Vibeshine's docs ask.
    @objc func refreshHardwareMetrics() {
        metricsLock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        guard !metricsInFlight, !metricsStopped, now - lastMetricsRequest >= metricsInterval else {
            metricsLock.unlock()
            return
        }
        metricsInFlight = true
        lastMetricsRequest = now
        metricsLock.unlock()

        Task {
            var line: String?
            var stop = false
            var interval: TimeInterval?
            do {
                let metrics = try await host.hardwareMetrics()
                line = metrics.overlayText
                interval = metrics.interval_ms.map { max(Double($0) / 1000, 0.5) }
            } catch VibeshineError.host(let code, let message) where code == 403 || code == 409 || code == 404 {
                StarwireLog.info("Hardware metrics: stopped (\(code) \(message))", StarwireLog.network)
                stop = true
            } catch {
                // Busy or a dropped packet: try again at the next interval
            }
            metricsLock.lock()
            metricsInFlight = false
            metricsStopped = metricsStopped || stop
            if let line { metricsLine = line }
            if let interval { metricsInterval = interval }
            metricsLock.unlock()
        }
    }
}
