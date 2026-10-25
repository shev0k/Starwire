//
//  ExternalDisplay.h
//  Starwire
//
//  A display plugged into the iPad or iPhone (USB-C, an adapter or AirPlay). By default iOS
//  mirrors the device as it always has. With "External display" set to "Video on the display" in
//  iOS Settings, the stream's video moves to the external display while the device keeps the
//  touch surface and the controls, as VoidLink's AirPlay mode does (SceneDelegate.m, by The Fried
//  Fish). On iPadOS with Stage Manager the display can also be an extended desktop, where the app
//  is a window like any other; that needs nothing from the app.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ExternalDisplayMode) {
    // iOS mirrors the screen
    ExternalDisplayModeMirror = 0,
    // The stream's video on the external display, the controls on the device
    ExternalDisplayModeVideo = 1,
};

// The user default and launch argument: "mirror" or "video"
extern NSString *const ExternalDisplayKey;
ExternalDisplayMode ExternalDisplayModeFromDefaults(NSUserDefaults *defaults);
// Whether the video should be on the external display
BOOL ExternalDisplayShowsVideo(ExternalDisplayMode mode, BOOL displayConnected);

// Posted on the main thread when an external display window comes or goes
extern NSNotificationName const ExternalDisplayDidChangeNotification;

@interface ExternalDisplay : NSObject
// The external display's window, while one is connected and the mode is video
@property (class, nonatomic, readonly, nullable) UIWindow *videoWindow;
@end

// The scene delegate for the external display role (Info.plist)
@interface ExternalDisplaySceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic, nullable) UIWindow *window;
@end

NS_ASSUME_NONNULL_END
