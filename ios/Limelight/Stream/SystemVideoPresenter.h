//
//  SystemVideoPresenter.h
//  Starwire
//
//  The "system" presenter: the stream is shown through the system's video layer
//  (AVSampleBufferDisplayLayer), as official moonlight-ios shows it and as picture in picture
//  always does. iPadOS converts the colours and maps HDR itself, so full screen and picture in
//  picture look the same.
//
//  A CADisplayLink on its own thread runs at the display refresh range (PacingDisplayRefreshRange).
//  At each refresh it takes a frame from the frame queue through the jitter buffer, as the display
//  presenter does, and hands it to the layer to show at once. Frames keep the refreshes their
//  interval covers (PacingRefreshesPerFrame).
//

#import <Foundation/Foundation.h>
#import "PacingPolicy.h"

@class StreamPictureInPicture;

NS_ASSUME_NONNULL_BEGIN

@interface SystemVideoPresenter : NSObject

- (instancetype)initWithLayer:(StreamPictureInPicture *)layer range:(PacingRefreshRange)range framerate:(double)framerate;
- (instancetype)init NS_UNAVAILABLE;

// Called once on the main thread when the first frame is shown
@property (nonatomic, copy, nullable) void (^onFirstFrame)(void);

- (void)start;
// Pauses at refreshes (the app is inactive; picture in picture is fed from the decoder then)
@property (atomic) BOOL paused;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
