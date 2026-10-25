//
//  PacingStats.m
//  Starwire
//

#import "PacingStats.h"
#import "Logger.h"
#import <os/lock.h>

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_PACING

// Two gaps a second for over an hour
#define PACING_MAX_GAP_TIMES 8192
// On-screen intervals kept for a window's 1% low: 5 s at 480 Hz with room to spare
#define PACING_MAX_SHOWN 4096

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

static int CompareDoubles(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

double PacingGapPeriod(const double *times, int count, double *regularShare) {
    if (regularShare) {
        *regularShare = 0;
    }
    if (count < 3) {
        return 0;
    }
    int n = count - 1;
    double *spacings = malloc(sizeof(double) * n);
    if (!spacings) {
        return 0;
    }
    for (int i = 0; i < n; i++) {
        spacings[i] = times[i + 1] - times[i];
    }
    qsort(spacings, n, sizeof(double), CompareDoubles);
    double median = (n % 2) ? spacings[n / 2] : (spacings[n / 2 - 1] + spacings[n / 2]) / 2.0;
    if (median > 0 && regularShare) {
        int regular = 0;
        for (int i = 0; i < n; i++) {
            double multiple = round(spacings[i] / median);
            if (multiple >= 1 && multiple <= 4 && fabs(spacings[i] - multiple * median) <= 0.15 * median) {
                regular++;
            }
        }
        *regularShare = (double)regular / n;
    }
    free(spacings);
    return median;
}

static int CompareDoublesDescending(const void *a, const void *b) {
    return -CompareDoubles(a, b);
}

double PacingOnePercentLowFps(const double *intervals, int count) {
    if (count <= 0) {
        return 0;
    }
    double *sorted = malloc(sizeof(double) * count);
    if (!sorted) {
        return 0;
    }
    memcpy(sorted, intervals, sizeof(double) * count);
    qsort(sorted, count, sizeof(double), CompareDoublesDescending);
    int worst = MAX(1, count / 100);
    double sum = 0;
    for (int i = 0; i < worst; i++) {
        sum += sorted[i];
    }
    free(sorted);
    return sum > 0 ? worst / sum : 0;
}

static NSString *RateOrDash(double value) {
    return value > 0 ? [NSString stringWithFormat:@"%.0f", value] : @"-";
}

NSString *PacingLiteOverlayLine(double fps, double onePercentLow, double networkDropPercent, double pacingDropPercent,
                                int rttMs, double decodeMs, double displayHz) {
    // Starts like the full overlay, which the device-run tests look for
    return [NSString stringWithFormat:@"Video stream: %.1f FPS, 1%% low %@, drops %.1f%% / %.1f%%, latency %@ ms, decode %.1f ms, display %@ Hz",
            fps, RateOrDash(onePercentLow), networkDropPercent, pacingDropPercent,
            rttMs >= 0 ? [NSString stringWithFormat:@"%d", rttMs] : @"-", decodeMs, RateOrDash(displayHz)];
}

CFTimeInterval PacingMediaTimeFromMicroseconds(uint64_t timeUs, uint64_t nowUs, CFTimeInterval nowMediaTime) {
    if (timeUs == 0) {
        return 0;
    }
    // Signed, so a time a little after "now" (clocks read in the other order) still converts
    double agoSeconds = ((double)(int64_t)(nowUs - timeUs)) / 1e6;
    return nowMediaTime - agoSeconds;
}

void PacingWindowAccumulate(PacingWindow *total, const PacingWindow *w) {
    total->windowSeconds += w->windowSeconds;
    total->netFrames += w->netFrames;
    total->netGaps += w->netGaps;
    total->netMaxGapMs = MAX(total->netMaxGapMs, w->netMaxGapMs);
    total->netClumped += w->netClumped;
    total->netMaxClump = MAX(total->netMaxClump, w->netMaxClump);
    total->netReceiveSeconds += w->netReceiveSeconds;
    total->netMaxReceiveMs = MAX(total->netMaxReceiveMs, w->netMaxReceiveMs);
    total->hostGaps += w->hostGaps;
    total->hostMaxGapMs = MAX(total->hostMaxGapMs, w->hostMaxGapMs);
    total->netLatencySamples += w->netLatencySamples;
    total->netLatencySeconds += w->netLatencySeconds;
    total->maxNetLatencyMs = MAX(total->maxNetLatencyMs, w->maxNetLatencyMs);
    if (w->onePercentLowFps > 0 && (total->onePercentLowFps == 0 || w->onePercentLowFps < total->onePercentLowFps)) {
        total->onePercentLowFps = w->onePercentLowFps;
    }
    total->interpolated += w->interpolated;
    total->interpolationFailures += w->interpolationFailures;
    total->interpolationSeconds += w->interpolationSeconds;
    total->jitterSamples += w->jitterSamples;
    total->jitterTargetSum += w->jitterTargetSum;
    total->maxJitterTarget = MAX(total->maxJitterTarget, w->maxJitterTarget);
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
    total->latencySamples += w->latencySamples;
    total->latencySeconds += w->latencySeconds;
    total->maxLatencyMs = MAX(total->maxLatencyMs, w->maxLatencyMs);
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

    CFTimeInterval _lastAssembled;
    uint64_t _lastHostTimeUs;
    int _clumpRun;
    // When each network gap ended, for the whole stream (the first PACING_MAX_GAP_TIMES)
    double *_gapTimes;
    int _gapTimeCount;
    double *_shownIntervals;
    int _shownCount;

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
        _jitterBufferName = @"off";
        _interpolationNote = @"off";
        _pictureInPictureNote = @"off";
        _colourNote = @"-";
        _gapTimes = calloc(PACING_MAX_GAP_TIMES, sizeof(double));
        _shownIntervals = calloc(PACING_MAX_SHOWN, sizeof(double));
    }
    return self;
}

- (void)dealloc {
    free(_gapTimes);
    free(_shownIntervals);
}

- (void)noteNetworkFrameReceivedAt:(CFTimeInterval)received assembledAt:(CFTimeInterval)assembled hostTimeUs:(uint64_t)hostTimeUs {
    if (assembled <= 0) {
        return;
    }
    [self rollWindowIfDueAt:assembled];

    os_unfair_lock_lock(&_lock);
    if (_windowStart == 0) {
        _windowStart = assembled;
    }
    _current.netFrames++;
    if (received > 0 && assembled >= received) {
        double receive = assembled - received;
        _current.netReceiveSeconds += receive;
        _current.netMaxReceiveMs = MAX(_current.netMaxReceiveMs, receive * 1000.0);
    }
    if (_lastAssembled > 0) {
        double gap = assembled - _lastAssembled;
        double frames = gap / _frameInterval;
        if (frames > 2.5) {
            _current.netGaps++;
            if (_gapTimes && _gapTimeCount < PACING_MAX_GAP_TIMES) {
                _gapTimes[_gapTimeCount++] = assembled;
            }
        }
        _current.netMaxGapMs = MAX(_current.netMaxGapMs, gap * 1000.0);
        if (frames < 0.5) {
            _current.netClumped++;
            _clumpRun++;
        } else {
            _clumpRun = 0;
        }
        // A clump counts the frame that started it too
        _current.netMaxClump = MAX(_current.netMaxClump, _clumpRun + 1);
    }
    _lastAssembled = assembled;

    if (_lastHostTimeUs > 0 && hostTimeUs > _lastHostTimeUs) {
        double hostGap = (double)(hostTimeUs - _lastHostTimeUs) / 1e6;
        if (hostGap / _frameInterval > 2.5) {
            _current.hostGaps++;
        }
        _current.hostMaxGapMs = MAX(_current.hostMaxGapMs, hostGap * 1000.0);
    }
    if (hostTimeUs > 0) {
        _lastHostTimeUs = hostTimeUs;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)noteInterpolatedFrame:(BOOL)made seconds:(double)seconds {
    os_unfair_lock_lock(&_lock);
    if (made) {
        _current.interpolated++;
        _current.interpolationSeconds += seconds;
    } else {
        _current.interpolationFailures++;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)noteJitterTarget:(int)target {
    os_unfair_lock_lock(&_lock);
    _current.jitterSamples++;
    _current.jitterTargetSum += target;
    _current.maxJitterTarget = MAX(_current.maxJitterTarget, target);
    os_unfair_lock_unlock(&_lock);
}

// The median time between network gaps over the whole stream, in ms, and how regular it is
- (double)gapPeriodMs:(double *)regularShare {
    os_unfair_lock_lock(&_lock);
    double period = PacingGapPeriod(_gapTimes, _gapTimeCount, regularShare);
    os_unfair_lock_unlock(&_lock);
    return period * 1000.0;
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
    [self notePresentedAt:presentedTime target:0 decodedAt:0];
}

- (void)notePresentedAt:(CFTimeInterval)presentedTime target:(CFTimeInterval)target decodedAt:(CFTimeInterval)decodedAt {
    [self notePresentedAt:presentedTime target:target decodedAt:decodedAt receivedAt:0];
}

- (void)notePresentedAt:(CFTimeInterval)presentedTime target:(CFTimeInterval)target decodedAt:(CFTimeInterval)decodedAt receivedAt:(CFTimeInterval)receivedAt {
    os_unfair_lock_lock(&_lock);
    if (presentedTime <= 0) {
        _current.presentSkipped++;
    } else {
        _current.presented++;
        if (_lastPresented > 0 && presentedTime > _lastPresented) {
            PacingIntervalsAdd(&_current.shown, presentedTime - _lastPresented, _step);
            if (_shownIntervals && _shownCount < PACING_MAX_SHOWN) {
                _shownIntervals[_shownCount++] = presentedTime - _lastPresented;
            }
        }
        if (target > 0 && presentedTime - target > _step / 2.0) {
            _current.presentLate++;
        }
        if (decodedAt > 0 && presentedTime >= decodedAt) {
            double latency = presentedTime - decodedAt;
            _current.latencySamples++;
            _current.latencySeconds += latency;
            if (latency * 1000.0 > _current.maxLatencyMs) {
                _current.maxLatencyMs = latency * 1000.0;
            }
        }
        if (receivedAt > 0 && presentedTime >= receivedAt) {
            double latency = presentedTime - receivedAt;
            _current.netLatencySamples++;
            _current.netLatencySeconds += latency;
            _current.maxNetLatencyMs = MAX(_current.maxNetLatencyMs, latency * 1000.0);
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
    _current.onePercentLowFps = PacingOnePercentLowFps(_shownIntervals, _shownCount);
    _shownCount = 0;
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

static double MeanLatencyMs(PacingWindow w) {
    return w.latencySamples > 0 ? w.latencySeconds * 1000.0 / w.latencySamples : 0.0;
}

static double MeanNetLatencyMs(PacingWindow w) {
    return w.netLatencySamples > 0 ? w.netLatencySeconds * 1000.0 / w.netLatencySamples : 0.0;
}

static double MeanJitterTarget(PacingWindow w) {
    return w.jitterSamples > 0 ? (double)w.jitterTargetSum / w.jitterSamples : 0.0;
}

// "gaps 90, max 141.1 ms, every 512 ms (80% regular), clumped 865, max clump 12, receive
// 1.2/9.0 ms, host gaps 0, max 9.1 ms"
- (NSString *)networkPartForWindow:(PacingWindow)w {
    double regular = 0;
    double period = [self gapPeriodMs:&regular];
    NSString *every = period > 0
        ? [NSString stringWithFormat:@"every %.0f ms (%.0f%% regular)", period, regular * 100.0]
        : @"every - ms";
    return [NSString stringWithFormat:@"gaps %d, max %.1f ms, %@, clumped %d, max clump %d, receive %.1f/%.1f ms, host gaps %d, max %.1f ms",
            w.netGaps, w.netMaxGapMs, every, w.netClumped, w.netMaxClump,
            w.netFrames > 0 ? w.netReceiveSeconds * 1000.0 / w.netFrames : 0.0, w.netMaxReceiveMs,
            w.hostGaps, w.hostMaxGapMs];
}

- (NSString *)logLineForWindow:(PacingWindow)w {
    int drops = TotalDrops(w);
    return [NSString stringWithFormat:
            @"pacing window %.1f s: in %d, drops %d (%.2f%%: incoming %d, oldest %d, replaced %d, after burst %d), max queue %d; "
            "arrival gaps burst/on time/late/gap %d/%d/%d/%d, max %.1f ms; "
            "shown %d, shown for %@, mean %.2f ms, max %.1f ms, off grid %d, late %d, skipped by compositor %d; "
            "refresh %@, mean %.2f ms; refreshes with/without a new frame %d/%d; drawable wait mean %.2f ms, max %.1f ms; "
            "decode to screen mean %.1f ms, max %.1f ms; network %d frames, %@; network to screen mean %.1f ms, max %.1f ms; "
            "jitter buffer %@ held mean %.2f, max %d, catch up %d",
            w.windowSeconds, w.arrivals, drops, Percent(drops, w.arrivals),
            w.drops[PacingDropIncoming], w.drops[PacingDropOldest], w.drops[PacingDropReplaced], w.dropsAfterBurst, w.maxQueueDepth,
            w.arrivalBursts, w.arrivalOnTime, w.arrivalLate, w.arrivalGaps, w.maxArrivalGapMs,
            w.presented, [self histogramOf:w.shown], MeanMs(w.shown), w.shown.maxSeconds * 1000.0, w.shown.offGrid,
            w.presentLate, w.presentSkipped,
            [self histogramOf:w.refresh], MeanMs(w.refresh),
            w.refreshesWithFrame, w.refreshesWithoutFrame,
            w.drawableWaits > 0 ? w.drawableWaitSeconds * 1000.0 / w.drawableWaits : 0.0, w.maxDrawableWaitMs,
            MeanLatencyMs(w), w.maxLatencyMs,
            w.netFrames, [self networkPartForWindow:w], MeanNetLatencyMs(w), w.maxNetLatencyMs,
            self.jitterBufferName, MeanJitterTarget(w), w.maxJitterTarget, w.drops[PacingDropCatchUp]];
}

- (NSString *)overlayLineForWindow:(PacingWindow)w {
    return [NSString stringWithFormat:@"Network: %@\n"
            "Pacing: bursts %.1f%%, drops after burst %d, skipped %d, late %d, jitter buffer %@ %.1f\n"
            "Shown for %@, mean %.2f ms, 1%% low %.1f FPS, refresh %.2f ms, decode to screen %.1f ms",
            [self networkPartForWindow:w],
            Percent(w.arrivalBursts, w.arrivals > 1 ? w.arrivals - 1 : 0),
            w.dropsAfterBurst,
            w.presentSkipped,
            w.presentLate,
            self.jitterBufferName, MeanJitterTarget(w),
            [self histogramOf:w.shown], MeanMs(w.shown), w.onePercentLowFps, MeanMs(w.refresh), MeanLatencyMs(w)];
}

- (NSString *)summaryLineForWindow:(PacingWindow)w {
    int drops = TotalDrops(w);
    int refreshes = w.refreshesWithFrame + w.refreshesWithoutFrame;
    return [NSString stringWithFormat:
            @"Pacing summary (%@): %.0f s, in %d, drops %.2f%% (incoming %d, oldest %d, replaced %d), "
            "arrival late %d, gaps %d, max gap %.1f ms; shown %d, "
            "shown for %@, mean %.2f ms, max %.1f ms, off grid %.1f%%, late %d, skipped %d; "
            "refresh mean %.2f ms, off grid %.1f%%; refreshes without a new frame %.1f%%; drawable wait mean %.2f ms; "
            "decode to screen mean %.1f ms, max %.1f ms; "
            "network %@; network to screen mean %.1f ms, max %.1f ms; "
            "jitter buffer %@, held mean %.2f, max %d, catch up %d; 1%% low (worst 5 s) %.1f FPS; "
            "interpolation %@, made %d, failed %d, mean %.2f ms; picture in picture %@; colour %@",
            self.presenterName, w.windowSeconds, w.arrivals, Percent(drops, w.arrivals),
            w.drops[PacingDropIncoming], w.drops[PacingDropOldest], w.drops[PacingDropReplaced],
            w.arrivalLate, w.arrivalGaps, w.maxArrivalGapMs, w.presented,
            [self histogramOf:w.shown], MeanMs(w.shown), w.shown.maxSeconds * 1000.0,
            Percent(w.shown.offGrid, w.shown.total), w.presentLate, w.presentSkipped,
            MeanMs(w.refresh), Percent(w.refresh.offGrid, w.refresh.total),
            Percent(w.refreshesWithoutFrame, refreshes),
            w.drawableWaits > 0 ? w.drawableWaitSeconds * 1000.0 / w.drawableWaits : 0.0,
            MeanLatencyMs(w), w.maxLatencyMs,
            [self networkPartForWindow:w], MeanNetLatencyMs(w), w.maxNetLatencyMs,
            self.jitterBufferName, MeanJitterTarget(w), w.maxJitterTarget, w.drops[PacingDropCatchUp],
            w.onePercentLowFps,
            self.interpolationNote, w.interpolated, w.interpolationFailures,
            w.interpolated > 0 ? w.interpolationSeconds * 1000.0 / w.interpolated : 0.0,
            self.pictureInPictureNote, self.colourNote];
}

@end
