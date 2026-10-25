//
//  VideoFormatTests.m
//  Starwire
//
//  The decoder's pixel format for 4:4:4 and full range streams, and the range the renderer
//  reads back from a decoded pixel format.
//

#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>

#import "VideoFormatPolicy.h"
#import "MetalVideoRenderer.h"
#import "HDRConstants.h"
#import "StreamPictureInPicture.h"
#import "ExternalDisplay.h"
#import "FrameInterpolator.h"
#import "PacingPolicy.h"
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


// Interpolation needs room on the display for twice the stream's rate
- (void)testFrameInterpolationApplies {
    XCTAssertTrue(FrameInterpolationApplies(YES, YES, 60, 120));
    XCTAssertTrue(FrameInterpolationApplies(YES, YES, 59.94, 120));
    XCTAssertFalse(FrameInterpolationApplies(YES, YES, 120, 120));
    XCTAssertFalse(FrameInterpolationApplies(NO, YES, 60, 120));
    XCTAssertFalse(FrameInterpolationApplies(YES, NO, 60, 120));
    XCTAssertFalse(FrameInterpolationApplies(YES, YES, 0, 120));
    // The simulator has no frame interpolation
    XCTAssertFalse([FrameInterpolator isAvailable]);
    XCTAssertNil([[FrameInterpolator alloc] initWithWidth:1920 height:1080]);
}

- (void)testFrameRateOverrideIsOnlyUsedWhenSet {
    NSString *suite = @"VideoFormatTests.fps";
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults removePersistentDomainForName:suite];
    XCTAssertEqual(StreamFrameRateWithOverride(defaults, 120), 120);
    [defaults setInteger:60 forKey:StreamFrameRateKey];
    XCTAssertEqual(StreamFrameRateWithOverride(defaults, 120), 60);
    [defaults removePersistentDomainForName:suite];
}


// Unset, the app's setting holds; set, the launch argument wins either way
- (void)testPlayAudioOnPCOverride {
    NSString *suite = @"VideoFormatTests.audio";
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults removePersistentDomainForName:suite];
    XCTAssertFalse(StreamPlayAudioOnPCWithOverride(defaults, NO));
    XCTAssertTrue(StreamPlayAudioOnPCWithOverride(defaults, YES));
    [defaults setBool:YES forKey:StreamPlayAudioOnPCKey];
    XCTAssertTrue(StreamPlayAudioOnPCWithOverride(defaults, NO));
    [defaults setBool:NO forKey:StreamPlayAudioOnPCKey];
    XCTAssertFalse(StreamPlayAudioOnPCWithOverride(defaults, YES));
    [defaults removePersistentDomainForName:suite];
}


- (void)testColorSpaceSetting {
    NSString *suite = @"VideoFormatTests.colorspace";
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults removePersistentDomainForName:suite];
    XCTAssertEqual(StreamColorSpaceFromDefaults(defaults), COLORSPACE_REC_601);
    [defaults setObject:@"709" forKey:StreamColorSpaceKey];
    XCTAssertEqual(StreamColorSpaceFromDefaults(defaults), COLORSPACE_REC_709);
    [defaults removePersistentDomainForName:suite];
}


// SDR asks for standard dynamic range explicitly; the default ("automatic") dimmed SDR white to
// 197 of 255 on the iPad Pro M4 with iPadOS 27
- (void)testSdrLayersAskForStandardDynamicRange {
    XCTAssertFalse(MetalLayerWantsHighDynamicRange(MetalLayerModeSDR));
    XCTAssertTrue(MetalLayerWantsHighDynamicRange(MetalLayerModeEDR));
    XCTAssertTrue(MetalLayerWantsHighDynamicRange(MetalLayerModePQ));
    CAMetalLayer *layer = [CAMetalLayer layer];
    MetalLayerApplyDynamicRange(layer, MetalLayerModeSDR);
    if (@available(iOS 26.0, *)) {
        XCTAssertEqualObjects(layer.preferredDynamicRange, CADynamicRangeStandard);
        MetalLayerApplyDynamicRange(layer, MetalLayerModeEDR);
        XCTAssertEqualObjects(layer.preferredDynamicRange, CADynamicRangeHigh);
    }
}


// PQ white for an SDR desktop in Windows HDR sits near BT.2408's 203 nits; at 100 the picture was
// pushed into the tone mapper and looked washed out next to picture in picture
- (void)testHdrReferenceWhiteIsBt2408 {
    XCTAssertEqual(STARWIRE_HDR_REFERENCE_WHITE_NITS, 203.0f);
}


// Up to the knee nothing changes; above it highlights ease toward the headroom and never pass it
- (void)testHdrRollOffKeepsNormalWhiteAndFitsHighlights {
    XCTAssertEqualWithAccuracy(StarwireHDRRollOff(0.5f, 3.0f), 0.5f, 1e-6);
    XCTAssertEqualWithAccuracy(StarwireHDRRollOff(1.0f, 3.0f), 1.0f, 1e-6);
    XCTAssertEqualWithAccuracy(StarwireHDRRollOff(2.4f, 3.0f), 2.4f, 1e-6);
    float a = StarwireHDRRollOff(3.0f, 3.0f), b = StarwireHDRRollOff(5.0f, 3.0f), c = StarwireHDRRollOff(50.0f, 3.0f);
    XCTAssertGreaterThan(a, 2.4f);
    XCTAssertGreaterThan(b, a);
    XCTAssertGreaterThan(c, b);
    XCTAssertLessThanOrEqual(c, 3.0f);
    // No headroom: normal white is the ceiling
    XCTAssertEqualWithAccuracy(StarwireHDRRollOff(4.0f, 1.0f), 1.0f, 1e-6);
    XCTAssertEqualWithAccuracy(StarwireHDRRollOff(0.7f, 0.5f), 0.7f, 1e-6);
}

@end
