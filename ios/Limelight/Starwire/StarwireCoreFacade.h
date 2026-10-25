//
//  StarwireCoreFacade.h
//  Starwire
//
//  The ObjC core, through plain types only, for the real versions of StarwireKit's seams
//  (LivePairingService, LiveStreamSession, LiveInputSink in StarwireSeams.swift). This header is
//  in the Swift bridging header, so it imports nothing of the core's.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// PairManager: the PIN flow with one PC
@interface StarwirePairingFacade : NSObject

// showPIN gets the PIN to show while the PC waits for its owner to type it. The completion gets
// the PC's certificate to pin, or alreadyPaired, or the error. Both are called on the main queue.
+ (void)pairWithAddress:(NSString *)address
              httpsPort:(unsigned short)httpsPort
                showPIN:(void (^)(NSString *pin))showPIN
             completion:(void (^)(NSData *_Nullable serverCertificate, BOOL alreadyPaired, NSString *_Nullable error))completion;

@end

// StreamManager: one stream into a view, from a StreamConfiguration built by the caller
@interface StarwireStreamFacade : NSObject

- (instancetype)initWithConfiguration:(NSObject *)streamConfiguration renderView:(UIView *)renderView;

// Called on the main queue
@property (nonatomic, copy, nullable) void (^onStage)(NSString *stage);
@property (nonatomic, copy, nullable) void (^onStarted)(void);
@property (nonatomic, copy, nullable) void (^onEnded)(NSString *_Nullable error);

- (void)start;
- (void)stop;

@end

// moonlight-common-c's input calls, one for each InputEvent case in StarwireKit. They do nothing
// without a stream. Values are passed through as the library takes them.
@interface StarwireInputFacade : NSObject

+ (void)mouseMoveX:(short)dx y:(short)dy;
+ (void)mousePositionX:(short)x y:(short)y width:(short)width height:(short)height;
+ (void)mouseMoveAsPositionX:(short)dx y:(short)dy width:(short)width height:(short)height;
// button: 1 left, 2 middle, 3 right, 4 back, 5 forward
+ (void)mouseButton:(int)button down:(BOOL)down;
// 120 per notch
+ (void)scroll:(short)amount;
+ (void)hScroll:(short)amount;
+ (void)key:(short)code down:(BOOL)down modifiers:(char)modifiers flags:(char)flags;
+ (void)text:(NSString *)text;
// type: LI_TOUCH_EVENT_*. x and y from 0 to 1 across the video.
+ (void)touchType:(uint8_t)type pointerID:(uint32_t)pointerID x:(float)x y:(float)y pressure:(float)pressure
     contactMajor:(float)contactMajor contactMinor:(float)contactMinor rotation:(uint16_t)rotation;
+ (void)penType:(uint8_t)type tool:(uint8_t)tool buttons:(uint8_t)buttons x:(float)x y:(float)y pressure:(float)pressure
       rotation:(uint16_t)rotation tilt:(uint8_t)tilt;
+ (void)controller:(short)number activeMask:(short)activeMask buttons:(int)buttons leftTrigger:(unsigned char)leftTrigger
      rightTrigger:(unsigned char)rightTrigger leftX:(short)leftX leftY:(short)leftY rightX:(short)rightX rightY:(short)rightY;
+ (void)controllerArrival:(uint8_t)number activeMask:(uint16_t)activeMask type:(uint8_t)type buttons:(uint32_t)buttons
             capabilities:(uint16_t)capabilities;
+ (void)controllerMotion:(uint8_t)number sensor:(uint8_t)sensor x:(float)x y:(float)y z:(float)z;
+ (void)controllerBattery:(uint8_t)number state:(uint8_t)state percent:(uint8_t)percent;
+ (void)controllerTouch:(uint8_t)number type:(uint8_t)type pointerID:(uint32_t)pointerID x:(float)x y:(float)y pressure:(float)pressure;

@end

NS_ASSUME_NONNULL_END
