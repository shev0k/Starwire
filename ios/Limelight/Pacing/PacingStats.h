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
//  statistics overlay.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PacingDropReason) {
    // The queue was full and the incoming frame was dropped
    PacingDropIncoming = 0,
    // The queue was full and its oldest frame was dropped to make room
    PacingDropOldest = 1,
    PacingDropReasonCount = 2,
};

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

    // Frames the compositor showed, by how many display refreshes the previous one stayed up
    int presented;
    int heldOneRefresh;
    int heldTwoRefreshes;
    int heldThreeOrMore;
    // Drawables the compositor never showed (presentedTime 0)
    int presentSkipped;
} PacingWindow;

@interface PacingStats : NSObject

// frameInterval is 1/stream FPS, refreshInterval is 1/display Hz, in seconds
- (instancetype)initWithFrameInterval:(double)frameInterval
                      refreshInterval:(double)refreshInterval
                         windowLength:(double)windowLength NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Called on the decoder's queue for every decoded frame, before it is queued
- (void)noteArrivalAt:(CFTimeInterval)time;
// Called by the frame queue for every drop
- (void)noteDrop:(PacingDropReason)reason queueDepth:(NSUInteger)depth;
// Called with the queue depth after each enqueue
- (void)noteQueueDepth:(NSUInteger)depth;
// Called from the drawable's presented handler. presentedTime 0 means the compositor skipped it.
- (void)notePresentedAt:(CFTimeInterval)presentedTime;

// The window being filled now, and the last finished one
- (PacingWindow)currentWindow;
- (PacingWindow)lastWindow;
// Ends the current window if it has run for windowLength by `time`, logs it, and returns YES
- (BOOL)rollWindowIfDueAt:(CFTimeInterval)time;

// One line for the log, and a shorter one for the overlay
+ (NSString *)logLineForWindow:(PacingWindow)window;
+ (NSString *)overlayLineForWindow:(PacingWindow)window;

@end

NS_ASSUME_NONNULL_END
