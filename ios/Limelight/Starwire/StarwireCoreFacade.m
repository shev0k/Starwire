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

+ (void)mousePositionX:(short)x y:(short)y width:(short)width height:(short)height {
    LiSendMousePositionEvent(x, y, width, height);
}

+ (void)mouseMoveAsPositionX:(short)dx y:(short)dy width:(short)width height:(short)height {
    LiSendMouseMoveAsMousePositionEvent(dx, dy, width, height);
}

+ (void)mouseButton:(int)button down:(BOOL)down {
    LiSendMouseButtonEvent(down ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, button);
}

+ (void)scroll:(short)amount {
    LiSendHighResScrollEvent(amount);
}

+ (void)hScroll:(short)amount {
    LiSendHighResHScrollEvent(amount);
}

+ (void)key:(short)code down:(BOOL)down modifiers:(char)modifiers flags:(char)flags {
    LiSendKeyboardEvent2(code, down ? KEY_ACTION_DOWN : KEY_ACTION_UP, modifiers, flags);
}

+ (void)text:(NSString *)text {
    const char *utf8 = text.UTF8String;
    if (utf8 != NULL && utf8[0] != 0) {
        LiSendUtf8TextEvent(utf8, (unsigned int)strlen(utf8));
    }
}

+ (void)touchType:(uint8_t)type pointerID:(uint32_t)pointerID x:(float)x y:(float)y pressure:(float)pressure
     contactMajor:(float)contactMajor contactMinor:(float)contactMinor rotation:(uint16_t)rotation {
    LiSendTouchEvent(type, pointerID, x, y, pressure, contactMajor, contactMinor, rotation);
}

+ (void)penType:(uint8_t)type tool:(uint8_t)tool buttons:(uint8_t)buttons x:(float)x y:(float)y pressure:(float)pressure
       rotation:(uint16_t)rotation tilt:(uint8_t)tilt {
    LiSendPenEvent(type, tool, buttons, x, y, pressure, 0, 0, rotation, tilt);
}

+ (void)controller:(short)number activeMask:(short)activeMask buttons:(int)buttons leftTrigger:(unsigned char)leftTrigger
      rightTrigger:(unsigned char)rightTrigger leftX:(short)leftX leftY:(short)leftY rightX:(short)rightX rightY:(short)rightY {
    LiSendMultiControllerEvent(number, activeMask, buttons, leftTrigger, rightTrigger, leftX, leftY, rightX, rightY);
}

+ (void)controllerArrival:(uint8_t)number activeMask:(uint16_t)activeMask type:(uint8_t)type buttons:(uint32_t)buttons
             capabilities:(uint16_t)capabilities {
    LiSendControllerArrivalEvent(number, activeMask, type, buttons, capabilities);
}

+ (void)controllerMotion:(uint8_t)number sensor:(uint8_t)sensor x:(float)x y:(float)y z:(float)z {
    LiSendControllerMotionEvent(number, sensor, x, y, z);
}

+ (void)controllerBattery:(uint8_t)number state:(uint8_t)state percent:(uint8_t)percent {
    LiSendControllerBatteryEvent(number, state, percent);
}

+ (void)controllerTouch:(uint8_t)number type:(uint8_t)type pointerID:(uint32_t)pointerID x:(float)x y:(float)y pressure:(float)pressure {
    LiSendControllerTouchEvent(number, type, pointerID, x, y, pressure);
}

@end
