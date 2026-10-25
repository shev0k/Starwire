//
//  VideoFormatPolicy.m
//  Starwire
//

#import "VideoFormatPolicy.h"
#include <Limelight.h>

NSString *const StreamFullRangeKey = @"StarwireFullRange";
NSString *const StreamColorSpaceKey = @"StarwireColorSpace";

BOOL StreamUsesFullRange(NSUserDefaults *defaults) {
    return [defaults boolForKey:StreamFullRangeKey];
}

int StreamColorSpaceFromDefaults(NSUserDefaults *defaults) {
    return [[defaults stringForKey:StreamColorSpaceKey] isEqualToString:@"709"] ? COLORSPACE_REC_709 : COLORSPACE_REC_601;
}

OSType StreamDecoderPixelFormat(int videoFormat, BOOL fullRange) {
    if (videoFormat & VIDEO_FORMAT_MASK_YUV444) {
        if (videoFormat & VIDEO_FORMAT_MASK_10BIT) {
            return fullRange ? kCVPixelFormatType_444YpCbCr10BiPlanarFullRange : kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange;
        }
        return fullRange ? kCVPixelFormatType_444YpCbCr8BiPlanarFullRange : kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange;
    }
    return fullRange ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;
}

BOOL StreamPixelFormatIsFullRange(OSType pixelFormat, BOOL *known) {
    BOOL isKnown = YES;
    BOOL full = NO;
    switch (pixelFormat) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
        case kCVPixelFormatType_444YpCbCr8BiPlanarFullRange:
        case kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:
            full = YES;
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
        case kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange:
        case kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange:
            full = NO;
            break;
        default:
            isKnown = NO;
            break;
    }
    if (known) {
        *known = isKnown;
    }
    return full;
}
