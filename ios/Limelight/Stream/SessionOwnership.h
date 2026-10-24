//
//  SessionOwnership.h
//  Starwire
//
//  moonlight-common-c has one global connection, and Connection.m keeps the renderer and the
//  callbacks in statics. This records which stream session owns them, so a session that is still
//  stopping can't stop or call into the next one, and a session stopped before it started never
//  starts. Built on daniel-zn's race fixes in Artemis iOS (commit 696ffae), which set and cleared
//  the statics per connection.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SessionOwnership : NSObject

// The session was stopped. If it hasn't begun, it never will.
- (void)cancel:(id)session;
// Makes the session the owner. Returns NO, and changes nothing, if it was cancelled first.
- (BOOL)begin:(id)session;
- (BOOL)isCurrent:(id)session;
// Returns YES and clears the owner if the session is the owner. A late call from an older
// session returns NO and leaves the newer owner alone.
- (BOOL)endIfCurrent:(id)session;

@end

NS_ASSUME_NONNULL_END
