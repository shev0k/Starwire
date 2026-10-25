//
//  PacingTests.m
//  Starwire
//
//  The present-timing rule, the pacing settings, the drop policies, the pacing statistics and the
//  display presenter's choice of frame.
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

- (void)testPresentIntervalsAreCountedInHalfRefreshSteps {
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
    XCTAssertEqual(w.shown.total, 4);
    XCTAssertEqual(w.shown.counts[2], 2);  // 8.33 ms
    XCTAssertEqual(w.shown.counts[4], 1);  // 16.67 ms
    XCTAssertEqual(w.shown.counts[6], 1);  // 25 ms and up
    XCTAssertEqual(w.shown.offGrid, 0);
    XCTAssertEqual(w.presentSkipped, 1);
}

- (void)testIntervalBuckets {
    const double step = 1.0 / 240;
    XCTAssertEqual(PacingIntervalBucket(0, step), 0);
    XCTAssertEqual(PacingIntervalBucket(0.0042, step), 1);
    XCTAssertEqual(PacingIntervalBucket(0.00833, step), 2);
    XCTAssertEqual(PacingIntervalBucket(0.0125, step), 3);
    XCTAssertEqual(PacingIntervalBucket(0.01667, step), 4);
    XCTAssertEqual(PacingIntervalBucket(0.0208, step), 5);
    XCTAssertEqual(PacingIntervalBucket(0.1, step), PACING_INTERVAL_BUCKETS - 1);
    XCTAssertEqual(PacingIntervalBucket(-1, step), 0);
    XCTAssertEqual(PacingIntervalBucket(0.01, 0), 0);
}

// Regression: the old counter put anything under 1.5 refreshes in "held 1", and 1.5 refreshes
// is exactly 12.5 ms at 120 Hz. A stream shown at 8.33 and 12.5 ms in turn averages 96 FPS
// but showed as nearly all "held for one refresh". Each interval now has its own bucket.
- (void)testFramesShownFor12_5MsAreNotCountedAsOneRefresh {
    PacingStats *stats = [self stats120];
    double t = 300.0;
    [stats notePresentedAt:t];
    for (int i = 0; i < 50; i++) {
        // Slightly under 12.5 ms, as a clock can report it
        [stats notePresentedAt:(t += 1.0 / 120)];
        [stats notePresentedAt:(t += 0.0124999)];
    }
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.shown.counts[2], 50);
    XCTAssertEqual(w.shown.counts[3], 50);
    XCTAssertEqualWithAccuracy(w.shown.sumSeconds * 1000.0 / w.shown.total, 10.4167, 0.001);
    NSString *overlay = [stats overlayLineForWindow:w];
    XCTAssertTrue([overlay containsString:@"4.2/8.3/12.5/16.7/20.8/25+ ms: 0.0/50.0/50.0/0.0/0.0/0.0%"], @"%@", overlay);
}

- (void)testIntervalsOffTheGridAreCounted {
    PacingStats *stats = [self stats120];
    // 10.4 ms is halfway between two 4.17 ms steps
    [stats noteRefreshInterval:0.0104];
    [stats noteRefreshInterval:1.0 / 120];
    [stats noteRefreshInterval:0];
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.refresh.total, 2);
    XCTAssertEqual(w.refresh.offGrid, 1);
    XCTAssertEqualWithAccuracy(w.refresh.maxSeconds, 0.0104, 1e-9);
}

- (void)testPresentLaterThanItsTargetIsLate {
    PacingStats *stats = [self stats120];
    [stats notePresentedAt:10.0 target:10.0 decodedAt:0];
    // 1 ms late is the same refresh as far as the panel is concerned
    [stats notePresentedAt:10.0093 target:10.0083 decodedAt:0];
    // a whole refresh late
    [stats notePresentedAt:10.025 target:10.0167 decodedAt:0];
    // no target known (the render loop)
    [stats notePresentedAt:10.05];
    XCTAssertEqual([stats currentWindow].presentLate, 1);
}

- (void)testDecodeToScreenLatency {
    PacingStats *stats = [self stats120];
    [stats notePresentedAt:20.010 target:0 decodedAt:20.000];
    [stats notePresentedAt:20.0283 target:0 decodedAt:20.0083];
    // Unknown decode time, a skipped drawable, and a clock that went backwards: not counted
    [stats notePresentedAt:20.04 target:0 decodedAt:0];
    [stats notePresentedAt:0 target:0 decodedAt:20.03];
    [stats notePresentedAt:20.05 target:0 decodedAt:20.06];
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.latencySamples, 2);
    XCTAssertEqualWithAccuracy(w.latencySeconds * 1000.0 / w.latencySamples, 15.0, 0.001);
    XCTAssertEqualWithAccuracy(w.maxLatencyMs, 20.0, 0.001);
    XCTAssertTrue([[stats overlayLineForWindow:w] containsString:@"decode to screen 15.0 ms"]);
}

- (void)testRefreshesWithAndWithoutAFrame {
    PacingStats *stats = [self stats120];
    [stats noteRefreshWithNewFrame:YES];
    [stats noteRefreshWithNewFrame:YES];
    [stats noteRefreshWithNewFrame:NO];
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.refreshesWithFrame, 2);
    XCTAssertEqual(w.refreshesWithoutFrame, 1);
}

- (void)testDrawableWaits {
    PacingStats *stats = [self stats120];
    [stats noteDrawableWait:0.002];
    [stats noteDrawableWait:0.008];
    [stats noteDrawableWait:-1];
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.drawableWaits, 2);
    XCTAssertEqualWithAccuracy(w.drawableWaitSeconds, 0.010, 1e-9);
    XCTAssertEqualWithAccuracy(w.maxDrawableWaitMs, 8.0, 1e-6);
}

- (void)testTotalAddsFinishedWindowsAndTheCurrentOne {
    PacingStats *stats = [self stats120];
    [stats noteArrivalAt:10.0];
    [stats noteDrop:PacingDropIncoming queueDepth:2];
    [stats notePresentedAt:10.0];
    [stats notePresentedAt:10.0 + 1.0 / 120];
    // Ends the first window
    [stats noteArrivalAt:15.0];
    [stats noteDrop:PacingDropReplaced queueDepth:1];
    [stats notePresentedAt:15.0];

    PacingWindow total = [stats totalWindow];
    XCTAssertEqual(total.arrivals, 2);
    XCTAssertEqual(total.drops[PacingDropIncoming], 1);
    XCTAssertEqual(total.drops[PacingDropReplaced], 1);
    XCTAssertEqual(total.presented, 3);
    XCTAssertEqual(total.shown.total, 2);
    XCTAssertEqualWithAccuracy(total.windowSeconds, 5.0, 0.0001);
    // The current window alone has only what came after the roll
    XCTAssertEqual([stats currentWindow].arrivals, 1);
}

- (void)testReplacedDropsAreNotCountedAsAfterABurst {
    PacingStats *stats = [self stats120];
    [stats noteArrivalAt:1.0];
    [stats noteArrivalAt:1.0005];
    [stats noteDrop:PacingDropReplaced queueDepth:2];
    XCTAssertEqual([stats currentWindow].dropsAfterBurst, 0);
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
    NSString *log = [stats logLineForWindow:w];
    XCTAssertTrue([log containsString:@"in 2"], @"%@", log);
    XCTAssertTrue([log containsString:@"drops 1"], @"%@", log);
    NSString *overlay = [stats overlayLineForWindow:w];
    // The network line first, then pacing
    XCTAssertTrue([overlay hasPrefix:@"Network: "], @"%@", overlay);
    XCTAssertTrue([overlay containsString:@"\nPacing: "], @"%@", overlay);
    XCTAssertTrue([overlay containsString:@"bursts 100.0%"], @"%@", overlay);
    XCTAssertTrue([overlay containsString:@"\nShown for "], @"%@", overlay);
}

- (void)testSummaryLineNamesThePresenter {
    PacingStats *stats = [self stats120];
    stats.presenterName = @"display";
    for (int i = 0; i < 4; i++) {
        [stats noteArrivalAt:1.0 + i / 120.0];
        [stats notePresentedAt:1.01 + i / 120.0];
    }
    [stats noteDrop:PacingDropReplaced queueDepth:1];
    NSString *summary = [stats summaryLineForWindow:[stats totalWindow]];
    XCTAssertTrue([summary hasPrefix:@"Pacing summary (display): "], @"%@", summary);
    XCTAssertTrue([summary containsString:@"in 4, drops 25.00% (incoming 0, oldest 0, replaced 1)"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"shown for 4.2/8.3/12.5/16.7/20.8/25+ ms: 0.0/100.0/0.0/0.0/0.0/0.0%"], @"%@", summary);
}

// A freeze shows in the summary as a long arrival gap or a long shown time, so a run can tell
// frames that came late from frames that came on time and were shown late
- (void)testSummaryLineShowsArrivalGapsAndLongestShown {
    PacingStats *stats = [self stats120];
    [stats noteArrivalAt:1.0];
    [stats noteArrivalAt:1.0 + 1 / 120.0];
    [stats noteArrivalAt:1.1];
    [stats notePresentedAt:1.01];
    [stats notePresentedAt:1.01 + 1 / 120.0];
    [stats notePresentedAt:1.11];
    NSString *summary = [stats summaryLineForWindow:[stats totalWindow]];
    XCTAssertTrue([summary containsString:@"arrival late 0, gaps 1, max gap 91.7 ms; shown 3,"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"mean 50.00 ms, max 91.7 ms,"], @"%@", summary);
}

#pragma mark - Display presenter

- (void)testPresenterSettings {
    // The system presenter is the default since batch 1
    PacingSettings *settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual(settings.presenter, PacingPresenterSystem);
    [_defaults setObject:@"loop" forKey:PacingPresenterKey];
    settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual(settings.presenter, PacingPresenterLoop);
    XCTAssertEqualObjects(settings.presenterName, @"loop");
    XCTAssertEqual(settings.effectiveDropPolicy, FrameDropPolicyAlternate);

    [_defaults setObject:@"display" forKey:PacingPresenterKey];
    settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual(settings.presenter, PacingPresenterDisplay);
    XCTAssertEqualObjects(settings.presenterName, @"display");
    // The display presenter always keeps the newest frame, whatever the drop policy says
    XCTAssertEqual(settings.dropPolicy, FrameDropPolicyAlternate);
    XCTAssertEqual(settings.effectiveDropPolicy, FrameDropPolicyNewest);
}

- (void)testDisplayFrameWaitIsHalfTheTimeLeft {
    XCTAssertEqualWithAccuracy(PacingDisplayFrameWait(10.0, 10.006), 0.003, 1e-9);
    XCTAssertEqual(PacingDisplayFrameWait(10.0, 10.0), 0);
    XCTAssertEqual(PacingDisplayFrameWait(10.01, 10.0), 0);
}

- (void)testDequeueNewestDropsTheOlderFrames {
    PacingStats *stats = [self stats120];
    FrameQueue *queue = [self queueWithPolicy:FrameDropPolicyNewest buffer:3 stats:stats];
    [queue enqueue:[self makeFrameOfType:FRAME_TYPE_IDR at:1.0]];
    [queue enqueue:[self makeFrameAt:1.002]];
    [queue enqueue:[self makeFrameAt:1.004]];

    // Already decoded, so even the IDR frame can be skipped
    XCTAssertEqual([queue dequeueNewestWithTimeout:0].frameNumber, 3);
    XCTAssertEqual([queue count], 0);
    XCTAssertEqual([stats currentWindow].drops[PacingDropReplaced], 2);

    // Counted in the overlay's drop share with the next arriving frame
    XCTAssertEqual(queue.frameDropMetrics.total, 0);
    [queue enqueue:[self makeFrameAt:1.0083]];
    XCTAssertEqual(queue.frameDropMetrics.total, 2);
    XCTAssertEqual(queue.frameDropMetrics.count, 4);
}

- (void)testDequeueNewestOnAnEmptyQueue {
    FrameQueue *queue = [self queueWithPolicy:FrameDropPolicyNewest buffer:2 stats:nil];
    XCTAssertNil([queue dequeueNewestWithTimeout:0]);
    [queue enqueue:[self makeFrameAt:1.0]];
    [queue stop];
    XCTAssertNil([queue dequeueNewestWithTimeout:0]);
}

// Frames arrive every 8.33 ms with up to 3 ms of jitter either way (a fixed-seed generator, so
// every run is the same), and the display asks for one at every 120 Hz refresh, half a refresh
// out of phase. Taking the newest frame at each refresh then shows every frame, one per
// refresh, with nothing left waiting: no drops and no extra frame of buffering.
- (void)testDisplayPresenterShowsEveryFrameWhenJitterIsUnderHalfARefresh {
    PacingStats *stats = [self stats120];
    FrameQueue *queue = [self queueWithPolicy:FrameDropPolicyNewest buffer:2 stats:stats];
    const double r = 1.0 / 120;
    uint32_t seed = 12345;
    enum { frames = 1200 };
    double arrivals[frames];
    for (int i = 0; i < frames; i++) {
        seed = seed * 1664525u + 1013904223u;
        double jitter = ((double)(seed >> 8) / (double)(1u << 24) - 0.5) * 0.006;
        arrivals[i] = 50.0 + i * r + jitter;
    }

    int shown = 0, empty = 0, next = 0;
    NSUInteger maxLeft = 0;
    for (int k = 0; k <= frames; k++) {
        double refresh = 50.0 + k * r + r / 2;
        while (next < frames && arrivals[next] <= refresh) {
            [stats noteArrivalAt:arrivals[next]];
            [queue enqueue:[self makeFrameAt:arrivals[next]]];
            next++;
        }
        Frame *frame = [queue dequeueNewestWithTimeout:0];
        if (frame) {
            shown++;
        } else {
            empty++;
        }
        maxLeft = MAX(maxLeft, [queue count]);
    }
    XCTAssertEqual(shown, frames);
    // Only the refresh after the last frame had nothing new
    XCTAssertEqual(empty, 1);
    PacingWindow total = [stats totalWindow];
    XCTAssertEqual(total.drops[PacingDropReplaced] + total.drops[PacingDropOldest] + total.drops[PacingDropIncoming], 0);
    XCTAssertEqual(maxLeft, 0u);
}

// Two frames in one refresh (a frame late, then one on time): the late one is replaced, which
// is the one kind of drop the display presenter makes.
- (void)testDisplayPresenterReplacesALateFrame {
    PacingStats *stats = [self stats120];
    FrameQueue *queue = [self queueWithPolicy:FrameDropPolicyNewest buffer:2 stats:stats];
    [queue enqueue:[self makeFrameAt:1.000]];
    XCTAssertEqual([queue dequeueNewestWithTimeout:0].frameNumber, 1);
    // nothing arrives for this refresh
    XCTAssertNil([queue dequeueNewestWithTimeout:0]);
    // frame 2 is a refresh late and frame 3 is on time
    [queue enqueue:[self makeFrameAt:1.0165]];
    [queue enqueue:[self makeFrameAt:1.0168]];
    XCTAssertEqual([queue dequeueNewestWithTimeout:0].frameNumber, 3);
    XCTAssertEqual([stats currentWindow].drops[PacingDropReplaced], 1);
}


#pragma mark - Network arrival

- (void)testMediaTimeFromMicroseconds {
    XCTAssertEqualWithAccuracy(PacingMediaTimeFromMicroseconds(1000000, 1250000, 10.0), 9.75, 1e-9);
    // A time read just after "now" still converts
    XCTAssertEqualWithAccuracy(PacingMediaTimeFromMicroseconds(1250100, 1250000, 10.0), 10.0001, 1e-9);
    XCTAssertEqual(PacingMediaTimeFromMicroseconds(0, 1250000, 10.0), 0);
}

// Frames on time, then a 50 ms hole and the 6 held frames at once: one gap and a clump of 6.
// The host's own times stay even, so the hole is the network's, not the host's.
- (void)testNetworkGapsAndClumpsAreMeasuredBeforeDecoding {
    PacingStats *stats = [self stats120];
    const double r = 1.0 / 120;
    double t = 1.0;
    uint64_t host = 1000000;
    for (int i = 0; i < 10; i++) {
        [stats noteNetworkFrameReceivedAt:t - 0.001 assembledAt:t hostTimeUs:host];
        t += r;
        host += 8333;
    }
    t += 0.050;
    for (int i = 0; i < 6; i++) {
        [stats noteNetworkFrameReceivedAt:t - 0.0005 assembledAt:t + i * 0.0002 hostTimeUs:host];
        host += 8333;
    }
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.netFrames, 16);
    XCTAssertEqual(w.netGaps, 1);
    XCTAssertEqualWithAccuracy(w.netMaxGapMs, 58.3, 0.1);
    XCTAssertEqual(w.netClumped, 5);
    XCTAssertEqual(w.netMaxClump, 6);
    XCTAssertEqual(w.hostGaps, 0);
    XCTAssertEqualWithAccuracy(w.netMaxReceiveMs, 1.5, 0.01);
}

- (void)testHostGapsAreCountedApart {
    PacingStats *stats = [self stats120];
    [stats noteNetworkFrameReceivedAt:1.0 assembledAt:1.001 hostTimeUs:1000000];
    // The host skipped 3 frames: its time jumps by 33 ms, and so does the arrival
    [stats noteNetworkFrameReceivedAt:1.034 assembledAt:1.035 hostTimeUs:1033333];
    PacingWindow w = [stats currentWindow];
    XCTAssertEqual(w.hostGaps, 1);
    XCTAssertEqual(w.netGaps, 1);
    XCTAssertEqualWithAccuracy(w.hostMaxGapMs, 33.3, 0.1);
}

- (void)testGapPeriodFindsARegularTimer {
    // Every 512 ms, with one missed (1024 ms) and a little wobble
    double times[] = {1.000, 1.512, 2.030, 2.536, 3.560, 4.072, 4.584};
    double regular = 0;
    double period = PacingGapPeriod(times, 7, &regular);
    XCTAssertEqualWithAccuracy(period, 0.512, 0.006);
    XCTAssertEqualWithAccuracy(regular, 1.0, 1e-9);

    // No timer: spacings all over the place
    double random[] = {1.0, 1.1, 1.9, 2.05, 3.4, 3.47, 4.9};
    PacingGapPeriod(random, 7, &regular);
    XCTAssertLessThan(regular, 0.5);

    XCTAssertEqual(PacingGapPeriod(times, 2, &regular), 0);
    XCTAssertEqual(regular, 0);
}

- (void)testSummaryShowsTheNetworkAndTheJitterBuffer {
    PacingStats *stats = [self stats120];
    stats.jitterBufferName = @"smooth";
    const double r = 1.0 / 120;
    double t = 1.0;
    for (int g = 0; g < 4; g++) {
        for (int i = 0; i < 60; i++) {
            [stats noteNetworkFrameReceivedAt:t assembledAt:t hostTimeUs:0];
            t += r;
        }
        t += 0.0333;
    }
    [stats noteJitterTarget:4];
    [stats noteJitterTarget:2];
    [stats notePresentedAt:2.0 target:0 decodedAt:1.99 receivedAt:1.98];
    NSString *summary = [stats summaryLineForWindow:[stats totalWindow]];
    XCTAssertTrue([summary containsString:@"network gaps 3, max 41.6 ms, every 533 ms (100% regular)"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"network to screen mean 20.0 ms"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"jitter buffer smooth, held mean 3.00, max 4, catch up 0"], @"%@", summary);
    NSString *overlay = [stats overlayLineForWindow:[stats currentWindow]];
    XCTAssertTrue([overlay hasPrefix:@"Network: gaps 3,"], @"%@", overlay);
}


#pragma mark - 1% low, refresh range and the Lite overlay

- (void)testOnePercentLowIsTheSlowestOnePercent {
    double intervals[200];
    for (int i = 0; i < 200; i++) {
        intervals[i] = 1.0 / 120;
    }
    // 2 of 200 frames held for 25 ms: the slowest 1% runs at 40 FPS
    intervals[17] = 0.025;
    intervals[150] = 0.025;
    XCTAssertEqualWithAccuracy(PacingOnePercentLowFps(intervals, 200), 40.0, 1e-6);
    // Fewer than 100 intervals still use the single slowest one
    intervals[3] = 0.050;
    XCTAssertEqualWithAccuracy(PacingOnePercentLowFps(intervals, 50), 20.0, 1e-6);
    XCTAssertEqual(PacingOnePercentLowFps(intervals, 0), 0);
}

- (void)testWindowsKeepTheirOnePercentLowAndTheStreamKeepsTheWorst {
    PacingStats *stats = [self stats120];
    [stats noteArrivalAt:1.0];
    double t = 1.0;
    for (int i = 0; i < 99; i++) {
        [stats notePresentedAt:(t += 1.0 / 120)];
    }
    [stats notePresentedAt:(t += 0.025)];
    XCTAssertTrue([stats rollWindowIfDueAt:6.1]);
    XCTAssertEqualWithAccuracy([stats lastWindow].onePercentLowFps, 40.0, 1e-6);

    for (int i = 0; i < 100; i++) {
        [stats notePresentedAt:(t += 1.0 / 120)];
    }
    XCTAssertTrue([stats rollWindowIfDueAt:11.2]);
    XCTAssertEqualWithAccuracy([stats lastWindow].onePercentLowFps, 120.0, 1e-6);
    XCTAssertEqualWithAccuracy([stats totalWindow].onePercentLowFps, 40.0, 1e-6);
    XCTAssertTrue([[stats overlayLineForWindow:[stats lastWindow]] containsString:@"1% low 120.0 FPS"]);
    XCTAssertTrue([[stats summaryLineForWindow:[stats totalWindow]] containsString:@"1% low (worst 5 s) 40.0 FPS"]);
}

- (void)testDisplayRefreshRangeKeepsTheTopRateUnlessReductionIsAllowed {
    PacingRefreshRange r = PacingDisplayRefreshRange(60, 120, NO);
    XCTAssertEqual(r.minimum, 60);
    XCTAssertEqual(r.maximum, 120);
    XCTAssertEqual(r.preferred, 120);
    r = PacingDisplayRefreshRange(60, 120, YES);
    XCTAssertEqual(r.minimum, 60);
    XCTAssertEqual(r.maximum, 60);
    XCTAssertEqual(r.preferred, 60);
    // A stream as fast as the display, or faster, runs at the display's rate
    r = PacingDisplayRefreshRange(120, 120, NO);
    XCTAssertEqual(r.preferred, 120);
    XCTAssertEqual(r.minimum, 120);
    r = PacingDisplayRefreshRange(240, 120, NO);
    XCTAssertEqual(r.maximum, 120);
    XCTAssertEqual(r.minimum, 120);
    r = PacingDisplayRefreshRange(0, 0, NO);
    XCTAssertEqual(r.preferred, 60);
}

- (void)testDisplaySettings {
    PacingSettings *settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertFalse(settings.reduceRefreshRate);
    XCTAssertEqual(settings.overlayLevel, StatsOverlayLevelFull);
    [_defaults setBool:YES forKey:PacingReduceRefreshRateKey];
    [_defaults setObject:@"lite" forKey:StatsOverlayLevelKey];
    settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertTrue(settings.reduceRefreshRate);
    XCTAssertEqual(settings.overlayLevel, StatsOverlayLevelLite);
}

- (void)testLiteOverlayIsOneLine {
    NSString *line = PacingLiteOverlayLine(119.84, 101.6, 0.0, 0.42, 14, 5.71, 120.0);
    XCTAssertEqualObjects(line, @"Video stream: 119.8 FPS, 1% low 102, drops 0.0% / 0.4%, latency 14 ms, decode 5.7 ms, display 120 Hz");
    line = PacingLiteOverlayLine(30, 0, 0, 0, -1, 0, 0);
    XCTAssertEqualObjects(line, @"Video stream: 30.0 FPS, 1% low -, drops 0.0% / 0.0%, latency - ms, decode 0.0 ms, display - Hz");
}


- (void)testSummaryShowsInterpolation {
    PacingStats *stats = [self stats120];
    stats.interpolationNote = @"on at 1920x1080";
    [stats noteInterpolatedFrame:YES seconds:0.003];
    [stats noteInterpolatedFrame:YES seconds:0.005];
    [stats noteInterpolatedFrame:NO seconds:0];
    NSString *summary = [stats summaryLineForWindow:[stats totalWindow]];
    XCTAssertTrue([summary containsString:@"; interpolation on at 1920x1080, made 2, failed 1, mean 4.00 ms;"], @"%@", summary);
}


- (void)testSummaryShowsPictureInPicture {
    PacingStats *stats = [self stats120];
    XCTAssertTrue([[stats summaryLineForWindow:[stats totalWindow]] containsString:@"; picture in picture off; colour -"]);
    stats.pictureInPictureNote = @"closed, started 1";
    XCTAssertTrue([[stats summaryLineForWindow:[stats totalWindow]] containsString:@"; picture in picture closed, started 1;"]);
}

- (void)testRefreshesPerFrame {
    XCTAssertEqual(PacingRefreshesPerFrame(120, 60), 2);
    XCTAssertEqual(PacingRefreshesPerFrame(120, 120), 1);
    XCTAssertEqual(PacingRefreshesPerFrame(120, 40), 3);
    XCTAssertEqual(PacingRefreshesPerFrame(60, 120), 1);
    XCTAssertEqual(PacingRefreshesPerFrame(0, 60), 1);
}

// 60 FPS on a 120 Hz display link, with frames landing within 1.5 ms of the refresh they are
// due for (a fixed-seed generator). Taking the newest frame at every refresh alternates 8.3 and
// 25 ms whenever a frame lands just after its refresh, as the iPad showed; holding each frame for
// two refreshes keeps nearly every frame on screen for 16.7 ms.
- (void)testHoldingEachFrameForItsRefreshesKeepsSixtyEven {
    const double r = 1.0 / 120;
    uint32_t seed = 4242;
    enum { frames = 600 };
    double arrivals[frames];
    for (int i = 0; i < frames; i++) {
        seed = seed * 1664525u + 1013904223u;
        double jitter = ((double)(seed >> 8) / (double)(1u << 24) - 0.5) * 0.003;
        arrivals[i] = 10.0 + i * 2 * r + jitter;
    }
    for (int hold = 0; hold <= 1; hold++) {
        int perFrame = hold ? PacingRefreshesPerFrame(120, 60) : 1;
        int since = perFrame, next = 0, queued = 0, lastShownRefresh = -1, even = 0, intervals = 0;
        for (int k = 0; k < frames * 2; k++) {
            double refresh = 10.0 + k * r;
            while (next < frames && arrivals[next] <= refresh) {
                queued++;
                next++;
            }
            since++;
            if (!PacingDisplayShouldTakeFrame(since, perFrame) || queued == 0) {
                continue;
            }
            queued = 0;   // the newest, as lowest latency does
            if (lastShownRefresh >= 0) {
                intervals++;
                even += (k - lastShownRefresh) == 2;
            }
            lastShownRefresh = k;
            since = 0;
        }
        if (hold) {
            XCTAssertGreaterThan((double)even / intervals, 0.99, @"held: %d of %d even", even, intervals);
        } else {
            XCTAssertLessThan((double)even / intervals, 0.9, @"not held: %d of %d even", even, intervals);
        }
    }
}

@end
