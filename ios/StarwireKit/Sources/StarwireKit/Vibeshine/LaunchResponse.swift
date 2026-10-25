import Foundation

/// What a `/launch` or `/resume` answer means.
///
/// Vibeshine answers some launches with status 410 and a message, in the XML (HTTP itself is
/// 200). There are two kinds, told apart only by the message:
/// - a question: Terminate from a second client, or a different game while one runs. Nothing
///   happened yet; the same request again within 60 seconds confirms it.
/// - a result: the confirmed Terminate, Disconnect Monitor and Disconnect Input. It's done, and
///   there's no stream to start.
public enum LaunchOutcome: Equatable, Sendable {
    /// Start the stream at this RTSP address.
    case started(sessionURL: String?, virtualDisplayDriverReady: Bool?, warning: String?)
    /// Show the message and ask; on yes, send the same request again.
    case needsConfirmation(message: String)
    /// Show the message; the action is done.
    case done(message: String)
    case failed(code: Int, message: String)

    public static func classify(_ xml: HostXML) -> LaunchOutcome {
        let message = xml.statusMessage ?? ""
        switch xml.statusCode {
        case 200:
            return .started(sessionURL: xml["sessionUrl0"],
                            virtualDisplayDriverReady: xml["VirtualDisplayDriverReady"].map { $0 == "true" || $0 == "1" },
                            warning: xml["clientWarning"])
        case 410:
            return isQuestion(message) ? .needsConfirmation(message: message) : .done(message: message)
        default:
            return .failed(code: xml.statusCode, message: message)
        }
    }

    /// Vibeshine's questions say to launch "again within 60 seconds" (remote_session.cpp).
    static func isQuestion(_ message: String) -> Bool {
        message.range(of: "again within", options: .caseInsensitive) != nil
    }

    /// The same, from the code and message the ObjC response gives, for the app's launch code.
    public static func classify(statusCode: Int, message: String?) -> LaunchOutcome {
        classify(HostXML(statusCode: statusCode, statusMessage: message, fields: [:], records: []))
    }
}

/// The 410 step as a small state machine, so the app's launch code and the tests share it: at
/// most one question per launch, and a second question counts as the answer.
public struct ConfirmedLaunch: Sendable {
    public private(set) var asked = false

    public init() {}

    public enum Step: Equatable, Sendable {
        case start(sessionURL: String?)
        /// Ask the user this; call `confirmed()` and send again on yes.
        case ask(String)
        case finished(String)
        case failed(code: Int, message: String)
    }

    public mutating func next(_ outcome: LaunchOutcome) -> Step {
        switch outcome {
        case .started(let url, _, _):
            return .start(sessionURL: url)
        case .needsConfirmation(let message):
            if asked {
                // The host asked again (the 60 seconds ran out, or the game changed): stop here
                return .finished(message)
            }
            asked = true
            return .ask(message)
        case .done(let message):
            return .finished(message)
        case .failed(let code, let message):
            return .failed(code: code, message: message)
        }
    }
}
