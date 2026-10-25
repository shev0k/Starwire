//
//  FrameInterpolator.h
//  Starwire
//
//  Frame interpolation on iOS 26 and later: VideoToolbox's low latency frame interpolation makes a
//  frame halfway between each pair of decoded frames, so a 60 FPS stream shows at 120 Hz. Each
//  real frame waits for its in-between frame, so this adds about half a stream frame of latency
//  plus the processing time. It follows VoidLink's FrameInterpolator.swift (by The Fried Fish),
//  without its downscaling: a stream larger than the system allows isn't interpolated.
//

#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The user default and launch argument
extern NSString *const FrameInterpolationKey;

// Whether interpolation runs for a stream: asked for, available on this device and at this size,
// and the display can show twice the stream's frame rate
BOOL FrameInterpolationApplies(BOOL wanted, BOOL availableAtSize, double streamFps, double displayHz);

@interface FrameInterpolator : NSObject

// iOS 26 or later on a device (not the simulator) whose VideoToolbox has the effect
+ (BOOL)isAvailable;
// Whether a stream of this size can be interpolated, as far as the system says
+ (BOOL)supportsWidth:(int)width height:(int)height;
// The size limits the system reports, for the log and the summary
+ (NSString *)limitsDescription;
// Whether `defaults` asks for interpolation and it can run for this stream
+ (BOOL)appliesWithDefaults:(NSUserDefaults *)defaults width:(int)width height:(int)height fps:(double)fps displayHz:(double)displayHz;

// nil when it can't run at this size
- (nullable instancetype)initWithWidth:(int)width height:(int)height;
- (instancetype)init NS_UNAVAILABLE;

// The pixel format to ask the decoder for, closest to `preferred` among those the effect takes
- (OSType)pixelFormatClosestTo:(OSType)preferred;
// Attributes the decoder's output buffers need to be usable here
- (NSDictionary *)sourcePixelBufferAttributes;

// A new frame halfway between two decoded frames, or NULL if processing failed. The caller
// releases it. Synchronous: call it from the decoder's output queue.
- (nullable CVPixelBufferRef)copyFrameBetween:(CVPixelBufferRef)previous
                                       atTime:(CMTime)previousTime
                                          and:(CVPixelBufferRef)current
                                       atTime:(CMTime)currentTime CF_RETURNS_RETAINED;

// Frames made, failures, and the mean processing time
@property (atomic, readonly) int made;
@property (atomic, readonly) int failed;
@property (atomic, readonly) double meanProcessMs;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
