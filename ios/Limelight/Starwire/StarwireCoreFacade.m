//
//  StarwireCoreFacade.m
//  Starwire
//

#import "StarwireCoreFacade.h"
#import "PairManager.h"
#import "HttpManager.h"
#import "CryptoManager.h"
#import "StreamManager.h"
#import "StreamConfiguration.h"

#include <Limelight.h>

#pragma mark - Pairing

@interface StarwirePairingCallback : NSObject <PairCallback>
@property (nonatomic, copy) void (^showPIN)(NSString *pin);
@property (nonatomic, copy) void (^completion)(NSData *_Nullable serverCertificate, BOOL alreadyPaired, NSString *_Nullable error);
@end

@implementation StarwirePairingCallback

- (void)startPairing:(NSString *)PIN {
    dispatch_async(dispatch_get_main_queue(), ^{ self.showPIN(PIN); });
}

- (void)pairSuccessful:(NSData *)serverCert {
    dispatch_async(dispatch_get_main_queue(), ^{ self.completion(serverCert, NO, nil); });
}

- (void)pairFailed:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{ self.completion(nil, NO, message ?: @"Pairing failed"); });
}

- (void)alreadyPaired {
    dispatch_async(dispatch_get_main_queue(), ^{ self.completion(nil, YES, nil); });
}

@end

@implementation StarwirePairingFacade

+ (void)pairWithAddress:(NSString *)address
              httpsPort:(unsigned short)httpsPort
                showPIN:(void (^)(NSString *))showPIN
             completion:(void (^)(NSData *_Nullable, BOOL, NSString *_Nullable))completion {
    [CryptoManager generateKeyPairUsingSSL];
    StarwirePairingCallback *callback = [[StarwirePairingCallback alloc] init];
    callback.showPIN = showPIN;
    callback.completion = completion;
    HttpManager *http = [[HttpManager alloc] initWithAddress:address httpsPort:httpsPort serverCert:nil];
    PairManager *pairing = [[PairManager alloc] initWithManager:http clientCert:[CryptoManager readCertFromFile] callback:callback];
    // The operation keeps the callback until it finishes
    [[[NSOperationQueue alloc] init] addOperation:pairing];
}

@end

#pragma mark - Stream

@interface StarwireStreamFacade () <ConnectionCallbacks>
@end

@implementation StarwireStreamFacade {
    StreamConfiguration *_config;
    UIView *_renderView;
    StreamManager *_manager;
}

- (instancetype)initWithConfiguration:(NSObject *)streamConfiguration renderView:(UIView *)renderView {
    self = [super init];
    NSAssert([streamConfiguration isKindOfClass:[StreamConfiguration class]], @"a StreamConfiguration");
    _config = (StreamConfiguration *)streamConfiguration;
    _renderView = renderView;
    return self;
}

- (void)start {
    _manager = [[StreamManager alloc] initWithConfig:_config renderView:_renderView connectionCallbacks:self];
    [[[NSOperationQueue alloc] init] addOperation:_manager];
}

- (void)stop {
    [_manager stopStream];
}

- (void)onMain:(void (^)(void))block {
    dispatch_async(dispatch_get_main_queue(), block);
}

- (void)connectionStarted {
    [self onMain:^{ if (self.onStarted) self.onStarted(); }];
}

- (void)connectionTerminated:(int)errorCode {
    NSString *error = errorCode == 0 ? nil : [NSString stringWithFormat:@"The connection ended (error %d)", errorCode];
    [self onMain:^{ if (self.onEnded) self.onEnded(error); }];
}

- (void)stageStarting:(const char *)stageName {
    NSString *stage = [NSString stringWithUTF8String:stageName];
    [self onMain:^{ if (self.onStage) self.onStage(stage); }];
}

- (void)stageComplete:(const char *)stageName {
}

- (void)stageFailed:(const char *)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    NSString *error = [NSString stringWithFormat:@"%s failed (error %d)", stageName, errorCode];
    [self onMain:^{ if (self.onEnded) self.onEnded(error); }];
}

- (void)launchFailed:(NSString *)message {
    [self onMain:^{ if (self.onEnded) self.onEnded(message ?: @"The PC didn't start the app"); }];
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
}

- (void)rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
}

- (void)setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
}

- (void)setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
}

- (void)connectionStatusUpdate:(int)status {
}

- (void)setHdrMode:(bool)enabled {
}

- (void)videoContentShown {
}

@end

#pragma mark - Input

@implementation StarwireInputFacade

+ (void)mouseMoveX:(short)dx y:(short)dy {
    LiSendMouseMoveEvent(dx, dy);
}

+ (void)mouseButton:(int)button down:(BOOL)down {
    LiSendMouseButtonEvent(down ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, button);
}

+ (void)scroll:(short)amount {
    LiSendHighResScrollEvent(amount);
}

+ (void)key:(short)code down:(BOOL)down modifiers:(char)modifiers {
    LiSendKeyboardEvent(code, down ? KEY_ACTION_DOWN : KEY_ACTION_UP, modifiers);
}

+ (void)touchID:(uint32_t)pointerID phase:(int)phase x:(float)x y:(float)y {
    static const uint8_t types[] = { LI_TOUCH_EVENT_DOWN, LI_TOUCH_EVENT_MOVE, LI_TOUCH_EVENT_UP, LI_TOUCH_EVENT_CANCEL };
    if (phase < 0 || phase > 3) {
        return;
    }
    LiSendTouchEvent(types[phase], pointerID, x, y, 0, 0, 0, LI_ROT_UNKNOWN);
}

@end
