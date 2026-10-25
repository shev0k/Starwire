//
//  DiscoveryWorker.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/2/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "TemporaryHost.h"

@class HttpManager;
@class ServerInfoResponse;

typedef NS_ENUM(int, DiscoveryAnswer) {
    DiscoveryAnswerNone,      // no answer, or another PC's
    DiscoveryAnswerAccepted,
    DiscoveryAnswerRefused,   // a pinned PC answering only without authenticating, in the grace
};

@interface DiscoveryWorker : NSOperation

- (id) initWithHost:(TemporaryHost*)host uniqueId:(NSString*)uniqueId;
- (void) discoverHost;
- (TemporaryHost*) getHost;
// The HttpManager a poll of this address uses
+ (HttpManager*) serverInfoManagerForAddress:(NSString*)address host:(TemporaryHost*)host;
// What the poll does with one answer from this address: take it into the host, or not
- (DiscoveryAnswer) acceptResponse:(ServerInfoResponse*)response atAddress:(NSString*)address;

@end
