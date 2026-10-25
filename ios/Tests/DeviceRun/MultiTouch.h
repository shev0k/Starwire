//
//  MultiTouch.h
//  Starwire
//
//  Several fingers at once for the device tests: XCTest's public API has one-finger drags and
//  multi-finger taps only. This drives XCTest's own event synthesiser (XCSynthesizedEventRecord
//  and XCPointerEventPath, looked up by name at run time since they aren't public).
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface StarwireMultiTouch : NSObject

/// Fingers that land together at `starts`, move in a straight line by `offset` over `duration`
/// seconds in `steps` steps, and lift. Points are in the screen's coordinates for `orientation`.
/// Returns NO with the reason in `error` when the synthesiser isn't there.
+ (BOOL)dragFingers:(NSArray<NSValue *> *)starts
                 by:(CGVector)offset
           duration:(NSTimeInterval)duration
              steps:(NSInteger)steps
        orientation:(UIInterfaceOrientation)orientation
              error:(NSError **)error;

/// Fingers that land and lift together, for `hold` seconds.
+ (BOOL)tapFingers:(NSArray<NSValue *> *)points
              hold:(NSTimeInterval)hold
       orientation:(UIInterfaceOrientation)orientation
             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
