//
//  PacingStats.m
//  Starwire
//

#import "PacingStats.h"
#import "Logger.h"
#import <os/lock.h>

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_PACING

@implementation PacingStats {
    os_unfair_lock _lock;
    double _frameInterval;
    double _refreshInterval;
    double _windowLength;

    CFTimeInterval _windowStart;
    CFTimeInterval _lastArrival;
    CFTimeInterval _lastPresented;
    double _lastArrivalGapFrames;

    PacingWindow _current;
    PacingWindow _last;
}

- (instancetype)initWithFrameInterval:(double)frameInterval
                      refreshInterval:(double)refreshInterval
                         windowLength:(double)windowLength {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _frameInterval = frameInterval > 0 ? frameInterval : 1.0 / 60.0;
        _refreshInterval = refreshInterval > 0 ? refreshInterval : 1.0 / 60.0;
        _windowLength = windowLength > 0 ? windowLength : 5.0;
        _lastArrivalGapFrames = 1.0;
    }
    return self;
}

- (void)noteArrivalAt:(CFTimeInterval)time {
    [self rollWindowIfDueAt:time];

    os_unfair_lock_lock(&_lock);
    if (_windowStart == 0) {
        _windowStart = time;
    }
    _current.arrivals++;
    if (_lastArrival > 0) {
        double gap = time - _lastArrival;
        double frames = gap / _frameInterval;
        _lastArrivalGapFrames = frames;
        if (frames < 0.5) {
            _current.arrivalBursts++;
        } else if (frames < 1.5) {
            _current.arrivalOnTime++;
        } else if (frames < 2.5) {
            _current.arrivalLate++;
        } else {
            _current.arrivalGaps++;
        }
        if (gap * 1000.0 > _current.maxArrivalGapMs) {
            _current.maxArrivalGapMs = gap * 1000.0;
        }
    }
    _lastArrival = time;
    os_unfair_lock_unlock(&_lock);
}

- (void)noteDrop:(PacingDropReason)reason queueDepth:(NSUInteger)depth {
    if (reason < 0 || reason >= PacingDropReasonCount) {
        return;
    }
    os_unfair_lock_lock(&_lock);
    _current.drops[reason]++;
    if (_lastArrivalGapFrames < 0.5) {
        _current.dropsAfterBurst++;
    }
    if ((int)depth > _current.maxQueueDepth) {
        _current.maxQueueDepth = (int)depth;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)noteQueueDepth:(NSUInteger)depth {
    os_unfair_lock_lock(&_lock);
    if ((int)depth > _current.maxQueueDepth) {
        _current.maxQueueDepth = (int)depth;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)notePresentedAt:(CFTimeInterval)presentedTime {
    os_unfair_lock_lock(&_lock);
    if (presentedTime <= 0) {
        _current.presentSkipped++;
    } else {
        _current.presented++;
        if (_lastPresented > 0 && presentedTime > _lastPresented) {
            double refreshes = (presentedTime - _lastPresented) / _refreshInterval;
            if (refreshes < 1.5) {
                _current.heldOneRefresh++;
            } else if (refreshes < 2.5) {
                _current.heldTwoRefreshes++;
            } else {
                _current.heldThreeOrMore++;
            }
        }
        _lastPresented = presentedTime;
    }
    os_unfair_lock_unlock(&_lock);
}

- (PacingWindow)currentWindow {
    os_unfair_lock_lock(&_lock);
    PacingWindow w = _current;
    os_unfair_lock_unlock(&_lock);
    return w;
}

- (PacingWindow)lastWindow {
    os_unfair_lock_lock(&_lock);
    PacingWindow w = _last;
    os_unfair_lock_unlock(&_lock);
    return w;
}

- (BOOL)rollWindowIfDueAt:(CFTimeInterval)time {
    PacingWindow finished;
    os_unfair_lock_lock(&_lock);
    if (_windowStart == 0 || time - _windowStart < _windowLength) {
        os_unfair_lock_unlock(&_lock);
        return NO;
    }
    _current.windowSeconds = time - _windowStart;
    finished = _current;
    _last = _current;
    memset(&_current, 0, sizeof(_current));
    _windowStart = time;
    os_unfair_lock_unlock(&_lock);

    Log(LOG_I, @"%@", [PacingStats logLineForWindow:finished]);
    return YES;
}

static double Percent(int part, int whole) {
    return whole > 0 ? (100.0 * part) / whole : 0.0;
}

+ (NSString *)logLineForWindow:(PacingWindow)w {
    int drops = w.drops[PacingDropIncoming] + w.drops[PacingDropOldest];
    return [NSString stringWithFormat:
            @"pacing window %.1f s: in %d, drops %d (%.2f%%: incoming %d, oldest %d, after burst %d), max queue %d; "
            "arrival gaps burst/on time/late/gap %d/%d/%d/%d, max %.1f ms; "
            "shown %d, held 1/2/3+ refreshes %d/%d/%d, skipped by compositor %d",
            w.windowSeconds, w.arrivals, drops, Percent(drops, w.arrivals),
            w.drops[PacingDropIncoming], w.drops[PacingDropOldest], w.dropsAfterBurst, w.maxQueueDepth,
            w.arrivalBursts, w.arrivalOnTime, w.arrivalLate, w.arrivalGaps, w.maxArrivalGapMs,
            w.presented, w.heldOneRefresh, w.heldTwoRefreshes, w.heldThreeOrMore, w.presentSkipped];
}

+ (NSString *)overlayLineForWindow:(PacingWindow)w {
    int held = w.heldOneRefresh + w.heldTwoRefreshes + w.heldThreeOrMore;
    return [NSString stringWithFormat:@"Pacing: bursts %.1f%%, drops after burst %d, held 2+ refreshes %.1f%%, skipped %d",
            Percent(w.arrivalBursts, w.arrivals > 1 ? w.arrivals - 1 : 0),
            w.dropsAfterBurst,
            Percent(w.heldTwoRefreshes + w.heldThreeOrMore, held),
            w.presentSkipped];
}

@end
