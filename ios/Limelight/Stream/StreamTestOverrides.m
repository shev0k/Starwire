//
//  StreamTestOverrides.m
//  Starwire
//

#import "StreamTestOverrides.h"
#import "PacingPolicy.h"

NSString *const StreamCodecKey = @"StarwireCodec";
NSString *const StreamResolutionKey = @"StarwireResolution";
NSString *const StreamHDRKey = @"StarwireHDR";
NSString *const StreamYUV444Key = @"StarwireYUV444";

NSString *StreamApplyTestOverrides(TemporarySettings *settings, NSUserDefaults *defaults) {
    NSMutableArray<NSString *> *changed = [NSMutableArray array];

    int rate = StreamFrameRateWithOverride(defaults, [settings.framerate intValue]);
    if (rate != [settings.framerate intValue]) {
        settings.framerate = @(rate);
        [changed addObject:[NSString stringWithFormat:@"%d FPS", rate]];
    }

    NSString *resolution = [defaults stringForKey:StreamResolutionKey];
    NSArray<NSString *> *parts = [resolution componentsSeparatedByString:@"x"];
    if (parts.count == 2 && parts[0].intValue > 0 && parts[1].intValue > 0) {
        settings.width = @(parts[0].intValue);
        settings.height = @(parts[1].intValue);
        [changed addObject:[NSString stringWithFormat:@"%dx%d", parts[0].intValue, parts[1].intValue]];
    }

    NSString *codec = [defaults stringForKey:StreamCodecKey];
    NSDictionary<NSString *, NSNumber *> *codecs = @{@"auto": @(CODEC_PREF_AUTO), @"h264": @(CODEC_PREF_H264),
                                                     @"hevc": @(CODEC_PREF_HEVC), @"av1": @(CODEC_PREF_AV1)};
    if (codec && codecs[codec]) {
        settings.preferredCodec = codecs[codec].intValue;
        [changed addObject:codec];
    }

    if ([defaults objectForKey:StreamHDRKey] != nil) {
        settings.enableHdr = [defaults boolForKey:StreamHDRKey];
        [changed addObject:settings.enableHdr ? @"HDR on" : @"HDR off"];
    }
    if ([defaults objectForKey:StreamYUV444Key] != nil) {
        settings.enableYUV444 = [defaults boolForKey:StreamYUV444Key];
        [changed addObject:settings.enableYUV444 ? @"4:4:4 on" : @"4:4:4 off"];
    }

    BOOL pcAudio = StreamPlayAudioOnPCWithOverride(defaults, settings.playAudioOnPC);
    if (pcAudio != settings.playAudioOnPC) {
        settings.playAudioOnPC = pcAudio;
        [changed addObject:pcAudio ? @"audio on the PC" : @"audio on this device"];
    }

    return [changed componentsJoinedByString:@", "];
}
