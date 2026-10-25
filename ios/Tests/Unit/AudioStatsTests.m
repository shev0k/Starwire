//
//  AudioStatsTests.m
//  Starwire
//
//  The overlay's audio bitrate and decode time. The overlay can be read twice within a few
//  milliseconds, which gave bitrates in the billions of kbps, and a window with no packets gave
//  "nan" for the decode time.
//

#import <XCTest/XCTest.h>

#import "AudioStatsMath.h"

@interface AudioStatsTests : XCTestCase
@end

@implementation AudioStatsTests

- (void)testBitrateOverAWindow {
    // 64 kbps Opus: 8000 bytes a second
    XCTAssertEqualWithAccuracy(AudioStatsKbps(8000, 1.0), 64.0, 1e-9);
    XCTAssertEqualWithAccuracy(AudioStatsKbps(4000, 0.5), 64.0, 1e-9);
    XCTAssertEqualWithAccuracy(AudioStatsKbps(0, 1.0), 0.0, 1e-9);
}

- (void)testShortWindowsAreNotSampled {
    // One 160 byte packet over 2 ms read as 640 kbps; over 0.1 ms as 12800
    XCTAssertEqual(AudioStatsKbps(160, 0.002), -1);
    XCTAssertEqual(AudioStatsKbps(160, 0.0001), -1);
    XCTAssertEqual(AudioStatsKbps(160, 0), -1);
    XCTAssertEqual(AudioStatsKbps(160, -1), -1);
}

- (void)testDecodeTimeIsPerPacketInMilliseconds {
    XCTAssertEqualWithAccuracy(AudioStatsMeanMs(12.0, 4), 3.0, 1e-9);
    XCTAssertEqual(AudioStatsMeanMs(0, 0), -1);
}

@end
