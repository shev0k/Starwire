/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The implementation of the cross-platform game view controller.
*/

#import "MetalViewController.h"
#import "FrameQueue.h"
#import "ImGuiRenderer.h"
#import "MetalVideoRenderer.h"
#import "PacingPolicy.h"

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_VIDEO

@interface MetalViewController ()
// Atomic: the render thread reads it while the main thread clears it in shutdown. The render
// thread takes a strong copy for each frame (as VoidLink does).
@property (atomic, strong) MetalVideoRenderer *renderer;
@end

@implementation MetalViewController {
    FrameQueue *_frameQueue;
    float _framerate;
    BOOL _enableHdr;
    MetalView *_metalView;
    MetricsHandler _metricsHandler;
    CADisplayLink *_displayLink;
    // Display presenter: the refresh the last update was for (render thread only)
    CFTimeInterval _lastTargetPresentation;
    // Display presenter: refreshes a frame stays up for, and refreshes since the last new one
    int _refreshesPerFrame;
    int _refreshesSinceShown;
}

- (nonnull instancetype)initWithFrame:(CGRect)bounds framerate:(float)framerate enableHdr:(BOOL)enableHdr metricsHandler:(MetricsHandler)metricsHandler {
    self = [super init];
    if (self) {
        _bounds = bounds;
        _frameQueue = [FrameQueue sharedInstance];
        _framerate = framerate;
        _enableHdr = enableHdr;
        _metricsHandler = metricsHandler;
    }
    return self;
}

- (void)loadView {
    self.view = [[MetalView alloc] initWithFrame:_bounds];
    Log(LOG_I, @"[MetalViewController] created MetalView %@", (MetalView *)self.view);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    __block MetalView *view = (MetalView *)self.view;
    if (!view) {
        Log(LOG_E, @"The view attached to MetalViewController isn't a MetalView.");
        return;
    }
    _metalView = view;
    _metalView.delegate = self;
    _metalView.framerate = _framerate;

    // Select the device to render with.
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        Log(LOG_E, @"Metal isn't supported on this device.");
        self.view = [[UIView alloc] initWithFrame:self.view.frame];
        return;
    }
    view.metalLayer.device = device;

    // Initialize the renderer.
    MetalVideoRenderer *renderer = [[MetalVideoRenderer alloc] initWithMetalDevice:device
                                                               drawablePixelFormat:MTLPixelFormatBGR10A2Unorm
                                                                         framerate:self->_framerate];
    if (!renderer) {
        Log(LOG_E, @"The renderer couldn't be initialized.");
        return;
    }

    // How long each frame stays on screen (see PacingMinimumPresentDuration)
    PacingSettings *pacing = [PacingSettings current];
    double displayHz = (double)UIScreen.mainScreen.maximumFramesPerSecond;
    renderer.minimumPresentDuration = PacingMinimumPresentDuration(pacing.presentTiming, _framerate, displayHz);
    Log(LOG_I, @"[MetalViewController] present timing %@: hold each frame at least %.3f ms (stream %.0f FPS, display %.0f Hz)",
        pacing.presentTimingName, renderer.minimumPresentDuration * 1000.0, _framerate, displayHz);

    self.renderer = renderer;
    Log(LOG_I, @"[MetalViewController] viewDidLoad, created renderer: %@", renderer);

    // Initialize the renderer-dependent view properties. SDR until a frame says otherwise: on
    // iOS 26 and later "automatic" dynamic range dimmed SDR white (MetalLayerApplyDynamicRange).
    view.metalLayer.pixelFormat = renderer.colorPixelFormat;
    MetalLayerApplyDynamicRange(view.metalLayer, MetalLayerModeSDR);
    view.metalLayer.maximumDrawableCount = 3;

    // The display's rate: its top rate, or the stream's with refresh rate reduction allowed
    PacingRefreshRange range = PacingDisplayRefreshRange(_framerate, displayHz, pacing.reduceRefreshRate);
    view.refreshRange = range;
    _refreshesPerFrame = PacingRefreshesPerFrame(range.preferred, _framerate);
    _refreshesSinceShown = _refreshesPerFrame;
    Log(LOG_I, @"[MetalViewController] display refresh range %.0f to %.0f, preferred %.0f (reduction %@)",
        range.minimum, range.maximum, range.preferred, pacing.reduceRefreshRate ? @"allowed" : @"off");

    // Which presenter draws (PacingPresenter). The display presenter's CAMetalDisplayLink holds
    // the frame rate itself.
    view.usesDisplayLink = pacing.presenter == PacingPresenterDisplay;
    Log(LOG_I, @"[MetalViewController] presenter %@", pacing.presenterName);
    if (view.usesDisplayLink) {
        return;
    }

    // We need a no-op displaylink timer or iOS can decide to run at 60fps
    // The overhead from this should be minimal. It also measures the refresh interval.
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkHandler:)];
    if (@available(iOS 15.0, tvOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(range.minimum, range.maximum, range.preferred);
    } else {
        _displayLink.preferredFramesPerSecond = (NSInteger)range.preferred;
    }
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)displayLinkHandler:(CADisplayLink *)link {
    // Rendering does not use DisplayLink, this exists to fool iOS into keeping us running at the desired framerate.
    // The time it gives this refresh is what the display is really doing (8.33 ms at 120 Hz).
    [_frameQueue.pacingStats noteRefreshInterval:link.targetTimestamp - link.timestamp];
}

// Display presenter: one call per refresh, on the render thread. Takes the frame the jitter
// buffer picks, or the newest one with no jitter buffer (waiting a little if none has come yet),
// drops older ones, and draws it into this refresh's drawable.
// A refresh with no new frame draws nothing, so the last frame stays up.
- (void)renderUpdate:(CAMetalDisplayLinkUpdate *)update toLayer:(CAMetalLayer *)layer {
    MetalVideoRenderer *renderer = self.renderer;
    if (!renderer || renderer.isStopping) {
        return;
    }

    PacingStats *stats = _frameQueue.pacingStats;
    CFTimeInterval target = update.targetPresentationTimestamp;
    if (_lastTargetPresentation > 0 && target > _lastTargetPresentation) {
        [stats noteRefreshInterval:target - _lastTargetPresentation];
    }
    _lastTargetPresentation = target;

    // A faster display than the stream: the frame on screen keeps its refreshes first
    _refreshesSinceShown++;
    if (!PacingDisplayShouldTakeFrame(_refreshesSinceShown, _refreshesPerFrame)) {
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval wait = PacingDisplayFrameWait(now, update.targetTimestamp);
    Frame *frame = [_frameQueue dequeueForRefreshAt:now waitingUpTo:wait];
    [stats noteRefreshWithNewFrame:frame != nil];
    if (frame) {
        _refreshesSinceShown = 0;
    }
    if (frame) {
        [renderer renderFrame:frame intoDrawable:update.drawable ofLayer:layer targetTime:target];
    }
}

- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer {
    MetalVideoRenderer *renderer = self.renderer;
    if (!renderer || renderer.isStopping) {
        // Don't spin while shutting down
        usleep(10000);
        return;
    }

    // Renderer obtains a nextDrawable, waiting if necessary
    [renderer waitToRenderTo:layer];

    // If we don't have a frame yet, wait on that too
    [_frameQueue waitForEnqueue];
}

/// Draw frame (used by manual loop)
- (void)renderTo:(nonnull CAMetalLayer *)layer {
    MetalVideoRenderer *renderer = self.renderer;
    if (!renderer || renderer.isStopping) {
        return;
    }
    CFTimeInterval timeout = (1.0f / _framerate) - renderer.averageGPUTime;
    Frame *frame = [_frameQueue dequeueWithTimeout:timeout];
    if (frame) {
        [renderer renderFrame:frame toLayer:layer];
    }
}

- (void)drawableResize:(CGSize)size {
    [self.renderer drawableResize:size];
}

// The app is inactive (Control Center, the app switcher, a call banner): stop drawing but keep
// the stream, and pick up again on return. From VoidLink's pause and resume path.
- (void)pauseRendering {
    Log(LOG_I, @"[MetalViewController] pausing rendering");
    _displayLink.paused = YES;
    self.renderer.isPaused = YES;
}

- (void)resumeRendering {
    Log(LOG_I, @"[MetalViewController] resuming rendering");
    self.renderer.isPaused = NO;
    _displayLink.paused = NO;
}

// Stops the renderer, then the render thread. Safe to call more than once.
- (void)shutdown {
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }

    // The renderer first: once it is stopping, the render thread can't start waiting on the main
    // thread, so the wait for it below can't deadlock
    MetalVideoRenderer *renderer = self.renderer;
    if (renderer) {
        [renderer shutdown];
        self.renderer = nil;
    }

    if (_metalView) {
        _metalView.delegate = nil;
        [_metalView shutdown];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    Log(LOG_I, @"[MetalViewController] viewDidDisappear");
    [self shutdown];
}

#if TARGET_OS_IOS
// Hides the Home indicator button automatically.
- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}
#endif

@end
