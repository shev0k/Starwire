//
//  SceneDelegate.m
//  Starwire
//

#import "SceneDelegate.h"
#import "AppDelegate.h"
#import "Moonlight-Swift.h"

#if !TARGET_OS_TV
@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    AppDelegate* appDelegate = (AppDelegate*)UIApplication.sharedApplication.delegate;

    // A Home Screen quick action that launched the app (was in the launch options)
    UIApplicationShortcutItem* shortcut = connectionOptions.shortcutItem;
    if (shortcut != nil) {
        appDelegate.pcUuidToLoad = (NSString*)[shortcut.userInfo objectForKey:@"UUID"];
    }

    // The same storyboards UIMainStoryboardFile and UIMainStoryboardFile~ipad named
    NSString* storyboardName = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone";
    UIStoryboard* storyboard = [UIStoryboard storyboardWithName:storyboardName bundle:nil];

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene*)scene];
    // The demo mode (iOS Settings) shows StarwireKit's fakes instead of the PC list
    self.window.rootViewController = StarwireSettings.demoModeEnabled
        ? [StarwireDemo makeViewController]
        : [storyboard instantiateInitialViewController];
    appDelegate.window = self.window;
    [self.window makeKeyAndVisible];
}

- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler {
    [(AppDelegate*)UIApplication.sharedApplication.delegate application:UIApplication.sharedApplication
                                           performActionForShortcutItem:shortcutItem
                                                      completionHandler:completionHandler];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    // The app delegate's background callbacks don't run with scenes, so save here
    [(AppDelegate*)UIApplication.sharedApplication.delegate saveContext];
}

@end
#endif
