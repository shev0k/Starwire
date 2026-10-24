//
//  SceneDelegate.h
//  Starwire
//
//  The UIScene lifecycle, which iOS says it will soon require. Based on the scene part of
//  upstream moonlight-ios pull request #729 by antoinealbaut23. tvOS keeps the app lifecycle.
//

#import <UIKit/UIKit.h>

#if !TARGET_OS_TV
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow *window;

@end
#endif
