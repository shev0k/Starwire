import XCTest
@testable import StarwireKit

final class KitInfoTests: XCTestCase {
    func testCurrentMatchesTheProjectDeploymentTarget() {
        // ios/project.yml builds for iOS 17.0; the two must agree.
        XCTAssertEqual(KitInfo.current.name, "StarwireKit")
        XCTAssertEqual(KitInfo.current.minimumOSMajorVersion, 17)
    }
}
