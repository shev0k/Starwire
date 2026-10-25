//
//  ExternalDisplay.m
//  Starwire
//

#import "ExternalDisplay.h"
#import "Logger.h"

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_VIDEO

NSString *const ExternalDisplayKey = @"StarwireExternalDisplay";
NSNotificationName const ExternalDisplayDidChangeNotification = @"StarwireExternalDisplayDidChange";

static UIWindow *sVideoWindow;

ExternalDisplayMode ExternalDisplayModeFromDefaults(NSUserDefaults *defaults) {
    return [[defaults stringForKey:ExternalDisplayKey] isEqualToString:@"video"] ? ExternalDisplayModeVideo : ExternalDisplayModeMirror;
}

BOOL ExternalDisplayShowsVideo(ExternalDisplayMode mode, BOOL displayConnected) {
    return displayConnected && mode == ExternalDisplayModeVideo;
}

@implementation ExternalDisplay

+ (UIWindow *)videoWindow {
    return sVideoWindow;
}

@end

@implementation ExternalDisplaySceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    CGSize size = windowScene.screen.bounds.size;
    ExternalDisplayMode mode = ExternalDisplayModeFromDefaults([NSUserDefaults standardUserDefaults]);
    Log(LOG_I, @"External display connected: %.0fx%.0f points, %@", size.width, size.height,
        mode == ExternalDisplayModeVideo ? @"video goes there during a stream" : @"mirroring");
    if (!ExternalDisplayShowsVideo(mode, YES)) {
        // No window: iOS mirrors the device
        return;
    }

    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = UIColor.blackColor;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = root;
    self.window.hidden = NO;
    sVideoWindow = self.window;
    [[NSNotificationCenter defaultCenter] postNotificationName:ExternalDisplayDidChangeNotification object:nil];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    Log(LOG_I, @"External display disconnected");
    if (sVideoWindow == self.window) {
        sVideoWindow = nil;
    }
    self.window = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:ExternalDisplayDidChangeNotification object:nil];
}

@end
