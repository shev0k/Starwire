//
//  LifecycleTests.m
//  Starwire
//
//  Regression tests for the stream start and stop races, the double alert, and the serverinfo
//  poll of a paired host.
//

#import <XCTest/XCTest.h>
#import <CoreMedia/CoreMedia.h>

#import "SessionOwnership.h"
#import "StreamAlertGate.h"
#import "FrameQueue.h"
#import "DiscoveryWorker.h"
#import "HttpManager.h"
#import "TemporaryHost.h"
#include "Limelight.h"

@interface LifecycleTests : XCTestCase
@end

@implementation LifecycleTests

#pragma mark - Which session owns the connection

- (void)testSessionStoppedBeforeItStartsNeverStarts {
    SessionOwnership *ownership = [[SessionOwnership alloc] init];
    NSObject *session = [NSObject new];
    [ownership cancel:session];
    XCTAssertFalse([ownership begin:session]);
    XCTAssertFalse([ownership isCurrent:session]);
}

- (void)testLateStopFromTheLastSessionLeavesTheNewOneRunning {
    SessionOwnership *ownership = [[SessionOwnership alloc] init];
    NSObject *first = [NSObject new];
    NSObject *second = [NSObject new];

    XCTAssertTrue([ownership begin:first]);
    XCTAssertTrue([ownership endIfCurrent:first]);
    [ownership cancel:first];
    XCTAssertTrue([ownership begin:second]);

    // The first session's stop arrives again, late: it must not end the second
    XCTAssertFalse([ownership endIfCurrent:first]);
    XCTAssertTrue([ownership isCurrent:second]);
    XCTAssertTrue([ownership endIfCurrent:second]);
    XCTAssertFalse([ownership isCurrent:second]);
}

- (void)testNewSessionTakesOverFromOneThatNeverStopped {
    SessionOwnership *ownership = [[SessionOwnership alloc] init];
    NSObject *first = [NSObject new];
    NSObject *second = [NSObject new];
    XCTAssertTrue([ownership begin:first]);
    XCTAssertTrue([ownership begin:second]);
    XCTAssertFalse([ownership endIfCurrent:first]);
    XCTAssertTrue([ownership isCurrent:second]);
}

#pragma mark - The shared frame queue

- (Frame *)frameNumbered:(int)number {
    CMSampleTimingInfo timing = {kCMTimeInvalid, CMTimeMake(number * 750, 90000), kCMTimeInvalid};
    CMSampleBufferRef buf = NULL;
    XCTAssertEqual(CMSampleBufferCreate(kCFAllocatorDefault, NULL, NO, NULL, NULL, NULL, 1, 1, &timing, 0, NULL, &buf), noErr);
    return [[Frame alloc] initWithSampleBuffer:buf frameNumber:number frameType:FRAME_TYPE_PFRAME];
}

- (void)testOldStreamCleanupDoesNotPauseTheNextStream {
    FrameQueue *queue = [[FrameQueue alloc] initWithMaxCapacity:15];
    NSObject *oldStream = [NSObject new];
    NSObject *newStream = [NSObject new];

    [queue startForOwner:oldStream];
    [queue startForOwner:newStream];
    // The old renderer's cleanup runs after the new stream started
    [queue stopForOwner:oldStream];

    XCTAssertFalse(queue.paused);
    [queue enqueue:[self frameNumbered:1]];
    XCTAssertEqual([queue dequeueWithTimeout:0].frameNumber, 1);

    [queue stopForOwner:newStream];
    XCTAssertTrue(queue.paused);
}

- (void)testStartDropsFramesLeftFromTheLastStream {
    FrameQueue *queue = [[FrameQueue alloc] initWithMaxCapacity:15];
    queue.highWaterMark = 5;
    [queue startForOwner:self];
    [queue enqueue:[self frameNumbered:1]];
    [queue enqueue:[self frameNumbered:2]];
    [queue startForOwner:[NSObject new]];
    XCTAssertEqual([queue count], 0);
}

- (void)testClearReleasesQueuedFrames {
    FrameQueue *queue = [[FrameQueue alloc] initWithMaxCapacity:15];
    [queue start];
    __weak Frame *weakFrame = nil;
    @autoreleasepool {
        Frame *frame = [self frameNumbered:1];
        weakFrame = frame;
        [queue enqueue:frame];
        [queue enqueue:[self frameNumbered:2]];
        // clear used to reset only the indices, keeping the frames (and their pixel buffers)
        // until their slots were overwritten
        [queue clear];
    }
    XCTAssertNil(weakFrame);
}

- (void)testStopWakesAWaitingRenderLoop {
    FrameQueue *queue = [[FrameQueue alloc] initWithMaxCapacity:15];
    [queue start];
    dispatch_semaphore_t returned = dispatch_semaphore_create(0);
    __block Frame *frame = (Frame *)[NSNull null];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Without a wakeup this waits the whole 30 seconds
        frame = [queue dequeueWithTimeout:30.0];
        dispatch_semaphore_signal(returned);
    });
    // Stop repeatedly until the waiter has returned, so the test doesn't depend on which thread
    // runs first. Ten seconds in all, well under the waiter's 30.
    BOOL done = NO;
    for (int i = 0; i < 100 && !done; i++) {
        [queue stop];
        done = dispatch_semaphore_wait(returned, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) == 0;
    }
    XCTAssertTrue(done);
    XCTAssertNil(frame);
}

#pragma mark - Alerts

- (void)testOnlyTheFirstAlertOfAStreamIsShown {
    StreamAlertGate *gate = [[StreamAlertGate alloc] init];
    XCTAssertTrue([gate shouldPresentAlertWithTitle:@"Connection Failed"]);
    // The same failure reported again as the connection terminates
    XCTAssertFalse([gate shouldPresentAlertWithTitle:@"Connection Error"]);
    XCTAssertEqualObjects(gate.suppressedTitles, @[@"Connection Error"]);
}

- (void)testNoAlertWhileTheStreamScreenCloses {
    StreamAlertGate *gate = [[StreamAlertGate alloc] init];
    [gate markExiting];
    XCTAssertTrue(gate.exiting);
    XCTAssertFalse([gate shouldPresentAlertWithTitle:@"Connection Terminated"]);
}

#pragma mark - serverinfo

- (TemporaryHost *)pairedHost {
    TemporaryHost *host = [[TemporaryHost alloc] init];
    host.serverCert = [@"pinned certificate bytes" dataUsingEncoding:NSUTF8StringEncoding];
    host.httpsPort = 47984;
    return host;
}

- (void)testPairedHostIsPolledOverHttpsWithoutAskingHttpFirst {
    HttpManager *hMan = [DiscoveryWorker serverInfoManagerForAddress:@"192.0.2.10" host:[self pairedHost]];
    NSURLRequest *request = [hMan newServerInfoRequest:true];
    XCTAssertEqualObjects(request.URL.scheme, @"https");
    XCTAssertEqualObjects(request.URL.port, @47984);
    XCTAssertEqualObjects(request.URL.path, @"/serverinfo");
}

- (void)testUnpairedHostIsPolledOverHttp {
    TemporaryHost *host = [[TemporaryHost alloc] init];
    host.httpsPort = 47984;
    HttpManager *hMan = [DiscoveryWorker serverInfoManagerForAddress:@"192.0.2.10" host:host];
    NSURLRequest *request = [hMan newServerInfoRequest:true];
    XCTAssertEqualObjects(request.URL.scheme, @"http");
    XCTAssertEqualObjects(request.URL.port, @47989);
}

- (void)testIPv6PollUsesBrackets {
    HttpManager *hMan = [DiscoveryWorker serverInfoManagerForAddress:@"[2001:db8::10]:47989" host:[self pairedHost]];
    NSURLRequest *request = [hMan newServerInfoRequest:true];
    XCTAssertEqualObjects(request.URL.scheme, @"https");
    XCTAssertEqualObjects(request.URL.host, @"2001:db8::10");
}

#pragma mark - Logs

- (void)testInputKeyIsRedactedFromLoggedUrls {
    NSString *url = @"https://192.0.2.10:47984/launch?uniqueid=0123456789ABCDEF&rikey=00112233445566778899AABBCCDDEEFF&rikeyid=12";
    NSString *redacted = [HttpManager redactSecrets:url];
    XCTAssertFalse([redacted containsString:@"00112233"]);
    XCTAssertTrue([redacted containsString:@"rikey=<redacted>&rikeyid=12"]);
}

@end
