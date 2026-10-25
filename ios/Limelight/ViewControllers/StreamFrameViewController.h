//
//  StreamFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Connection.h"
#import "FloatBuffer.h"
#import "ImGuiRenderer.h"
#import "MetalViewController.h"
#import "StreamConfiguration.h"
#import "StreamView.h"

#import <UIKit/UIKit.h>

#if TARGET_OS_TV
@import GameController;

@interface StreamFrameViewController : GCEventViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>
#else
@interface StreamFrameViewController : UIViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>
#endif
@property (nonatomic) StreamConfiguration* streamConfig;
@property (nonatomic, strong) MetalViewController *metalViewController;
@property (nonatomic, strong) ImGuiRenderer *imguiView;
// Starwire: called when the stream screen goes away. The SwiftUI app presents this screen
// modally, so it is dismissed then instead of popped.
@property (nonatomic, copy) void (^onFinished)(void);

-(void)updatePreferredDisplayMode:(BOOL)streamActive;

@end
