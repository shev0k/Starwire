#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#import "Frame.h"
#import "FloatBuffer.h"
#import "PacingPolicy.h"
#import "PacingStats.h"

NS_ASSUME_NONNULL_BEGIN

@interface FrameQueue : NSObject

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic) FloatBuffer *frameDropMetrics;
@property (nonatomic) int highWaterMark;
@property (nonatomic, readonly) int maxCapacity;
@property (atomic) BOOL paused;
// What to drop when the queue is full. Set before a stream starts.
@property (atomic) FrameDropPolicy dropPolicy;
// Receives every drop with its reason. Optional.
@property (atomic, nullable) PacingStats *pacingStats;

// The queue shared by the decoder and the Metal renderer
+ (instancetype)sharedInstance;

// A separate queue, for tests
- (instancetype)initWithMaxCapacity:(int)maxCapacity NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (BOOL)isEmpty;
// Empties the queue and releases its frames
- (void)clear;
- (int)enqueue:(Frame *)frame;
- (int)enqueue:(Frame *)frame withSlackSize:(int)slack;
- (nullable Frame *)dequeue;
// Waits up to `timeout` seconds for a frame. Returns nil at once when paused.
- (nullable Frame *)dequeueWithTimeout:(CFTimeInterval)timeout;
// Frames per second arriving, from the frames' decodedAt times
- (CFTimeInterval)estimatedFramerate;
- (int)currentSoftCap;
- (void)waitForEnqueue;
- (void)start;
- (void)stop;
// Start and stop for one session. A stop from an owner that is no longer current is ignored, so
// a late cleanup from the last stream can't pause the next one (from VoidLink).
- (void)startForOwner:(nullable id)owner;
- (void)stopForOwner:(nullable id)owner;

@end

NS_ASSUME_NONNULL_END
