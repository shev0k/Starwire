import XCTest
@testable import StarwireKit

final class IdentityMigrationTests: XCTestCase {
    private let identity: [IdentityItem: Data] = [
        .certificate: Data("-----BEGIN CERTIFICATE-----\nMIIC\n-----END CERTIFICATE-----\n".utf8),
        .privateKey: Data("-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----\n".utf8),
        .pkcs12: Data([0x30, 0x82, 0x09, 0x01, 0x02, 0x03]),
    ]

    func testTheFilesAreCopiedByteForByte() {
        let files = MemoryIdentityStore(items: identity)
        let keychain = MemoryIdentityStore()

        XCTAssertEqual(IdentityMigration(removeFiles: false).run(files: files, keychain: keychain), .migrated(filesRemoved: false))
        XCTAssertEqual(keychain.items, identity)
        XCTAssertEqual(files.items, identity, "the files stay until the copy is proven")
    }

    func testTheFilesGoOnlyWhenAskedAndTheCopyMatches() {
        let files = MemoryIdentityStore(items: identity)
        let keychain = MemoryIdentityStore()

        XCTAssertEqual(IdentityMigration(removeFiles: true).run(files: files, keychain: keychain), .migrated(filesRemoved: true))
        XCTAssertEqual(keychain.items, identity)
        XCTAssertTrue(files.items.isEmpty)
    }

    func testALaterRunRemovesTheFilesOnceTheyMatch() {
        let files = MemoryIdentityStore(items: identity)
        let keychain = MemoryIdentityStore(items: identity)

        XCTAssertEqual(IdentityMigration(removeFiles: false).run(files: files, keychain: keychain), .alreadyInKeychain(filesRemoved: false))
        XCTAssertEqual(files.items, identity)
        XCTAssertEqual(IdentityMigration(removeFiles: true).run(files: files, keychain: keychain), .alreadyInKeychain(filesRemoved: true))
        XCTAssertTrue(files.items.isEmpty)
        XCTAssertEqual(keychain.items, identity)
    }

    func testAKeychainThatRefusesLeavesEverythingAsItWas() {
        let files = MemoryIdentityStore(items: identity)
        let keychain = MemoryIdentityStore()
        keychain.failWrites = true

        guard case .failed = IdentityMigration(removeFiles: true).run(files: files, keychain: keychain) else {
            return XCTFail("expected a failure")
        }
        XCTAssertEqual(files.items, identity)
        XCTAssertTrue(keychain.items.isEmpty)
    }

    func testADifferentReadBackIsUndone() {
        let files = MemoryIdentityStore(items: identity)
        let keychain = MemoryIdentityStore()
        keychain.corruptReads[.privateKey] = Data("something else".utf8)

        guard case .failed = IdentityMigration(removeFiles: true).run(files: files, keychain: keychain) else {
            return XCTFail("expected a failure")
        }
        XCTAssertEqual(files.items, identity)
        XCTAssertTrue(keychain.items.isEmpty)
    }

    func testHalfAnIdentityInTheKeychainIsReplaced() {
        let files = MemoryIdentityStore(items: identity)
        let keychain = MemoryIdentityStore(items: [.certificate: Data("stale".utf8)])

        XCTAssertEqual(IdentityMigration(removeFiles: false).run(files: files, keychain: keychain), .migrated(filesRemoved: false))
        XCTAssertEqual(keychain.items, identity)
    }

    func testDifferentIdentitiesAreLeftAlone() {
        var other = identity
        other[.privateKey] = Data("another key".utf8)
        let files = MemoryIdentityStore(items: other)
        let keychain = MemoryIdentityStore(items: identity)

        XCTAssertEqual(IdentityMigration(removeFiles: true).run(files: files, keychain: keychain), .conflict)
        XCTAssertEqual(files.items, other)
        XCTAssertEqual(keychain.items, identity)
    }

    func testNoIdentityAnywhere() {
        XCTAssertEqual(IdentityMigration(removeFiles: true).run(files: MemoryIdentityStore(), keychain: MemoryIdentityStore()), .nothingToMigrate)
    }

    func testHalfAnIdentityInFilesIsNotMigrated() {
        let files = MemoryIdentityStore(items: [.certificate: identity[.certificate]!])
        let keychain = MemoryIdentityStore()
        XCTAssertEqual(IdentityMigration(removeFiles: true).run(files: files, keychain: keychain), .nothingToMigrate)
        XCTAssertEqual(files.items.count, 1, "nothing is deleted")
    }
}
