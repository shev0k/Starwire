//
//  SystemVideoPresenter.m
//  Starwire
//

#import <QuartzCore/QuartzCore.h>
#import "SystemVideoPresenter.h"
#import "StreamPictureInPicture.h"
#import "FrameQueue.h"
#import "Logger.h"

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_VIDEO

@implementation SystemVideoPresenter {
    StreamPictureInPicture *_layer;
    PacingRefreshRange _range;
    double _framerate;
    NSThread *_thread;
    dispatch_semaphore_t _exited;

    // Display link thread only
    CFTimeInterval _lastTarget;
    int _refreshesPerFrame;
    int _refreshesSinceShown;
}

- (instancetype)initWithLayer:(StreamPictureInPicture *)layer range:(PacingRefreshRange)range framerate:(double)framerate {
    self = [super init];
    if (self) {
        _layer = layer;
        _range = range;
        _framerate = framerate > 0 ? framerate : 60;
        _refreshesPerFrame = PacingRefreshesPerFrame(range.preferred, _framerate);
        _refreshesSinceShown = _refreshesPerFrame;
    }
    return self;
}

- (void)start {
    if (_thread) {
        return;
    }
    dispatch_semaphore_t exited = dispatch_semaphore_create(0);
    _exited = exited;
    __weak SystemVideoPresenter *weakSelf = self;
    PacingRefreshRange range = _range;
    _thread = [[NSThread alloc] initWithBlock:^{
        SystemVideoPresenter *presenter = weakSelf;
        if (!presenter) {
            dispatch_semaphore_signal(exited);
            return;
        }
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:presenter selector:@selector(refresh:)];
        link.preferredFrameRateRange = CAFrameRateRangeMake(range.minimum, range.maximum, range.preferred);
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [link addToRunLoop:runLoop forMode:NSDefaultRunLoopMode];
        presenter = nil;
        Log(LOG_I, @"[SystemVideoPresenter] display link started, range %.0f to %.0f, preferred %.0f",
            range.minimum, range.maximum, range.preferred);
        while (![NSThread currentThread].isCancelled) {
            @autoreleasepool {
                [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
        }
        [link invalidate];
        dispatch_semaphore_signal(exited);
    }];
    _thread.name = @"SystemVideoPresenter";
    _thread.qualityOfService = NSQualityOfServiceUserInteractive;
    [_thread start];
}

- (void)stop {
    if (!_thread) {
        return;
    }
    [_thread cancel];
    dispatch_semaphore_wait(_exited, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    _thread = nil;
}

- (void)dealloc {
    [self stop];
}

// One call per refresh, on the presenter's thread
- (void)refresh:(CADisplayLink *)link {
    if ([NSThread currentThread].isCancelled) {
        [link invalidate];
        return;
    }
    if (self.paused) {
        return;
    }
    FrameQueue *queue = [FrameQueue sharedInstance];
    PacingStats *stats = queue.pacingStats;
    CFTimeInterval target = link.targetTimestamp;
    if (_lastTarget > 0 && target > _lastTarget) {
        [stats noteRefreshInterval:target - _lastTarget];
    }
    _lastTarget = target;

    // A faster display than the stream: the frame on screen keeps its refreshes first
    _refreshesSinceShown++;
    if (!PacingDisplayShouldTakeFrame(_refreshesSinceShown, _refreshesPerFrame)) {
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    Frame *frame = [queue dequeueForRefreshAt:now waitingUpTo:PacingDisplayFrameWait(now, target)];
    [stats noteRefreshWithNewFrame:frame != nil];
    if (!frame || !frame.pixelBuffer) {
        return;
    }
    _refreshesSinceShown = 0;
    [_layer showPixelBuffer:frame.pixelBuffer at:now];
}

@end
