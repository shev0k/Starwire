//
//  DiscoveryManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/1/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "MDNSManager.h"
#import "TemporaryHost.h"

@protocol DiscoveryCallback <NSObject>

- (void) updateAllHosts:(NSArray*)hosts;

@end

@interface DiscoveryManager : NSObject <MDNSCallback>

- (id) initWithHosts:(NSArray*)hosts andCallback:(id<DiscoveryCallback>) callback;
- (void) startDiscovery;
- (void) stopDiscovery;
- (void) stopDiscoveryBlocking;
- (void) resetDiscoveryState;
- (BOOL) addHostToDiscovery:(TemporaryHost*)host;
- (void) removeHostFromDiscovery:(TemporaryHost*)host;
- (void) pauseDiscoveryForHost:(TemporaryHost *)host;
- (void) resumeDiscoveryForHost:(TemporaryHost *)host;
- (void) discoverHost:(NSString*)hostAddress withCallback:(void (^)(TemporaryHost*, NSString*))callback;

// For a PC mDNS found: if it is a saved, paired PC at one of the same addresses, copy that PC's
// pinned certificate, HTTPS port, UUID, pair state and MAC, so it is polled over HTTPS
+ (BOOL) takeSavedPairingFrom:(NSArray<TemporaryHost*>*)savedHosts into:(TemporaryHost*)found;

@end
