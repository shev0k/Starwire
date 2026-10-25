//
//  StarwireLaunchFlow.swift
//  Starwire
//
//  StarwireKit's launch rules for StreamManager: Vibeshine's control tiles, and the HTTP 410
//  answers that ask to confirm (Terminate, or another game while one runs) or report a result
//  (Disconnect Monitor). ConfirmedLaunch asks at most once per launch.
//

import Foundation
import StarwireKit

@objc(StarwireLaunchStep)
enum StarwireLaunchStep: Int {
    case start
    case ask
    case finished
    case failed
}

@objc(StarwireLaunchFlow)
final class StarwireLaunchFlow: NSObject {
    private var flow = ConfirmedLaunch()

    /// What to do with a launch or resume answer.
    @objc func next(statusCode: Int, message: String?) -> StarwireLaunchStep {
        switch flow.next(LaunchOutcome.classify(statusCode: statusCode, message: message)) {
        case .start: return .start
        case .ask: return .ask
        case .finished: return .finished
        case .failed: return .failed
        }
    }

    /// True for Vibeshine's control tiles (Remote Input, Remote Monitor, Terminate, ...). They
    /// are always launched, never resumed: /resume would ignore the tile and join the game.
    @objc static func isControlTile(_ appID: String) -> Bool {
        HostApp.kind(id: appID, uuid: nil) != .game
    }
}
