#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#import "ConnectionCallbacks.h"
#import "Frame.h"
#import "Plot.h"

// How the layer shows a frame
typedef NS_ENUM(NSInteger, MetalLayerMode) {
    // SDR: 8 or 10 bit in the frame's own colour space
    MetalLayerModeSDR = 0,
    // HDR10 as PQ in a 10 bit layer, without EDR metadata (EDR not available)
    MetalLayerModePQ = 1,
    // HDR10 the way VoidLink shows it: PQ decoded to linear light in a half-float layer, with the
    // stream's HDR10 metadata as the layer's EDRMetadata, so the system maps it to the panel
    MetalLayerModeEDR = 2,
};

// The mode for a frame: EDR for PQ frames when the system has it, PQ without it, else SDR
MetalLayerMode MetalLayerModeForFrame(BOOL isPQ, BOOL edrAvailable);

// Whether a layer in this mode should ask iOS 26 and later for high dynamic range. SDR must ask
// for standard: left on "automatic", iPadOS 27 showed SDR white at about 77% (197 of 255) and
// full colours at about 80%, after a second or two, on the iPad Pro M4.
BOOL MetalLayerWantsHighDynamicRange(MetalLayerMode mode);
// Sets the layer's dynamic range for the mode (preferredDynamicRange on iOS 26 and later,
// wantsExtendedDynamicRangeContent before). Main thread only.
void MetalLayerApplyDynamicRange(CAMetalLayer *_Nonnull layer, MetalLayerMode mode);

@interface MetalVideoRenderer : NSObject

@property (atomic) CFTimeInterval averageGPUTime;
@property (nonatomic) NSUInteger sampleCount;
@property (nonatomic) MTLPixelFormat colorPixelFormat;
@property (atomic) CFTimeInterval lastPresented;
@property (nonatomic) id<CAMetalDrawable> _Nullable nextDrawable;
@property (atomic) BOOL isStopping;
// While the app is inactive, frames are let go without drawing (from VoidLink's pause path)
@property (atomic) BOOL isPaused;
// The minimum time each frame stays on screen (PacingMinimumPresentDuration). Set before the
// first frame.
@property (atomic) CFTimeInterval minimumPresentDuration;

- (nonnull instancetype)initWithMetalDevice:(nonnull id<MTLDevice>)device drawablePixelFormat:(MTLPixelFormat)drawablePixelFormat framerate:(float)framerate;
// Render loop: takes the layer's next drawable and presents it after minimumPresentDuration.
// Returns YES when the frame was committed for display.
- (BOOL)renderFrame:(nonnull Frame *)frame toLayer:(nonnull CAMetalLayer *)layer;
// Display presenter: draws into the drawable a CAMetalDisplayLink update handed over and presents
// it with no minimum duration. targetTime is the update's targetPresentationTimestamp, which the
// statistics compare with the time the frame really appeared.
- (BOOL)renderFrame:(nonnull Frame *)frame
       intoDrawable:(nonnull id<CAMetalDrawable>)drawable
            ofLayer:(nonnull CAMetalLayer *)layer
         targetTime:(CFTimeInterval)targetTime;
- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer;
- (void)drawableResize:(CGSize)drawableSize;
- (void)shutdown;

+ (NSString *_Nullable)currentColorSpace;

@end
