//
//  PacingStats.h
//  Starwire
//
//  Counts what happens to each frame between the decoder and the screen, so a run can tell
//  frames dropped because too many arrived at once (bursty arrival) from frames dropped because
//  the screen took them too slowly (late presentation). Times are passed in, never read from a
//  clock here, so the class can be tested with made-up timelines.
//
//  Every window (5 s by default) the totals are logged to the "pacing" category and kept for the
//  statistics overlay. A running total over the whole stream gives the summary line that the
//  device-run tests read from the overlay.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PacingDropReason) {
    // The queue was full and the incoming frame was dropped
    PacingDropIncoming = 0,
    // The queue was full and its oldest frame was dropped to make room
    PacingDropOldest = 1,
    // The display presenter found a newer frame waiting at a refresh and skipped this one
    PacingDropReplaced = 2,
    // The jitter buffer held more frames than its target and dropped one to catch up
    PacingDropCatchUp = 3,
    PacingDropReasonCount = 4,
};

// Intervals are sorted into steps of half a display refresh: 4.17 ms at 120 Hz. Index n counts
// the intervals that round to n steps, so at 120 Hz index 2 is 8.33 ms, 3 is 12.5 ms and 4 is
// 16.67 ms. The last index also counts everything longer.
//
// Half steps, because a ProMotion panel can show a frame on a 4.17 ms grid. The old "held 2+
// refreshes" counter cut at 1.5 refreshes, which is exactly 12.5 ms, so a frame shown for
// 12.5 ms could be counted as held for one refresh.
#define PACING_INTERVAL_BUCKETS 7

typedef struct {
    int counts[PACING_INTERVAL_BUCKETS];
    int total;
    double sumSeconds;
    double maxSeconds;
    // Intervals more than a quarter step away from a whole number of steps
    int offGrid;
} PacingIntervals;

typedef struct {
    double windowSeconds;

    // Frames out of the decoder
    int arrivals;
    // Arrival gaps, in stream frame intervals: under 0.5 (a burst), 0.5 to 1.5 (on time),
    // 1.5 to 2.5 (one frame late), and over 2.5
    int arrivalBursts;
    int arrivalOnTime;
    int arrivalLate;
    int arrivalGaps;
    double maxArrivalGapMs;

    // Frames as the network delivered them, before decoding (DECODE_UNIT receiveTimeUs and
    // enqueueTimeUs): frames whose last packet came more than 2.5 frame intervals after the last
    // packet of the frame before (gaps), and frames that came within half an interval of the one
    // before (clumped), with the largest run of those
    int netFrames;
    int netGaps;
    double netMaxGapMs;
    int netClumped;
    int netMaxClump;
    // From a frame's first packet to its last
    double netReceiveSeconds;
    double netMaxReceiveMs;
    // Gaps of more than 2.5 frame intervals in the host's own frame times: frames the host
    // didn't send, rather than frames the network held up
    int hostGaps;
    double hostMaxGapMs;

    int drops[PacingDropReasonCount];
    // Drops where the frame that overflowed the queue came within half a frame interval of the
    // previous one
    int dropsAfterBurst;
    int maxQueueDepth;

    // Frames the screen showed, and how long the one before each stayed up (from the
    // drawables' presentedTime)
    int presented;
    PacingIntervals shown;
    // The frame rate of the slowest 1% of on-screen intervals, set when a window ends. Over a
    // whole stream, the worst window's.
    double onePercentLowFps;
    // Drawables the compositor never showed (presentedTime 0)
    int presentSkipped;
    // Shown more than half a step after the refresh they were rendered for. Only the display
    // presenter knows that refresh.
    int presentLate;
    // From the end of decoding to the moment the frame appeared: the time a frame spends in the
    // queue, the render and the compositor. Shown frames only.
    int latencySamples;
    double latencySeconds;
    double maxLatencyMs;
    // From the frame's last packet to the moment it appeared: what the jitter buffer adds shows
    // here
    int netLatencySamples;
    double netLatencySeconds;
    double maxNetLatencyMs;

    // The time between display refreshes, as the display link reports them
    PacingIntervals refresh;
    // Display presenter: refreshes that had a new frame to show, and ones that didn't
    int refreshesWithFrame;
    int refreshesWithoutFrame;

    // Frame interpolation: frames made, failures, and the time spent making them
    int interpolated;
    int interpolationFailures;
    double interpolationSeconds;

    // Display presenter with a jitter buffer: frames held back, sampled at every refresh
    int jitterSamples;
    int jitterTargetSum;
    int maxJitterTarget;

    // Render loop: time spent waiting in nextDrawable
    int drawableWaits;
    double drawableWaitSeconds;
    double maxDrawableWaitMs;
} PacingWindow;

// The bucket an interval goes in, for a step of half a refresh. Exposed for the tests.
int PacingIntervalBucket(double interval, double step);
void PacingIntervalsAdd(PacingIntervals *intervals, double interval, double step);
// Adds a finished window to a running total
void PacingWindowAccumulate(PacingWindow *total, const PacingWindow *window);
// The usual time between network gaps: the median spacing of `count` gap times, in seconds, and
// in regularShare the share of spacings within 15% of 1 to 4 times that median. A steady period
// points at something on a timer, such as the Wi-Fi radio leaving the channel for AWDL. 0 with
// fewer than 3 gaps.
double PacingGapPeriod(const double *times, int count, double *_Nullable regularShare);
// 1% low: 1 / the mean of the longest 1% of `count` intervals (at least one). 0 for none.
double PacingOnePercentLowFps(const double *intervals, int count);
// The Lite statistics overlay: one line. onePercentLow, displayHz or rttMs below 0 (or 0 for the
// rates) show as "-" while not known yet.
NSString *PacingLiteOverlayLine(double fps, double onePercentLow, double networkDropPercent, double pacingDropPercent,
                                int rttMs, double decodeMs, double displayHz);
// A common-c time (LiGetMicroseconds) as a CACurrentMediaTime, given both clocks read now
CFTimeInterval PacingMediaTimeFromMicroseconds(uint64_t timeUs, uint64_t nowUs, CFTimeInterval nowMediaTime);

@interface PacingStats : NSObject

// frameInterval is 1/stream FPS, refreshInterval is 1/display Hz, in seconds
- (instancetype)initWithFrameInterval:(double)frameInterval
                      refreshInterval:(double)refreshInterval
                         windowLength:(double)windowLength NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Which presenter is drawing ("loop" or "display"), for the summary line
@property (atomic, copy) NSString *presenterName;

// Called on the decoder's queue for every decoded frame, before it is queued
- (void)noteArrivalAt:(CFTimeInterval)time;
// Called for every frame the network delivers, before decoding: when its first and last packets
// came, and the host's time for it in microseconds (DECODE_UNIT presentationTimeUs)
- (void)noteNetworkFrameReceivedAt:(CFTimeInterval)received assembledAt:(CFTimeInterval)assembled hostTimeUs:(uint64_t)hostTimeUs;
// Called by the frame queue for every drop
- (void)noteDrop:(PacingDropReason)reason queueDepth:(NSUInteger)depth;
// Called with the queue depth after each enqueue
- (void)noteQueueDepth:(NSUInteger)depth;
// Called from the drawable's presented handler. presentedTime 0 means the compositor skipped it.
// target is the time the frame was rendered for, and decodedAt the time its decoding ended; 0
// for either means not known.
- (void)notePresentedAt:(CFTimeInterval)presentedTime target:(CFTimeInterval)target decodedAt:(CFTimeInterval)decodedAt;
// The same, with the time the frame's last packet came (0 if not known)
- (void)notePresentedAt:(CFTimeInterval)presentedTime target:(CFTimeInterval)target decodedAt:(CFTimeInterval)decodedAt receivedAt:(CFTimeInterval)receivedAt;
- (void)notePresentedAt:(CFTimeInterval)presentedTime;
// The time from one display refresh to the next, from a display link
- (void)noteRefreshInterval:(double)interval;
// Display presenter: whether a refresh had a new frame to show
- (void)noteRefreshWithNewFrame:(BOOL)hadFrame;
// Display presenter with a jitter buffer: frames it holds back at this refresh
- (void)noteJitterTarget:(int)target;
// The jitter buffer's name, for the summary line ("off" when there is none)
@property (atomic, copy) NSString *jitterBufferName;
// Frame interpolation: one made-up frame (or a failure) and how long it took
- (void)noteInterpolatedFrame:(BOOL)made seconds:(double)seconds;
// What frame interpolation is doing this stream, for the summary ("off" by default)
@property (atomic, copy) NSString *interpolationNote;
// What picture in picture has done this stream, for the summary ("off" by default)
@property (atomic, copy) NSString *pictureInPictureNote;
// Render loop: how long nextDrawable took
- (void)noteDrawableWait:(double)seconds;

// The window being filled now, the last finished one, and everything since the stream started
- (PacingWindow)currentWindow;
- (PacingWindow)lastWindow;
- (PacingWindow)totalWindow;
// Ends the current window if it has run for windowLength by `time`, logs it, and returns YES
- (BOOL)rollWindowIfDueAt:(CFTimeInterval)time;

// One line for the log, a shorter one for the overlay, and the whole-stream summary
- (NSString *)logLineForWindow:(PacingWindow)window;
- (NSString *)overlayLineForWindow:(PacingWindow)window;
- (NSString *)summaryLineForWindow:(PacingWindow)window;

@end

NS_ASSUME_NONNULL_END
