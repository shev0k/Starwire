#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#import "ConnectionCallbacks.h"
#import "Frame.h"
#import "Plot.h"

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
// Returns YES when the frame was committed for display
- (BOOL)renderFrame:(nonnull Frame *)frame toLayer:(nonnull CAMetalLayer *)layer;
- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer;
- (void)drawableResize:(CGSize)drawableSize;
- (void)shutdown;

+ (NSString *_Nullable)currentColorSpace;

@end
