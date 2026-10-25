//
//  PacingStats.m
//  Starwire
//

#import "PacingStats.h"
#import "Logger.h"
#import <os/lock.h>

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_PACING

int PacingIntervalBucket(double interval, double step) {
    if (!(interval > 0) || !(step > 0)) {
        return 0;
    }
    long steps = lround(interval / step);
    if (steps < 0) {
        return 0;
    }
    return steps >= PACING_INTERVAL_BUCKETS ? PACING_INTERVAL_BUCKETS - 1 : (int)steps;
}

void PacingIntervalsAdd(PacingIntervals *intervals, double interval, double step) {
    if (!(interval > 0) || !(step > 0)) {
        return;
    }
    intervals->counts[PacingIntervalBucket(interval, step)]++;
    intervals->total++;
    intervals->sumSeconds += interval;
    if (interval > intervals->maxSeconds) {
        intervals->maxSeconds = interval;
    }
    double steps = interval / step;
    if (fabs(steps - round(steps)) > 0.25) {
        intervals->offGrid++;
    }
}

static void AccumulateIntervals(PacingIntervals *total, const PacingIntervals *add) {
    for (int i = 0; i < PACING_INTERVAL_BUCKETS; i++) {
        total->counts[i] += add->counts[i];
    }
    total->total += add->total;
    total->sumSeconds += add->sumSeconds;
    total->maxSeconds = MAX(total->maxSeconds, add->maxSeconds);
    total->offGrid += add->offGrid;
}

void PacingWindowAccumulate(PacingWindow *total, const PacingWindow *w) {
    total->windowSeconds += w->windowSeconds;
    total->arrivals += w->arrivals;
    total->arrivalBursts += w->arrivalBursts;
    total->arrivalOnTime += w->arrivalOnTime;
    total->arrivalLate += w->arrivalLate;
    total->arrivalGaps += w->arrivalGaps;
    total->maxArrivalGapMs = MAX(total->maxArrivalGapMs, w->maxArrivalGapMs);
    for (int i = 0; i < PacingDropReasonCount; i++) {
        total->drops[i] += w->drops[i];
    }
    total->dropsAfterBurst += w->dropsAfterBurst;
    total->maxQueueDepth = MAX(total->maxQueueDepth, w->maxQueueDepth);
    total->presented += w->presented;
    AccumulateIntervals(&total->shown, &w->shown);
    total->presentSkipped += w->presentSkipped;
    total->presentLate += w->presentLate;
    AccumulateIntervals(&total->refresh, &w->refresh);
    total->refreshesWithFrame += w->refreshesWithFrame;
    total->refreshesWithoutFrame += w->refreshesWithoutFrame;
    total->drawableWaits += w->drawableWaits;
    total->drawableWaitSeconds += w->drawableWaitSeconds;
    total->maxDrawableWaitMs = MAX(total->maxDrawableWaitMs, w->maxDrawableWaitMs);
}

@implementation PacingStats {
    os_unfair_lock _lock;
    double _frameInterval;
    double _refreshInterval;
    double _step;
    double _windowLength;

    CFTimeInterval _windowStart;
    CFTimeInterval _lastArrival;
    CFTimeInterval _lastPresented;
    double _lastArrivalGapFrames;

    PacingWindow _current;
    PacingWindow _last;
    // Every finished window added up
    PacingWindow _finished;
}

- (instancetype)initWithFrameInterval:(double)frameInterval
                      refreshInterval:(double)refreshInterval
                         windowLength:(double)windowLength {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _frameInterval = frameInterval > 0 ? frameInterval : 1.0 / 60.0;
        _refreshInterval = refreshInterval > 0 ? refreshInterval : 1.0 / 60.0;
        _step = _refreshInterval / 2.0;
        _windowLength = windowLength > 0 ? windowLength : 5.0;
        _lastArrivalGapFrames = 1.0;
        _presenterName = @"loop";
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
    if (reason != PacingDropReplaced && _lastArrivalGapFrames < 0.5) {
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
    [self notePresentedAt:presentedTime target:0];
}

- (void)notePresentedAt:(CFTimeInterval)presentedTime target:(CFTimeInterval)target {
    os_unfair_lock_lock(&_lock);
    if (presentedTime <= 0) {
        _current.presentSkipped++;
    } else {
        _current.presented++;
        if (_lastPresented > 0 && presentedTime > _lastPresented) {
            PacingIntervalsAdd(&_current.shown, presentedTime - _lastPresented, _step);
        }
        if (target > 0 && presentedTime - target > _step / 2.0) {
            _current.presentLate++;
        }
        _lastPresented = presentedTime;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)noteRefreshInterval:(double)interval {
    os_unfair_lock_lock(&_lock);
    PacingIntervalsAdd(&_current.refresh, interval, _step);
    os_unfair_lock_unlock(&_lock);
}

- (void)noteRefreshWithNewFrame:(BOOL)hadFrame {
    os_unfair_lock_lock(&_lock);
    if (hadFrame) {
        _current.refreshesWithFrame++;
    } else {
        _current.refreshesWithoutFrame++;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)noteDrawableWait:(double)seconds {
    if (seconds < 0) {
        return;
    }
    os_unfair_lock_lock(&_lock);
    _current.drawableWaits++;
    _current.drawableWaitSeconds += seconds;
    if (seconds * 1000.0 > _current.maxDrawableWaitMs) {
        _current.maxDrawableWaitMs = seconds * 1000.0;
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

- (PacingWindow)totalWindow {
    os_unfair_lock_lock(&_lock);
    PacingWindow total = _finished;
    PacingWindow current = _current;
    os_unfair_lock_unlock(&_lock);
    PacingWindowAccumulate(&total, &current);
    return total;
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
    PacingWindowAccumulate(&_finished, &_current);
    memset(&_current, 0, sizeof(_current));
    _windowStart = time;
    os_unfair_lock_unlock(&_lock);

    Log(LOG_I, @"%@", [self logLineForWindow:finished]);
    return YES;
}

#pragma mark - Lines

static double Percent(int part, int whole) {
    return whole > 0 ? (100.0 * part) / whole : 0.0;
}

static int TotalDrops(PacingWindow w) {
    int drops = 0;
    for (int i = 0; i < PacingDropReasonCount; i++) {
        drops += w.drops[i];
    }
    return drops;
}

// "4.2/8.3/12.5/16.7/20.8/25+ ms: 0.0/88.0/10.0/1.5/0.5/0.0%". The first column also holds the
// few intervals that round to no steps at all.
- (NSString *)histogramOf:(PacingIntervals)intervals {
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSMutableArray<NSString *> *shares = [NSMutableArray array];
    for (int i = 1; i < PACING_INTERVAL_BUCKETS; i++) {
        int count = intervals.counts[i] + (i == 1 ? intervals.counts[0] : 0);
        NSString *label = [NSString stringWithFormat:@"%.1f", i * _step * 1000.0];
        if (i == PACING_INTERVAL_BUCKETS - 1) {
            label = [NSString stringWithFormat:@"%.0f+", i * _step * 1000.0];
        }
        [labels addObject:label];
        [shares addObject:[NSString stringWithFormat:@"%.1f", Percent(count, intervals.total)]];
    }
    return [NSString stringWithFormat:@"%@ ms: %@%%",
            [labels componentsJoinedByString:@"/"], [shares componentsJoinedByString:@"/"]];
}

static double MeanMs(PacingIntervals intervals) {
    return intervals.total > 0 ? intervals.sumSeconds * 1000.0 / intervals.total : 0.0;
}

- (NSString *)logLineForWindow:(PacingWindow)w {
    int drops = TotalDrops(w);
    return [NSString stringWithFormat:
            @"pacing window %.1f s: in %d, drops %d (%.2f%%: incoming %d, oldest %d, replaced %d, after burst %d), max queue %d; "
            "arrival gaps burst/on time/late/gap %d/%d/%d/%d, max %.1f ms; "
            "shown %d, shown for %@, mean %.2f ms, max %.1f ms, off grid %d, late %d, skipped by compositor %d; "
            "refresh %@, mean %.2f ms; refreshes with/without a new frame %d/%d; drawable wait mean %.2f ms, max %.1f ms",
            w.windowSeconds, w.arrivals, drops, Percent(drops, w.arrivals),
            w.drops[PacingDropIncoming], w.drops[PacingDropOldest], w.drops[PacingDropReplaced], w.dropsAfterBurst, w.maxQueueDepth,
            w.arrivalBursts, w.arrivalOnTime, w.arrivalLate, w.arrivalGaps, w.maxArrivalGapMs,
            w.presented, [self histogramOf:w.shown], MeanMs(w.shown), w.shown.maxSeconds * 1000.0, w.shown.offGrid,
            w.presentLate, w.presentSkipped,
            [self histogramOf:w.refresh], MeanMs(w.refresh),
            w.refreshesWithFrame, w.refreshesWithoutFrame,
            w.drawableWaits > 0 ? w.drawableWaitSeconds * 1000.0 / w.drawableWaits : 0.0, w.maxDrawableWaitMs];
}

- (NSString *)overlayLineForWindow:(PacingWindow)w {
    return [NSString stringWithFormat:@"Pacing: bursts %.1f%%, drops after burst %d, skipped %d, late %d\n"
            "Shown for %@, mean %.2f ms, refresh %.2f ms",
            Percent(w.arrivalBursts, w.arrivals > 1 ? w.arrivals - 1 : 0),
            w.dropsAfterBurst,
            w.presentSkipped,
            w.presentLate,
            [self histogramOf:w.shown], MeanMs(w.shown), MeanMs(w.refresh)];
}

- (NSString *)summaryLineForWindow:(PacingWindow)w {
    int drops = TotalDrops(w);
    int refreshes = w.refreshesWithFrame + w.refreshesWithoutFrame;
    return [NSString stringWithFormat:
            @"Pacing summary (%@): %.0f s, in %d, drops %.2f%% (incoming %d, oldest %d, replaced %d), shown %d, "
            "shown for %@, mean %.2f ms, off grid %.1f%%, late %d, skipped %d; "
            "refresh mean %.2f ms, off grid %.1f%%; refreshes without a new frame %.1f%%; drawable wait mean %.2f ms",
            self.presenterName, w.windowSeconds, w.arrivals, Percent(drops, w.arrivals),
            w.drops[PacingDropIncoming], w.drops[PacingDropOldest], w.drops[PacingDropReplaced], w.presented,
            [self histogramOf:w.shown], MeanMs(w.shown), Percent(w.shown.offGrid, w.shown.total), w.presentLate, w.presentSkipped,
            MeanMs(w.refresh), Percent(w.refresh.offGrid, w.refresh.total),
            Percent(w.refreshesWithoutFrame, refreshes),
            w.drawableWaits > 0 ? w.drawableWaitSeconds * 1000.0 / w.drawableWaits : 0.0];
}

@end
