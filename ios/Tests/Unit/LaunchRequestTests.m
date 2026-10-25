//
//  LaunchRequestTests.m
//  Starwire
//
//  The launch and resume requests carry Vibeshine's virtualDisplay parameter when it is asked
//  for, and only then. Nothing is sent; the requests are only built.
//

#import <XCTest/XCTest.h>

#import "HttpManager.h"
#import "StreamConfiguration.h"

@interface LaunchRequestTests : XCTestCase
@end

@implementation LaunchRequestTests

- (StreamConfiguration *)configWithVirtualDisplay:(BOOL)virtualDisplay {
    StreamConfiguration *config = [[StreamConfiguration alloc] init];
    config.appID = @"1";
    config.appVersion = @"7.1.431.-1";
    config.width = 2420;
    config.height = 1668;
    config.frameRate = 120;
    config.riKey = [NSMutableData dataWithLength:16];
    config.riKeyId = 1;
    config.virtualDisplay = virtualDisplay;
    return config;
}

- (NSString *)urlFor:(NSString *)verb virtualDisplay:(BOOL)virtualDisplay {
    // A documentation address (RFC 5737) and a known HTTPS port, so no serverinfo is needed
    HttpManager *http = [[HttpManager alloc] initWithAddress:@"192.0.2.10" httpsPort:47984 serverCert:nil];
    NSURLRequest *request = [http newLaunchOrResumeRequest:verb config:[self configWithVirtualDisplay:virtualDisplay]];
    XCTAssertNotNil(request);
    return request.URL.absoluteString;
}

- (void)testLaunchAndResumeAskForAVirtualDisplay {
    for (NSString *verb in @[ @"launch", @"resume" ]) {
        NSString *url = [self urlFor:verb virtualDisplay:YES];
        XCTAssertTrue([url containsString:[NSString stringWithFormat:@"/%@?", verb]], @"%@", url);
        XCTAssertTrue([url containsString:@"&virtualDisplay=1"], @"%@", url);
        XCTAssertTrue([url containsString:@"mode=2420x1668x120"], @"%@", url);
    }
}

- (void)testNoVirtualDisplayParameterWhenOff {
    XCTAssertFalse([[self urlFor:@"launch" virtualDisplay:NO] containsString:@"virtualDisplay"]);
}

@end
