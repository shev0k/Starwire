// This is based on the following Apple example
// https://developer.apple.com/documentation/metal/achieving-smooth-frame-rates-with-a-metal-display-link?language=objc
// https://developer.apple.com/wwdc23/10123/

#import "MetalView.h"
#import "MetalConfig.h"

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_VIDEO

@interface MetalView () <CAMetalDisplayLinkDelegate>
@end

@implementation MetalView {
    // The secondary thread containing the render loop.
    NSThread *_renderThread;
    // Signalled by the render thread as it exits
    dispatch_semaphore_t _renderThreadExited;
}

#pragma mark - Initialization and Setup.

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (void)initCommon {
    _metalLayer = (CAMetalLayer *)self.layer;
    self.layer.delegate = self;
}

- (void)shutdown {
    if (_renderThread) {
        Log(LOG_I, @"[MetalView] sending renderThread a cancel message");
        [_renderThread cancel];
        // This runs on the main thread. It used to spin until the render thread finished, which
        // deadlocked if the render thread was waiting on the main thread (a layer change). The
        // render thread no longer waits on the main thread once it is stopping, and this wait is
        // bounded as well (as in VoidLink). The thread holds this view, so letting it finish on
        // its own is safe.
        Log(LOG_I, @"[MetalView] waiting on renderThread to finish");
        if (dispatch_semaphore_wait(_renderThreadExited, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0) {
            Log(LOG_I, @"[MetalView] renderThread has finished");
        } else {
            Log(LOG_W, @"[MetalView] renderThread still busy after 1 s, letting it exit on its own");
        }
        _renderThread = nil;
        _renderThreadExited = nil;
    }
}

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (void)didMoveToWindow {
    [self movedToWindow];
}

- (void)movedToWindow {
    if (!self.window) {
        Log(LOG_I, @"[MetalView] movedToWindow(nil): shutting down...");
        [self shutdown];
        return;
    }

    // Moving between windows must not start a second render loop (VoidLink)
    if (_renderThread) {
        Log(LOG_W, @"[MetalView] movedToWindow with a live renderThread, restarting it");
        [self shutdown];
    }

    // Render on a new thread
    dispatch_semaphore_t exited = dispatch_semaphore_create(0);
    _renderThreadExited = exited;
    BOOL usesDisplayLink = self.usesDisplayLink;
    _renderThread = [[NSThread alloc] initWithBlock:^{
        if (usesDisplayLink) {
            if (@available(iOS 17.0, tvOS 17.0, *)) {
                [self runDisplayLink];
                Log(LOG_I, @"[MetalView] renderThread is exiting");
                dispatch_semaphore_signal(exited);
                return;
            }
            Log(LOG_W, @"[MetalView] CAMetalDisplayLink needs iOS 17, using the render loop");
        }
        while (![NSThread currentThread].isCancelled) {
            @autoreleasepool {
                id<MetalViewDelegate> delegate = self.delegate;
                if (!delegate) {
                    // The view controller is gone; don't spin
                    break;
                }
                [delegate waitToRenderTo:self.metalLayer];
                [delegate renderTo:self.metalLayer];
            }
        }
        Log(LOG_I, @"[MetalView] renderThread is exiting");
        dispatch_semaphore_signal(exited);
    }];
    _renderThread.name = @"MetalVideoRenderer";
    _renderThread.qualityOfService = NSQualityOfServiceUserInteractive;
    [_renderThread start];
    Log(LOG_I, @"[MetalView] started renderThread %@", _renderThread);

    // Perform any actions that need to know the size and scale of the drawable. When UIKit calls
    // didMoveToWindow after the view initialization, this is the first opportunity to notify
    // components of the drawable's size.
#if AUTOMATICALLY_RESIZE
    [self resizeDrawable:self.window.screen.nativeScale];
#else
    // Notify the delegate of the default drawable size when the system can calculate it.
    CGSize defaultDrawableSize = self.bounds.size;
    defaultDrawableSize.width *= self.layer.contentsScale;
    defaultDrawableSize.height *= self.layer.contentsScale;
    [self.delegate drawableResize:defaultDrawableSize];
#endif
}

#pragma mark - Display link

// The display presenter's thread, as in Apple's "Achieving smooth frame rates with a Metal
// display link" sample: the link lives on this thread's run loop, so a callback that waits a
// little for a frame never holds up the main thread. The settings follow Nonary's moonlight-qt
// (vt_metal.mm, by Cameron Gutman): the stream's rate as minimum, maximum and preferred, and a
// frame latency of 1, so the drawable is handed over one refresh before it is shown. The range is
// the display's top rate unless refresh rate reduction is allowed (PacingDisplayRefreshRange).
- (void)runDisplayLink API_AVAILABLE(ios(17.0), tvos(17.0)) {
    CAMetalDisplayLink *link = [[CAMetalDisplayLink alloc] initWithMetalLayer:self.metalLayer];
    link.delegate = self;
    float fps = self.framerate > 0 ? self.framerate : 60;
    PacingRefreshRange range = self.refreshRange;
    if (range.preferred <= 0) {
        range = (PacingRefreshRange){fps, fps, fps};
    }
    link.preferredFrameRateRange = CAFrameRateRangeMake(range.minimum, range.maximum, range.preferred);
    link.preferredFrameLatency = 1;

    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    // A port keeps runMode from returning at once if the link has nothing scheduled
    [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
    [link addToRunLoop:runLoop forMode:NSDefaultRunLoopMode];
    Log(LOG_I, @"[MetalView] CAMetalDisplayLink started for %.0f FPS, range %.0f to %.0f, preferred %.0f",
        fps, range.minimum, range.maximum, range.preferred);

    while (![NSThread currentThread].isCancelled && self.delegate) {
        @autoreleasepool {
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    }
    [link invalidate];
}

- (void)metalDisplayLink:(CAMetalDisplayLink *)link needsUpdate:(CAMetalDisplayLinkUpdate *)update API_AVAILABLE(ios(17.0), tvos(17.0)) {
    if ([NSThread currentThread].isCancelled) {
        return;
    }
    id<MetalViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(renderUpdate:toLayer:)]) {
        [delegate renderUpdate:update toLayer:self.metalLayer];
    }
}

#pragma mark - Resizing

#if AUTOMATICALLY_RESIZE

// Override all methods that indicate the view's size has changed.

- (void)setContentScaleFactor:(CGFloat)contentScaleFactor {
    [super setContentScaleFactor:contentScaleFactor];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)resizeDrawable:(CGFloat)scaleFactor {
    CGSize newSize = self.bounds.size;
    newSize.width *= scaleFactor;
    newSize.height *= scaleFactor;

    if (newSize.width <= 0 || newSize.height <= 0) {
        return;
    }

    // The system calls all AppKit and UIKit calls that notify of a resize on the main thread. Use
    // a synchronized block to ensure that resize notifications on the delegate are atomic.
    @synchronized(_metalLayer) {
        if (newSize.width == _metalLayer.drawableSize.width && newSize.height == _metalLayer.drawableSize.height) {
            return;
        }

        Log(LOG_I, @"[MetalView] resizeDrawable: %.2f x %.2f", newSize.width, newSize.height);

        _metalLayer.drawableSize = newSize;

        [_delegate drawableResize:newSize];
    }
}
#endif  // END AUTOMATICALLY_RESIZE

@end
