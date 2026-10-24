//
//  StreamAlertGate.m
//  Starwire
//

#import "StreamAlertGate.h"

@implementation StreamAlertGate {
    BOOL _shown;
    BOOL _exiting;
    NSMutableArray<NSString *> *_suppressed;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _suppressed = [NSMutableArray array];
    }
    return self;
}

- (void)markExiting {
    @synchronized(self) {
        _exiting = YES;
    }
}

- (BOOL)exiting {
    @synchronized(self) {
        return _exiting;
    }
}

- (BOOL)shouldPresentAlertWithTitle:(NSString *)title {
    @synchronized(self) {
        if (_exiting || _shown) {
            [_suppressed addObject:title];
            return NO;
        }
        _shown = YES;
        return YES;
    }
}

- (NSArray<NSString *> *)suppressedTitles {
    @synchronized(self) {
        return [_suppressed copy];
    }
}

@end
