//
//  JitterBuffer.h
//  Starwire
//
//  Starwire's jitter buffer for the display presenter, with the same four choices as Starwire for
//  Android's "Jitter buffer" setting (jitter_buffer). It decides, at each display refresh, which
//  queued frame to show. Frames come out in order, one per refresh, so a short hole in arrivals
//  is covered by frames held back. How many frames it holds (the target) follows the holes it has
//  seen:
//  - a frame that arrives n frame intervals after the one before needs n - 1 frames held to cover
//    the hole without a repeat;
//  - the target is the largest need seen in the last few seconds, capped by the mode;
//  - it grows at once and shrinks when the holes stop.
//
//  With nothing queued at a refresh the last frame stays up (a repeat). Above the target for a
//  while, it drops one frame at a time to catch up; far above it (after a long hole and the clump
//  that follows), it drops down to two frames above the target at once, so latency stays bounded.
//
//  Android paces from the host's timestamps with a percentile of transit times
//  (app/src/main/jni/vulkan/frame_pacer.cpp). Vibeshine doesn't send the clock sync that needs, so
//  this one counts frames instead. Times are passed in, never read here, so tests can make up
//  timelines. Not thread safe: FrameQueue calls it under its lock.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JitterBufferMode) {
    // Always the newest frame, never held: the display presenter's first behaviour
    JitterBufferModeLowestLatency = 0,
    // Holds at most 1 frame
    JitterBufferModeLowLatency = 1,
    // Holds up to 2 frames
    JitterBufferModeBalanced = 2,
    // Holds up to 4 frames
    JitterBufferModeSmooth = 3,
};

// The user default and launch argument, with Android's values: "lowest-latency", "low-latency",
// "balanced" or "smooth"
extern NSString *const JitterBufferKey;

// The mode for a stored value. Unknown or missing values give JitterBufferDefaultMode.
JitterBufferMode JitterBufferModeFromString(NSString *_Nullable value);
NSString *JitterBufferModeName(JitterBufferMode mode);
// The most frames a mode will hold back
int JitterBufferMaxTarget(JitterBufferMode mode);
// The mode used when nothing is set
extern const JitterBufferMode JitterBufferDefaultMode;

typedef struct {
    // Oldest frames to drop before taking the next one
    int drop;
    // Whether a frame is shown at this refresh. NO means the last frame stays up.
    BOOL show;
} JitterBufferChoice;

@interface JitterBuffer : NSObject

- (instancetype)initWithMode:(JitterBufferMode)mode frameInterval:(double)frameInterval NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) JitterBufferMode mode;
// Frames held back after the one shown, as of the last choice
@property (nonatomic, readonly) int target;
// Refreshes with nothing to show, once frames had started
@property (nonatomic, readonly) int underflows;
// Frames dropped one at a time to catch up, and frames dropped at once after a long hole
@property (nonatomic, readonly) int catchUpDrops;
@property (nonatomic, readonly) int trimDrops;

// A frame entered the queue at `time`
- (void)noteArrivalAt:(CFTimeInterval)time;
// A display refresh at `now` with `queued` frames waiting
- (JitterBufferChoice)chooseWithQueued:(int)queued at:(CFTimeInterval)now;

@end

NS_ASSUME_NONNULL_END
