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

// moonlight-common-c's input calls. They do nothing without a stream.
@interface StarwireInputFacade : NSObject

+ (void)mouseMoveX:(short)dx y:(short)dy;
// button: 1 left, 2 middle, 3 right, 4 back, 5 forward
+ (void)mouseButton:(int)button down:(BOOL)down;
+ (void)scroll:(short)amount;
+ (void)key:(short)code down:(BOOL)down modifiers:(char)modifiers;
// phase: 0 down, 1 move, 2 up, 3 cancel. x and y from 0 to 1 across the video.
+ (void)touchID:(uint32_t)pointerID phase:(int)phase x:(float)x y:(float)y;

@end

NS_ASSUME_NONNULL_END
