//
//  KeychainIdentityTests.swift
//  Starwire
//
//  The client identity in the Keychain (StarwireIdentity.swift): the items keep their bytes, are
//  readable after the first unlock on this device only, and the migration from the old files
//  keeps the files until it is told otherwise. Uses its own Keychain service and a temporary
//  folder, never the app's identity.
//

import Security
import StarwireKit
import XCTest
@testable import Starwire

final class KeychainIdentityTests: XCTestCase {
    private let keychain = KeychainIdentityStore(service: "io.github.shev0k.starwire.tests.identity")
    private var folder: URL!
    private var appKeychain: IdentityStore!
    private var appFiles: IdentityStore!

    private let identity: [IdentityItem: Data] = [
        .certificate: Data("test certificate".utf8),
        .privateKey: Data("test key".utf8),
        .pkcs12: Data([0x30, 0x82, 0x01, 0x02]),
    ]

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in IdentityItem.allCases {
            try keychain.delete(item)
        }
        appKeychain = StarwireIdentity.keychain
        appFiles = StarwireIdentity.files
    }

    override func tearDownWithError() throws {
        for item in IdentityItem.allCases {
            try keychain.delete(item)
        }
        try? FileManager.default.removeItem(at: folder)
        StarwireIdentity.reset(keychain: appKeychain, files: appFiles)
    }

    func testItemsKeepTheirBytesAndStayOnThisDevice() throws {
        for (item, data) in identity {
            try keychain.write(data, for: item)
        }
        for (item, data) in identity {
            XCTAssertEqual(try keychain.read(item), data)
            XCTAssertEqual(keychain.accessibility(item), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        }
        try keychain.delete(.privateKey)
        XCTAssertNil(try keychain.read(.privateKey))
    }

    func testWritingAgainReplacesTheItem() throws {
        try keychain.write(Data("one".utf8), for: .certificate)
        try keychain.write(Data("two".utf8), for: .certificate)
        XCTAssertEqual(try keychain.read(.certificate), Data("two".utf8))
    }

    func testTheOldFilesMoveIntoTheKeychainAndGo() throws {
        let files = FileIdentityStore(folder: folder)
        for (item, data) in identity {
            try files.write(data, for: item)
        }
        StarwireIdentity.reset(keychain: keychain, files: files)

        XCTAssertEqual(StarwireIdentity.data(forItem: "client.key"), identity[.privateKey])
        XCTAssertEqual(StarwireIdentity.migrationOutcome, "migrated(filesRemoved: true)")
        for (item, data) in identity {
            XCTAssertEqual(try keychain.read(item), data)
            XCTAssertNil(try files.read(item), "the files go once the Keychain holds the same bytes")
        }
    }

    func testFilesLeftFromTheFirstBatch2BuildGoOnTheNextLaunch() throws {
        // The first batch 2 build copied the identity and kept the files
        let files = FileIdentityStore(folder: folder)
        for (item, data) in identity {
            try files.write(data, for: item)
            try keychain.write(data, for: item)
        }
        StarwireIdentity.reset(keychain: keychain, files: files)

        XCTAssertEqual(StarwireIdentity.data(forItem: "client.p12"), identity[.pkcs12])
        XCTAssertEqual(StarwireIdentity.migrationOutcome, "alreadyInKeychain(filesRemoved: true)")
        for item in IdentityItem.allCases {
            XCTAssertNil(try files.read(item))
        }
    }

    func testANewIdentityGoesStraightIntoTheKeychain() throws {
        let files = FileIdentityStore(folder: folder)
        StarwireIdentity.reset(keychain: keychain, files: files)
        StarwireIdentity.write(identity[.certificate]!, forItem: "client.crt")
        XCTAssertEqual(try keychain.read(.certificate), identity[.certificate])
        XCTAssertNil(try files.read(.certificate))
    }

    func testAnAddressGivesTheHostPart() {
        XCTAssertEqual(PinnedHostTransport.hostPart(of: "192.0.2.10"), "192.0.2.10")
        XCTAssertEqual(PinnedHostTransport.hostPart(of: "192.0.2.10:47989"), "192.0.2.10")
        XCTAssertEqual(PinnedHostTransport.hostPart(of: "[2001:db8::10]:47989"), "2001:db8::10")
        XCTAssertEqual(PinnedHostTransport.hostPart(of: "2001:db8::10"), "2001:db8::10")
        XCTAssertEqual(PinnedHostTransport(address: "[2001:db8::10]:47989", httpsPort: 47984, certificate: Data())?.baseURL.absoluteString,
                       "https://[2001:db8::10]:47984")
    }
}
