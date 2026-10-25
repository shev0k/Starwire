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
#import "JitterBuffer.h"

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
    // oldest queued frame and presents it with a minimum duration (PresentTiming). A test choice
    // ("loop") since batch 1.
    PacingPresenterLoop = 0,
    // The default: the display drives it. A CAMetalDisplayLink asks for a frame at every
    // refresh, the jitter buffer picks one, and it is drawn into the drawable the link hands over
    PacingPresenterDisplay = 1,
};

extern NSString *const PacingPresenterKey;         // "loop" or "display"
extern NSString *const PacingPresentTimingKey;     // "nearest" or "frame"
extern NSString *const PacingDropPolicyKey;        // "alternate" or "newest"
extern NSString *const PacingFramesToBufferKey;    // 0 = the app's "Frames to buffer" setting, else 1 to 5
extern NSString *const StreamVirtualDisplayKey;    // YES = ask Vibeshine for a virtual display
extern NSString *const PacingReduceRefreshRateKey; // YES = let the display drop to the stream's rate
extern NSString *const StatsOverlayLevelKey;       // "full" or "lite"
extern NSString *const StreamFrameRateKey;         // a frame rate that replaces the app's setting, for tests
extern NSString *const StreamPlayAudioOnPCKey;     // YES or NO replaces the app's "Play audio on PC", for tests

typedef NS_ENUM(NSInteger, StatsOverlayLevel) {
    // Every line: video, network, pacing and the whole-stream summary
    StatsOverlayLevelFull = 0,
    // One line: frame rate, 1% low, drops, latency and the display's rate
    StatsOverlayLevelLite = 1,
};

// The display link's frame rate range, in frames per second
typedef struct {
    float minimum;
    float maximum;
    float preferred;
} PacingRefreshRange;

@interface PacingSettings : NSObject

@property (nonatomic, readonly) PacingPresenter presenter;
@property (nonatomic, readonly) PresentTiming presentTiming;
@property (nonatomic, readonly) FrameDropPolicy dropPolicy;
// 0 when there is no override
@property (nonatomic, readonly) int framesToBufferOverride;
// Android's "Allow refresh rate reduction", off by default: the display stays at its top rate,
// so a new frame can show at the next of its refreshes
@property (nonatomic, readonly) BOOL reduceRefreshRate;
@property (nonatomic, readonly) StatsOverlayLevel overlayLevel;
// Display presenter only (JitterBufferKey)
@property (nonatomic, readonly) JitterBufferMode jitterBuffer;

// Reads the user defaults once. Call when a stream starts.
+ (instancetype)current;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

// The frames to buffer to use, given the app's own setting
- (int)framesToBufferWithAppSetting:(int)appSetting;

// The display presenter's jitter buffer for a stream at frameInterval seconds a frame, or nil to
// show the newest frame at every refresh (lowest latency, or the render loop)
- (nullable JitterBuffer *)makeJitterBufferForFrameInterval:(double)frameInterval;
// The same with frame interpolation running. Its made-up frame arrives together with the real
// one, so lowest latency (always the newest) would skip every made-up frame; low latency shows
// both in order instead.
- (nullable JitterBuffer *)makeJitterBufferForFrameInterval:(double)frameInterval interpolating:(BOOL)interpolating;
- (JitterBufferMode)jitterBufferModeInterpolating:(BOOL)interpolating;
// The frames the queue may hold: enough for the jitter buffer's target plus the frames it lets
// pile up before catching up. The render loop uses frames to buffer.
- (int)queueLimitWithFramesToBuffer:(int)framesToBuffer;
- (NSString *)jitterBufferName;

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

// The display link's range. With reduction allowed (or a stream as fast as the display) it asks
// for the stream's rate; otherwise for the display's top rate, never below the stream's.
// Anything not positive falls back to 60.
PacingRefreshRange PacingDisplayRefreshRange(double streamFps, double displayHz, BOOL reduceRefreshRate);

// The app's frame rate setting, or StreamFrameRateKey when that is set above 0. Launch argument
// only (`-StarwireFrameRate 60`), so a device run can try a rate without touching the settings.
int StreamFrameRateWithOverride(NSUserDefaults *defaults, int appSetting);
// The app's "Play audio on PC", or StreamPlayAudioOnPCKey when it is set. Launch argument only:
// the device runs keep the PC's sound on the PC, so someone using the PC hears it.
BOOL StreamPlayAudioOnPCWithOverride(NSUserDefaults *defaults, BOOL appSetting);

// Display presenter: refreshes each frame should stay up for, when the display link runs
// faster than the stream (2 for 60 FPS on 120 Hz). At least 1.
int PacingRefreshesPerFrame(double linkHz, double presentFps);
// Whether to take a new frame at this refresh: only once the one on screen has had its
// refreshes. A frame that comes a little after its refresh then waits one refresh, and the
// cadence stays even instead of alternating 8.3 and 25 ms.
BOOL PacingDisplayShouldTakeFrame(int refreshesSinceShown, int refreshesPerFrame);

// Whether to ask the host for a virtual display (Vibeshine's virtualDisplay=1 launch parameter)
BOOL StreamUsesVirtualDisplay(NSUserDefaults *defaults);

NS_ASSUME_NONNULL_END
