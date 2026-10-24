//
//  PacingPolicy.m
//  Starwire
//

#import "PacingPolicy.h"

NSString *const PacingPresentTimingKey = @"StarwirePresentTiming";
NSString *const PacingDropPolicyKey = @"StarwireDropPolicy";
NSString *const PacingFramesToBufferKey = @"StarwireFramesToBuffer";
NSString *const StreamVirtualDisplayKey = @"StarwireVirtualDisplay";

@implementation PacingSettings

+ (instancetype)current {
    return [[PacingSettings alloc] initWithDefaults:[NSUserDefaults standardUserDefaults]];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        NSString *timing = [defaults stringForKey:PacingPresentTimingKey];
        _presentTiming = [timing isEqualToString:@"frame"] ? PresentTimingFrameInterval : PresentTimingNearestRefresh;

        NSString *policy = [defaults stringForKey:PacingDropPolicyKey];
        _dropPolicy = [policy isEqualToString:@"newest"] ? FrameDropPolicyNewest : FrameDropPolicyAlternate;

        NSInteger buffer = [defaults integerForKey:PacingFramesToBufferKey];
        _framesToBufferOverride = (buffer >= 1 && buffer <= 5) ? (int)buffer : 0;
    }
    return self;
}

- (int)framesToBufferWithAppSetting:(int)appSetting {
    if (_framesToBufferOverride > 0) {
        return _framesToBufferOverride;
    }
    return appSetting > 0 ? appSetting : 2;
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

BOOL StreamUsesVirtualDisplay(NSUserDefaults *defaults) {
    return [defaults boolForKey:StreamVirtualDisplayKey];
}
