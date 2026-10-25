//
//  PacingPolicy.h
//  Starwire
//
//  The pacing choices the phase 1a A/B runs switch between, and the rule for how long the Metal
//  renderer holds each frame on screen. Phase 4 replaces this with full pacing modes.
//
//  The choices are user defaults, so they can be set from iOS Settings (Settings.bundle) or as
//  launch arguments, for example `-StarwirePresentTiming frame`. The app's own settings screen
//  doesn't show them yet.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// When the frame queue is full and another frame arrives
typedef NS_ENUM(NSInteger, FrameDropPolicy) {
    // Andy Grundman's original: drop the incoming frame, then on the next overflow drop the
    // oldest queued frame instead, and alternate
    FrameDropPolicyAlternate = 0,
    // Always drop the oldest queued frame, so the newest frame is the one that gets shown
    FrameDropPolicyNewest = 1,
};

// How long each frame must stay on screen before the next one may replace it
typedef NS_ENUM(NSInteger, PresentTiming) {
    // Round the stream's frame interval to the nearest display refresh: a 120 FPS stream on a
    // 120 Hz display holds each frame for one refresh, never two
    PresentTimingNearestRefresh = 0,
    // The original: at least one full stream frame interval (1/fps). On a 120 Hz display at
    // 120 FPS this sits exactly on a refresh boundary, so a frame can miss a refresh and be held
    // for two
    PresentTimingFrameInterval = 1,
};

// What decides when a frame is drawn
typedef NS_ENUM(NSInteger, PacingPresenter) {
    // Andy Grundman's render loop: a thread that waits for a drawable and a frame, draws the
    // oldest queued frame and presents it with a minimum duration (PresentTiming)
    PacingPresenterLoop = 0,
    // The display drives it: a CAMetalDisplayLink asks for a frame at every refresh, and the
    // newest decoded frame is drawn into the drawable it hands over and presented as it is
    PacingPresenterDisplay = 1,
};

extern NSString *const PacingPresenterKey;         // "loop" or "display"
extern NSString *const PacingPresentTimingKey;     // "nearest" or "frame"
extern NSString *const PacingDropPolicyKey;        // "alternate" or "newest"
extern NSString *const PacingFramesToBufferKey;    // 0 = the app's "Frames to buffer" setting, else 1 to 5
extern NSString *const StreamVirtualDisplayKey;    // YES = ask Vibeshine for a virtual display

@interface PacingSettings : NSObject

@property (nonatomic, readonly) PacingPresenter presenter;
@property (nonatomic, readonly) PresentTiming presentTiming;
@property (nonatomic, readonly) FrameDropPolicy dropPolicy;
// 0 when there is no override
@property (nonatomic, readonly) int framesToBufferOverride;

// Reads the user defaults once. Call when a stream starts.
+ (instancetype)current;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

// The frames to buffer to use, given the app's own setting
- (int)framesToBufferWithAppSetting:(int)appSetting;

// The drop policy the frame queue should use. The display presenter always keeps the newest
// frame: it shows whatever is newest at each refresh, so an old frame is never worth keeping.
- (FrameDropPolicy)effectiveDropPolicy;

- (NSString *)presenterName;
- (NSString *)presentTimingName;
- (NSString *)dropPolicyName;

@end

// The minimum time a frame stays on screen, for presentDrawable:afterMinimumDuration:.
// streamFps and displayHz must be positive; anything else returns 0 (present on the next refresh).
CFTimeInterval PacingMinimumPresentDuration(PresentTiming timing, double streamFps, double displayHz);

// Display presenter: how long to wait for a frame when a refresh comes and none is waiting.
// Half the time left until the drawable must be committed (targetTimestamp), as in Nonary's
// moonlight-qt vt_metal.mm, so a frame that is a little late still makes this refresh and the
// other half is left to draw it. 0 when that time has passed.
CFTimeInterval PacingDisplayFrameWait(CFTimeInterval now, CFTimeInterval targetTimestamp);

// Whether to ask the host for a virtual display (Vibeshine's virtualDisplay=1 launch parameter)
BOOL StreamUsesVirtualDisplay(NSUserDefaults *defaults);

NS_ASSUME_NONNULL_END
