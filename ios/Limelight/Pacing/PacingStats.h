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
    PacingDropReasonCount = 3,
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

    int drops[PacingDropReasonCount];
    // Drops where the frame that overflowed the queue came within half a frame interval of the
    // previous one
    int dropsAfterBurst;
    int maxQueueDepth;

    // Frames the screen showed, and how long the one before each stayed up (from the
    // drawables' presentedTime)
    int presented;
    PacingIntervals shown;
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

    // The time between display refreshes, as the display link reports them
    PacingIntervals refresh;
    // Display presenter: refreshes that had a new frame to show, and ones that didn't
    int refreshesWithFrame;
    int refreshesWithoutFrame;

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
// Called by the frame queue for every drop
- (void)noteDrop:(PacingDropReason)reason queueDepth:(NSUInteger)depth;
// Called with the queue depth after each enqueue
- (void)noteQueueDepth:(NSUInteger)depth;
// Called from the drawable's presented handler. presentedTime 0 means the compositor skipped it.
// target is the time the frame was rendered for, and decodedAt the time its decoding ended; 0
// for either means not known.
- (void)notePresentedAt:(CFTimeInterval)presentedTime target:(CFTimeInterval)target decodedAt:(CFTimeInterval)decodedAt;
- (void)notePresentedAt:(CFTimeInterval)presentedTime;
// The time from one display refresh to the next, from a display link
- (void)noteRefreshInterval:(double)interval;
// Display presenter: whether a refresh had a new frame to show
- (void)noteRefreshWithNewFrame:(BOOL)hadFrame;
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
