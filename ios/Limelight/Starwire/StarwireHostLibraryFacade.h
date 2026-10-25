//
//  StarwireHostLibraryFacade.h
//  Starwire
//
//  The PCs and their apps for the SwiftUI screens (phase 3), through plain types: discovery,
//  adding and removing a PC, pairing, the app list and box art, quitting, hiding an app, the
//  network test, and the stream screen for an app. The logic is moonlight-ios's
//  MainFrameViewController's, moved here unchanged where it could be, so the storyboard screens
//  can stay in the tree unused. Like StarwireCoreFacade.h, this header imports nothing of the
//  core's, because it is in the Swift bridging header.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface StarwireAppSnapshot : NSObject
@property (nonatomic, readonly, copy) NSString *appID;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) BOOL hdrSupported;
@property (nonatomic, readonly) BOOL hidden;
// Where the app's cover art is saved, if the PC sent one
@property (nonatomic, readonly, copy, nullable) NSString *boxArtPath;
@end

typedef NS_ENUM(NSInteger, StarwireHostStatus) {
    StarwireHostStatusUnknown = 0,
    StarwireHostStatusOnline,
    StarwireHostStatusOffline,
};

typedef NS_ENUM(NSInteger, StarwireHostPairing) {
    StarwireHostPairingUnknown = 0,
    StarwireHostPairingPaired,
    StarwireHostPairingUnpaired,
};

@interface StarwireHostSnapshot : NSObject
@property (nonatomic, readonly, copy) NSString *uuid;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) StarwireHostStatus status;
@property (nonatomic, readonly) StarwireHostPairing pairing;
@property (nonatomic, readonly, copy, nullable) NSString *activeAddress;
@property (nonatomic, readonly, copy, nullable) NSString *localAddress;
@property (nonatomic, readonly, copy, nullable) NSString *externalAddress;
@property (nonatomic, readonly, copy, nullable) NSString *ipv6Address;
@property (nonatomic, readonly, copy, nullable) NSString *manualAddress;
@property (nonatomic, readonly, copy, nullable) NSString *macAddress;
// The running app's ID, or nil when nothing runs ("0" from the PC)
@property (nonatomic, readonly, copy, nullable) NSString *runningAppID;
@property (nonatomic, readonly) unsigned short httpsPort;
@property (nonatomic, readonly) BOOL canSleep;
@property (nonatomic, readonly, copy, nullable) NSData *serverCert;
// Sorted by name, hidden ones included
@property (nonatomic, readonly, copy) NSArray<StarwireAppSnapshot *> *apps;
@end

@interface StarwireHostLibraryFacade : NSObject

// Called on the main queue whenever a PC or an app list changes
@property (nonatomic, copy, nullable) void (^onChange)(void);

// The saved PCs, read from Core Data, sorted by name
- (NSArray<StarwireHostSnapshot *> *)hosts;

- (void)startDiscovery;
- (void)stopDiscovery;

// Finds a PC by address and adds it. The completion (main queue) gets an error to show, or nil.
- (void)addHostWithAddress:(NSString *)address completion:(void (^)(NSString *_Nullable error))completion;
- (void)removeHost:(NSString *)uuid;

// Asks the PC for its state, then its apps and their box art. needsPairing is YES when the PC
// answered but isn't paired with this device. Main queue.
- (void)refreshHost:(NSString *)uuid completion:(void (^)(NSString *_Nullable error, BOOL needsPairing))completion;

// Pairs with the PIN flow: showPIN gets the PIN to show (main queue). The completion (main
// queue) gets nil when paired, or the error.
- (void)pairHost:(NSString *)uuid showPIN:(void (^)(NSString *pin))showPIN completion:(void (^)(NSString *_Nullable error))completion;
// Stops waiting for the PIN (the user cancelled)
- (void)cancelPairing;

// Quits the running app on the PC. The completion (main queue) gets nil or the error.
- (void)quitAppOnHost:(NSString *)uuid completion:(void (^)(NSString *_Nullable error))completion;

- (void)setApp:(NSString *)appID hidden:(BOOL)hidden onHost:(NSString *)uuid;

// moonlight-ios's Wake-on-LAN. Returns what to tell the user.
- (NSString *)wakeHost:(NSString *)uuid;

// moonlight-common-c's port test against Moonlight's test server. blockedPorts is empty when
// nothing was blocked, nil when the test couldn't run. Main queue.
+ (void)testNetwork:(void (^)(NSString *_Nullable blockedPorts))completion;

// The stream screen for an app, built from the settings as they are now (the caller writes the
// store's values to the old settings first). Nil if the PC or the app is gone. Its onFinished
// runs on the main queue when the stream screen goes away.
- (nullable UIViewController *)streamViewControllerForApp:(NSString *)appID
                                                   onHost:(NSString *)uuid
                                               onFinished:(void (^)(void))onFinished;

// The PC a Home Screen quick action asked for, once, or nil
- (nullable NSString *)takePendingShortcutHost;

// Copies the store's values into moonlight-ios's Core Data settings record
+ (void)saveLegacyCoreDataSettingsBitrate:(NSInteger)bitrate framerate:(NSInteger)framerate height:(NSInteger)height
                                    width:(NSInteger)width audioConfig:(NSInteger)audioConfig
                             spatialAudio:(NSInteger)spatialAudio onscreenControls:(NSInteger)onscreenControls
                            optimizeGames:(BOOL)optimizeGames multiController:(BOOL)multiController
                          swapABXYButtons:(BOOL)swapABXYButtons audioOnPC:(BOOL)audioOnPC
                           preferredCodec:(NSInteger)preferredCodec frameQueueSize:(NSInteger)frameQueueSize
                                enableHdr:(BOOL)enableHdr enableYUV444:(BOOL)enableYUV444
                           btMouseSupport:(BOOL)btMouseSupport absoluteTouchMode:(BOOL)absoluteTouchMode
                             statsOverlay:(BOOL)statsOverlay enableGraphs:(BOOL)enableGraphs
                             graphOpacity:(NSInteger)graphOpacity;

// moonlight-ios's Core Data settings record (a TemporarySettings), for the one-time copy into the store
+ (NSObject *)legacyCoreDataSettings;

@end

NS_ASSUME_NONNULL_END
