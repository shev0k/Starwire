//
//  StarwireLog.swift
//  Starwire
//
//  The Swift side of Logger.h: the same subsystem and categories, and the same "<INFO>" prefixes,
//  so Swift lines sit with the ObjC ones in the device logs. Messages are public, so they must
//  never hold keys, PINs or certificates.
//

import Foundation
import os

enum StarwireLog {
    private static let subsystem = "io.github.shev0k.starwire"
    private static let app = Logger(subsystem: subsystem, category: "app")
    static let network = Logger(subsystem: subsystem, category: "network")

    static func info(_ message: String, _ logger: Logger = app) {
        logger.log("<INFO> \(message, privacy: .public)")
    }

    /// Only with "Verbose logging" on (StarwireVerboseLogging), like LOG_D in the ObjC code
    static func debug(_ message: @autoclosure () -> String, _ logger: Logger = app) {
        guard UserDefaults.standard.bool(forKey: "StarwireVerboseLogging") else { return }
        let text = message()
        logger.log("<DEBUG> \(text, privacy: .public)")
    }

    static func warning(_ message: String, _ logger: Logger = app) {
        logger.log("<WARN> \(message, privacy: .public)")
    }

    static func error(_ message: String, _ logger: Logger = app) {
        logger.error("<ERROR> \(message, privacy: .public)")
    }
}
