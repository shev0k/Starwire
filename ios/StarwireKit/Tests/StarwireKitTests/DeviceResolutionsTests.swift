import XCTest
@testable import StarwireKit

final class DeviceResolutionsTests: XCTestCase {
    func testTheIPadPro11FullScreenAndSafeArea() {
        // iPad Pro 11-inch (M4) in landscape: 1210x834 points at 2x, the home indicator's 20 points
        let choices = DeviceResolutions.choices(screen: CGSize(width: 1210, height: 834), insets: (0, 0, 20, 0), scale: 2)
        XCTAssertEqual(choices, DeviceResolutions.Choices(fullScreen: "2420x1668", safeArea: "2420x1628"))
    }

    func testAPhoneHeldUprightGivesLandscapeSizes() {
        // iPhone 16 Pro upright: 402x874 points at 3x, notch and home indicator insets
        let choices = DeviceResolutions.choices(screen: CGSize(width: 402, height: 874), insets: (62, 0, 34, 0), scale: 3)
        XCTAssertEqual(choices.fullScreen, "2622x1206")
        XCTAssertEqual(choices.safeArea, "2334x1206")
    }

    func testOddPixelCountsAreRoundedDownToEven() {
        let choices = DeviceResolutions.choices(screen: CGSize(width: 100.5, height: 50.5), insets: (0, 0, 0, 0), scale: 1)
        XCTAssertEqual(choices.fullScreen, "100x50")
    }

    func testTheSizesAreValidResolutions() throws {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let choices = DeviceResolutions.choices(screen: CGSize(width: 1210, height: 834), insets: (0, 0, 20, 0), scale: 2)
        try store.set(.string(choices.safeArea), for: "list_resolution")
        XCTAssertNotNil(SettingsStore.parseResolution(choices.safeArea))
    }
}
