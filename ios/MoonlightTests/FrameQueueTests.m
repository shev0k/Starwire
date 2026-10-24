// Andy Grundman's FrameQueue tests, from andyg.ios-metal-squash.
//
// Starwire changes: each test gets its own queue instead of the shared one, and the tests that
// slept or timed the wall clock (frame rate estimate, dequeue timeouts, producer/consumer and the
// performance measure) now use the frames' own timestamps or check only the outcome, so they
// give the same result on every run.

#import <XCTest/XCTest.h>
#import <CoreMedia/CoreMedia.h>

#define FRAME_QUEUE_VERBOSE

#import "FrameQueue.h"
#import "Logger.h"
#include "Limelight.h"

@interface FrameQueueTests : XCTestCase
@property (nonatomic, strong) FrameQueue *queue;
@end

@implementation FrameQueueTests {
    int _frameNumber;
    uint32_t _tick;
}

- (void)setUp {
    [super setUp];
    self.queue = [[FrameQueue alloc] initWithMaxCapacity:15];
    [self.queue setHighWaterMark:3];
    [self.queue start];
    _frameNumber = 0;
    _tick = 0;
}

- (void)tearDown {
    [self.queue clear];
    self.queue = nil;
    [super tearDown];
}

- (CMSampleBufferRef)makeEmptySampleBufferFor:(uint32_t)tick {
    CMSampleTimingInfo sampleTiming = {
        .duration              = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake((int64_t)tick, 90000),
        .decodeTimeStamp       = kCMTimeInvalid,
    };

    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus status = CMSampleBufferCreate(kCFAllocatorDefault,
                                           NULL, NO, NULL, NULL, NULL,
                                           1, 1, &sampleTiming, 0, NULL,
                                           &sampleBuffer);
    XCTAssertEqual(status, noErr, @"makeEmptySampleBufferFor:%d ok", tick);
    return sampleBuffer;
}

- (Frame *)makeFrameNumber:(int)num type:(int)type pts:(uint32_t)tick {
    // The Frame takes over the reference from CMSampleBufferCreate and releases it in dealloc
    CMSampleBufferRef buf = [self makeEmptySampleBufferFor:tick];
    Frame *frame = [[Frame alloc] initWithSampleBuffer:buf
                                           frameNumber:num
                                             frameType:type];
    _frameNumber = num; // reset the counter
    return frame;
}

- (Frame *)makeFrame {
    const uint32_t ONE_FRAME = 90000 / 60;
    Frame *frame = [self makeFrameNumber:++_frameNumber
                                    type:FRAME_TYPE_PFRAME
                                    pts:_tick];
    _tick += ONE_FRAME;
    return frame;
}

- (void)testEnqueueThenDequeue {
    Frame *f1 = [self makeFrameNumber:1 type:FRAME_TYPE_IDR pts:0];
    Frame *f2 = [self makeFrame];

    [self.queue enqueue:f1];
    [self.queue enqueue:f2];
    XCTAssertEqual([self.queue count], 2);

    Frame *out1 = [self.queue dequeue];
    XCTAssertEqual(out1.frameNumber, 1);
    XCTAssertEqual([self.queue count], 1);

    Frame *out2 = [self.queue dequeue];
    XCTAssertEqual(out2.frameNumber, 2);
    XCTAssertEqual([self.queue count], 0);

    // empty now
    XCTAssertNil([self.queue dequeue]);
}

- (void)testOverflow {
    [self.queue setHighWaterMark:3];

    for (int i = 0; i < self.queue.highWaterMark; i++) {
        [self.queue enqueue:[self makeFrame]];
    }
    XCTAssertEqual([self.queue count], 3);

    // queue should be full at 3
    // 4: dropped, 5: queued, causes 1 to be dropped
    // 6: dropped, 7: queued, causes 2 to be dropped
    // 8: dropped, 9: queued, causes 3 to be dropped
    for (int i = 0; i < 6; i++) {
        [self.queue enqueue:[self makeFrame]];
    }
    XCTAssertEqual([self.queue count], 3);
    XCTAssertEqual([[self.queue frameDropMetrics] total], 6);
    Log(LOG_I, @"queue after overflow: %@", self.queue);
    for (NSNumber *expected in @[@5, @7, @9]) {
        Frame *frame = [self.queue dequeue];
        XCTAssertEqual(frame.frameNumber, expected.integerValue);
    }
}

- (void)testOverflowWithIDR {
    [self.queue setHighWaterMark:5];

    [self.queue enqueue:[self makeFrameNumber:1 type:FRAME_TYPE_IDR pts:0]];
    [self.queue enqueue:[self makeFrame]];
    [self.queue enqueue:[self makeFrameNumber:3 type:FRAME_TYPE_IDR pts:0]];
    [self.queue enqueue:[self makeFrame]];
    [self.queue enqueue:[self makeFrame]];
    XCTAssertEqual([self.queue count], 5);

    // queue should be full at 5
    // 6: dropped, 7: queued, does NOT drop 1 (IDR)
    // 8: dropped, 9: queued, does NOT drop 1 (IDR) - will be stuck here until it's dequeued
    // 10: dropped, 11: queued, does NOT drop 3 (IDR)
    for (int i = 0; i < 6; i++) {
        [self.queue enqueue:[self makeFrame]];
    }
    XCTAssertEqual([self.queue count], 8);
    XCTAssertEqual([[self.queue frameDropMetrics] total], 3);
    Log(LOG_I, @"queue after overflow: %@", self.queue);

    for (NSNumber *expected in @[@1, @2, @3, @4, @5, @7, @9, @11]) {
        XCTAssertEqual([self.queue dequeue].frameNumber, expected.integerValue);
    }
}

- (void)testClear {
    for (int i = 0; i < self.queue.highWaterMark; i++) {
        [self.queue enqueue:[self makeFrame]];
    }
    XCTAssertEqual([self.queue count], self.queue.highWaterMark);

    [self.queue clear];
    XCTAssertEqual([self.queue count], 0);
    XCTAssertEqual([[self.queue frameDropMetrics] total], 0);
    XCTAssertNil([self.queue dequeue]);
}

- (void)testDequeueWithTimeout {
    [self.queue enqueue:[self makeFrame]];

    // returns the queued frame
    Frame *out = [self.queue dequeueWithTimeout:1];
    XCTAssertNotNil(out);
    XCTAssertEqual(out.frameNumber, 1);

    // nothing queued: nil once the wait ends
    XCTAssertNil([self.queue dequeueWithTimeout:0.01]);

    // no timeout
    XCTAssertNil([self.queue dequeueWithTimeout:0]);
}

- (void)testDuration {
    // 2nd frame will compute 1st frame's duration. makeFrame generates sequential frames at 60fps
    [self.queue clear];
    [self.queue enqueue:[self makeFrame]];
    [self.queue enqueue:[self makeFrame]];
    XCTAssertEqual([self.queue count], 2);
    Frame *first = [self.queue dequeue];
    XCTAssertEqualWithAccuracy(first.duration, (float)1.0f / 60, 0.0001f);
}

- (void)testEstimatedFramerate {
    // 24 fps for 5 seconds, timed by the frames' own decodedAt
    [self.queue setHighWaterMark:15];
    for (int i = 0; i < 24 * 5; i++) {
        Frame *frame = [self makeFrame];
        frame.decodedAt = 1000.0 + i / 24.0;
        // these get dropped once the queue fills, but every one counts toward the rate
        [self.queue enqueue:frame];
    }
    XCTAssertEqualWithAccuracy([self.queue estimatedFramerate], 24.0, 0.5);
}

- (void)testProducerConsumer {
    static const int TotalFrames = 200;
    [self.queue setHighWaterMark:15];

    XCTestExpectation *dequeueAll = [self expectationWithDescription:@"consumer dequeued all frames"];

    // The producer only queues a frame once the consumer has taken the last one, so nothing is
    // dropped however the threads are scheduled
    dispatch_semaphore_t taken = dispatch_semaphore_create(0);
    dispatch_queue_t producerQ = dispatch_queue_create("moonlight.test.producer", DISPATCH_QUEUE_SERIAL);
    dispatch_async(producerQ, ^{
        for (int i = 0; i < TotalFrames; i++) {
            [self.queue enqueue:[self makeFrame]];
            dispatch_semaphore_wait(taken, DISPATCH_TIME_FOREVER);
        }
    });

    dispatch_queue_t consumerQ = dispatch_queue_create("moonlight.test.consumer", DISPATCH_QUEUE_SERIAL);
    dispatch_async(consumerQ, ^{
        int received = 0;
        while (received < TotalFrames) {
            // A long timeout: the producer's enqueue wakes this wait early
            Frame *frame = [self.queue dequeueWithTimeout:10.0];
            if (!frame) {
                continue;
            }
            received++;
            XCTAssertEqual(frame.frameNumber, received);
            dispatch_semaphore_signal(taken);
        }
        [dequeueAll fulfill];
    });

    [self waitForExpectationsWithTimeout:60.0 handler:nil];
    XCTAssertEqual([self.queue count], 0, @"Queue should be empty at end");
    XCTAssertEqual([[self.queue frameDropMetrics] total], 0);
}

@end
