//
//  VideoFormatTests.m
//  Starwire
//
//  The decoder's pixel format for 4:4:4 and full range streams, and the range the renderer
//  reads back from a decoded pixel format.
//

#import <XCTest/XCTest.h>

#import "VideoFormatPolicy.h"
#import "MetalVideoRenderer.h"
#import "StreamPictureInPicture.h"
#import "ExternalDisplay.h"
#include "Limelight.h"

@interface VideoFormatTests : XCTestCase
@end

@implementation VideoFormatTests

- (void)testFourTwoZeroUsesTenBitsInTheAskedRange {
    XCTAssertEqual(StreamDecoderPixelFormat(VIDEO_FORMAT_H265, NO), kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange);
    XCTAssertEqual(StreamDecoderPixelFormat(VIDEO_FORMAT_H265, YES), kCVPixelFormatType_420YpCbCr10BiPlanarFullRange);
    XCTAssertEqual(StreamDecoderPixelFormat(VIDEO_FORMAT_AV1_MAIN10, NO), kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange);
}

- (void)testFourFourFourKeepsItsBitDepth {
    XCTAssertEqual(StreamDecoderPixelFormat(VIDEO_FORMAT_H265_REXT8_444, NO), kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange);
    XCTAssertEqual(StreamDecoderPixelFormat(VIDEO_FORMAT_H265_REXT8_444, YES), kCVPixelFormatType_444YpCbCr8BiPlanarFullRange);
    XCTAssertEqual(StreamDecoderPixelFormat(VIDEO_FORMAT_H265_REXT10_444, NO), kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange);
    XCTAssertEqual(StreamDecoderPixelFormat(VIDEO_FORMAT_H265_REXT10_444, YES), kCVPixelFormatType_444YpCbCr10BiPlanarFullRange);
}

- (void)testRangeComesFromThePixelFormat {
    BOOL known = NO;
    XCTAssertTrue(StreamPixelFormatIsFullRange(kCVPixelFormatType_444YpCbCr8BiPlanarFullRange, &known));
    XCTAssertTrue(known);
    XCTAssertFalse(StreamPixelFormatIsFullRange(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, &known));
    XCTAssertTrue(known);
    // Every format the decoder can be asked for has a known range
    int formats[] = {VIDEO_FORMAT_H265, VIDEO_FORMAT_H265_REXT8_444, VIDEO_FORMAT_H265_REXT10_444};
    for (int i = 0; i < 3; i++) {
        for (int full = 0; full <= 1; full++) {
            BOOL isFull = StreamPixelFormatIsFullRange(StreamDecoderPixelFormat(formats[i], full), &known);
            XCTAssertTrue(known);
            XCTAssertEqual(isFull, (BOOL)full);
        }
    }
    StreamPixelFormatIsFullRange(kCVPixelFormatType_32BGRA, &known);
    XCTAssertFalse(known);
}

- (void)testFullRangeSetting {
    NSString *suite = @"VideoFormatTests.fullRange";
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults removePersistentDomainForName:suite];
    XCTAssertFalse(StreamUsesFullRange(defaults));
    [defaults setBool:YES forKey:StreamFullRangeKey];
    XCTAssertTrue(StreamUsesFullRange(defaults));
    [defaults removePersistentDomainForName:suite];
}


// HDR10 frames use VoidLink's EDR path when the system has EDR; SDR frames never do, so a stream
// that leaves HDR goes back to a plain layer
- (void)testLayerModeForFrames {
    XCTAssertEqual(MetalLayerModeForFrame(YES, YES), MetalLayerModeEDR);
    XCTAssertEqual(MetalLayerModeForFrame(YES, NO), MetalLayerModePQ);
    XCTAssertEqual(MetalLayerModeForFrame(NO, YES), MetalLayerModeSDR);
    XCTAssertEqual(MetalLayerModeForFrame(NO, NO), MetalLayerModeSDR);
}


// Two frames a second keep the layer ready while the app is in front; every frame once the
// picture in picture window is up
- (void)testPictureInPictureFeedsTheLayerSlowlyUntilItShows {
    XCTAssertTrue(PictureInPictureShouldEnqueue(NO, 10.0, 0, 0.5));
    XCTAssertFalse(PictureInPictureShouldEnqueue(NO, 10.2, 10.0, 0.5));
    XCTAssertTrue(PictureInPictureShouldEnqueue(NO, 10.5, 10.0, 0.5));
    XCTAssertTrue(PictureInPictureShouldEnqueue(YES, 10.0083, 10.0, 0.5));
}

- (void)testOnlyPictureInPictureKeepsTheStreamInTheBackground {
    XCTAssertTrue(StreamEndsOnBackground(NO));
    XCTAssertFalse(StreamEndsOnBackground(YES));
    NSString *suite = @"VideoFormatTests.pip";
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults removePersistentDomainForName:suite];
    // Off by default, as on Android
    XCTAssertFalse(StreamUsesPictureInPicture(defaults));
    [defaults setBool:YES forKey:StreamPictureInPictureKey];
    XCTAssertTrue(StreamUsesPictureInPicture(defaults));
    [defaults removePersistentDomainForName:suite];
}


// Mirroring unless the video is set to go to the display, and only while one is connected
- (void)testExternalDisplayMode {
    XCTAssertFalse(ExternalDisplayShowsVideo(ExternalDisplayModeMirror, YES));
    XCTAssertFalse(ExternalDisplayShowsVideo(ExternalDisplayModeVideo, NO));
    XCTAssertTrue(ExternalDisplayShowsVideo(ExternalDisplayModeVideo, YES));
    NSString *suite = @"VideoFormatTests.external";
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults removePersistentDomainForName:suite];
    XCTAssertEqual(ExternalDisplayModeFromDefaults(defaults), ExternalDisplayModeMirror);
    [defaults setObject:@"video" forKey:ExternalDisplayKey];
    XCTAssertEqual(ExternalDisplayModeFromDefaults(defaults), ExternalDisplayModeVideo);
    [defaults removePersistentDomainForName:suite];
}

@end
