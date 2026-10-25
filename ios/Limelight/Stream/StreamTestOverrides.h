//
//  StreamTestOverrides.h
//  Starwire
//
//  Launch arguments that replace some of the app's saved settings for one launch, so the device
//  runs can try a codec, a size or HDR without changing what the owner set. They are only ever
//  launch arguments (the argument domain of NSUserDefaults), never saved:
//
//    -StarwireFrameRate 60          -StarwireCodec av1|hevc|h264|auto
//    -StarwireResolution 1920x1080  -StarwireHDR YES|NO     -StarwireYUV444 YES|NO
//    -StarwirePlayAudioOnPC YES|NO
//
//  Unset arguments leave the settings alone.
//

#import <Foundation/Foundation.h>
#import "TemporarySettings.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const StreamCodecKey;
extern NSString *const StreamResolutionKey;
extern NSString *const StreamHDRKey;
extern NSString *const StreamYUV444Key;

// Applies every override that is set. Returns a short description of what changed, empty if
// nothing did, for the log.
NSString *StreamApplyTestOverrides(TemporarySettings *settings, NSUserDefaults *defaults);

NS_ASSUME_NONNULL_END
