//
//  MultiTouch.m
//  Starwire
//

#import "MultiTouch.h"

// The selectors XCTest's synthesiser answers to (XCTest's private headers, Xcode 15 and later)
@protocol StarwirePointerPath
- (instancetype)initForTouchAtPoint:(CGPoint)point offset:(double)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(double)offset;
- (void)liftUpAtOffset:(double)offset;
@end

@protocol StarwireEventRecord
- (instancetype)initWithName:(NSString *)name interfaceOrientation:(UIInterfaceOrientation)orientation;
- (void)addPointerEventPath:(id)path;
- (BOOL)synthesizeWithError:(NSError **)error;
@end

@implementation StarwireMultiTouch

+ (BOOL)run:(NSArray<id<StarwirePointerPath>> *)paths name:(NSString *)name
orientation:(UIInterfaceOrientation)orientation error:(NSError **)error {
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    if (recordClass == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"StarwireMultiTouch" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"XCTest has no XCSynthesizedEventRecord"}];
        }
        return NO;
    }
    id<StarwireEventRecord> record = [(id<StarwireEventRecord>)[recordClass alloc] initWithName:name interfaceOrientation:orientation];
    for (id path in paths) {
        [record addPointerEventPath:path];
    }
    return [record synthesizeWithError:error];
}

+ (nullable id<StarwirePointerPath>)pathAt:(CGPoint)point error:(NSError **)error {
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (pathClass == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"StarwireMultiTouch" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"XCTest has no XCPointerEventPath"}];
        }
        return nil;
    }
    return [(id<StarwirePointerPath>)[pathClass alloc] initForTouchAtPoint:point offset:0];
}

+ (BOOL)dragFingers:(NSArray<NSValue *> *)starts by:(CGVector)offset duration:(NSTimeInterval)duration
              steps:(NSInteger)steps orientation:(UIInterfaceOrientation)orientation error:(NSError **)error {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSValue *value in starts) {
        CGPoint start = value.CGPointValue;
        id<StarwirePointerPath> path = [self pathAt:start error:error];
        if (path == nil) {
            return NO;
        }
        // A short pause on landing, then the move in even steps
        double begin = 0.05;
        for (NSInteger step = 1; step <= steps; step++) {
            double t = (double)step / steps;
            [path moveToPoint:CGPointMake(start.x + offset.dx * t, start.y + offset.dy * t) atOffset:begin + duration * t];
        }
        [path liftUpAtOffset:begin + duration + 0.02];
        [paths addObject:path];
    }
    return [self run:paths name:@"Starwire drag" orientation:orientation error:error];
}

+ (BOOL)tapFingers:(NSArray<NSValue *> *)points hold:(NSTimeInterval)hold
       orientation:(UIInterfaceOrientation)orientation error:(NSError **)error {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSValue *value in points) {
        id<StarwirePointerPath> path = [self pathAt:value.CGPointValue error:error];
        if (path == nil) {
            return NO;
        }
        [path liftUpAtOffset:hold];
        [paths addObject:path];
    }
    return [self run:paths name:@"Starwire tap" orientation:orientation error:error];
}

@end
