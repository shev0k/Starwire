//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "StreamFrameViewController.h"
#import "MainFrameViewController.h"
#import "VideoDecoderRenderer.h"
#import "StreamManager.h"
#import "ControllerSupport.h"
#import "DataManager.h"
#import "PaddedLabel.h"
#import "ImGuiRenderer.h"
#import "RelativeTouchHandler.h"
#import "MetalVideoRenderer.h"
#import "StreamAlertGate.h"
#import "StreamPictureInPicture.h"
#import "ExternalDisplay.h"
#import "FrameInterpolator.h"
#import "SystemVideoPresenter.h"
#import "StreamTestOverrides.h"
#import "PacingPolicy.h"
#import "FrameQueue.h"
#import "Moonlight-Swift.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <Limelight.h>

#if TARGET_OS_TV
#import <AVFoundation/AVDisplayCriteria.h>
#import <AVKit/AVDisplayManager.h>
#import <AVKit/UIWindow.h>
#endif

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_STREAM

@interface AVDisplayCriteria()
@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;
- (id)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;
@end

@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    StreamManager *_streamMan;
    TemporarySettings *_settings;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    PaddedLabel *_overlayView;
    UILabel *_stageLabel;
    UILabel *_tipLabel;
    UIActivityIndicatorView *_spinner;
    StreamView *_streamView;
    UIScrollView *_scrollView;
    BOOL _userIsInteracting;
    CGSize _keyboardSize;
    PlotMetrics _decodeMetrics;
    PlotMetrics _frameDropMetrics;
    PlotMetrics _frameQueueMetrics;
    // One alert per stream, none while closing (see StreamAlertGate)
    StreamAlertGate *_alertGate;
    __weak UIAlertController *_presentedAlert;
    // Picture in picture, when it's on in iOS Settings (StarwirePictureInPicture). With the system
    // presenter it is also the full-screen video layer.
    StreamPictureInPicture *_pictureInPicture;
    // The system presenter (PacingPresenterSystem), or nil with Metal
    SystemVideoPresenter *_systemPresenter;
    // Vibeshine's own requests (bitrate, hardware metrics), nil for a PC with no pinned certificate
    StarwireHostActions *_hostActions;
    BOOL _hostSendsMetrics;
    int _bitrateKbps;
#if !TARGET_OS_TV
    // The stream menu, its floating button, the on-screen controller, the full keyboard and the
    // touch modes (StarwireStreamControls.swift)
    StarwireStreamControls *_streamControls;
#endif

#if TARGET_OS_TV
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    UITapGestureRecognizer *_remoteDoubleSelectRecognizer;
#else
    UIScreenEdgePanGestureRecognizer *_exitSwipeRecognizer;
    UISwipeGestureRecognizer *_topSwipeRecognizer;
    UISwipeGestureRecognizer *_topSwipeUpRecognizer;
#endif

}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
#if !TARGET_OS_TV
    [[self revealViewController] setPrimaryViewController:self];
#endif
}

#if TARGET_OS_TV
- (void)controllerPauseButtonPressed:(id)sender { }
- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self returnToMainFrame];
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- backing out of stream");
    [self returnToMainFrame];
}
- (void)remoteSelectButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Select button double-tapped -- toggling stats");
    if (!self->_statsUpdateTimer) {
        [self showStats];
    } else {
        [self hideStats];
    }
}
#endif


- (void)viewDidLoad
{
    [super viewDidLoad];

    // What the storyboard set, for the SwiftUI app that creates this screen in code
    self.view.backgroundColor = [UIColor blackColor];
    self.view.multipleTouchEnabled = YES;

    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [[[DataManager alloc] init] getSettings];
    StreamApplyTestOverrides(_settings, [NSUserDefaults standardUserDefaults]);
    _alertGate = [[StreamAlertGate alloc] init];

    _stageLabel = [[UILabel alloc] init];
    [_stageLabel setUserInteractionEnabled:NO];
    [_stageLabel setText:[NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName]];
    [_stageLabel sizeToFit];
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.textColor = [UIColor whiteColor];
    _stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    
    _spinner = [[UIActivityIndicatorView alloc] init];
    [_spinner setUserInteractionEnabled:NO];
#if TARGET_OS_TV
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
#else
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleMedium];
#endif
    [_spinner sizeToFit];
    [_spinner startAnimating];
    _spinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2 - _stageLabel.frame.size.height - _spinner.frame.size.height);
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    // Audio haptics drive the first controller's motors (Starwire)
    __weak ControllerSupport *weakControllers = _controllerSupport;
    StarwireAudioHaptics.shared.rumble = ^(uint16_t low, uint16_t high) {
        [weakControllers rumble:0 lowFreqMotor:low highFreqMotor:high];
    };
    _inactivityTimer = nil;
    
#if TARGET_OS_TV
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer || !_remoteDoubleSelectRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _remoteDoubleSelectRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(remoteSelectButtonDoublePressed:)];
        _remoteDoubleSelectRecognizer.numberOfTapsRequired = 2;
        _remoteDoubleSelectRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];
    [self.view addGestureRecognizer:_remoteDoubleSelectRecognizer];

#else
    _exitSwipeRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwiped)];
    _exitSwipeRecognizer.edges = UIRectEdgeLeft;
    _exitSwipeRecognizer.delaysTouchesBegan = NO;
    _exitSwipeRecognizer.delaysTouchesEnded = NO;
    
    [self.view addGestureRecognizer:_exitSwipeRecognizer];

    _topSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(topSwiped)];
    _topSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
    _topSwipeRecognizer.numberOfTouchesRequired = 2;
    _topSwipeRecognizer.enabled = TRUE;
    [self.view addGestureRecognizer:_topSwipeRecognizer];

    _topSwipeUpRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(topSwipedUp)];
    _topSwipeUpRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
    _topSwipeUpRecognizer.numberOfTouchesRequired = 2;
    _topSwipeUpRecognizer.enabled = FALSE;
    // This is added to the _overlayView when displayed
#endif

    _streamView = [[StreamView alloc] initWithFrame:self.view.frame];
#if !TARGET_OS_TV
    [self setUpStreamControls];
#endif
    [_streamView setupStreamView:_controllerSupport
             interactionDelegate:self
                          config:self.streamConfig];
#if TARGET_OS_TV
    // we need to tell the other remote handler in RelativeTouchHandler to wait for our double-select
    RelativeTouchHandler *touchHandler = (RelativeTouchHandler *)[_streamView touchHandler];
    UIGestureRecognizer *remotePressRecognizer = [touchHandler remotePressRecognizer];
    [remotePressRecognizer requireGestureRecognizerToFail:_remoteDoubleSelectRecognizer];
#endif

    _tipLabel = [[UILabel alloc] init];
    [_tipLabel setUserInteractionEnabled:NO];
    
#if TARGET_OS_TV
    [_tipLabel setText:@"Tip: Tap the Play/Pause button on the Apple TV Remote to disconnect from your PC. Double-click Select for stats."];
#else
    [_tipLabel setText:@"Tip: Swipe from the left edge to disconnect from your PC. Swipe down with 2 fingers for stats."];
#endif
    
    [_tipLabel sizeToFit];
    _tipLabel.textColor = [UIColor whiteColor];
    _tipLabel.textAlignment = NSTextAlignmentCenter;
    _tipLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height * 0.9);
    
    _bitrateKbps = self.streamConfig.bitRate;
    _hostActions = [[StarwireHostActions alloc] initWithAddress:self.streamConfig.host
                                                      httpsPort:self.streamConfig.httpsPort
                                                     serverCert:self.streamConfig.serverCert];
    [_hostActions capabilities:^(BOOL sleep, BOOL metrics) {
        self->_hostSendsMetrics = metrics;
    }];

    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                            renderView:_streamView
                                   connectionCallbacks:self];
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];

#if 0
    // FIXME: This doesn't work reliably on iPad for some reason. Showing and hiding the keyboard
    // several times in a row will not correctly restore the state of the UIScrollView.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillShow:)
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillHide:)
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
#endif
    
    // Only enable scroll and zoom in absolute touch mode (moonlight-ios's; Starwire's touch modes
    // zoom the picture themselves)
#if !TARGET_OS_TV
    if (_settings.absoluteTouchMode && _streamControls == nil) {
#else
    if (_settings.absoluteTouchMode) {
#endif
        _scrollView = [[UIScrollView alloc] initWithFrame:self.view.frame];
#if !TARGET_OS_TV
        [_scrollView.panGestureRecognizer setMinimumNumberOfTouches:2];
#endif
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setShowsVerticalScrollIndicator:NO];
        [_scrollView setDelegate:self];
        [_scrollView setMaximumZoomScale:10.0f];
        
        // Add StreamView inside a UIScrollView for absolute mode
        [_scrollView addSubview:_streamView];
        [self.view addSubview:_scrollView];
    }
    else {
        // Add StreamView directly in relative mode
        [self.view addSubview:_streamView];
    }
    
    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];

    // Metal view for video
    Log(LOG_I, @"StreamFrameViewController creating MetalViewController");
    // With frame interpolation the screen shows twice the stream's frames (FrameInterpolator.h)
    float presentRate = [self->_settings.framerate floatValue];
    if ([FrameInterpolator appliesWithDefaults:[NSUserDefaults standardUserDefaults]
                                         width:self.streamConfig.width height:self.streamConfig.height
                                           fps:presentRate displayHz:UIScreen.mainScreen.maximumFramesPerSecond]) {
        presentRate *= 2;
    }
    PacingSettings *pacing = [PacingSettings current];
    // "Video on the external display" moves the Metal view, so it keeps Metal
    BOOL externalVideo = ExternalDisplayModeFromDefaults([NSUserDefaults standardUserDefaults]) == ExternalDisplayModeVideo;
    if (pacing.presenter == PacingPresenterSystem && !externalVideo) {
        // The system's video layer shows the stream, as picture in picture does (SystemVideoPresenter.h)
        Log(LOG_I, @"StreamFrameViewController showing video through the system's video layer");
        _pictureInPicture = [[StreamPictureInPicture alloc] initWithView:self.view
                                                       pictureInPicture:StreamUsesPictureInPicture([NSUserDefaults standardUserDefaults])];
        PacingRefreshRange range = PacingDisplayRefreshRange(presentRate, UIScreen.mainScreen.maximumFramesPerSecond, pacing.reduceRefreshRate);
        _systemPresenter = [[SystemVideoPresenter alloc] initWithLayer:_pictureInPicture range:range framerate:presentRate];
        // The system's layer sits under this screen's views, so nothing covers the loading
        // spinner the way the Metal view did: stop it at the first frame
        __weak UIActivityIndicatorView *spinner = _spinner;
        _systemPresenter.onFirstFrame = ^{
            [spinner stopAnimating];
            spinner.hidden = YES;
        };
        [_systemPresenter start];
    } else {
        self.metalViewController = [[MetalViewController alloc] initWithFrame:self.view.bounds
                                                                    framerate:presentRate
                                                                    enableHdr:self->_settings.enableHdr
                                                               metricsHandler:self.imguiView.metricsHandler];
        self.metalViewController.view.userInteractionEnabled = NO;
        [self.view addSubview:self.metalViewController.view];
        [self.view bringSubviewToFront:self.metalViewController.view];
    }

    // Make a MetalKit view for ImGui
    self.imguiView = [[ImGuiRenderer alloc] initWithFrame:self.view.bounds
                                                streamFps:[_settings.framerate intValue]
                                             enableGraphs:_settings.enableGraphs
                                             graphOpacity:[_settings.graphOpacity intValue]];
    self.imguiView.mtkView.userInteractionEnabled = NO;
    [self.view addSubview:self.imguiView.mtkView];
    [self.view bringSubviewToFront:self.imguiView.mtkView];

#if !TARGET_OS_TV
    // The video goes to an external display when one is set up for it (ExternalDisplay.h)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(placeVideoView)
                                                 name:ExternalDisplayDidChangeNotification
                                               object:nil];
    [self placeVideoView];

    BOOL showSampleBufferLayer = [[NSUserDefaults standardUserDefaults] boolForKey:StreamShowSampleBufferLayerKey];
    if (_systemPresenter) {
        // Fed by the system presenter while the app is active (see applicationWillResignActive)
    } else if (StreamUsesPictureInPicture([NSUserDefaults standardUserDefaults]) || showSampleBufferLayer) {
        _pictureInPicture = [[StreamPictureInPicture alloc] initWithView:self.view];
        if (showSampleBufferLayer) {
            // A colour comparison: the system's video layer full screen, Metal hidden
            Log(LOG_I, @"Showing the sample buffer layer instead of Metal");
            _pictureInPicture.feedsEveryFrame = YES;
            self.metalViewController.view.hidden = YES;
        }
        [FrameQueue sharedInstance].decodedFrameObserver = _pictureInPicture;
    }
    if (_pictureInPicture) {
        __weak StreamFrameViewController *weakSelf = self;
        _pictureInPicture.onStop = ^(BOOL restored) {
            // Closing the window while the app is away ends the stream, as going to the
            // background without picture in picture does
            if (!restored && UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
                Log(LOG_I, @"Picture in picture closed in the background, ending the stream");
                [weakSelf returnToMainFrame];
            }
        };
    }
#endif
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [_pictureInPicture layout];
#if !TARGET_OS_TV
    [_streamControls layout];
#endif
}

#if !TARGET_OS_TV
- (void)setUpStreamControls {
    _streamControls = [[StarwireStreamControls alloc] initWithView:self.view
                                                       streamWidth:self.streamConfig.width
                                                      streamHeight:self.streamConfig.height
                                                               fps:self.streamConfig.frameRate
                                                           appName:self.streamConfig.appName ?: @""];
    _streamView.input = _streamControls.input;
    // The stream menu has the stats switch; a two-finger swipe would take two-finger scrolls
    _topSwipeRecognizer.enabled = NO;

    __weak StreamFrameViewController *weakSelf = self;
    _streamControls.input.onVideoTransform = ^(CGAffineTransform transform) {
        [weakSelf setVideoTransform:transform];
    };
    _streamControls.onBitrate = ^{
        [weakSelf showBitrateMenu:nil];
    };
    _streamControls.onToggleStats = ^{
        StreamFrameViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (strongSelf->_statsUpdateTimer != nil) {
            [strongSelf hideStats];
        } else {
            [strongSelf showStats];
        }
    };
    _streamControls.onSystemKeyboard = ^{
        StreamFrameViewController *strongSelf = weakSelf;
        [strongSelf->_streamView toggleSystemKeyboard];
    };
    _streamControls.onQuit = ^{
        [weakSelf quitSession];
    };
    _streamControls.onDisconnect = ^{
        Log(LOG_I, @"Disconnect from the stream menu");
        [weakSelf returnToMainFrame];
    };
    _streamControls.onNotice = ^(NSString *text) {
        [weakSelf showToast:text];
    };
    _streamControls.present = ^(UIViewController *controller) {
        [[weakSelf topPresenter] presentViewController:controller animated:YES completion:nil];
    };
}

// Pinch to zoom and pan and zoom mode move the picture; touches map through the same zoom
// (VideoGeometry in StarwireKit)
- (void)setVideoTransform:(CGAffineTransform)transform {
    self.metalViewController.view.transform = transform;
    [_pictureInPicture setVideoTransform:transform];
}

// Quit Session: leave the stream, then end the game on the PC, as Android does
- (void)quitSession {
    Log(LOG_I, @"Quit Session from the stream menu");
    StarwireHostActions *actions = _hostActions;
    [self returnToMainFrame];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [actions quitApp:^(NSString *error) {
            if (error != nil) {
                Log(LOG_W, @"Quit Session: the PC refused: %@", error);
            }
        }];
    });
}
#endif

// Puts the video on the external display's window while there is one, else back on this screen
// under the statistics view
- (void)placeVideoView {
    UIView *video = self.metalViewController.view;
    if (!video) {
        return;
    }
#if !TARGET_OS_TV
    UIView *target = ExternalDisplay.videoWindow.rootViewController.view ?: self.view;
#else
    UIView *target = self.view;
#endif
    if (video.superview == target) {
        return;
    }
    [video removeFromSuperview];
    video.frame = target.bounds;
    video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (target == self.view) {
        [self.view insertSubview:video belowSubview:self.imguiView.mtkView];
        Log(LOG_I, @"Video on this screen");
    } else {
        [target addSubview:video];
        Log(LOG_I, @"Video on the external display");
    }
}

- (void)stopPictureInPicture {
    if (_pictureInPicture) {
        if ([FrameQueue sharedInstance].decodedFrameObserver == _pictureInPicture) {
            [FrameQueue sharedInstance].decodedFrameObserver = nil;
        }
        [_pictureInPicture invalidate];
        _pictureInPicture = nil;
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    // Only cleanup when we're being destroyed
    if (parent == nil) {
        [_alertGate markExiting];
        [_systemPresenter stop];
        _systemPresenter = nil;
        [self stopPictureInPicture];
        // Stop drawing before the view goes away (VoidLink stops the renderer explicitly too)
        [self.metalViewController shutdown];
        // It may be on the external display's window, which outlives this screen
        [self.metalViewController.view removeFromSuperview];
        [_controllerSupport cleanup];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamMan stopStream];
        if (_inactivityTimer != nil) {
            [_inactivityTimer invalidate];
            _inactivityTimer = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

#if 0
- (void)keyboardWillShow:(NSNotification *)notification {
    _keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;

    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height -= self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}

-(void)keyboardWillHide:(NSNotification *)notification {
    // NOTE: UIKeyboardFrameEndUserInfoKey returns a different keyboard size
    // than UIKeyboardFrameBeginUserInfoKey, so it's unsuitable for use here
    // to undo the changes made by keyboardWillShow.
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height += self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}
#endif

- (void)updateStatsOverlay {
    NSString* overlayText = [self->_streamMan getStatsOverlayText];
    // Vibeshine: the PC's CPU and GPU, when the PC sends them (its hardware_metrics setting)
    if (_hostSendsMetrics) {
        [_hostActions refreshHardwareMetrics];
        NSString* hostLine = _hostActions.hardwareMetricsLine;
        if (overlayText.length > 0 && hostLine.length > 0) {
            overlayText = [NSString stringWithFormat:@"%@\n%@", overlayText, hostLine];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *text = overlayText;
#if !TARGET_OS_TV
        // What input has reached the PC (StarwireKit's InputTally), and how touches are read
        if (text.length > 0 && self->_streamControls != nil) {
            text = [NSString stringWithFormat:@"%@\nTouch: %@\n%@", text, self->_streamControls.input.touchModeTitle,
                    StarwireStreamInput.inputSummary];
        }
#endif
        [self updateOverlayText:text];
    });
}

- (void)updateOverlayText:(NSString*)text {
    if (_overlayView == nil) {
        _overlayView = [[PaddedLabel alloc] initWithFrame:CGRectZero];
        [_overlayView setTextInsets:UIEdgeInsetsMake(10, 15, 10, 15)];
        [_overlayView setUserInteractionEnabled:YES];
        [_overlayView setNumberOfLines:100];
        [_overlayView.layer setCornerRadius:12];
        [_overlayView.layer setMasksToBounds:YES];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
        [_overlayView setTextColor:[UIColor lightGrayColor]];
        [_overlayView setBackgroundColor:[UIColor blackColor]];
#if TARGET_OS_TV
        [_overlayView setFont:[UIFont systemFontOfSize:24 weight:UIFontWeightMedium]];
#else
        [_overlayView setFont:[UIFont systemFontOfSize:12 weight:UIFontWeightMedium]];

        _topSwipeUpRecognizer.enabled = TRUE;
        [_overlayView addGestureRecognizer:_topSwipeUpRecognizer];
#endif
        int opacity = MAX([_settings.graphOpacity intValue], 60);
        [_overlayView setAlpha:(float)opacity / 100.0];
        [self.view addSubview:_overlayView];
    }
    
    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, (12 + (_overlayView.frame.size.height / 2)))];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void) returnToMainFrame {
#if !TARGET_OS_TV
    // Show the PC's cursor again if Starwire hid it, and give the keys a moment to arrive
    // before the connection stops (HostCursorController)
    if (!_alertGate.exiting && [_streamControls streamStopping]) {
        [_alertGate markExiting];
        StarwireStreamControls *controls = _streamControls;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [controls.input streamStopFlushed];
            [self finishReturnToMainFrame];
        });
        return;
    }
#endif
    [self finishReturnToMainFrame];
}

- (void) finishReturnToMainFrame {
    [_alertGate markExiting];
    [StarwireMicrophone.shared streamStopped];
    StarwireAudioHaptics.shared.rumble = nil;
    // An alert presented above the stream stays up after the stream screen is popped (for
    // example when the app goes to the background), so take it down with the stream
    UIAlertController *alert = _presentedAlert;
    if (alert != nil && alert.presentingViewController != nil && !alert.isBeingDismissed) {
        [alert.presentingViewController dismissViewControllerAnimated:NO completion:nil];
    }

    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;

#if !TARGET_OS_TV
    _topSwipeRecognizer.enabled = FALSE;
    _topSwipeUpRecognizer.enabled = FALSE;
#endif

    if (self.navigationController != nil) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    } else if (self.presentingViewController != nil && !self.isBeingDismissed) {
        // Starwire's SwiftUI app presents the stream modally
        [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    }
    void (^onFinished)(void) = self.onFinished;
    self.onFinished = nil;
    if (onFinished != nil) {
        onFinished();
    }
}

// This will fire if the user opens control center or gets a low battery message
- (void)applicationWillResignActive:(NSNotification *)notification {
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
    }

    // iOS doesn't allow GPU work in the background; stop drawing until we're active again
    [self.metalViewController pauseRendering];
    // The system presenter's display link stops in the background; picture in picture is then fed
    // every decoded frame instead
    if (_systemPresenter) {
        _systemPresenter.paused = YES;
        _pictureInPicture.feedsEveryFrame = YES;
        [FrameQueue sharedInstance].decodedFrameObserver = _pictureInPicture;
    }
    
#if !TARGET_OS_TV
    // Terminate the stream if the app is inactive for 60 seconds
    Log(LOG_I, @"Starting inactivity termination timer");
    _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:60
                                                      target:self
                                                    selector:@selector(inactiveTimerExpired:)
                                                    userInfo:nil
                                                     repeats:NO];
#endif
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
    if (_pictureInPicture.active) {
        Log(LOG_I, @"Inactive for 60 seconds, but picture in picture is showing the stream");
        _inactivityTimer = nil;
        return;
    }
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    // Back in the app: the full screen takes over from the picture in picture window
    [_pictureInPicture stop];
    [self.metalViewController resumeRendering];
    if (_systemPresenter) {
        [FrameQueue sharedInstance].decodedFrameObserver = nil;
        _pictureInPicture.feedsEveryFrame = NO;
        _systemPresenter.paused = NO;
    }

    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
}

// This fires when the home button is pressed
- (void)applicationDidEnterBackground:(UIApplication *)application {
    if (!StreamEndsOnBackground(_pictureInPicture.active)) {
        Log(LOG_I, @"In the background with picture in picture: the stream goes on");
        return;
    }
    Log(LOG_I, @"Terminating stream immediately for backgrounding");

    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    
    [self returnToMainFrame];
}

- (void)edgeSwiped {
    Log(LOG_I, @"User swiped to end stream");
    
    [self returnToMainFrame];
}

- (void)topSwiped {
    Log(LOG_I, @"User swiped/cicked down for stats");
    [self showStats];

#if !TARGET_OS_TV
    _topSwipeRecognizer.enabled = FALSE;
    _topSwipeUpRecognizer.enabled = TRUE;
#endif
}

- (void)showStats {
#if !TARGET_OS_TV
    _streamControls.statsShown = YES;
#endif
    if (self->_statsUpdateTimer == nil) {
        self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                   target:self
                                                                 selector:@selector(updateStatsOverlay)
                                                                 userInfo:nil
                                                                  repeats:YES];
        [self->_statsUpdateTimer fire];

        if (_settings.enableGraphs) {
            [self.imguiView start];
            [self.imguiView show];
        }
    }
}

- (void)topSwipedUp {
    Log(LOG_I, @"User swiped up to hide stats");
    [self hideStats];

#if !TARGET_OS_TV
    _topSwipeRecognizer.enabled = TRUE;
    _topSwipeUpRecognizer.enabled = FALSE;
#endif
}

- (void)hideStats {
#if !TARGET_OS_TV
    _streamControls.statsShown = NO;
#endif
    if (self->_statsUpdateTimer != nil) {
        [_statsUpdateTimer invalidate];
        _statsUpdateTimer = nil;
    }

    if (_overlayView != nil) {
        [_overlayView setHidden:YES];
    }

    if (_settings.enableGraphs) {
        [self.imguiView hide];
        [self.imguiView stop];
    }
}

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    // The microphone to the PC's receiver, if the settings ask for it (Starwire)
    [StarwireMicrophone.shared streamStarted];
    dispatch_async(dispatch_get_main_queue(), ^{
        // The user may have left while it was connecting (daniel-zn's Artemis iOS guards this too)
        if (self->_alertGate.exiting) {
            return;
        }
        // Leave the spinner spinning until it's obscured by
        // the first frame of video.
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
        
        [self->_streamView showOnScreenControls];
#if !TARGET_OS_TV
        [self->_streamControls streamStartedWithHostFeatureFlags:LiGetHostFeatureFlags()
                                                         pcUUID:nil
                                                           host:self.streamConfig.host
                                                          appID:[self.streamConfig.appID integerValue]];
#endif
        
        [self->_controllerSupport connectionEstablished];
        
        if (self->_settings.statsOverlay) {
            [self topSwiped];
        }
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);
#if !TARGET_OS_TV
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_streamControls.input connectionLostWithErrorCode:errorCode];
    });
#endif
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = @"Connection Error";
            message = @"Your device's network connection is blocking Moonlight. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = @"Connection Error";
                    message = @"No video received from host.";
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = @"Connection Error";
                    message = @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection.";
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = @"Connection Error";
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = @"Connection Error";
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    if (abs(errorCode) > 1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    
                    title = @"Connection Terminated";
                    message = [NSString stringWithFormat: @"The connection was terminated\n\nError code: %@", errorString];
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:conTermAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentStreamAlert:conTermAlert];
    });

    [_streamMan stopStream];
}

// The view controller that is on top, so the alert never asks a controller that is already
// presenting something to present again
- (UIViewController *)topPresenter {
    UIViewController *top = self.view.window.rootViewController ?: self;
    while (top.presentedViewController != nil && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    return top;
}

// Every stream error alert goes through here. One failure can report itself twice (a stage
// failing, then the connection terminating), which showed two alerts at once: the second one is
// only logged.
#pragma mark - Vibeshine: confirmation and the bitrate

// Called on the launch thread, which waits here for the answer
- (BOOL) launchNeedsConfirmation:(NSString*)message {
    dispatch_semaphore_t answered = dispatch_semaphore_create(0);
    __block BOOL confirmed = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:self.streamConfig.appName
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction* action) {
            dispatch_semaphore_signal(answered);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
            confirmed = YES;
            dispatch_semaphore_signal(answered);
        }]];
        [[self topPresenter] presentViewController:alert animated:YES completion:nil];
    });
    dispatch_semaphore_wait(answered, DISPATCH_TIME_FOREVER);
    return confirmed;
}

- (void) launchFinished:(NSString*)message {
    Log(LOG_I, @"Launch finished without a stream: %@", message);
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        if (message.length == 0) {
            [self returnToMainFrame];
            return;
        }
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:self.streamConfig.appName
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentStreamAlert:alert];
    });
}

#if !TARGET_OS_TV
// The stream menu's Bitrate tile (Android's choices); the PC may lower what is asked for
- (void)showBitrateMenu:(id)sender {
    if (_hostActions == nil) {
        [self showToast:@"This PC can't change the bitrate during a stream."];
        return;
    }
    UIAlertController* menu = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Bitrate (now %d Mbps)", _bitrateKbps / 1000]
                                                                  message:@"The PC may lower it."
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber* mbps in [StarwireStreamControls bitrateChoicesMbps]) {
        int kbps = mbps.intValue * 1000;
        NSString* title = [NSString stringWithFormat:@"%@ Mbps%@", mbps, kbps == _bitrateKbps ? @" (now)" : @""];
        [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
            [self changeBitrate:kbps];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.view;
    menu.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMaxX(self.view.bounds) - 240, CGRectGetMidY(self.view.bounds), 1, 1);
    [[self topPresenter] presentViewController:menu animated:YES completion:nil];
}

- (void)changeBitrate:(int)kbps {
    [_hostActions setBitrate:kbps completion:^(NSInteger applied, NSString* error) {
        if (applied > 0) {
            Log(LOG_I, @"Bitrate changed during the stream: %d kbps asked, %ld applied", kbps, (long)applied);
            self->_bitrateKbps = (int)applied;
#if !TARGET_OS_TV
            self->_streamControls.bitrateText = [NSString stringWithFormat:@"%ld Mbps", (long)applied / 1000];
#endif
            [self showToast:[NSString stringWithFormat:@"Bitrate set to %ld Mbps", (long)applied / 1000]];
        } else {
            Log(LOG_W, @"Bitrate change refused: %@", error);
            [self showToast:[NSString stringWithFormat:@"Couldn't change bitrate: %@", error ?: @""]];
        }
    }];
}

// A short message above the stream that fades by itself
- (void)showToast:(NSString*)text {
    PaddedLabel* toast = [[PaddedLabel alloc] initWithFrame:CGRectZero];
    [toast setTextInsets:UIEdgeInsetsMake(8, 14, 8, 14)];
    toast.text = text;
    toast.accessibilityIdentifier = @"StreamToast";
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    toast.layer.cornerRadius = 10;
    toast.layer.masksToBounds = YES;
    [toast sizeToFit];
    toast.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height - 60);
    [self.view addSubview:toast];
    [UIView animateWithDuration:0.4 delay:4 options:0 animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}
#endif

- (void)presentStreamAlert:(UIAlertController *)alert {
    if (![_alertGate shouldPresentAlertWithTitle:alert.title ?: @""]) {
        Log(LOG_W, @"Not showing a second stream alert: %@: %@", alert.title, alert.message);
        return;
    }
    _presentedAlert = alert;
    [[self topPresenter] presentViewController:alert animated:YES completion:nil];
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* lowerCase = [NSString stringWithFormat:@"%s in progress...", stageName];
        NSString* titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_stageLabel setText:titleCase];
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
    });
}

- (void) stageComplete:(const char*)stageName {
}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:@"\n\nYour device's network connection is blocking Moonlight. Streaming may not work while connected to this network."];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentStreamAlert:alert];
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentStreamAlert:alert];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    Log(LOG_D, @"Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor);
    
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Log(LOG_D, @"Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger);
    
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Log(LOG_I, @"Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz);
    
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Log(LOG_I, @"Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b);
    
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);

    // The stats overlay takes precedence over these warnings
    if (_statsUpdateTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:@"Slow connection to PC\nReduce your bitrate"];
                }
                else {
                    [self updateOverlayText:@"Poor connection to PC"];
                }
                break;
        }
    });
}

- (void)applicationDidFinishSwitchingModes:(NSNotification *)notification {
#if TARGET_OS_TV
    // Check the current refresh rate of the TV for a fractional NTSC rate such as 59.94
    UIScreen *screen = [UIScreen mainScreen];

    // XXX: I can see screen.currentMode.refreshRate in the debugger, but don't know how to access it :(

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVDisplayManagerModeSwitchEndNotification
                                                  object:nil];
#endif
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
        AVDisplayManager* displayManager = [window avDisplayManager];

        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(applicationDidFinishSwitchingModes:)
                                                     name: AVDisplayManagerModeSwitchEndNotification
                                                   object: nil];

        // This logic comes from Kodi and MrMC
        if (streamActive) {
            int dynamicRange;
            
            if (LiGetCurrentHostDisplayHdrMode()) {
                dynamicRange = 2; // HDR10
            }
            else {
                dynamicRange = 0; // SDR
            }

            float refreshRate = [_settings.framerate floatValue];
            Log(LOG_I, @"Changing TV refresh rate to %f Hz %@", refreshRate, dynamicRange == 2 ? @"HDR" : @"SDR");
            AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:refreshRate
                                                                              videoDynamicRange:dynamicRange];
            displayManager.preferredDisplayCriteria = displayCriteria;
        }
        else {
            // Switch back to the default display mode
            displayManager.preferredDisplayCriteria = nil;
        }
    }
#endif
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
    [_spinner stopAnimating];
    [self.view setBackgroundColor:[UIColor blackColor]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)gamepadPresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)mousePresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
#endif
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self returnToMainFrame];
}

- (void)userInteractionBegan {
    // Disable hiding home bar when user is interacting.
    // iOS will force it to be shown anyway, but it will
    // also discard our edges deferring system gestures unless
    // we willingly give up home bar hiding preference.
    _userIsInteracting = YES;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

#if !TARGET_OS_TV
// Require a confirmation when streaming to activate a system gesture
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    if ([_controllerSupport getConnectedGamepadCount] > 0 &&
        [_streamView getCurrentOscState] == OnScreenControlsLevelOff &&
        _userIsInteracting == NO) {
        // Autohide the home bar when a gamepad is connected
        // and the on-screen controls are disabled. We can't
        // do this all the time because any touch on the display
        // will cause the home indicator to reappear, and our
        // preferredScreenEdgesDeferringSystemGestures will also
        // be suppressed (leading to possible errant exits of the
        // stream).
        return YES;
    }
    
    return NO;
}

- (BOOL)prefersPointerLocked {
    // Pointer lock breaks the UIKit mouse APIs, which is a problem because
    // GCMouse is horribly broken on iOS 14.0 for certain mice. Only lock
    // the cursor if there is a GCMouse present.
    return [GCMouse mice].count > 0;
}
#endif

@end
