import XCTest
@testable import StarwireKit

final class MenuButtonOptionsTests: XCTestCase {
    func testDefaultsKeepAndroidsButton() {
        let options = MenuButtonOptions(store: SettingsStore(storage: MemorySettingsStorage()))
        XCTAssertEqual(options.style, .floating)
        XCTAssertEqual(options.size.points, 44)
        XCTAssertEqual(options.idleOpacity, 0.6, accuracy: 1e-9)
        XCTAssertNil(options.autoHide, "it never docks by itself unless asked")
    }

    func testSavedChoicesAreRead() throws {
        let store = SettingsStore(storage: MemorySettingsStorage())
        try store.set(.string("edge"), for: MenuButtonOptions.styleKey)
        try store.set(.string("large"), for: MenuButtonOptions.sizeKey)
        try store.set(.int(35), for: MenuButtonOptions.opacityKey)
        try store.set(.string("5"), for: MenuButtonOptions.autoHideKey)
        let options = MenuButtonOptions(store: store)
        XCTAssertEqual(options, MenuButtonOptions(style: .edge, size: .large, idleOpacity: 0.35, autoHide: 5))
    }

    func testTheTabDocksToTheNearerSideWithinTheSafeArea() {
        let screen = CGSize(width: 1194, height: 834)
        let left = CGRect(x: 100, y: 200, width: 44, height: 44)
        XCTAssertEqual(MenuButtonDock.nearestEdge(buttonFrame: left, screen: screen), .left)
        XCTAssertEqual(MenuButtonDock.nearestEdge(buttonFrame: left.offsetBy(dx: 900, dy: 0), screen: screen), .right)

        XCTAssertEqual(MenuButtonDock.tabFrame(edge: .right, centreY: 222, screen: screen),
                       CGRect(x: 1194 - 14, y: 190, width: 14, height: 64))
        XCTAssertEqual(MenuButtonDock.tabFrame(edge: .left, centreY: 0, screen: screen, top: 24).minY, 24)
        XCTAssertEqual(MenuButtonDock.tabFrame(edge: .left, centreY: 834, screen: screen, bottom: 20).maxY, 814)
    }

    func testOnlyAButtonLetGoNearASideSnaps() {
        let screen = CGSize(width: 800, height: 600)
        XCTAssertTrue(MenuButtonDock.snaps(buttonFrame: CGRect(x: 10, y: 300, width: 44, height: 44), screen: screen))
        XCTAssertTrue(MenuButtonDock.snaps(buttonFrame: CGRect(x: 740, y: 300, width: 44, height: 44), screen: screen))
        XCTAssertFalse(MenuButtonDock.snaps(buttonFrame: CGRect(x: 300, y: 300, width: 44, height: 44), screen: screen))
    }

    func testTheButtonComesOutBesideItsTab() {
        let screen = CGSize(width: 800, height: 600)
        let tab = MenuButtonDock.tabFrame(edge: .right, centreY: 300, screen: screen)
        XCTAssertEqual(MenuButtonDock.buttonFrame(fromTab: tab, edge: .right, size: 44, screen: screen),
                       CGRect(x: 800 - 44 - 8, y: 278, width: 44, height: 44))
    }
}
