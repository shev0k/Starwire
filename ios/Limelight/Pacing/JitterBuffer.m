//
//  JitterBuffer.m
//  Starwire
//

#import "JitterBuffer.h"

NSString *const JitterBufferKey = @"StarwireJitterBuffer";
// Picked from the batch 1 device runs (device-runs/2026-10-25-feature-ios-batch-1.md). Android's
// default is balanced, which paces differently (host timestamps).
const JitterBufferMode JitterBufferDefaultMode = JitterBufferModeLowLatency;

// How long a hole keeps the target up, per mode. The same windows as Android's presets
// (frame_pacer.cpp): 2 s for low latency, 3 s for balanced, 30 s for smooth.
static double HoldSeconds(JitterBufferMode mode) {
    switch (mode) {
        case JitterBufferModeLowLatency: return 2.0;
        case JitterBufferModeBalanced: return 3.0;
        case JitterBufferModeSmooth: return 30.0;
        default: return 0;
    }
}

// Above the target for this long before catching up, then one frame every few frame intervals
static const double kCatchUpAfterSeconds = 0.25;
static const double kCatchUpEveryFrames = 4.0;
// Never more than this many frames above the target: the rest go at once
static const int kMaxExcess = 2;
// Needs remembered, newest last; more than one hole per frame interval can't happen
#define NEED_HISTORY 64

JitterBufferMode JitterBufferModeFromString(NSString *value) {
    if ([value isEqualToString:@"lowest-latency"]) {
        return JitterBufferModeLowestLatency;
    }
    if ([value isEqualToString:@"low-latency"]) {
        return JitterBufferModeLowLatency;
    }
    if ([value isEqualToString:@"balanced"]) {
        return JitterBufferModeBalanced;
    }
    if ([value isEqualToString:@"smooth"]) {
        return JitterBufferModeSmooth;
    }
    return JitterBufferDefaultMode;
}

NSString *JitterBufferModeName(JitterBufferMode mode) {
    switch (mode) {
        case JitterBufferModeLowestLatency: return @"lowest-latency";
        case JitterBufferModeLowLatency: return @"low-latency";
        case JitterBufferModeBalanced: return @"balanced";
        case JitterBufferModeSmooth: return @"smooth";
    }
    return @"balanced";
}

int JitterBufferMaxTarget(JitterBufferMode mode) {
    switch (mode) {
        case JitterBufferModeLowLatency: return 1;
        case JitterBufferModeBalanced: return 2;
        case JitterBufferModeSmooth: return 4;
        default: return 0;
    }
}

@implementation JitterBuffer {
    double _frameInterval;
    int _maxTarget;
    double _holdSeconds;

    CFTimeInterval _lastArrival;
    CFTimeInterval _needTimes[NEED_HISTORY];
    int _needs[NEED_HISTORY];
    int _needCount;
    int _needNext;

    BOOL _started;
    CFTimeInterval _lastShown;
    CFTimeInterval _aboveSince;
    CFTimeInterval _lastCatchUp;
}

- (instancetype)initWithMode:(JitterBufferMode)mode frameInterval:(double)frameInterval {
    self = [super init];
    if (self) {
        _mode = mode;
        _frameInterval = frameInterval > 0 ? frameInterval : 1.0 / 60.0;
        _maxTarget = JitterBufferMaxTarget(mode);
        _holdSeconds = HoldSeconds(mode);
    }
    return self;
}

- (void)noteArrivalAt:(CFTimeInterval)time {
    if (_lastArrival > 0 && time > _lastArrival && _maxTarget > 0) {
        // A frame n intervals after the last one leaves n - 1 refreshes with nothing new. Rounded,
        // so the normal wobble around one interval needs nothing.
        double frames = (time - _lastArrival) / _frameInterval;
        int need = (int)floor(frames - 0.5);
        if (need > 0) {
            _needTimes[_needNext] = time;
            _needs[_needNext] = MIN(need, _maxTarget);
            _needNext = (_needNext + 1) % NEED_HISTORY;
            _needCount = MIN(_needCount + 1, NEED_HISTORY);
        }
    }
    _lastArrival = time;
}

- (int)targetAt:(CFTimeInterval)now {
    int target = 0;
    for (int i = 0; i < _needCount; i++) {
        if (now - _needTimes[i] <= _holdSeconds && _needs[i] > target) {
            target = _needs[i];
        }
    }
    return target;
}

- (JitterBufferChoice)chooseWithQueued:(int)queued at:(CFTimeInterval)now {
    JitterBufferChoice choice = {0, NO};
    if (queued <= 0) {
        // A display faster than the stream (60 FPS on 120 Hz) has refreshes with nothing new by
        // design; only a frame that is late for its own time counts
        if (_started && now - _lastShown >= 0.75 * _frameInterval) {
            _underflows++;
        }
        _aboveSince = 0;
        return choice;
    }
    _started = YES;
    _lastShown = now;
    choice.show = YES;

    if (_maxTarget == 0) {
        // Lowest latency: the newest frame, every time
        choice.drop = queued - 1;
        _target = 0;
        return choice;
    }

    _target = [self targetAt:now];
    // Frames left after this one, beyond the target
    int excess = queued - 1 - _target;
    if (excess > kMaxExcess) {
        choice.drop = excess - kMaxExcess;
        _trimDrops += choice.drop;
        excess = kMaxExcess;
    }
    if (excess <= 0) {
        _aboveSince = 0;
        return choice;
    }
    if (_aboveSince == 0) {
        _aboveSince = now;
        return choice;
    }
    if (now - _aboveSince >= kCatchUpAfterSeconds - 1e-6 &&
        now - _lastCatchUp >= kCatchUpEveryFrames * _frameInterval - 1e-6) {
        choice.drop++;
        _catchUpDrops++;
        _lastCatchUp = now;
    }
    return choice;
}

@end
