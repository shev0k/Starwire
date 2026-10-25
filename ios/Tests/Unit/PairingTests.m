//
//  PairingTests.m
//  Starwire
//
//  How the poll treats a PC's answers (DiscoveryWorker with StarwirePairState): a pinned PC that
//  answers only over plain HTTP keeps its pairing for 30 seconds, a poll never forgets the MAC,
//  and a PC that mDNS finds again is polled as the saved PC. Time comes from a fake clock and
//  nothing is sent: only answers that need no second request are used.
//

#import <XCTest/XCTest.h>

#import "DiscoveryManager.h"
#import "DiscoveryWorker.h"
#import "HttpManager.h"
#import "ServerInfoResponse.h"
#import "Moonlight-Swift.h"

@interface PairingTests : XCTestCase
@end

@implementation PairingTests

- (void)setUp {
    [StarwirePairState useFakeClock];
}

- (void)tearDown {
    [StarwirePairState useSystemClock];
}

static NSString *const PCUUID = @"6B1C3A4E-0000-4000-8000-00000000F1C5";

- (ServerInfoResponse *)answerPaired:(BOOL)paired authenticated:(BOOL)authenticated mac:(NSString *)mac {
    NSString *xml = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"utf-8\"?><root status_code=\"200\">"
                     "<hostname>Gaming PC</hostname><uniqueid>%@</uniqueid><HttpsPort>47984</HttpsPort>"
                     "<mac>%@</mac><LocalIP>192.0.2.10</LocalIP><PairStatus>%d</PairStatus><currentgame>0</currentgame>"
                     "<state>SUNSHINE_SERVER_FREE</state></root>", PCUUID, mac, paired ? 1 : 0];
    ServerInfoResponse *response = [[ServerInfoResponse alloc] init];
    [response populateWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    response.authenticated = authenticated;
    return response;
}

- (TemporaryHost *)pairedHost {
    TemporaryHost *host = [[TemporaryHost alloc] init];
    host.name = @"Gaming PC";
    host.uuid = PCUUID;
    host.serverCert = [@"pinned certificate bytes" dataUsingEncoding:NSUTF8StringEncoding];
    host.httpsPort = 47984;
    host.pairState = PairStatePaired;
    host.mac = @"00:00:5E:00:53:01";
    return host;
}

- (void)testAPlainHTTPAnswerDoesNotUnpairAPinnedPCAtOnce {
    TemporaryHost *host = [self pairedHost];
    DiscoveryWorker *worker = [[DiscoveryWorker alloc] initWithHost:host uniqueId:@"0123456789ABCDEF"];
    ServerInfoResponse *refusal = [self answerPaired:NO authenticated:NO mac:@"00:00:00:00:00:00"];

    XCTAssertEqual([worker acceptResponse:refusal atAddress:@"192.0.2.10"], DiscoveryAnswerRefused);
    XCTAssertEqual(host.pairState, PairStatePaired);
    XCTAssertNotNil(host.refusedSince);

    [StarwirePairState advanceFakeClock:29];
    XCTAssertEqual([worker acceptResponse:refusal atAddress:@"192.0.2.10"], DiscoveryAnswerRefused);
    XCTAssertEqual(host.pairState, PairStatePaired);

    [StarwirePairState advanceFakeClock:1];
    XCTAssertEqual([worker acceptResponse:refusal atAddress:@"192.0.2.10"], DiscoveryAnswerAccepted);
    XCTAssertEqual(host.pairState, PairStateUnpaired, @"30 seconds of refusals: the PC no longer knows it");
}

- (void)testAnAuthenticatedAnswerEndsTheGrace {
    TemporaryHost *host = [self pairedHost];
    DiscoveryWorker *worker = [[DiscoveryWorker alloc] initWithHost:host uniqueId:@"0123456789ABCDEF"];
    [worker acceptResponse:[self answerPaired:NO authenticated:NO mac:@"00:00:00:00:00:00"] atAddress:@"192.0.2.10"];
    XCTAssertEqual([worker acceptResponse:[self answerPaired:YES authenticated:YES mac:@"00:00:5e:00:53:01"] atAddress:@"192.0.2.10"],
                   DiscoveryAnswerAccepted);
    XCTAssertNil(host.refusedSince);
    XCTAssertEqual(host.pairState, PairStatePaired);
}

- (void)testAnUnpinnedPCIsTakenAtItsWord {
    TemporaryHost *host = [self pairedHost];
    host.serverCert = nil;
    host.pairState = PairStateUnknown;
    DiscoveryWorker *worker = [[DiscoveryWorker alloc] initWithHost:host uniqueId:@"0123456789ABCDEF"];
    XCTAssertEqual([worker acceptResponse:[self answerPaired:NO authenticated:NO mac:@"00:00:00:00:00:00"] atAddress:@"192.0.2.10"],
                   DiscoveryAnswerAccepted);
    XCTAssertEqual(host.pairState, PairStateUnpaired);
}

- (void)testAnotherPCsAnswerIsNotTaken {
    TemporaryHost *host = [self pairedHost];
    host.uuid = @"00000000-0000-4000-8000-000000000000";
    DiscoveryWorker *worker = [[DiscoveryWorker alloc] initWithHost:host uniqueId:@"0123456789ABCDEF"];
    XCTAssertEqual([worker acceptResponse:[self answerPaired:YES authenticated:YES mac:@"00:00:5e:00:53:01"] atAddress:@"192.0.2.10"],
                   DiscoveryAnswerNone);
}

- (void)testAPollWithoutTheMacKeepsTheKnownOne {
    TemporaryHost *host = [self pairedHost];
    [[self answerPaired:NO authenticated:NO mac:@"00:00:00:00:00:00"] populateHost:host];
    XCTAssertEqualObjects(host.mac, @"00:00:5E:00:53:01");
    [[self answerPaired:YES authenticated:YES mac:@"00:00:5e:00:53:02"] populateHost:host];
    XCTAssertEqualObjects(host.mac, @"00:00:5E:00:53:02");
}

- (void)testAPCFoundByMDNSIsPolledAsTheSavedPC {
    TemporaryHost *saved = [self pairedHost];
    saved.localAddress = @"192.0.2.10:47989";
    TemporaryHost *found = [[TemporaryHost alloc] init];
    found.address = @"192.0.2.10";

    XCTAssertTrue([DiscoveryManager takeSavedPairingFrom:@[ saved ] into:found]);
    XCTAssertEqualObjects(found.serverCert, saved.serverCert);
    XCTAssertEqualObjects(found.uuid, PCUUID);
    XCTAssertEqual(found.httpsPort, 47984);
    XCTAssertEqual(found.pairState, PairStatePaired);

    // So its poll goes over HTTPS with the pinned certificate
    HttpManager *hMan = [DiscoveryWorker serverInfoManagerForAddress:found.address host:found];
    XCTAssertEqualObjects([hMan newServerInfoRequest:true].URL.scheme, @"https");
}

- (void)testAnUnknownPCFoundByMDNSIsLeftAlone {
    TemporaryHost *saved = [self pairedHost];
    saved.localAddress = @"192.0.2.10:47989";
    TemporaryHost *found = [[TemporaryHost alloc] init];
    found.address = @"192.0.2.99";
    XCTAssertFalse([DiscoveryManager takeSavedPairingFrom:@[ saved ] into:found]);
    XCTAssertNil(found.serverCert);
}

- (void)testControlTilesAndTheConfirmationStep {
    XCTAssertTrue([StarwireLaunchFlow isControlTile:@"2147483504"]);
    XCTAssertTrue([StarwireLaunchFlow isControlTile:@"2147483506"]);
    XCTAssertFalse([StarwireLaunchFlow isControlTile:@"707688810"]);

    StarwireLaunchFlow *flow = [[StarwireLaunchFlow alloc] init];
    NSString *ask = @"This will close the active stream but leave Remote Monitor and Remote Input connected. Launch Terminate again within 60 seconds to confirm this was intentional.";
    XCTAssertEqual([flow nextWithStatusCode:410 message:ask], StarwireLaunchStepAsk);
    XCTAssertEqual([flow nextWithStatusCode:410 message:@"Active stream terminated. Remote Monitor and Remote Input remain connected."],
                   StarwireLaunchStepFinished);
    XCTAssertEqual([[[StarwireLaunchFlow alloc] init] nextWithStatusCode:200 message:nil], StarwireLaunchStepStart);
    XCTAssertEqual([[[StarwireLaunchFlow alloc] init] nextWithStatusCode:503 message:@"busy"], StarwireLaunchStepFailed);
}

@end
