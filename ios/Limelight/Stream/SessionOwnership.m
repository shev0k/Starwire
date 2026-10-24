//
//  SessionOwnership.m
//  Starwire
//

#import "SessionOwnership.h"

@implementation SessionOwnership {
    // Weak, so a finished session isn't kept alive
    __weak id _current;
    NSHashTable *_cancelled;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cancelled = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (void)cancel:(id)session {
    @synchronized(self) {
        [_cancelled addObject:session];
    }
}

- (BOOL)begin:(id)session {
    @synchronized(self) {
        if ([_cancelled containsObject:session]) {
            return NO;
        }
        _current = session;
        return YES;
    }
}

- (BOOL)isCurrent:(id)session {
    @synchronized(self) {
        return _current != nil && _current == session;
    }
}

- (BOOL)endIfCurrent:(id)session {
    @synchronized(self) {
        if (_current == nil || _current != session) {
            return NO;
        }
        _current = nil;
        return YES;
    }
}

@end
