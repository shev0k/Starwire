//
//  StreamTestOverridesTests.m
//  Starwire
//
//  The launch arguments the device runs use to try a codec, size, HDR or 4:4:4 for one launch.
//

#import <XCTest/XCTest.h>

#import "StreamTestOverrides.h"
#import "PacingPolicy.h"

@interface StreamTestOverridesTests : XCTestCase
@end

@implementation StreamTestOverridesTests {
    NSString *_suite;
    NSUserDefaults *_defaults;
}

- (void)setUp {
    [super setUp];
    _suite = [NSString stringWithFormat:@"StreamTestOverridesTests.%@", self.name];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suite];
    [_defaults removePersistentDomainForName:_suite];
}

- (void)tearDown {
    [_defaults removePersistentDomainForName:_suite];
    [super tearDown];
}

- (TemporarySettings *)settings {
    TemporarySettings *s = [[TemporarySettings alloc] init];
    s.framerate = @120;
    s.width = @2420;
    s.height = @1668;
    s.preferredCodec = CODEC_PREF_HEVC;
    s.enableHdr = NO;
    s.enableYUV444 = NO;
    s.playAudioOnPC = NO;
    return s;
}

- (void)testNothingSetChangesNothing {
    TemporarySettings *s = [self settings];
    XCTAssertEqualObjects(StreamApplyTestOverrides(s, _defaults), @"");
    XCTAssertEqual(s.framerate.intValue, 120);
    XCTAssertEqual(s.preferredCodec, CODEC_PREF_HEVC);
    XCTAssertFalse(s.playAudioOnPC);
}

- (void)testEveryOverride {
    [_defaults setInteger:60 forKey:StreamFrameRateKey];
    [_defaults setObject:@"1920x1080" forKey:StreamResolutionKey];
    [_defaults setObject:@"av1" forKey:StreamCodecKey];
    [_defaults setBool:YES forKey:StreamHDRKey];
    [_defaults setBool:YES forKey:StreamYUV444Key];
    [_defaults setBool:YES forKey:StreamPlayAudioOnPCKey];
    [_defaults setBool:YES forKey:StreamStatsOverlayKey];
    TemporarySettings *s = [self settings];
    NSString *changed = StreamApplyTestOverrides(s, _defaults);
    XCTAssertEqualObjects(changed, @"60 FPS, 1920x1080, av1, HDR on, 4:4:4 on, overlay on, audio on the PC");
    XCTAssertTrue(s.statsOverlay);
    XCTAssertEqual(s.framerate.intValue, 60);
    XCTAssertEqual(s.width.intValue, 1920);
    XCTAssertEqual(s.height.intValue, 1080);
    XCTAssertEqual(s.preferredCodec, CODEC_PREF_AV1);
    XCTAssertTrue(s.enableHdr);
    XCTAssertTrue(s.enableYUV444);
    XCTAssertTrue(s.playAudioOnPC);
}

- (void)testBadValuesAreIgnored {
    [_defaults setObject:@"wide" forKey:StreamResolutionKey];
    [_defaults setObject:@"vp9" forKey:StreamCodecKey];
    TemporarySettings *s = [self settings];
    XCTAssertEqualObjects(StreamApplyTestOverrides(s, _defaults), @"");
    XCTAssertEqual(s.width.intValue, 2420);
    XCTAssertEqual(s.preferredCodec, CODEC_PREF_HEVC);
}

@end
