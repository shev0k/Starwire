import Foundation

/// A PC's `/serverinfo`, with Vibeshine's extras. Over plain HTTP the host leaves out what's
/// only for paired clients: the real MAC address, `PairStatus` 1, the power actions, the
/// PyroWave details and hardware metrics.
public struct ServerInfo: Equatable, Sendable {
    public var xml: HostXML

    public init(xml: HostXML) {
        self.xml = xml
    }

    public static func parse(_ data: Data) throws -> ServerInfo {
        ServerInfo(xml: try HostXML.parse(data))
    }

    private func int(_ name: String) -> Int? { xml[name].flatMap { Int($0) } }
    private func flag(_ name: String) -> Bool {
        guard let value = xml[name]?.lowercased() else { return false }
        return value == "1" || value == "true"
    }

    // Standard
    public var hostName: String? { xml["hostname"] }
    public var uuid: String? { xml["uniqueid"] }
    public var appVersion: String? { xml["appversion"] }
    public var httpsPort: Int { int("HttpsPort") ?? 47984 }
    public var externalPort: Int { int("ExternalPort") ?? 47989 }
    /// The MAC address, or nil when the host doesn't say (all zeros on plain HTTP).
    public var macAddress: String? { MacAddress.normalized(xml["mac"]) }
    public var localIP: String? { xml["LocalIP"] }
    public var pairState: HostPairState {
        guard let status = int("PairStatus") else { return .unknown }
        return status == 1 ? .paired : .unpaired
    }
    public var currentGameID: Int { int("currentgame") ?? 0 }
    public var isBusy: Bool { xml["state"]?.hasSuffix("_SERVER_BUSY") ?? false }
    public var codecModeSupport: UInt32 { xml["ServerCodecModeSupport"].flatMap { UInt32($0) } ?? 0 }
    public var maxLumaPixelsHEVC: Int { int("MaxLumaPixelsHEVC") ?? 0 }

    /// True for Vibeshine and the hosts built on it, which add the fields below.
    public var isVibeshine: Bool { xml["VirtualDisplayCapable"] != nil || xml["HardwareMetricsVersion"] != nil }

    // Vibeshine: virtual displays
    public var virtualDisplayCapable: Bool { flag("VirtualDisplayCapable") }
    public var virtualDisplayDriverReady: Bool { flag("VirtualDisplayDriverReady") }
    public var virtualDisplayHDRCapable: Bool { flag("VirtualDisplayHDRCapable") }
    public var currentGameUUID: String? { xml["currentgameuuid"].flatMap { $0.isEmpty ? nil : $0 } }

    // Vibeshine: frame limiter
    public var frameLimiterSupported: Bool { flag("FrameLimiterSupported") }
    public var frameLimiterEnabled: Bool { flag("FrameLimiterEnabled") }
    public var virtualDisplayFrameLimiterEnabled: Bool { flag("VirtualDisplayFrameLimiterEnabled") }
    /// 0 when there is no limit.
    public var frameLimiterFpsLimitMilliHz: Int { int("FrameLimiterFpsLimitMilliHz") ?? 0 }

    // Vibeshine: what this client may do (paired HTTPS view only)
    /// 1 or more when the host answers `/api/hardware-metrics` for this client. The host's
    /// `hardware_metrics` setting is off by default.
    public var hardwareMetricsVersion: Int { int("HardwareMetricsVersion") ?? 0 }
    public var powerActionVersion: Int { int("PowerActionVersion") ?? 0 }
    /// The PC can sleep (Windows with S3 or Modern Standby).
    public var sleepSupported: Bool { flag("SleepSupported") }
    /// The host's owner allows this client to sleep the PC (off by default, per client).
    public var sleepAllowed: Bool { flag("SleepAllowed") }

    // Vibeshine: PyroWave (phase 7)
    public static let pyroWaveCodecMask: UInt32 = 0x0080_0000 | 0x0100_0000 | 0x0200_0000 | 0x0400_0000
    public var supportsPyroWave: Bool { codecModeSupport & Self.pyroWaveCodecMask != 0 }
    /// The host's wired link in Mbps, 0 if unknown or wireless. Paired view with PyroWave only.
    public var pyroWaveHostLinkMbps: Int { int("PyroWaveHostLinkMbps") ?? 0 }
    public var pyroWaveBandwidthProbeBytes: Int { int("PyroWaveBandwidthProbeBytes") ?? 0 }
    public var pyroWaveCriticalFecPercentage: Int? { int("PyroWaveCriticalFecPercentage") }
    public var pyroWaveMinParityShards: Int? { int("PyroWaveMinParityShards") }
    public var pyroWaveUdpProbeVersion: Int { int("PyroWaveUdpProbeVersion") ?? 0 }

    // Features Vibeshine doesn't have but other hosts do; checked so they can be turned on later
    /// Server commands (Apollo's `ServerCommand` list).
    public var hasServerCommands: Bool { xml["ServerCommand"] != nil }
}
