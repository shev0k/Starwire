//
//  PacingTests.m
//  Starwire
//
//  The present-timing rule, the pacing settings, the drop policies and the pacing statistics.
//  Every time here is made up and passed in; nothing reads a clock.
//

#import <XCTest/XCTest.h>
#import <CoreMedia/CoreMedia.h>

#import "FrameQueue.h"
#import "PacingPolicy.h"
#import "PacingStats.h"
#include "Limelight.h"

static const double kMs = 1000.0;

@interface PacingTests : XCTestCase
@end

@implementation PacingTests {
    int _frameNumber;
    NSString *_suiteName;
    NSUserDefaults *_defaults;
}

- (void)setUp {
    [super setUp];
    _frameNumber = 0;
    _suiteName = [NSString stringWithFormat:@"PacingTests.%@", self.name];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suiteName];
    [_defaults removePersistentDomainForName:_suiteName];
}

- (void)tearDown {
    [_defaults removePersistentDomainForName:_suiteName];
    [super tearDown];
}

- (Frame *)makeFrameOfType:(int)type at:(CFTimeInterval)time {
    CMSampleTimingInfo timing = {
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake((int64_t)(_frameNumber * 750), 90000),
        .decodeTimeStamp = kCMTimeInvalid,
    };
    CMSampleBufferRef buf = NULL;
    XCTAssertEqual(CMSampleBufferCreate(kCFAllocatorDefault, NULL, NO, NULL, NULL, NULL, 1, 1, &timing, 0, NULL, &buf), noErr);
    Frame *frame = [[Frame alloc] initWithSampleBuffer:buf frameNumber:++_frameNumber frameType:type];
    frame.decodedAt = time;
    return frame;
}

- (Frame *)makeFrameAt:(CFTimeInterval)time {
    return [self makeFrameOfType:FRAME_TYPE_PFRAME at:time];
}

#pragma mark - Present timing

- (void)testNearestRefreshHoldsOneRefreshAt120FpsOn120Hz {
    // Half a refresh short of the frame interval, so a frame can't slip to a second refresh
    XCTAssertEqualWithAccuracy(PacingMinimumPresentDuration(PresentTimingNearestRefresh, 120, 120) * kMs, 4.1667, 0.001);
}

- (void)testNearestRefreshHoldsTwoRefreshesAt60FpsOn120Hz {
    double ms = PacingMinimumPresentDuration(PresentTimingNearestRefresh, 60, 120) * kMs;
    XCTAssertEqualWithAccuracy(ms, 12.5, 0.001);
    // More than one refresh (8.33 ms), less than two (16.67 ms)
    XCTAssertGreaterThan(ms, 1000.0 / 120);
    XCTAssertLessThan(ms, 2000.0 / 120);
}

- (void)testFrameIntervalIsTheOldRule {
    XCTAssertEqualWithAccuracy(PacingMinimumPresentDuration(PresentTimingFrameInterval, 120, 120) * kMs, 8.3333, 0.001);
}

- (void)testStreamFasterThanDisplayPresentsEveryRefresh {
    XCTAssertEqual(PacingMinimumPresentDuration(PresentTimingNearestRefresh, 120, 60), 0);
}

- (void)testBadInputsPresentOnNextRefresh {
    XCTAssertEqual(PacingMinimumPresentDuration(PresentTimingNearestRefresh, 0, 120), 0);
    XCTAssertEqual(PacingMinimumPresentDuration(PresentTimingNearestRefresh, 120, 0), 0);
    XCTAssertEqual(PacingMinimumPresentDuration(PresentTimingFrameInterval, -1, 120), 0);
}

#pragma mark - Settings

- (void)testDefaults {
    PacingSettings *settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual(settings.presentTiming, PresentTimingNearestRefresh);
    XCTAssertEqual(settings.dropPolicy, FrameDropPolicyAlternate);
    XCTAssertEqual(settings.framesToBufferOverride, 0);
    XCTAssertEqual([settings framesToBufferWithAppSetting:2], 2);
    XCTAssertFalse(StreamUsesVirtualDisplay(_defaults));
}

- (void)testSettingsFromDefaults {
    [_defaults setObject:@"frame" forKey:PacingPresentTimingKey];
    [_defaults setObject:@"newest" forKey:PacingDropPolicyKey];
    [_defaults setInteger:3 forKey:PacingFramesToBufferKey];
    [_defaults setBool:YES forKey:StreamVirtualDisplayKey];

    PacingSettings *settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual(settings.presentTiming, PresentTimingFrameInterval);
    XCTAssertEqual(settings.dropPolicy, FrameDropPolicyNewest);
    XCTAssertEqual([settings framesToBufferWithAppSetting:2], 3);
    XCTAssertEqualObjects(settings.presentTimingName, @"frame");
    XCTAssertEqualObjects(settings.dropPolicyName, @"newest");
    XCTAssertTrue(StreamUsesVirtualDisplay(_defaults));
}

- (void)testOutOfRangeBufferOverrideIsIgnored {
    [_defaults setInteger:9 forKey:PacingFramesToBufferKey];
    PacingSettings *settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual([settings framesToBufferWithAppSetting:2], 2);
}

#pragma mark - Drop policies

- (FrameQueue *)queueWithPolicy:(FrameDropPolicy)policy buffer:(int)buffer stats:(PacingStats *)stats {
    FrameQueue *queue = [[FrameQueue alloc] initWithMaxCapacity:15];
    queue.highWaterMark = buffer;
    queue.dropPolicy = policy;
    queue.pacingStats = stats;
    [queue start];
    return queue;
}

- (PacingStats *)stats120 {
    return [[PacingStats alloc] initWithFrameInterval:1.0 / 120 refreshInterval:1.0 / 120 windowLength:5.0];
}

- (void)testNewestPolicyAlwaysKeepsTheNewestFrames {
    PacingStats *stats = [self stats120];
    FrameQueue *queue = [self queueWithPolicy:FrameDropPolicyNewest buffer:2 stats:stats];
    for (int i = 0; i < 5; i++) {
        [queue enqueue:[self makeFrameAt:10.0 + i / 120.0]];
    }
    // 1 and 2 queued; 3, 4 and 5 each push out the oldest
    XCTAssertEqual([queue dequeue].frameNumber, 4);
    XCTAssertEqual([queue dequeue].frameNumber, 5);
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.drops[PacingDropOldest], 3);
    XCTAssertEqual(w.drops[PacingDropIncoming], 0);
}

- (void)testAlternatePolicyReportsBothReasons {
    PacingStats *stats = [self stats120];
    FrameQueue *queue = [self queueWithPolicy:FrameDropPolicyAlternate buffer:2 stats:stats];
    for (int i = 0; i < 4; i++) {
        [queue enqueue:[self makeFrameAt:10.0 + i / 120.0]];
    }
    // 3 is dropped as it arrives, then 4 pushes out 1
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.drops[PacingDropIncoming], 1);
    XCTAssertEqual(w.drops[PacingDropOldest], 1);
    XCTAssertEqual([queue dequeue].frameNumber, 2);
    XCTAssertEqual([queue dequeue].frameNumber, 4);
}

- (void)testNewestPolicyNeverDropsAnIDRFrame {
    FrameQueue *queue = [self queueWithPolicy:FrameDropPolicyNewest buffer:1 stats:nil];
    [queue enqueue:[self makeFrameOfType:FRAME_TYPE_IDR at:1.0]];
    [queue enqueue:[self makeFrameAt:1.01]];
    XCTAssertEqual([queue dequeue].frameNumber, 1);
    XCTAssertEqual([queue dequeue].frameNumber, 2);
}

- (void)testQueueNeverOverwritesWhenFullOfIDRFrames {
    FrameQueue *queue = [[FrameQueue alloc] initWithMaxCapacity:4];
    queue.highWaterMark = 2;
    [queue start];
    for (int i = 0; i < 6; i++) {
        [queue enqueue:[self makeFrameOfType:FRAME_TYPE_IDR at:1.0 + i]];
    }
    XCTAssertEqual([queue count], 4);
    // The oldest two made room; the newest four remain, in order
    for (int expected = 3; expected <= 6; expected++) {
        XCTAssertEqual([queue dequeue].frameNumber, expected);
    }
}

#pragma mark - Pacing statistics

- (void)testSteadyArrivalsAreOnTime {
    PacingStats *stats = [self stats120];
    for (int i = 0; i < 120; i++) {
        [stats noteArrivalAt:100.0 + i / 120.0];
    }
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.arrivals, 120);
    XCTAssertEqual(w.arrivalOnTime, 119);
    XCTAssertEqual(w.arrivalBursts, 0);
    XCTAssertEqualWithAccuracy(w.maxArrivalGapMs, 8.333, 0.01);
}

- (void)testPairedArrivalsCountAsBursts {
    // Frames arrive two at a time, every two frame intervals: what a host capturing a 480 Hz
    // desktop at 120 FPS, or Wi-Fi batching, can look like
    PacingStats *stats = [self stats120];
    for (int pair = 0; pair < 60; pair++) {
        double t = 100.0 + pair * (2.0 / 120);
        [stats noteArrivalAt:t];
        [stats noteArrivalAt:t + 0.0005];
    }
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.arrivalBursts, 60);
    XCTAssertEqual(w.arrivalLate, 59);
    XCTAssertEqual(w.arrivalOnTime, 0);
}

- (void)testDropRightAfterABurstIsAttributedToIt {
    PacingStats *stats = [self stats120];
    [stats noteArrivalAt:100.0];
    [stats noteArrivalAt:100.0 + 1.0 / 120];
    [stats noteDrop:PacingDropIncoming queueDepth:2];
    [stats noteArrivalAt:100.0 + 1.0 / 120 + 0.0005];
    [stats noteDrop:PacingDropOldest queueDepth:2];
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.drops[PacingDropIncoming], 1);
    XCTAssertEqual(w.drops[PacingDropOldest], 1);
    XCTAssertEqual(w.dropsAfterBurst, 1);
    XCTAssertEqual(w.maxQueueDepth, 2);
}

- (void)testPresentHoldsAreCountedInRefreshes {
    PacingStats *stats = [self stats120];
    const double r = 1.0 / 120;
    double t = 200.0;
    [stats notePresentedAt:t];
    // one refresh, one refresh, two refreshes, three refreshes
    [stats notePresentedAt:(t += r)];
    [stats notePresentedAt:(t += r)];
    [stats notePresentedAt:(t += 2 * r)];
    [stats notePresentedAt:(t += 3 * r)];
    // the compositor skipped one
    [stats notePresentedAt:0];
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.presented, 5);
    XCTAssertEqual(w.heldOneRefresh, 2);
    XCTAssertEqual(w.heldTwoRefreshes, 1);
    XCTAssertEqual(w.heldThreeOrMore, 1);
    XCTAssertEqual(w.presentSkipped, 1);
}

- (void)testWindowRollsAfterItsLength {
    PacingStats *stats = [self stats120];
    [stats noteArrivalAt:10.0];
    [stats noteArrivalAt:12.0];
    XCTAssertFalse([stats rollWindowIfDueAt:14.9]);
    XCTAssertEqual([stats lastWindow].arrivals, 0);

    // The arrival at 15 s ends the first window, then counts in the next
    [stats noteArrivalAt:15.0];
    PacingWindow last = [stats lastWindow];
    XCTAssertEqual(last.arrivals, 2);
    XCTAssertEqualWithAccuracy(last.windowSeconds, 5.0, 0.0001);
    XCTAssertEqual([stats currentWindow].arrivals, 1);
}

- (void)testLinesNameTheNumbers {
    PacingStats *stats = [self stats120];
    [stats noteArrivalAt:1.0];
    [stats noteArrivalAt:1.0005];
    [stats noteDrop:PacingDropIncoming queueDepth:2];
    PacingWindow w = [stats currentWindow];
    NSString *log = [PacingStats logLineForWindow:w];
    XCTAssertTrue([log containsString:@"in 2"], @"%@", log);
    XCTAssertTrue([log containsString:@"drops 1"], @"%@", log);
    NSString *overlay = [PacingStats overlayLineForWindow:w];
    XCTAssertTrue([overlay hasPrefix:@"Pacing: "], @"%@", overlay);
    XCTAssertTrue([overlay containsString:@"bursts 100.0%"], @"%@", overlay);
}

@end
