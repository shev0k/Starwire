//
//  StreamPictureInPicture.m
//  Starwire
//

#import "StreamPictureInPicture.h"
#import "Logger.h"

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_VIDEO

NSString *const StreamPictureInPictureKey = @"StarwirePictureInPicture";

// While the app is in front: two frames a second keep the layer ready
static const CFTimeInterval kIdleEnqueueInterval = 0.5;

BOOL StreamUsesPictureInPicture(NSUserDefaults *defaults) {
    return [defaults boolForKey:StreamPictureInPictureKey];
}

BOOL PictureInPictureShouldEnqueue(BOOL active, CFTimeInterval now, CFTimeInterval lastEnqueue, CFTimeInterval idleInterval) {
    if (active || lastEnqueue <= 0) {
        return YES;
    }
    return now - lastEnqueue >= idleInterval;
}

BOOL StreamEndsOnBackground(BOOL pictureInPictureActive) {
    return !pictureInPictureActive;
}

@interface StreamPictureInPicture () <AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate>
@end

@implementation StreamPictureInPicture {
    AVSampleBufferDisplayLayer *_layer;
    AVPictureInPictureController *_controller;
    __weak UIView *_view;
    BOOL _restoring;

    // Decoder queue only
    CFTimeInterval _lastEnqueue;
    CMVideoFormatDescriptionRef _format;
}

- (instancetype)initWithView:(UIView *)view {
    if (![AVPictureInPictureController isPictureInPictureSupported]) {
        Log(LOG_I, @"Picture in picture isn't supported on this device");
        return nil;
    }
    self = [super init];
    if (self) {
        _view = view;
        _layer = [AVSampleBufferDisplayLayer layer];
        _layer.videoGravity = AVLayerVideoGravityResizeAspect;
        _layer.frame = view.bounds;
        [view.layer insertSublayer:_layer atIndex:0];

        AVPictureInPictureControllerContentSource *source =
            [[AVPictureInPictureControllerContentSource alloc] initWithSampleBufferDisplayLayer:_layer playbackDelegate:self];
        _controller = [[AVPictureInPictureController alloc] initWithContentSource:source];
        _controller.delegate = self;
        _controller.canStartPictureInPictureAutomaticallyFromInline = YES;
        // A live stream: no seeking, no play and pause
        _controller.requiresLinearPlayback = YES;
        Log(LOG_I, @"Picture in picture ready");
    }
    return self;
}

- (void)dealloc {
    if (_format) {
        CFRelease(_format);
    }
}

- (void)layout {
    _layer.frame = _view.bounds;
}

- (void)invalidate {
    _controller.delegate = nil;
    if (_controller.isPictureInPictureActive) {
        [_controller stopPictureInPicture];
    }
    _controller = nil;
    [_layer.sampleBufferRenderer flushWithRemovalOfDisplayedImage:YES completionHandler:nil];
    [_layer removeFromSuperlayer];
}

- (void)noteDecodedPixelBuffer:(CVPixelBufferRef)pixelBuffer at:(CFTimeInterval)now {
    if (_lastEnqueue <= 0) {
        // The first frame of a stream: its statistics exist now
        [FrameQueue sharedInstance].pacingStats.pictureInPictureNote = [self note];
    }
    if (!pixelBuffer || !PictureInPictureShouldEnqueue(self.active, now, _lastEnqueue, kIdleEnqueueInterval)) {
        return;
    }
    _lastEnqueue = now;

    if (!_format || !CMVideoFormatDescriptionMatchesImageBuffer(_format, pixelBuffer)) {
        if (_format) {
            CFRelease(_format);
            _format = NULL;
        }
        if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &_format) != noErr) {
            Log(LOG_W, @"Picture in picture: no format description for the frame");
            return;
        }
    }

    CMSampleTimingInfo timing = {
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMakeWithSeconds(now, 1000000),
        .decodeTimeStamp = kCMTimeInvalid,
    };
    CMSampleBufferRef sample = NULL;
    if (CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixelBuffer, _format, &timing, &sample) != noErr || !sample) {
        return;
    }
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, YES);
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    }

    AVSampleBufferVideoRenderer *renderer = _layer.sampleBufferRenderer;
    if (renderer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        Log(LOG_W, @"Picture in picture layer failed (%@), flushing", renderer.error);
        [renderer flush];
    }
    [renderer enqueueSampleBuffer:sample];
    CFRelease(sample);
}

- (NSString *)note {
    if (self.active) {
        return [NSString stringWithFormat:@"showing, started %d", self.startCount];
    }
    return self.startCount > 0 ? [NSString stringWithFormat:@"closed, started %d", self.startCount] : @"ready";
}

#pragma mark - AVPictureInPictureControllerDelegate

- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)controller {
    Log(LOG_I, @"Picture in picture starting");
    _restoring = NO;
    _active = YES;
    _startCount++;
    [FrameQueue sharedInstance].pacingStats.pictureInPictureNote = [self note];
}

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)controller {
    Log(LOG_I, @"Picture in picture started");
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller failedToStartPictureInPictureWithError:(NSError *)error {
    Log(LOG_W, @"Picture in picture failed to start: %@", error);
    _active = NO;
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completionHandler {
    Log(LOG_I, @"Picture in picture: back to the app");
    _restoring = YES;
    completionHandler(YES);
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller {
    Log(LOG_I, @"Picture in picture stopped (%@)", _restoring ? @"back to the app" : @"closed");
    _active = NO;
    [FrameQueue sharedInstance].pacingStats.pictureInPictureNote = [self note];
    if (self.onStop) {
        self.onStop(_restoring);
    }
}

#pragma mark - AVPictureInPictureSampleBufferPlaybackDelegate

- (void)pictureInPictureController:(AVPictureInPictureController *)controller setPlaying:(BOOL)playing {
    // A live stream can't pause
}

- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)controller {
    // Live: no start, no end
    return CMTimeRangeMake(kCMTimeNegativeInfinity, kCMTimePositiveInfinity);
}

- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)controller {
    return NO;
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller didTransitionToRenderSize:(CMVideoDimensions)newRenderSize {
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
                    skipByInterval:(CMTime)skipInterval
                 completionHandler:(void (^)(void))completionHandler {
    completionHandler();
}

@end
