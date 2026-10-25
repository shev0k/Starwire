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

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene*)scene];
    // The SwiftUI app (phase 3). Upstream's storyboards stay in the tree, unused. The demo mode
    // shows StarwireKit's demo PC instead of the real ones.
    self.window.rootViewController = [StarwireAppUI makeRootViewController];
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
