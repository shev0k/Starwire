#import <Metal/Metal.h>
#import <QuartzCore/CAMetalDisplayLink.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import "MetalConfig.h"
#import "PacingPolicy.h"

// The protocol to provide resize and redraw callbacks to a delegate.
@protocol MetalViewDelegate <NSObject>

- (void)drawableResize:(CGSize)size;
- (void)renderTo:(nonnull CAMetalLayer *)layer;
- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer;

@optional
// Display presenter: called on the render thread for every display refresh
- (void)renderUpdate:(nonnull CAMetalDisplayLinkUpdate *)update toLayer:(nonnull CAMetalLayer *)layer API_AVAILABLE(ios(17.0), tvos(17.0));

@end

// The Metal game view base class.
@interface MetalView : UIView <CALayerDelegate>

@property (nonatomic, nonnull, readonly) CAMetalLayer *metalLayer;
// Set before the view joins a window. NO: the render loop (waitToRenderTo, then renderTo).
// YES: a CAMetalDisplayLink on the render thread calls renderUpdate at every refresh.
@property (nonatomic) BOOL usesDisplayLink;
// Weak: the view controller owns this view (it was a retain cycle; VoidLink made it weak)
@property (nonatomic, weak, nullable) id<MetalViewDelegate> delegate;
@property (nonatomic) float framerate;
// The display link's range (PacingDisplayRefreshRange). All zero uses the frame rate.
@property (nonatomic) PacingRefreshRange refreshRange;

- (void)initCommon;
- (void)shutdown;
#if AUTOMATICALLY_RESIZE
- (void)resizeDrawable:(CGFloat)scaleFactor;
#endif

@end
