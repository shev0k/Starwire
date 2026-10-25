//
//  LaunchRequestTests.m
//  Starwire
//
//  The launch and resume requests carry Vibeshine's launch options from the settings store
//  (virtualDisplay, scaleFactor, clientVrrRequested, clientName and an exact rate in mode), and
//  only what is asked for. Nothing is sent; the requests are only built.
//

#import <XCTest/XCTest.h>

#import "HttpManager.h"
#import "StreamConfiguration.h"
#import "Moonlight-Swift.h"

@interface LaunchRequestTests : XCTestCase
@end

@implementation LaunchRequestTests {
    NSUserDefaults *_settings;
    NSDictionary *_saved;
}

static NSArray<NSString *> *launchKeys(void) {
    return @[ @"virtual_display_mode", @"seekbar_virtual_display_scale", @"checkbox_vrr_request",
              @"text_client_name", @"list_fps" ];
}

- (void)setUp {
    // The app's own settings suite: keep what was there and put it back afterwards
    _settings = [[NSUserDefaults alloc] initWithSuiteName:@"io.github.shev0k.starwire.settings"];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in launchKeys()) {
        id value = [_settings objectForKey:key];
        if (value != nil) {
            saved[key] = value;
        }
        [_settings removeObjectForKey:key];
    }
    _saved = saved;
    [StarwireSettings reload];
}

- (void)tearDown {
    for (NSString *key in launchKeys()) {
        [_settings setObject:_saved[key] forKey:key];
    }
    [StarwireSettings reload];
}

- (StreamConfiguration *)config {
    StreamConfiguration *config = [[StreamConfiguration alloc] init];
    config.appID = @"1";
    config.appVersion = @"7.1.431.-1";
    config.width = 2420;
    config.height = 1668;
    config.frameRate = 120;
    config.riKey = [NSMutableData dataWithLength:16];
    config.riKeyId = 1;
    return config;
}

- (NSString *)urlFor:(NSString *)verb {
    [StarwireSettings reload];
    // A documentation address (RFC 5737) and a known HTTPS port, so no serverinfo is needed
    HttpManager *http = [[HttpManager alloc] initWithAddress:@"192.0.2.10" httpsPort:47984 serverCert:nil];
    NSURLRequest *request = [http newLaunchOrResumeRequest:verb config:[self config]];
    XCTAssertNotNil(request);
    return request.URL.absoluteString;
}

- (void)testLaunchAndResumeAskForAVirtualDisplay {
    [_settings setObject:@"virtual" forKey:@"virtual_display_mode"];
    for (NSString *verb in @[ @"launch", @"resume" ]) {
        NSString *url = [self urlFor:verb];
        NSString *path = [NSString stringWithFormat:@"/%@?", verb];
        XCTAssertTrue([url containsString:path], @"%@", url);
        XCTAssertTrue([url containsString:@"&virtualDisplay=1"], @"%@", url);
        XCTAssertTrue([url containsString:@"mode=2420x1668x120&"], @"%@", url);
    }
}

- (void)testThePCsOwnMonitorIsAskedForWithZero {
    [_settings setObject:@"primary" forKey:@"virtual_display_mode"];
    XCTAssertTrue([[self urlFor:@"launch"] containsString:@"&virtualDisplay=0"]);
}

- (void)testTheHostDecidesByDefault {
    NSString *url = [self urlFor:@"launch"];
    XCTAssertFalse([url containsString:@"virtualDisplay"], @"%@", url);
    XCTAssertFalse([url containsString:@"scaleFactor"], @"%@", url);
    XCTAssertFalse([url containsString:@"clientVrrRequested"], @"%@", url);
    XCTAssertTrue([url containsString:@"&clientName=Starwire%20on%20"], @"%@", url);
}

- (void)testScaleVRRAndAnExactRate {
    [_settings setInteger:150 forKey:@"seekbar_virtual_display_scale"];
    [_settings setBool:YES forKey:@"checkbox_vrr_request"];
    [_settings setObject:@"119.88" forKey:@"list_fps"];
    [_settings setObject:@"Shev's iPad" forKey:@"text_client_name"];
    NSString *url = [self urlFor:@"launch"];
    XCTAssertTrue([url containsString:@"mode=2420x1668x119.88&"], @"%@", url);
    XCTAssertTrue([url containsString:@"&scaleFactor=150"], @"%@", url);
    XCTAssertTrue([url containsString:@"&clientVrrRequested=1"], @"%@", url);
    XCTAssertTrue([url containsString:@"&clientName=Shev%27s%20iPad"], @"%@", url);
}

- (void)testAnExactRateForAnotherFrameRateIsNotUsed {
    // 119.88 is stale when the stream is set to 60 FPS
    [_settings setObject:@"119.88" forKey:@"list_fps"];
    StreamConfiguration *config = [self config];
    config.frameRate = 60;
    [StarwireSettings reload];
    HttpManager *http = [[HttpManager alloc] initWithAddress:@"192.0.2.10" httpsPort:47984 serverCert:nil];
    NSString *url = [http newLaunchOrResumeRequest:@"launch" config:config].URL.absoluteString;
    XCTAssertTrue([url containsString:@"mode=2420x1668x60&"], @"%@", url);
}

@end
