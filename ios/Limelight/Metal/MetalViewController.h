#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#import "FrameQueue.h"
#import "ImGuiRenderer.h"
#import "MetalVideoRenderer.h"
#import "MetalView.h"

@interface MetalViewController : UIViewController <MetalViewDelegate>

@property (nonatomic) CGRect bounds;

- (nonnull instancetype)initWithFrame:(CGRect)bounds
                            framerate:(float)framerate
                            enableHdr:(BOOL)enableHdr
                       metricsHandler:(MetricsHandler _Nonnull)metricsHandler;

// While the app is inactive: stop drawing, keep the stream
- (void)pauseRendering;
- (void)resumeRendering;
// Stops the renderer and its thread. Safe to call more than once.
- (void)shutdown;

@end
