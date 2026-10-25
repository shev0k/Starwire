//
//  StreamPictureInPicture.h
//  Starwire
//
//  Picture in picture for a stream, as Android's "Enable Picture-in-Picture observer mode"
//  (checkbox_enable_pip, off by default): the stream can be watched, not controlled, while
//  another app is in front.
//
//  iOS only shows AVKit's player layers in picture in picture, not Metal. So an
//  AVSampleBufferDisplayLayer sits behind the Metal view and is fed the decoded frames: a couple
//  a second while the app is in front, enough for iOS to offer picture in picture when the app
//  leaves, and every frame while the window is up. The Metal renderer draws nothing then. The
//  idea and the delegate handling follow VoidLink's StreamFrameViewController (by The Fried Fish),
//  which uses the AVSB layer as its main renderer instead.
//

#import <AVKit/AVKit.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>
#import "FrameQueue.h"

NS_ASSUME_NONNULL_BEGIN

// The user default and launch argument
extern NSString *const StreamPictureInPictureKey;
// Launch argument only: show the sample buffer layer full screen instead of the Metal view, so
// the device runs can compare the two renderers' colours
extern NSString *const StreamShowSampleBufferLayerKey;
BOOL StreamUsesPictureInPicture(NSUserDefaults *defaults);

// Whether to pass a decoded frame to the layer: every frame while picture in picture is up,
// otherwise one every `idleInterval` seconds
BOOL PictureInPictureShouldEnqueue(BOOL active, CFTimeInterval now, CFTimeInterval lastEnqueue, CFTimeInterval idleInterval);

// Whether the stream must end when the app goes to the background: yes, unless picture in
// picture is showing it or about to
BOOL StreamEndsOnBackground(BOOL pictureInPictureActive);

@interface StreamPictureInPicture : NSObject <DecodedFrameObserver>

// Adds the layer behind everything else in `view`. Returns nil where iOS has no picture in
// picture (it isn't supported on every device).
- (nullable instancetype)initWithView:(UIView *)view;
// The same, for the system presenter: the layer shows the stream full screen, with picture in
// picture only when `pictureInPicture` (and the device has it). Never nil.
- (instancetype)initWithView:(UIView *)view pictureInPicture:(BOOL)pictureInPicture;

// Shows a frame at once (the system presenter, one per refresh)
- (void)showPixelBuffer:(CVPixelBufferRef)pixelBuffer at:(CFTimeInterval)now;
- (instancetype)init NS_UNAVAILABLE;

// Feed every frame, not two a second: for showing the layer full screen in a colour comparison
@property (atomic) BOOL feedsEveryFrame;
// Showing or about to show (from willStart to didStop)
@property (atomic, readonly) BOOL active;
// Times it started this stream
@property (atomic, readonly) int startCount;
// "ready", "showing" or "closed", with the start count, for the statistics summary
- (NSString *)note;
// Called on the main thread when the window closes. restored is YES when the user went back to
// the app from it, NO when they closed it.
@property (nonatomic, copy, nullable) void (^onStop)(BOOL restored);

// From the decoder's queue, for every decoded frame
- (void)noteDecodedPixelBuffer:(CVPixelBufferRef)pixelBuffer at:(CFTimeInterval)now;
// Closes the window if it's showing, as a return to the app (the stream goes on)
- (void)stop;
// Keeps the layer the size of the view
- (void)layout;
// Zooms and pans the picture (pinch to zoom, pan and zoom mode)
- (void)setVideoTransform:(CGAffineTransform)transform;
// Fit, stretch or fill (AVLayerVideoGravity)
- (void)setVideoGravity:(AVLayerVideoGravity)gravity;
// Removes the layer and the controller. Call before the stream view goes away.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
