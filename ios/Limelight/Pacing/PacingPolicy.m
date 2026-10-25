//
//  PacingPolicy.m
//  Starwire
//

#import "PacingPolicy.h"

NSString *const PacingPresenterKey = @"StarwirePresenter";
NSString *const PacingPresentTimingKey =@"StarwirePresentTiming";
NSString *const PacingDropPolicyKey = @"StarwireDropPolicy";
NSString *const PacingFramesToBufferKey = @"StarwireFramesToBuffer";
NSString *const StreamVirtualDisplayKey = @"StarwireVirtualDisplay";
NSString *const PacingReduceRefreshRateKey = @"StarwireReduceRefreshRate";
NSString *const StatsOverlayLevelKey = @"StarwireOverlay";
NSString *const StreamFrameRateKey = @"StarwireFrameRate";
NSString *const StreamPlayAudioOnPCKey = @"StarwirePlayAudioOnPC";

@implementation PacingSettings

+ (instancetype)current {
    return [[PacingSettings alloc] initWithDefaults:[NSUserDefaults standardUserDefaults]];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        NSString *presenter = [defaults stringForKey:PacingPresenterKey];
        _presenter = [presenter isEqualToString:@"display"] ? PacingPresenterDisplay : PacingPresenterLoop;

        NSString *timing = [defaults stringForKey:PacingPresentTimingKey];
        _presentTiming = [timing isEqualToString:@"frame"] ? PresentTimingFrameInterval : PresentTimingNearestRefresh;

        NSString *policy = [defaults stringForKey:PacingDropPolicyKey];
        _dropPolicy = [policy isEqualToString:@"newest"] ? FrameDropPolicyNewest : FrameDropPolicyAlternate;

        NSInteger buffer = [defaults integerForKey:PacingFramesToBufferKey];
        _framesToBufferOverride = (buffer >= 1 && buffer <= 5) ? (int)buffer : 0;

        _jitterBuffer = JitterBufferModeFromString([defaults stringForKey:JitterBufferKey]);
        _reduceRefreshRate = [defaults boolForKey:PacingReduceRefreshRateKey];
        _overlayLevel = [[defaults stringForKey:StatsOverlayLevelKey] isEqualToString:@"lite"]
            ? StatsOverlayLevelLite : StatsOverlayLevelFull;
    }
    return self;
}

- (int)framesToBufferWithAppSetting:(int)appSetting {
    if (_framesToBufferOverride > 0) {
        return _framesToBufferOverride;
    }
    return appSetting > 0 ? appSetting : 2;
}

- (JitterBuffer *)makeJitterBufferForFrameInterval:(double)frameInterval {
    if (_presenter != PacingPresenterDisplay || _jitterBuffer == JitterBufferModeLowestLatency) {
        return nil;
    }
    return [[JitterBuffer alloc] initWithMode:_jitterBuffer frameInterval:frameInterval];
}

- (int)queueLimitWithFramesToBuffer:(int)framesToBuffer {
    if (_presenter != PacingPresenterDisplay) {
        return framesToBuffer;
    }
    // The target, the frame being shown, two frames above the target and one arriving
    return MAX(framesToBuffer, JitterBufferMaxTarget(_jitterBuffer) + 4);
}

- (NSString *)jitterBufferName {
    return _presenter == PacingPresenterDisplay ? JitterBufferModeName(_jitterBuffer) : @"off";
}

- (FrameDropPolicy)effectiveDropPolicy {
    return _presenter == PacingPresenterDisplay ? FrameDropPolicyNewest : _dropPolicy;
}

- (NSString *)presenterName {
    return _presenter == PacingPresenterDisplay ? @"display" : @"loop";
}

- (NSString *)presentTimingName {
    return _presentTiming == PresentTimingFrameInterval ? @"frame" : @"nearest";
}

- (NSString *)dropPolicyName {
    return _dropPolicy == FrameDropPolicyNewest ? @"newest" : @"alternate";
}

@end

CFTimeInterval PacingMinimumPresentDuration(PresentTiming timing, double streamFps, double displayHz) {
    if (!(streamFps > 0) || !(displayHz > 0)) {
        return 0;
    }

    double frameInterval = 1.0 / streamFps;
    if (timing == PresentTimingFrameInterval) {
        return frameInterval;
    }

    // Half a refresh less than the frame interval. The compositor only swaps on a refresh, so
    // this still gives each frame as many refreshes as its interval rounds to (one at 120 on
    // 120 Hz, two at 60 on 120 Hz), but a frame that is a few microseconds early for its
    // refresh is no longer pushed to the one after.
    double refreshInterval = 1.0 / displayHz;
    double duration = frameInterval - refreshInterval / 2.0;
    return duration > 0 ? duration : 0;
}

CFTimeInterval PacingDisplayFrameWait(CFTimeInterval now, CFTimeInterval targetTimestamp) {
    CFTimeInterval left = targetTimestamp - now;
    return left > 0 ? left / 2.0 : 0;
}

PacingRefreshRange PacingDisplayRefreshRange(double streamFps, double displayHz, BOOL reduceRefreshRate) {
    float fps = streamFps > 0 ? (float)streamFps : 60;
    float display = displayHz > 0 ? (float)displayHz : 60;
    fps = MIN(fps, display);
    if (reduceRefreshRate || fps >= display) {
        return (PacingRefreshRange){fps, fps, fps};
    }
    return (PacingRefreshRange){fps, display, display};
}

int StreamFrameRateWithOverride(NSUserDefaults *defaults, int appSetting) {
    NSInteger rate = [defaults integerForKey:StreamFrameRateKey];
    return rate > 0 ? (int)rate : appSetting;
}

BOOL StreamPlayAudioOnPCWithOverride(NSUserDefaults *defaults, BOOL appSetting) {
    if ([defaults objectForKey:StreamPlayAudioOnPCKey] == nil) {
        return appSetting;
    }
    return [defaults boolForKey:StreamPlayAudioOnPCKey];
}

BOOL StreamUsesVirtualDisplay(NSUserDefaults *defaults) {
    return [defaults boolForKey:StreamVirtualDisplayKey];
}
