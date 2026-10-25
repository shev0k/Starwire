//
//  JitterBufferTests.m
//  Starwire
//
//  The display presenter's jitter buffer: its modes and settings, how its target follows holes in
//  arrival, catching up, and a whole timeline with regular holes like the ones measured on the
//  iPad Pro on Wi-Fi. Every time here is made up and passed in; nothing reads a clock.
//

#import <XCTest/XCTest.h>
#import <CoreMedia/CoreMedia.h>

#import "FrameQueue.h"
#import "JitterBuffer.h"
#import "PacingPolicy.h"
#import "PacingStats.h"
#include "Limelight.h"

static const double kFrame = 1.0 / 120;

@interface JitterBufferTests : XCTestCase
@end

@implementation JitterBufferTests {
    int _frameNumber;
    NSString *_suiteName;
    NSUserDefaults *_defaults;
}

- (void)setUp {
    [super setUp];
    _frameNumber = 0;
    _suiteName = [NSString stringWithFormat:@"JitterBufferTests.%@", self.name];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suiteName];
    [_defaults removePersistentDomainForName:_suiteName];
}

- (void)tearDown {
    [_defaults removePersistentDomainForName:_suiteName];
    [super tearDown];
}

- (JitterBuffer *)buffer:(JitterBufferMode)mode {
    return [[JitterBuffer alloc] initWithMode:mode frameInterval:kFrame];
}

#pragma mark - Modes and settings

- (void)testModesUseAndroidsValues {
    XCTAssertEqual(JitterBufferModeFromString(@"lowest-latency"), JitterBufferModeLowestLatency);
    XCTAssertEqual(JitterBufferModeFromString(@"low-latency"), JitterBufferModeLowLatency);
    XCTAssertEqual(JitterBufferModeFromString(@"balanced"), JitterBufferModeBalanced);
    XCTAssertEqual(JitterBufferModeFromString(@"smooth"), JitterBufferModeSmooth);
    XCTAssertEqual(JitterBufferModeFromString(@"garbage"), JitterBufferDefaultMode);
    XCTAssertEqual(JitterBufferModeFromString(nil), JitterBufferDefaultMode);
    // Chosen from the batch 1 device runs
    XCTAssertEqual(JitterBufferDefaultMode, JitterBufferModeLowLatency);
    for (JitterBufferMode mode = JitterBufferModeLowestLatency; mode <= JitterBufferModeSmooth; mode++) {
        XCTAssertEqual(JitterBufferModeFromString(JitterBufferModeName(mode)), mode);
    }
}

- (void)testMostFramesHeldPerMode {
    XCTAssertEqual(JitterBufferMaxTarget(JitterBufferModeLowestLatency), 0);
    XCTAssertEqual(JitterBufferMaxTarget(JitterBufferModeLowLatency), 1);
    XCTAssertEqual(JitterBufferMaxTarget(JitterBufferModeBalanced), 2);
    XCTAssertEqual(JitterBufferMaxTarget(JitterBufferModeSmooth), 4);
}

- (void)testSettingsMakeAJitterBufferOnlyForTheDisplayPresenter {
    [_defaults setObject:@"smooth" forKey:JitterBufferKey];
    [_defaults setObject:@"loop" forKey:PacingPresenterKey];
    PacingSettings *loop = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual(loop.jitterBuffer, JitterBufferModeSmooth);
    XCTAssertNil([loop makeJitterBufferForFrameInterval:kFrame]);
    XCTAssertEqualObjects(loop.jitterBufferName, @"off");
    XCTAssertEqual([loop queueLimitWithFramesToBuffer:2], 2);

    [_defaults setObject:@"display" forKey:PacingPresenterKey];
    PacingSettings *display = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual([display makeJitterBufferForFrameInterval:kFrame].mode, JitterBufferModeSmooth);
    XCTAssertEqualObjects(display.jitterBufferName, @"smooth");
    XCTAssertEqual([display queueLimitWithFramesToBuffer:2], 8);

    // Lowest latency is the display presenter's newest-frame path, with no buffer object
    [_defaults setObject:@"lowest-latency" forKey:JitterBufferKey];
    display = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertNil([display makeJitterBufferForFrameInterval:kFrame]);
    XCTAssertEqualObjects(display.jitterBufferName, @"lowest-latency");
}

#pragma mark - Choices

- (void)testLowestLatencyAlwaysShowsTheNewest {
    JitterBuffer *jb = [self buffer:JitterBufferModeLowestLatency];
    JitterBufferChoice c = [jb chooseWithQueued:3 at:1.0];
    XCTAssertTrue(c.show);
    XCTAssertEqual(c.drop, 2);
    c = [jb chooseWithQueued:0 at:1.0 + kFrame];
    XCTAssertFalse(c.show);
    XCTAssertEqual(jb.underflows, 1);
}

- (void)testNoUnderflowIsCountedBeforeTheFirstFrame {
    JitterBuffer *jb = [self buffer:JitterBufferModeBalanced];
    [jb chooseWithQueued:0 at:1.0];
    [jb chooseWithQueued:0 at:1.0 + kFrame];
    XCTAssertEqual(jb.underflows, 0);
    [jb chooseWithQueued:1 at:1.0 + 2 * kFrame];
    // Half a frame later is not late yet; two frames later is
    [jb chooseWithQueued:0 at:1.0 + 2.5 * kFrame];
    XCTAssertEqual(jb.underflows, 0);
    [jb chooseWithQueued:0 at:1.0 + 4 * kFrame];
    XCTAssertEqual(jb.underflows, 1);
}

// 60 FPS on a 120 Hz display: every other refresh has nothing new, which isn't an underflow
- (void)testAFasterDisplayIsNotAnUnderflow {
    JitterBuffer *jb = [[JitterBuffer alloc] initWithMode:JitterBufferModeBalanced frameInterval:1.0 / 60];
    for (int k = 0; k < 120; k++) {
        double t = 1.0 + k * kFrame;
        if (k % 2 == 0) {
            [jb noteArrivalAt:t - 0.001];
        }
        [jb chooseWithQueued:(k % 2 == 0) ? 1 : 0 at:t];
    }
    XCTAssertEqual(jb.underflows, 0);
    XCTAssertEqual(jb.target, 0);
}

- (void)testTargetFollowsTheLongestRecentHoleUpToTheModesCap {
    // A frame 3 intervals after the one before leaves 2 refreshes with nothing new
    JitterBuffer *balanced = [self buffer:JitterBufferModeBalanced];
    [balanced noteArrivalAt:1.0];
    [balanced noteArrivalAt:1.0 + 3 * kFrame];
    [balanced chooseWithQueued:1 at:1.03];
    XCTAssertEqual(balanced.target, 2);

    // A 141 ms hole wants 16 frames; each mode holds only what it allows
    for (JitterBufferMode mode = JitterBufferModeLowLatency; mode <= JitterBufferModeSmooth; mode++) {
        JitterBuffer *jb = [self buffer:mode];
        [jb noteArrivalAt:1.0];
        [jb noteArrivalAt:1.141];
        [jb chooseWithQueued:1 at:1.15];
        XCTAssertEqual(jb.target, JitterBufferMaxTarget(mode), @"%@", JitterBufferModeName(mode));
    }
}

- (void)testSmallWobbleNeedsNothing {
    JitterBuffer *jb = [self buffer:JitterBufferModeSmooth];
    [jb noteArrivalAt:1.0];
    // 1.4 intervals late, then 0.6 early: both round to one interval
    [jb noteArrivalAt:1.0 + 1.4 * kFrame];
    [jb noteArrivalAt:1.0 + 2.0 * kFrame];
    [jb chooseWithQueued:1 at:1.02];
    XCTAssertEqual(jb.target, 0);
}

- (void)testTargetComesDownWhenTheHolesStop {
    JitterBuffer *jb = [self buffer:JitterBufferModeBalanced];
    [jb noteArrivalAt:1.0];
    [jb noteArrivalAt:1.0 + 3 * kFrame];
    [jb chooseWithQueued:1 at:1.1];
    XCTAssertEqual(jb.target, 2);
    // Balanced remembers a hole for 3 seconds
    [jb chooseWithQueued:1 at:3.9];
    XCTAssertEqual(jb.target, 2);
    [jb chooseWithQueued:1 at:4.1];
    XCTAssertEqual(jb.target, 0);
}

- (void)testFarAboveTheTargetDropsDownToTwoAboveAtOnce {
    JitterBuffer *jb = [self buffer:JitterBufferModeBalanced];
    // No holes, so the target is 0; 6 queued leaves 5 after this one
    JitterBufferChoice c = [jb chooseWithQueued:6 at:1.0];
    XCTAssertTrue(c.show);
    XCTAssertEqual(c.drop, 3);
    XCTAssertEqual(jb.trimDrops, 3);
}

- (void)testAboveTheTargetCatchesUpOneFrameAtATime {
    JitterBuffer *jb = [self buffer:JitterBufferModeLowLatency];
    // One frame more than the target, refresh after refresh
    double t = 1.0;
    int dropsBefore = 0;
    for (; t < 1.0 + 0.25 - kFrame / 2; t += kFrame) {
        dropsBefore += [jb chooseWithQueued:2 at:t].drop;
    }
    XCTAssertEqual(dropsBefore, 0, @"nothing dropped in the first quarter second");
    XCTAssertEqual([jb chooseWithQueued:2 at:t].drop, 1);
    // Then no more than one every 4 frame intervals
    XCTAssertEqual([jb chooseWithQueued:2 at:t + kFrame].drop, 0);
    XCTAssertEqual([jb chooseWithQueued:2 at:t + 3 * kFrame].drop, 0);
    XCTAssertEqual([jb chooseWithQueued:2 at:t + 4 * kFrame].drop, 1);
    XCTAssertEqual(jb.catchUpDrops, 2);
    // Back at the target, the wait starts again
    XCTAssertEqual([jb chooseWithQueued:1 at:t + 5 * kFrame].drop, 0);
    XCTAssertEqual([jb chooseWithQueued:2 at:t + 6 * kFrame].drop, 0);
}

#pragma mark - A timeline

typedef struct {
    int shown;
    int repeats;
    int drops;
} Playout;

// 120 FPS for `seconds`, with every frame in a hole of `holeFrames` frames held back and
// delivered together with the frame after it, every `holeEvery` seconds (the clumps seen on the
// iPad). Refreshes come at 120 Hz, half a refresh after each frame is due. The queue is a count:
// the buffer only ever sees how many frames are waiting.
- (Playout)playMode:(JitterBufferMode)mode holeFrames:(int)holeFrames holeEvery:(double)holeEvery seconds:(double)seconds {
    JitterBuffer *jb = [self buffer:mode];
    int total = (int)(seconds / kFrame);
    int framesPerHole = (int)lround(holeEvery / kFrame);
    double *arrivals = malloc(sizeof(double) * total);
    for (int i = 0; i < total; i++) {
        double due = 10.0 + i * kFrame;
        int phase = i % framesPerHole;
        // Frames 60..60+holeFrames-1 of each period arrive with the frame after the hole
        int holeStart = framesPerHole / 2;
        if (phase >= holeStart && phase < holeStart + holeFrames) {
            due = 10.0 + (i - phase + holeStart + holeFrames) * kFrame;
        }
        arrivals[i] = due;
    }

    Playout p = {0, 0, 0};
    int queued = 0, next = 0;
    BOOL started = NO;
    for (int k = 0; k < total; k++) {
        double refresh = 10.0 + k * kFrame + kFrame / 2;
        while (next < total && arrivals[next] <= refresh) {
            [jb noteArrivalAt:arrivals[next]];
            queued++;
            next++;
        }
        JitterBufferChoice c = [jb chooseWithQueued:queued at:refresh];
        int drop = MIN(c.drop, MAX(queued - 1, 0));
        queued -= drop;
        p.drops += drop;
        if (c.show && queued > 0) {
            queued--;
            p.shown++;
            started = YES;
        } else if (started) {
            p.repeats++;
        }
    }
    free(arrivals);
    return p;
}

// Holes of 2 frames twice a second: the newest-frame presenter repeats a frame and skips one at
// every hole. Balanced and smooth cover them after the first one, at the cost of 2 frames held.
- (void)testBalancedAndSmoothRideOutRegularShortHoles {
    Playout lowest = [self playMode:JitterBufferModeLowestLatency holeFrames:2 holeEvery:0.5 seconds:10];
    Playout low = [self playMode:JitterBufferModeLowLatency holeFrames:2 holeEvery:0.5 seconds:10];
    Playout balanced = [self playMode:JitterBufferModeBalanced holeFrames:2 holeEvery:0.5 seconds:10];
    Playout smooth = [self playMode:JitterBufferModeSmooth holeFrames:2 holeEvery:0.5 seconds:10];

    // 20 holes in 10 s
    XCTAssertEqual(lowest.repeats, 40);
    XCTAssertEqual(lowest.drops, 40);
    // Low latency holds 1 frame: one repeat per hole instead of two
    XCTAssertLessThanOrEqual(low.repeats, 21);
    // Only the first hole shows
    XCTAssertLessThanOrEqual(balanced.repeats, 2);
    XCTAssertEqual(balanced.drops, 0);
    XCTAssertLessThanOrEqual(smooth.repeats, 2);
    XCTAssertEqual(smooth.drops, 0);
}

// Holes longer than any mode holds (8 frames, about the 67 ms seen on the iPad) still repeat,
// but smooth repeats about 4 fewer refreshes per hole than lowest latency and shows more frames
- (void)testLongHolesAreShortenedNotHidden {
    Playout lowest = [self playMode:JitterBufferModeLowestLatency holeFrames:8 holeEvery:0.5 seconds:10];
    Playout smooth = [self playMode:JitterBufferModeSmooth holeFrames:8 holeEvery:0.5 seconds:10];
    XCTAssertEqual(lowest.repeats, 20 * 8);
    XCTAssertLessThanOrEqual(smooth.repeats, 20 * 4 + 4);
    XCTAssertGreaterThan(smooth.shown, lowest.shown);
}

#pragma mark - With the frame queue

- (Frame *)frameAt:(CFTimeInterval)time {
    CMSampleTimingInfo timing = {
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake((int64_t)(_frameNumber * 750), 90000),
        .decodeTimeStamp = kCMTimeInvalid,
    };
    CMSampleBufferRef buf = NULL;
    XCTAssertEqual(CMSampleBufferCreate(kCFAllocatorDefault, NULL, NO, NULL, NULL, NULL, 1, 1, &timing, 0, NULL, &buf), noErr);
    Frame *frame = [[Frame alloc] initWithSampleBuffer:buf frameNumber:++_frameNumber frameType:FRAME_TYPE_PFRAME];
    frame.decodedAt = time;
    return frame;
}

- (void)testQueueShowsFramesInOrderAndCountsCatchUpDrops {
    PacingStats *stats = [[PacingStats alloc] initWithFrameInterval:kFrame refreshInterval:kFrame windowLength:5.0];
    FrameQueue *queue = [[FrameQueue alloc] initWithMaxCapacity:15];
    queue.pacingStats = stats;
    queue.dropPolicy = FrameDropPolicyNewest;
    queue.highWaterMark = 6;
    queue.jitterBuffer = [self buffer:JitterBufferModeLowLatency];
    [queue start];

    [queue enqueue:[self frameAt:1.0]];
    [queue enqueue:[self frameAt:1.001]];
    // In order, not the newest
    XCTAssertEqual([queue dequeueForRefreshAt:1.005 waitingUpTo:0].frameNumber, 1);
    XCTAssertEqual([queue count], 1u);

    // Keep one frame above the target for more than a quarter second
    double t = 1.005;
    int catchUps = 0;
    for (int i = 0; i < 40; i++) {
        t += kFrame;
        [queue enqueue:[self frameAt:t - 0.001]];
        [queue dequeueForRefreshAt:t waitingUpTo:0];
    }
    catchUps = [stats currentWindow].drops[PacingDropCatchUp];
    XCTAssertEqual(catchUps, 1);
    XCTAssertEqual([queue count], 0u);
    XCTAssertEqual([stats currentWindow].jitterSamples, 41);
    [queue stop];
    XCTAssertNil([queue dequeueForRefreshAt:t waitingUpTo:0]);
}

- (void)testQueueWithoutAJitterBufferShowsTheNewest {
    FrameQueue *queue = [[FrameQueue alloc] initWithMaxCapacity:15];
    queue.dropPolicy = FrameDropPolicyNewest;
    queue.highWaterMark = 4;
    [queue start];
    [queue enqueue:[self frameAt:1.0]];
    [queue enqueue:[self frameAt:1.001]];
    XCTAssertEqual([queue dequeueForRefreshAt:1.005 waitingUpTo:0].frameNumber, 2);
}


// Frame interpolation queues its made-up frame with the real one; showing the newest would skip
// every made-up frame, so lowest latency becomes low latency while it runs
- (void)testInterpolationShowsFramesInOrder {
    [_defaults setObject:@"display" forKey:PacingPresenterKey];
    [_defaults setObject:@"lowest-latency" forKey:JitterBufferKey];
    PacingSettings *settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertNil([settings makeJitterBufferForFrameInterval:kFrame interpolating:NO]);
    XCTAssertEqual([settings makeJitterBufferForFrameInterval:kFrame interpolating:YES].mode, JitterBufferModeLowLatency);
    [_defaults setObject:@"smooth" forKey:JitterBufferKey];
    settings = [[PacingSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual([settings jitterBufferModeInterpolating:YES], JitterBufferModeSmooth);

    // Pairs arriving together every two refreshes come out one per refresh, none skipped
    JitterBuffer *jb = [self buffer:JitterBufferModeLowLatency];
    int queued = 0, shown = 0, drops = 0;
    for (int k = 0; k < 240; k++) {
        double t = 1.0 + k * kFrame;
        if (k % 2 == 0) {
            [jb noteArrivalAt:t - 0.002];
            [jb noteArrivalAt:t - 0.0019];
            queued += 2;
        }
        JitterBufferChoice c = [jb chooseWithQueued:queued at:t];
        queued -= c.drop;
        drops += c.drop;
        if (c.show && queued > 0) {
            queued--;
            shown++;
        }
    }
    XCTAssertEqual(drops, 0);
    XCTAssertGreaterThanOrEqual(shown, 238);
}

@end
