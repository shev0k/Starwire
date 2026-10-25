import Foundation

/// An app in a PC's `/applist`, with Vibeshine's control tiles told apart from games.
public struct HostApp: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case game
        /// Vibeshine: control another client's or its own remote session
        case resume
        case disconnectMonitor
        case disconnectInput
        /// Ends another client's game. Asks for confirmation (HTTP 410) first.
        case terminate
        /// Streams this client's own virtual display, next to the PC's monitors.
        case remoteMonitor
        /// Sends input only: no picture or sound.
        case remoteInput
        /// Another client's running game, to join it.
        case runningGame
    }

    public var id: String
    /// The title with Vibeshine's sorting spaces taken off the front.
    public var name: String
    public var uuid: String?
    public var hdrSupported: Bool
    public var kind: Kind

    public init(id: String, name: String, uuid: String? = nil, hdrSupported: Bool = false, kind: Kind = .game) {
        self.id = id
        self.name = name
        self.uuid = uuid
        self.hdrSupported = hdrSupported
        self.kind = kind
    }

    /// Vibeshine's fixed control IDs (remote_session.h): the primary, the second client's and
    /// the legacy one for each.
    static let controlIDs: [Int: Kind] = [
        2_147_483_501: .resume, 2_147_483_511: .resume, 2_147_483_601: .resume,
        2_147_483_502: .disconnectMonitor, 2_147_483_602: .disconnectMonitor,
        2_147_483_503: .disconnectInput, 2_147_483_603: .disconnectInput,
        2_147_483_504: .terminate, 2_147_483_514: .terminate, 2_147_483_604: .terminate,
        2_147_483_505: .remoteMonitor, 2_147_483_515: .remoteMonitor, 2_147_483_605: .remoteMonitor,
        2_147_483_506: .remoteInput, 2_147_483_516: .remoteInput, 2_147_483_606: .remoteInput,
    ]
    /// The running-game tile's UUID; its numeric ID is made up from the game's.
    static let runningGameUUID = "9a1c5a25-58fe-40e0-b9aa-7d3f00000007"
    static let controlUUIDPrefix = "9a1c5a25-58fe-40e0-b9aa-7d3f0000000"

    public static func kind(id: String, uuid: String?) -> Kind {
        if let number = Int(id), let kind = controlIDs[number] {
            return kind
        }
        if uuid?.lowercased() == runningGameUUID {
            return .runningGame
        }
        return .game
    }

    /// True for tiles that control a session rather than start a game.
    public var isControl: Bool { kind != .game }

    /// True when launching it may come back with a question to confirm (HTTP 410).
    public var mayAskToConfirm: Bool { kind == .terminate || kind == .game }
}

public enum HostAppList {
    /// Reads `/applist`. Apps with no ID are skipped.
    public static func parse(_ data: Data) throws -> (xml: HostXML, apps: [HostApp]) {
        let xml = try HostXML.parse(data)
        let apps = xml.records.filter { $0.name == "App" }.compactMap { record -> HostApp? in
            guard let id = record.fields["ID"], !id.isEmpty else { return nil }
            let uuid = record.fields["UUID"].flatMap { $0.isEmpty ? nil : $0 }
            let title = (record.fields["AppTitle"] ?? "").trimmingCharacters(in: .whitespaces)
            return HostApp(id: id, name: title, uuid: uuid, hdrSupported: record.fields["IsHdrSupported"] == "1",
                           kind: HostApp.kind(id: id, uuid: uuid))
        }
        return (xml, apps)
    }
}
