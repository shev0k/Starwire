import Foundation

/// The launch options Vibeshine adds to `/launch` and `/resume`, from the settings.
///
/// - `virtualDisplay`: left out to let the host decide, 1 for a virtual display, 0 for the PC's
///   own monitor.
/// - `scaleFactor`: the virtual display's size as a percent of the stream's. Left out at 0 or 100.
/// - `clientVrrRequested=1`: a variable refresh rate virtual display.
/// - `clientName`: a label the host shows only for clients it knows as "self".
/// - `mode`: `WxHxFPS`, where the frame rate may have up to three decimals ("119.88").
public struct LaunchOptions: Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// The display rate in hertz, for `mode`. May be fractional.
    public var refreshRate: Double
    public var virtualDisplay: VirtualDisplayMode
    public var scalePercent: Int
    public var requestVRR: Bool
    public var clientName: String?

    public init(width: Int, height: Int, refreshRate: Double, virtualDisplay: VirtualDisplayMode = .host,
                scalePercent: Int = 0, requestVRR: Bool = false, clientName: String? = nil) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.virtualDisplay = virtualDisplay
        self.scalePercent = scalePercent
        self.requestVRR = requestVRR
        self.clientName = clientName
    }

    /// From the settings, for a stream of `width` x `height`.
    public init(settings: SettingsStore, width: Int, height: Int, deviceName: String) {
        let name = settings[.clientName].trimmingCharacters(in: .whitespaces)
        self.init(width: width, height: height, refreshRate: Self.parseRate(settings[.frameRate]) ?? 60,
                  virtualDisplay: settings[.virtualDisplayMode], scalePercent: settings[.virtualDisplayScale],
                  requestVRR: settings[.vrrRequest], clientName: name.isEmpty ? deviceName : name)
    }

    /// "119.88" or "120" as a rate in hertz, or nil.
    public static func parseRate(_ text: String) -> Double? {
        guard let rate = Double(text.trimmingCharacters(in: .whitespaces)), rate >= 10, rate <= 1000 else {
            return nil
        }
        return rate
    }

    /// The whole frame rate the stream itself runs at (moonlight-common-c takes an integer):
    /// rounded half up, as Vibeshine does (119.88 runs at 120).
    public var streamFrameRate: Int {
        Int((refreshRate * 1000).rounded() + 500) / 1000
    }

    /// The rate as Vibeshine parses it: whole hertz, or up to three decimals with no trailing
    /// zeros.
    public static func formatRate(_ rate: Double) -> String {
        let millihertz = Int((rate * 1000).rounded())
        if millihertz % 1000 == 0 {
            return String(millihertz / 1000)
        }
        var fraction = String(format: "%03d", millihertz % 1000)
        while fraction.hasSuffix("0") {
            fraction.removeLast()
        }
        return "\(millihertz / 1000).\(fraction)"
    }

    public var mode: String {
        "\(width)x\(height)x\(Self.formatRate(refreshRate))"
    }

    /// The query items Vibeshine reads, beyond the standard ones. `mode` is separate, since the
    /// launch request already has one.
    public var extraQueryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        switch virtualDisplay {
        case .host: break
        case .virtual: items.append(URLQueryItem(name: "virtualDisplay", value: "1"))
        case .primary: items.append(URLQueryItem(name: "virtualDisplay", value: "0"))
        }
        if scalePercent > 0 && scalePercent != 100 {
            items.append(URLQueryItem(name: "scaleFactor", value: String(scalePercent)))
        }
        if requestVRR {
            items.append(URLQueryItem(name: "clientVrrRequested", value: "1"))
        }
        if let clientName, !clientName.isEmpty {
            items.append(URLQueryItem(name: "clientName", value: clientName))
        }
        return items
    }

    /// The extra items as a query string fragment that starts with "&", percent-encoded, for
    /// the ObjC launch request that builds its URL as text.
    public var extraQueryString: String {
        extraQueryItems.map { item in
            "&\(item.name)=\(Self.encode(item.value ?? ""))"
        }.joined()
    }

    static func encode(_ value: String) -> String {
        // RFC 3986 unreserved characters only (CharacterSet.alphanumerics would let "é" through)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
