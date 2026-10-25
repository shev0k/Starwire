//
//  FrameInterpolator.m
//  Starwire
//

#import "FrameInterpolator.h"
#import "Logger.h"
#import <QuartzCore/QuartzCore.h>
#import <VideoToolbox/VideoToolbox.h>

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_VIDEO

NSString *const FrameInterpolationKey = @"StarwireFrameInterpolation";

BOOL FrameInterpolationApplies(BOOL wanted, BOOL availableAtSize, double streamFps, double displayHz) {
    return wanted && availableAtSize && streamFps > 0 && displayHz >= 2 * streamFps - 1;
}

@implementation FrameInterpolator {
#if !TARGET_OS_SIMULATOR
    id _configuration;   // VTLowLatencyFrameInterpolationConfiguration
    id _processor;       // VTFrameProcessor
    CVPixelBufferPoolRef _pool;
#endif
    double _processSeconds;
}

+ (BOOL)isAvailable {
#if TARGET_OS_SIMULATOR
    return NO;
#else
    if (@available(iOS 26.0, tvOS 26.0, *)) {
        return VTLowLatencyFrameInterpolationConfiguration.isSupported;
    }
    return NO;
#endif
}

+ (BOOL)supportsWidth:(int)width height:(int)height {
#if TARGET_OS_SIMULATOR
    return NO;
#else
    if (![self isAvailable] || width <= 0 || height <= 0) {
        return NO;
    }
    if (@available(iOS 27.0, tvOS 27.0, *)) {
        NSInteger maxDimension = [VTLowLatencyFrameInterpolationConfiguration maximumDimensionForSpatialScaleFactor:1];
        NSInteger maxPixels = [VTLowLatencyFrameInterpolationConfiguration maximumPixelCountForSpatialScaleFactor:1];
        LogOnce(LOG_I, @"Frame interpolation limits: %ld pixels on a side, %ld pixels", (long)maxDimension, (long)maxPixels);
        if ((maxDimension > 0 && (width > maxDimension || height > maxDimension)) ||
            (maxPixels > 0 && (NSInteger)width * height > maxPixels)) {
            return NO;
        }
    }
    if (@available(iOS 26.0, tvOS 26.0, *)) {
        // The configuration itself refuses sizes it can't do
        return [[VTLowLatencyFrameInterpolationConfiguration alloc] initWithFrameWidth:width frameHeight:height numberOfInterpolatedFrames:1] != nil;
    }
    return NO;
#endif
}

+ (NSString *)limitsDescription {
#if !TARGET_OS_SIMULATOR
    if (@available(iOS 27.0, tvOS 27.0, *)) {
        if ([self isAvailable]) {
            return [NSString stringWithFormat:@"up to %ld on a side and %ld pixels",
                    (long)[VTLowLatencyFrameInterpolationConfiguration maximumDimensionForSpatialScaleFactor:1],
                    (long)[VTLowLatencyFrameInterpolationConfiguration maximumPixelCountForSpatialScaleFactor:1]];
        }
    }
#endif
    return [self isAvailable] ? @"limits not reported" : @"not available";
}

+ (BOOL)appliesWithDefaults:(NSUserDefaults *)defaults width:(int)width height:(int)height fps:(double)fps displayHz:(double)displayHz {
    BOOL wanted = [defaults boolForKey:FrameInterpolationKey];
    if (!wanted) {
        return NO;
    }
    BOOL applies = FrameInterpolationApplies(YES, [self supportsWidth:width height:height], fps, displayHz);
    LogOnce(LOG_I, @"Frame interpolation asked for at %dx%d %.0f FPS on %.0f Hz: %@", width, height, fps, displayHz,
            applies ? @"on" : @"not possible here");
    return applies;
}

- (instancetype)initWithWidth:(int)width height:(int)height {
#if TARGET_OS_SIMULATOR
    return nil;
#else
    if (![FrameInterpolator supportsWidth:width height:height]) {
        return nil;
    }
    self = [super init];
    if (!self) {
        return nil;
    }
    if (@available(iOS 26.0, tvOS 26.0, *)) {
        VTLowLatencyFrameInterpolationConfiguration *configuration =
            [[VTLowLatencyFrameInterpolationConfiguration alloc] initWithFrameWidth:width frameHeight:height numberOfInterpolatedFrames:1];
        if (!configuration) {
            return nil;
        }
        VTFrameProcessor *processor = [[VTFrameProcessor alloc] init];
        NSError *error = nil;
        if (![processor startSessionWithConfiguration:configuration error:&error]) {
            Log(LOG_W, @"Frame interpolation session didn't start: %@", error);
            return nil;
        }
        CVReturn status = CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL,
                                                  (__bridge CFDictionaryRef)configuration.destinationPixelBufferAttributes, &_pool);
        if (status != kCVReturnSuccess) {
            Log(LOG_W, @"Frame interpolation buffer pool failed: %d", status);
            [processor endSession];
            return nil;
        }
        _configuration = configuration;
        _processor = processor;
        Log(LOG_I, @"Frame interpolation ready at %dx%d, pixel formats %@", width, height, configuration.frameSupportedPixelFormats);
        return self;
    }
    return nil;
#endif
}

- (void)dealloc {
    [self invalidate];
}

- (void)invalidate {
#if !TARGET_OS_SIMULATOR
    if (@available(iOS 26.0, tvOS 26.0, *)) {
        if (_processor) {
            [(VTFrameProcessor *)_processor endSession];
            _processor = nil;
        }
    }
    if (_pool) {
        CVPixelBufferPoolRelease(_pool);
        _pool = NULL;
    }
#endif
}

- (OSType)pixelFormatClosestTo:(OSType)preferred {
#if !TARGET_OS_SIMULATOR
    if (@available(iOS 26.0, tvOS 26.0, *)) {
        NSArray<NSNumber *> *formats = ((VTLowLatencyFrameInterpolationConfiguration *)_configuration).frameSupportedPixelFormats;
        if (formats.count == 0 || [formats containsObject:@(preferred)]) {
            return preferred;
        }
        // Same chroma and range first, then whatever comes first
        for (NSNumber *f in formats) {
            OSType format = f.unsignedIntValue;
            if (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && preferred == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange) {
                return format;
            }
            if (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange && preferred == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange) {
                return format;
            }
        }
        return formats.firstObject.unsignedIntValue;
    }
#endif
    return preferred;
}

- (NSDictionary *)sourcePixelBufferAttributes {
#if !TARGET_OS_SIMULATOR
    if (@available(iOS 26.0, tvOS 26.0, *)) {
        return ((VTLowLatencyFrameInterpolationConfiguration *)_configuration).sourcePixelBufferAttributes ?: @{};
    }
#endif
    return @{};
}

- (CVPixelBufferRef)copyFrameBetween:(CVPixelBufferRef)previous atTime:(CMTime)previousTime
                                 and:(CVPixelBufferRef)current atTime:(CMTime)currentTime {
#if TARGET_OS_SIMULATOR
    return NULL;
#else
    if (@available(iOS 26.0, tvOS 26.0, *)) {
        if (!_processor || !_pool) {
            return NULL;
        }
        CVPixelBufferRef destination = NULL;
        if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &destination) != kCVReturnSuccess || !destination) {
            _failed++;
            return NULL;
        }
        CMTime middle = CMTimeMultiplyByRatio(CMTimeAdd(previousTime, currentTime), 1, 2);
        VTFrameProcessorFrame *source = [[VTFrameProcessorFrame alloc] initWithBuffer:current presentationTimeStamp:currentTime];
        VTFrameProcessorFrame *before = [[VTFrameProcessorFrame alloc] initWithBuffer:previous presentationTimeStamp:previousTime];
        VTFrameProcessorFrame *output = [[VTFrameProcessorFrame alloc] initWithBuffer:destination presentationTimeStamp:middle];
        VTLowLatencyFrameInterpolationParameters *parameters = (source && before && output)
            ? [[VTLowLatencyFrameInterpolationParameters alloc] initWithSourceFrame:source previousFrame:before
                                                                 interpolationPhase:@[@0.5] destinationFrames:@[output]]
            : nil;
        if (!parameters) {
            LogOnce(LOG_W, @"Frame interpolation can't take these frames (pixel format 0x%08x)", (unsigned int)CVPixelBufferGetPixelFormatType(current));
            CVPixelBufferRelease(destination);
            _failed++;
            return NULL;
        }
        // Colour space and HDR metadata go with the frame
        CVBufferPropagateAttachments(current, destination);

        CFTimeInterval start = CACurrentMediaTime();
        NSError *error = nil;
        BOOL ok = [(VTFrameProcessor *)_processor processWithParameters:parameters error:&error];
        double took = CACurrentMediaTime() - start;
        if (!ok) {
            LogOnce(LOG_W, @"Frame interpolation failed: %@", error);
            CVPixelBufferRelease(destination);
            _failed++;
            return NULL;
        }
        _processSeconds += took;
        _made++;
        return destination;
    }
    return NULL;
#endif
}

- (double)meanProcessMs {
    return _made > 0 ? _processSeconds * 1000.0 / _made : 0;
}

@end
