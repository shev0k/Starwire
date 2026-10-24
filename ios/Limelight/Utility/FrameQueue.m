@import AVFoundation;
@import VideoToolbox;

#import <pthread.h>
#import <os/signpost.h>
#import <Limelight.h>
#import "Logger.h"
#import "FloatBuffer.h"
#import "FrameQueue.h"
#import "ImGuiPlots.h"

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_PACING

// Starwire changes to Andy Grundman's queue:
// - a mutex and condition variable replace the unfair lock, the semaphore and the usleep(100)
//   poll in dequeueWithTimeout
// - a choice of drop policy, and every drop reported to PacingStats with its reason
// - clear releases the queued frames, and start and stop are scoped to an owner (from VoidLink)
// - the frame rate estimate uses the frames' own timestamps, so it can be tested
// - instances can be made for tests; the app uses sharedInstance

@implementation FrameQueue {
    NSMutableArray<id> *_buffer;
    int _capacity;
    int _head;
    int _tail;
    int _count;

    BOOL _droppedLast;
    int _framesIn;
    CMTime _ptsCorrection;
    pthread_mutex_t _mutex;
    pthread_cond_t _cond;

    FloatBuffer *_queueSizeHistory;
    int _currentSoftCap;
    __weak id _owner;

    CFTimeInterval _fpsWindowStart;
    int _fpsWindowFrames;
    CFTimeInterval _fpsEstimate;
}

+ (instancetype)sharedInstance {
    static FrameQueue *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[FrameQueue alloc] initWithMaxCapacity:15];
    });
    return sharedInstance;
}

- (instancetype)initWithMaxCapacity:(int)maxCapacity {
    self = [super init];
    if (self) {
        _droppedLast       = NO;
        _frameDropMetrics  = [[FloatBuffer alloc] initWithCapacity:512];
        _framesIn          = 0;
        _highWaterMark     = 2;
        _maxCapacity       = maxCapacity > 0 ? maxCapacity : 15;
        _ptsCorrection     = CMTimeMake(0, 90000);
        _queueSizeHistory  = [[FloatBuffer alloc] initWithCapacity:64];
        _paused            = YES; // caller will call start()
        _dropPolicy        = FrameDropPolicyAlternate;
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);

        // ring buffer
        _capacity = _maxCapacity;
        _buffer = [NSMutableArray arrayWithCapacity:_capacity];
        for (int i = 0; i < _capacity; i++) {
            [_buffer addObject:[NSNull null]];
        }
        _head = _tail = _count = 0;
    }
    return self;
}

- (void)dealloc {
    pthread_cond_destroy(&_cond);
    pthread_mutex_destroy(&_mutex);
}

// Push into buffer at _tail
- (void)_pushFrame:(Frame *)frame {
    [_buffer replaceObjectAtIndex:_tail withObject:frame];
    _tail = (_tail + 1) % _capacity;
    _count++;

    // Wakes a render loop waiting in dequeueWithTimeout or waitForEnqueue
    pthread_cond_signal(&_cond);

    FQLog(LOG_I, @"[-> %@ %d / %f] enqueue frame, queue size %d / %d",
        frame.frameType == FRAME_TYPE_IDR ? @"IDR" : @"P",
        frame.frameNumber, frame.pts, _count, _highWaterMark);
}

// Pop oldest frame from _head
- (Frame *)_popFrame {
    id obj = _buffer[_head];
    Frame *frame = (obj == [NSNull null] ? nil : obj);
    [_buffer replaceObjectAtIndex:_head withObject:[NSNull null]];
    _head = (_head + 1) % _capacity;
    _count--;
    return frame;
}

// Peek next frame (without removing)
- (Frame *)_peekFrame {
    id frame = (_count > 0) ? _buffer[_head] : nil;
    return (frame == [NSNull null]) ? nil : frame;
}

// enumerate in‐buffer frames
- (void)_enumerateFrames:(void(^)(Frame *frame, NSUInteger idx, BOOL *stop))block {
    BOOL stop = NO;
    for (int i = 0; i < _count; i++) {
        int idx = (_head + i) % _capacity;
        block([_buffer objectAtIndex:idx], i, &stop);
        if (stop) break;
    }
}

- (void)_noteDroppedFrame:(Frame *)frame reason:(PacingDropReason)reason {
    [_pacingStats noteDrop:reason queueDepth:_count];
    os_signpost_event_emit(LogHandle(LOGCAT_PACING), OS_SIGNPOST_ID_EXCLUSIVE, "drop", "frame %d, %{public}s, queue %d",
                           frame.frameNumber, reason == PacingDropIncoming ? "incoming" : "oldest", _count);

    if ([frame durationIsValid]) {
        _ptsCorrection = CMTimeAdd(_ptsCorrection, frame.duration90);
        FQLog(LOG_W, @"dropped frame %d with duration %.3f ms", frame.frameNumber, frame.duration * 1000.0);
    } else {
        // count unknowns as 1 avg frametime
        CFTimeInterval fps = (_framesIn > 1000) ? _fpsEstimate : 0.0f;
        CMTime oneFrame = (fps > 0) ? CMTimeMake((int)(90000.0f / fps), 90000) : kCMTimeZero;
        _ptsCorrection = CMTimeAdd(_ptsCorrection, oneFrame);
        FQLog(LOG_W, @"dropped frame %d with unknown duration, using %.3f ms (%.1f fps) instead",
            frame.frameNumber, CMTimeGetSeconds(oneFrame) * 1000.0, fps);
    }
}

// Drops the oldest queued frame unless it's an IDR frame. Returns the number dropped.
- (int)_dropOldestUnlessIDR {
    if (_count == 0 || [self _peekFrame].frameType == FRAME_TYPE_IDR) {
        return 0;
    }
    Frame *oldest = [self _popFrame];
    [oldest setDurationFromNext:[self _peekFrame]];
    [self _noteDroppedFrame:oldest reason:PacingDropOldest];
    return 1;
}

- (void)_noteArrivalForFramerate:(Frame *)frame {
    CFTimeInterval t = frame.decodedAt;
    if (t <= 0) {
        return;
    }
    if (_fpsWindowStart == 0) {
        _fpsWindowStart = t;
        _fpsWindowFrames = 0;
    }
    _fpsWindowFrames++;
    if (t - _fpsWindowStart >= 1.0) {
        _fpsEstimate = (_fpsWindowFrames - 1) / (t - _fpsWindowStart);
        _fpsWindowStart = t;
        _fpsWindowFrames = 1;
    }
}

- (int)_unsafeEnqueue:(Frame *)frame withDropTarget:(int)frameDropTarget {
    int dropCount = 0;
    [self _noteArrivalForFramerate:frame];

    // The ring can't grow. Only a run of IDR frames could fill it, but don't overwrite.
    if (_count >= _capacity) {
        Frame *oldest = [self _popFrame];
        [self _noteDroppedFrame:oldest reason:PacingDropOldest];
        dropCount++;
    }

    // Always accept IDR frames, allow exceeding HWM
    if (frame.frameType == FRAME_TYPE_IDR || _count < frameDropTarget) {
        [self _pushFrame:frame];
        _droppedLast = NO;
    } else if (_dropPolicy == FrameDropPolicyNewest) {
        // Keep the newest: drop the oldest & enqueue new
        dropCount += [self _dropOldestUnlessIDR];
        [self _pushFrame:frame];
        _droppedLast = NO;
    } else {
        if (!_droppedLast) {
            // alternate between: drop newest...
            [self _noteDroppedFrame:frame reason:PacingDropIncoming];
            dropCount++;
            _droppedLast = YES;
        } else {
            // and: drop oldest & enqueue new
            dropCount += [self _dropOldestUnlessIDR];
            [self _pushFrame:frame];
            _droppedLast = NO;
        }
    }
    // regardless of drop status, every enqueue is a frame
    // for estimatedFramerate purposes
    _framesIn++;
    [_frameDropMetrics addValue:(float)dropCount];
    [_pacingStats noteQueueDepth:_count];

    // Stats displays the soft cap
    _currentSoftCap = frameDropTarget;
    return dropCount;
}

- (int)enqueue:(Frame *)frame {
    pthread_mutex_lock(&_mutex);
    int dropCount = [self _unsafeEnqueue:frame withDropTarget:_highWaterMark];
    pthread_mutex_unlock(&_mutex);
    return dropCount;
}

// The slack isn't used: Andy's adaptive drop target (moonlight-qt's 500 ms queue history) was
// left commented out, and phase 4 replaces this pacing. Kept for the decoder's call.
- (int)enqueue:(Frame *)frame withSlackSize:(int)slack {
    pthread_mutex_lock(&_mutex);
    [_queueSizeHistory addValue:(float)_count];
    int dropCount = [self _unsafeEnqueue:frame withDropTarget:_highWaterMark];
    pthread_mutex_unlock(&_mutex);
    return dropCount;
}

static struct timespec TimespecFromInterval(CFTimeInterval interval) {
    struct timespec ts;
    if (interval < 0) {
        interval = 0;
    }
    ts.tv_sec = (time_t)interval;
    ts.tv_nsec = (long)((interval - (double)ts.tv_sec) * 1e9);
    return ts;
}

// Allows the render loop to wait if the queue is empty
- (void)waitForEnqueue {
    pthread_mutex_lock(&_mutex);
    if (!self.paused && _count == 0) {
        // 100ms, then the caller's loop checks for cancellation
        struct timespec ts = TimespecFromInterval(0.1);
        pthread_cond_timedwait_relative_np(&_cond, &_mutex, &ts);
    }
    pthread_mutex_unlock(&_mutex);
}

- (Frame *)_unsafeDequeue {
    Frame *frame = nil;
    if (_count > 0) {
        frame = [self _popFrame];
        // compute duration from next
        Frame *next = [self _peekFrame];
        if (next) {
            [frame setDurationFromNext:next];
        }
        FQLog(LOG_I, @"[<- %d / %f%@] dequeue frame, queue size %d/%d",
            frame.frameNumber, frame.pts,
            [frame durationIsValid] ? [NSString stringWithFormat:@" dur %.3f ms", frame.duration * 1000.0] : @"",
            _count, _highWaterMark);
    }
    return frame;
}

- (Frame *)dequeue {
    pthread_mutex_lock(&_mutex);
    Frame *frame = [self _unsafeDequeue];
    pthread_mutex_unlock(&_mutex);
    return frame;
}

- (Frame *)dequeueWithTimeout:(CFTimeInterval)timeout {
    if (self.paused) {
        return nil;
    }

    pthread_mutex_lock(&_mutex);
    if (_count == 0 && timeout > 0 && !self.paused) {
        // One wait: a frame or stop() wakes it early, so there's no polling. A spurious wakeup
        // just returns nil early, which the render loop treats like a timeout.
        struct timespec ts = TimespecFromInterval(timeout);
        pthread_cond_timedwait_relative_np(&_cond, &_mutex, &ts);
    }
    Frame *frame = self.paused ? nil : [self _unsafeDequeue];
    pthread_mutex_unlock(&_mutex);
    return frame;
}

- (NSUInteger)count {
    pthread_mutex_lock(&_mutex);
    NSUInteger c = _count;
    pthread_mutex_unlock(&_mutex);
    return c;
}

- (BOOL)isEmpty {
    return [self count] == 0;
}

- (void)clear {
    pthread_mutex_lock(&_mutex);
    for (int i = 0; i < _capacity; i++) {
        [_buffer replaceObjectAtIndex:i withObject:[NSNull null]];
    }
    _head = _tail = _count = 0;
    _droppedLast = NO;
    _ptsCorrection = CMTimeMake(0, 90000);
    _frameDropMetrics = [[FloatBuffer alloc] initWithCapacity:512];
    _framesIn = 0;
    _fpsWindowStart = 0;
    _fpsWindowFrames = 0;
    _fpsEstimate = 0;
    pthread_mutex_unlock(&_mutex);
}

- (CFTimeInterval)estimatedFramerate {
    pthread_mutex_lock(&_mutex);
    CFTimeInterval fps = _fpsEstimate;
    pthread_mutex_unlock(&_mutex);
    return fps;
}

- (int)currentSoftCap {
    pthread_mutex_lock(&_mutex);
    int cap = _currentSoftCap;
    pthread_mutex_unlock(&_mutex);
    return cap;
}

- (void)stop {
    [self stopForOwner:nil];
}

- (void)start {
    [self startForOwner:nil];
}

- (void)startForOwner:(id)owner {
    // (re)start for a new renderer, without frames left from the last one
    [self clear];
    pthread_mutex_lock(&_mutex);
    _owner = owner;
    self.paused = NO;
    pthread_mutex_unlock(&_mutex);
    Log(LOG_I, @"FrameQueue started");
}

- (void)stopForOwner:(id)owner {
    pthread_mutex_lock(&_mutex);
    id current = _owner;
    if (owner != nil && current != nil && owner != current) {
        pthread_mutex_unlock(&_mutex);
        Log(LOG_W, @"FrameQueue stop from an old session ignored");
        return;
    }
    _owner = nil;
    // new frames will no longer be coming in, make sure consumer side is not left waiting
    self.paused = YES;
    pthread_cond_broadcast(&_cond);
    pthread_mutex_unlock(&_mutex);
    [self clear];
    Log(LOG_I, @"FrameQueue stopped");
}

// For use with NSLog("%@", franeQueue);
- (NSString *)description {
    pthread_mutex_lock(&_mutex);
    __block NSMutableArray *parts = [NSMutableArray arrayWithCapacity:_count];
    [self _enumerateFrames:^(Frame *frame, NSUInteger idx, BOOL *stop) {
        [parts addObject:[frame description]];
    }];
    pthread_mutex_unlock(&_mutex);
    return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@",\n"]];
}

@end
