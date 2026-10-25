//
//  AccessibilityTests.m
//  Starwire
//
//  App tiles and PC cards carry their name as an accessibility label. The device-run tests find
//  the "Desktop" tile that way, and the tile itself only shows box art.
//

#import <XCTest/XCTest.h>

#import "TemporaryApp.h"
#import "TemporaryHost.h"
#import "UIAppView.h"
#import "UIComputerView.h"

@interface UIComputerView (Testing)
- (void)updateContentsForHost:(TemporaryHost *)host;
@end

@interface AccessibilityTests : XCTestCase
@end

@implementation AccessibilityTests

- (void)testAppTileIsLabelledWithTheAppName {
    TemporaryHost *host = [[TemporaryHost alloc] init];
    // The box art cache path is made from these
    host.uuid = @"accessibility-test-host";
    TemporaryApp *app = [[TemporaryApp alloc] init];
    app.id = @"1";
    app.name = @"Desktop";
    app.host = host;
    UIAppView *tile = [[UIAppView alloc] initWithApp:app cache:[[NSCache alloc] init] andCallback:nil];
    XCTAssertTrue(tile.isAccessibilityElement);
    XCTAssertEqualObjects(tile.accessibilityLabel, @"Desktop");
}

- (void)testPCCardIsLabelledWithThePCName {
    TemporaryHost *host = [[TemporaryHost alloc] init];
    host.name = @"Gaming PC";
    UIComputerView *card = [[UIComputerView alloc] initWithComputer:host andCallback:nil];
    XCTAssertTrue(card.isAccessibilityElement);
    XCTAssertEqualObjects(card.accessibilityLabel, @"Gaming PC");

    // A renamed PC gets the new name
    host.name = @"Living room";
    [card updateContentsForHost:host];
    XCTAssertEqualObjects(card.accessibilityLabel, @"Living room");
}

@end
