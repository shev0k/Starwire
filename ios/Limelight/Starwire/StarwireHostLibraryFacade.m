//
//  StarwireHostLibraryFacade.m
//  Starwire
//
//  The host and app logic of moonlight-ios's MainFrameViewController (GPL-3.0, Moonlight Stream
//  and Diego Waxemberg), moved out of the view controller for the SwiftUI screens. What it does
//  with the PC is unchanged; only the alerts went, since SwiftUI shows its own.
//

@import ImageIO;
@import AVFoundation;

#import "StarwireHostLibraryFacade.h"
#import "Moonlight-Swift.h"
#import "AppDelegate.h"
#import "AppAssetManager.h"
#import "AppListResponse.h"
#import "ConnectionHelper.h"
#import "ControllerSupport.h"
#import "CryptoManager.h"
#import "DataManager.h"
#import "DiscoveryManager.h"
#import "HttpManager.h"
#import "IdManager.h"
#import "PairManager.h"
#import "ServerInfoResponse.h"
#import "StreamConfiguration.h"
#import "StreamFrameViewController.h"
#import "StreamTestOverrides.h"
#import "TemporaryApp.h"
#import "TemporaryHost.h"
#import "TemporarySettings.h"
#import "VideoFormatPolicy.h"
#import "WakeOnLanManager.h"

#import <VideoToolbox/VideoToolbox.h>
#include <Limelight.h>

@implementation StarwireAppSnapshot

- (instancetype)initWithApp:(TemporaryApp *)app {
    self = [super init];
    if (self) {
        _appID = [app.id copy] ?: @"";
        _name = [app.name copy] ?: @"";
        _hdrSupported = app.hdrSupported;
        _hidden = app.hidden;
        NSString *path = [AppAssetManager boxArtPathForApp:app];
        _boxArtPath = [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
    }
    return self;
}

@end

@implementation StarwireHostSnapshot

- (instancetype)initWithHost:(TemporaryHost *)host {
    self = [super init];
    if (self) {
        _uuid = [host.uuid copy] ?: @"";
        _name = [host.name copy] ?: @"";
        _status = host.state == StateOnline ? StarwireHostStatusOnline
            : host.state == StateOffline ? StarwireHostStatusOffline : StarwireHostStatusUnknown;
        _pairing = host.pairState == PairStatePaired ? StarwireHostPairingPaired
            : host.pairState == PairStateUnpaired ? StarwireHostPairingUnpaired : StarwireHostPairingUnknown;
        _activeAddress = [host.activeAddress copy];
        _localAddress = [host.localAddress copy];
        _externalAddress = [host.externalAddress copy];
        _ipv6Address = [host.ipv6Address copy];
        _manualAddress = [host.address copy];
        _macAddress = [host.mac copy];
        NSString *running = host.currentGame;
        _runningAppID = (running.length > 0 && ![running isEqualToString:@"0"]) ? [running copy] : nil;
        _httpsPort = host.httpsPort;
        _canSleep = host.canSleep;
        _serverCert = [host.serverCert copy];
        NSMutableArray *apps = [NSMutableArray array];
        for (TemporaryApp *app in [[host.appList allObjects] sortedArrayUsingSelector:@selector(compareName:)]) {
            [apps addObject:[[StarwireAppSnapshot alloc] initWithApp:app]];
        }
        _apps = apps;
    }
    return self;
}

@end

@interface StarwireHostLibraryFacade () <DiscoveryCallback, PairCallback, AppAssetCallback>
@end

@implementation StarwireHostLibraryFacade {
    NSMutableSet<TemporaryHost *> *_hostList;
    DiscoveryManager *_discMan;
    AppAssetManager *_appManager;
    NSOperationQueue *_opQueue;
    NSData *_clientCert;
    // The pairing in progress: its host and the caller's blocks
    TemporaryHost *_pairingHost;
    void (^_showPIN)(NSString *);
    void (^_pairCompletion)(NSString *_Nullable);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // The client identity (in the Keychain since batch 2)
        [CryptoManager generateKeyPairUsingSSL];
        [IdManager getUniqueId];
        _clientCert = [CryptoManager readCertFromFile];
        _appManager = [[AppAssetManager alloc] initWithCallback:self];
        _opQueue = [[NSOperationQueue alloc] init];
        _hostList = [NSMutableSet set];

        DataManager *dataMan = [[DataManager alloc] init];
        for (TemporaryHost *host in [dataMan getHosts]) {
            // The non-persistent state, as MainFrameViewController's retrieveSavedHosts set it
            if (host.activeAddress == nil) host.activeAddress = host.localAddress;
            if (host.activeAddress == nil) host.activeAddress = host.externalAddress;
            if (host.activeAddress == nil) host.activeAddress = host.address;
            if (host.activeAddress == nil) host.activeAddress = host.ipv6Address;
            [_hostList addObject:host];
        }
        _discMan = [[DiscoveryManager alloc] initWithHosts:[_hostList allObjects] andCallback:self];
    }
    return self;
}

- (NSArray<StarwireHostSnapshot *> *)hosts {
    NSMutableArray *snapshots = [NSMutableArray array];
    @synchronized (_hostList) {
        for (TemporaryHost *host in [[_hostList allObjects] sortedArrayUsingSelector:@selector(compareName:)]) {
            [snapshots addObject:[[StarwireHostSnapshot alloc] initWithHost:host]];
        }
    }
    return snapshots;
}

- (TemporaryHost *)hostWithUUID:(NSString *)uuid {
    @synchronized (_hostList) {
        for (TemporaryHost *host in _hostList) {
            if ([host.uuid isEqualToString:uuid]) {
                return host;
            }
        }
    }
    return nil;
}

- (void)changed {
    void (^onChange)(void) = self.onChange;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateHostShortcuts];
        if (onChange != nil) {
            onChange();
        }
    });
}

#pragma mark - Discovery

- (void)startDiscovery {
    // Reset first so PCs removed before can be found again
    [_discMan resetDiscoveryState];
    [_discMan startDiscovery];
}

- (void)stopDiscovery {
    [_discMan stopDiscovery];
}

- (void)updateAllHosts:(NSArray *)hosts {
    NSArray *copy = [NSArray arrayWithArray:hosts];
    @synchronized (_hostList) {
        [_hostList removeAllObjects];
        [_hostList addObjectsFromArray:copy];
    }
    [self changed];
}

- (void)addHostWithAddress:(NSString *)address completion:(void (^)(NSString *_Nullable))completion {
    NSString *trimmed = [address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self->_discMan discoverHost:trimmed withCallback:^(TemporaryHost *host, NSString *error) {
            if (host != nil) {
                @synchronized (self->_hostList) {
                    [self->_hostList addObject:host];
                }
                [self changed];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
                return;
            }
            NSString *message = error ?: @"";
            unsigned int ports = LiTestClientConnectivity(CONN_TEST_SERVER, 443, ML_PORT_FLAG_TCP_47984 | ML_PORT_FLAG_TCP_47989);
            if (ports != ML_TEST_RESULT_INCONCLUSIVE && ports != 0) {
                message = [message stringByAppendingString:@"\n\nThis network seems to block Starwire. Streaming may not work on it."];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(message); });
        }];
    });
}

- (void)removeHost:(NSString *)uuid {
    TemporaryHost *host = [self hostWithUUID:uuid];
    if (host == nil) {
        return;
    }
    [_discMan removeHostFromDiscovery:host];
    [[[DataManager alloc] init] removeHost:host];
    @synchronized (_hostList) {
        [_hostList removeObject:host];
    }
    [self changed];
}

#pragma mark - Apps

- (void)refreshHost:(NSString *)uuid completion:(void (^)(NSString *_Nullable, BOOL))completion {
    TemporaryHost *host = [self hostWithUUID:uuid];
    if (host == nil) {
        completion(@"This PC is no longer saved.", NO);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        HttpManager *hMan = [[HttpManager alloc] initWithHost:host];
        ServerInfoResponse *serverInfoResp = [[ServerInfoResponse alloc] init];
        // Exempt this PC from discovery while asking it
        [self->_discMan pauseDiscoveryForHost:host];
        [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                                            fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
        [self->_discMan resumeDiscoveryForHost:host];
        if (![serverInfoResp isStatusOk]) {
            Log(LOG_W, @"Failed to get server info: %@", serverInfoResp.statusMessage);
            host.state = StateOffline;
            [self changed];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(serverInfoResp.statusMessage ?: @"", NO); });
            return;
        }
        [serverInfoResp populateHost:host];
        if (host.pairState != PairStatePaired) {
            [self changed];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, YES); });
            return;
        }
        [self loadAppsForHost:host completion:^(NSString *error) {
            completion(error, NO);
        }];
    });
}

// MainFrameViewController's alreadyPaired, without the screens. Runs off the main queue.
- (void)loadAppsForHost:(TemporaryHost *)host completion:(void (^)(NSString *_Nullable))completion {
    [_discMan pauseDiscoveryForHost:host];
    AppListResponse *appListResp = [ConnectionHelper getAppListForHost:host];
    [_discMan resumeDiscoveryForHost:host];
    if (![appListResp isStatusOk] || [appListResp getAppList] == nil) {
        Log(LOG_W, @"Failed to get applist: %@", appListResp.statusMessage);
        host.state = StateOffline;
        [self changed];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(appListResp.statusMessage ?: @""); });
        return;
    }
    NSSet *list = [appListResp getAppList];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateApplist:list forHost:host];
        [self->_appManager stopRetrieving];
        [self->_appManager retrieveAssetsFromHost:host];
        [self changed];
        completion(nil);
    });
}

- (void)updateApplist:(NSSet *)newList forHost:(TemporaryHost *)host {
    DataManager *database = [[DataManager alloc] init];
    NSMutableSet *merged = [NSMutableSet setWithSet:host.appList];
    for (TemporaryApp *app in newList) {
        BOOL known = NO;
        for (TemporaryApp *saved in merged) {
            if ([app.id isEqualToString:saved.id]) {
                saved.name = app.name;
                saved.hdrSupported = app.hdrSupported;
                // Hidden stays as this device set it
                known = YES;
                break;
            }
        }
        if (!known) {
            app.host = host;
            [merged addObject:app];
        }
    }
    // Apps the PC no longer has
    NSMutableArray *gone = [NSMutableArray array];
    for (TemporaryApp *app in merged) {
        BOOL stillThere = NO;
        for (TemporaryApp *fresh in newList) {
            if ([fresh.id isEqualToString:app.id]) {
                stillThere = YES;
                break;
            }
        }
        if (!stillThere) {
            [gone addObject:app];
        }
    }
    for (TemporaryApp *app in gone) {
        [merged removeObject:app];
        // Removed from the database too, or appList breaks its constraint
        [database removeApp:app];
    }
    host.appList = merged;
    [database updateAppsForExistingHost:host];
}

- (void)receivedAssetForApp:(TemporaryApp *)app {
    [self changed];
}

- (void)setApp:(NSString *)appID hidden:(BOOL)hidden onHost:(NSString *)uuid {
    TemporaryHost *host = [self hostWithUUID:uuid];
    for (TemporaryApp *app in host.appList) {
        if ([app.id isEqualToString:appID]) {
            app.hidden = hidden;
            [[[DataManager alloc] init] updateAppsForExistingHost:host];
            [self changed];
            return;
        }
    }
}

- (void)quitAppOnHost:(NSString *)uuid completion:(void (^)(NSString *_Nullable))completion {
    TemporaryHost *host = [self hostWithUUID:uuid];
    if (host == nil) {
        completion(@"This PC is no longer saved.");
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        HttpManager *hMan = [[HttpManager alloc] initWithHost:host];
        HttpResponse *quitResponse = [[HttpResponse alloc] init];
        HttpRequest *quitRequest = [HttpRequest requestForResponse:quitResponse withUrlRequest:[hMan newQuitAppRequest]];
        [self->_discMan pauseDiscoveryForHost:host];
        [hMan executeRequestSynchronously:quitRequest];
        if (quitResponse.statusCode == 200) {
            ServerInfoResponse *serverInfoResp = [[ServerInfoResponse alloc] init];
            [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                                                fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
            if (![serverInfoResp isStatusOk] || [[serverInfoResp getStringTag:@"state"] hasSuffix:@"_SERVER_BUSY"]) {
                // Newer GFE says the quit worked when another client's game didn't really quit
                quitResponse.statusCode = 599;
            } else {
                [serverInfoResp populateHost:host];
            }
        }
        [self->_discMan resumeDiscoveryForHost:host];
        if (quitResponse.statusCode == 200) {
            host.currentGame = @"0";
        }
        [self changed];
        NSString *error = quitResponse.statusCode == 200 ? nil
            : @"The app didn't quit. If another device started it, quit it from that device.";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

- (NSString *)wakeHost:(NSString *)uuid {
    TemporaryHost *host = [self hostWithUUID:uuid];
    if (host == nil || host.mac == nil || [host.mac isEqualToString:@"00:00:00:00:00:00"]) {
        return @"The PC's network address (MAC) isn't known, so it can't be woken.";
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [WakeOnLanManager wakeHost:host];
    });
    return @"Sent a wake-up request. iOS only lets apps with Apple's multicast permission send it to the whole network, so it may not reach the PC.";
}

+ (void)testNetwork:(void (^)(NSString *_Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        unsigned int result = LiTestClientConnectivity(CONN_TEST_SERVER, 443, ML_PORT_FLAG_ALL);
        NSString *blocked = nil;
        if (result == 0) {
            blocked = @"";
        } else if (result != ML_TEST_RESULT_INCONCLUSIVE) {
            char ports[512];
            LiStringifyPortFlags(result, "\n", ports, sizeof(ports));
            blocked = [NSString stringWithUTF8String:ports];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(blocked); });
    });
}

#pragma mark - Pairing

- (void)pairHost:(NSString *)uuid showPIN:(void (^)(NSString *))showPIN completion:(void (^)(NSString *_Nullable))completion {
    TemporaryHost *host = [self hostWithUUID:uuid];
    if (host == nil) {
        completion(@"This PC is no longer saved.");
        return;
    }
    _pairingHost = host;
    _showPIN = [showPIN copy];
    _pairCompletion = [completion copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Polling the PC while pairing confuses it
        [self->_discMan stopDiscoveryBlocking];
        HttpManager *hMan = [[HttpManager alloc] initWithHost:host];
        PairManager *pMan = [[PairManager alloc] initWithManager:hMan clientCert:self->_clientCert callback:self];
        [self->_opQueue addOperation:pMan];
    });
}

- (void)cancelPairing {
    _pairingHost = nil;
    _showPIN = nil;
    _pairCompletion = nil;
    [_discMan startDiscovery];
}

- (void)startPairing:(NSString *)PIN {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_showPIN != nil) {
            self->_showPIN(PIN);
        }
    });
}

- (void)finishPairing:(NSString *_Nullable)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^completion)(NSString *) = self->_pairCompletion;
        self->_pairingHost = nil;
        self->_showPIN = nil;
        self->_pairCompletion = nil;
        [self->_discMan startDiscovery];
        if (completion != nil) {
            completion(error);
        }
    });
}

- (void)pairSuccessful:(NSData *)serverCert {
    TemporaryHost *host = _pairingHost;
    host.serverCert = serverCert;
    host.pairState = PairStatePaired;
    if (host != nil) {
        [[[DataManager alloc] init] updateHost:host];
    }
    [self changed];
    [self finishPairing:nil];
}

- (void)pairFailed:(NSString *)message {
    [self finishPairing:message ?: @""];
}

- (void)alreadyPaired {
    _pairingHost.pairState = PairStatePaired;
    [self changed];
    [self finishPairing:nil];
}

#pragma mark - Shortcuts

- (void)updateHostShortcuts {
    NSMutableArray *quickActions = [NSMutableArray array];
    @synchronized (_hostList) {
        for (TemporaryHost *host in _hostList) {
            // The app list stays saved for paired PCs, even before their pair state is known
            if (host.appList.count > 0) {
                [quickActions addObject:[[UIApplicationShortcutItem alloc] initWithType:@"PC"
                                                                         localizedTitle:host.name
                                                                      localizedSubtitle:nil
                                                                                   icon:[UIApplicationShortcutIcon iconWithType:UIApplicationShortcutIconTypePlay]
                                                                               userInfo:@{@"UUID": host.uuid}]];
            }
        }
    }
    [UIApplication sharedApplication].shortcutItems = quickActions;
}

- (NSString *)takePendingShortcutHost {
    AppDelegate *delegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    NSString *uuid = delegate.pcUuidToLoad;
    if (uuid == nil) {
        return nil;
    }
    delegate.pcUuidToLoad = nil;
    BOOL found = [self hostWithUUID:uuid] != nil;
    if (delegate.shortcutCompletionHandler != nil) {
        delegate.shortcutCompletionHandler(found);
        delegate.shortcutCompletionHandler = nil;
    }
    return found ? uuid : nil;
}

#pragma mark - Streaming

- (UIViewController *)streamViewControllerForApp:(NSString *)appID onHost:(NSString *)uuid onFinished:(void (^)(void))onFinished {
    TemporaryHost *host = [self hostWithUUID:uuid];
    TemporaryApp *app = nil;
    for (TemporaryApp *candidate in host.appList) {
        if ([candidate.id isEqualToString:appID]) {
            app = candidate;
            break;
        }
    }
    if (app == nil) {
        return nil;
    }
    [_appManager stopRetrieving];
    // Discovery pauses while streaming, as it did when the main screen disappeared
    [_discMan stopDiscovery];

    StreamFrameViewController *stream = [[StreamFrameViewController alloc] init];
    stream.streamConfig = [StarwireHostLibraryFacade configurationForApp:app];
    stream.modalPresentationStyle = UIModalPresentationFullScreen;
    __weak StarwireHostLibraryFacade *weakSelf = self;
    stream.onFinished = ^{
        [weakSelf startDiscovery];
        onFinished();
    };
    return stream;
}

// MainFrameViewController's prepareToStreamApp, unchanged apart from where it lives
+ (StreamConfiguration *)configurationForApp:(TemporaryApp *)app {
    StreamConfiguration *config = [[StreamConfiguration alloc] init];
    config.host = app.host.activeAddress;
    config.httpsPort = app.host.httpsPort;
    config.appID = app.id;
    config.appName = app.name;
    config.serverCert = app.host.serverCert;

    TemporarySettings *streamSettings = [[[DataManager alloc] init] getSettings];
    // Launch arguments from the device runs (StreamTestOverrides.h); none in normal use
    NSString *overrides = StreamApplyTestOverrides(streamSettings, [NSUserDefaults standardUserDefaults]);
    if (overrides.length > 0) {
        Log(LOG_I, @"Settings replaced by launch arguments for this launch: %@", overrides);
    }

    config.frameRate = [streamSettings.framerate intValue];
    // Don't stream more FPS than the display can show
    if (config.frameRate > [UIScreen mainScreen].maximumFramesPerSecond) {
        config.frameRate = (int)[UIScreen mainScreen].maximumFramesPerSecond;
        Log(LOG_W, @"Clamping FPS to maximum refresh rate: %d", config.frameRate);
    }
    config.height = [streamSettings.height intValue];
    config.width = [streamSettings.width intValue];
    config.bitRate = [streamSettings.bitrate intValue];
    config.optimizeGameSettings = streamSettings.optimizeGames;
    config.playAudioOnPC = streamSettings.playAudioOnPC;
    config.swapABXYButtons = streamSettings.swapABXYButtons;
    // multiController must be set before getConnectedGamepadMask
    config.multiController = streamSettings.multiController;
    config.fullRange = StreamUsesFullRange([NSUserDefaults standardUserDefaults]);
    config.gamepadMask = [ControllerSupport getConnectedGamepadMask:config];

    int channels = [streamSettings.audioConfig intValue];
    Log(LOG_I, @"Selected number of audio channels %d", channels);
    if (channels >= 8) {
        config.audioConfiguration = AUDIO_CONFIGURATION_71_SURROUND;
    } else if (channels >= 6) {
        config.audioConfiguration = AUDIO_CONFIGURATION_51_SURROUND;
    } else {
        config.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    }

    config.serverCodecModeSupport = app.host.serverCodecModeSupport;

    switch (streamSettings.preferredCodec) {
    case CODEC_PREF_AV1:
        if (VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)) {
            config.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN8;
        }
        // Fall-through
    case CODEC_PREF_AUTO:
    case CODEC_PREF_HEVC:
        if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
            config.supportedVideoFormats |= VIDEO_FORMAT_H265;
            if (streamSettings.enableYUV444) {
                config.supportedVideoFormats |= VIDEO_FORMAT_H265_REXT8_444;
            }
        }
        // Fall-through
    case CODEC_PREF_H264:
        config.supportedVideoFormats |= VIDEO_FORMAT_H264;
        break;
    }

    // HEVC when the resolution or HDR needs it and the chip has it
    if ((config.width > 4096 || config.height > 4096 || streamSettings.enableHdr) && VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
        config.supportedVideoFormats |= VIDEO_FORMAT_H265;
        if (streamSettings.enableYUV444) {
            config.supportedVideoFormats |= VIDEO_FORMAT_H265_REXT8_444;
        }
        // HEVC Main10 when HDR is on and the display has it
        if (streamSettings.enableHdr && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10) != 0) {
            config.supportedVideoFormats |= VIDEO_FORMAT_H265_MAIN10;
            if (streamSettings.enableYUV444) {
                config.supportedVideoFormats |= VIDEO_FORMAT_H265_REXT10_444;
            }
        }
    }
    // AV1 Main10 when AV1 and HDR are both on and supported
    if ((config.supportedVideoFormats & VIDEO_FORMAT_MASK_AV1) && streamSettings.enableHdr &&
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10) != 0) {
        config.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN10;
    }
    return config;
}

#pragma mark - Settings

+ (void)saveLegacyCoreDataSettingsBitrate:(NSInteger)bitrate framerate:(NSInteger)framerate height:(NSInteger)height
                                    width:(NSInteger)width audioConfig:(NSInteger)audioConfig
                             spatialAudio:(NSInteger)spatialAudio onscreenControls:(NSInteger)onscreenControls
                            optimizeGames:(BOOL)optimizeGames multiController:(BOOL)multiController
                          swapABXYButtons:(BOOL)swapABXYButtons audioOnPC:(BOOL)audioOnPC
                           preferredCodec:(NSInteger)preferredCodec frameQueueSize:(NSInteger)frameQueueSize
                                enableHdr:(BOOL)enableHdr enableYUV444:(BOOL)enableYUV444
                           btMouseSupport:(BOOL)btMouseSupport absoluteTouchMode:(BOOL)absoluteTouchMode
                             statsOverlay:(BOOL)statsOverlay enableGraphs:(BOOL)enableGraphs
                             graphOpacity:(NSInteger)graphOpacity {
    [[[DataManager alloc] init] saveSettingsWithBitrate:bitrate framerate:framerate height:height width:width
                                            audioConfig:audioConfig spatialAudio:(uint32_t)spatialAudio
                                       onscreenControls:onscreenControls optimizeGames:optimizeGames
                                        multiController:multiController swapABXYButtons:swapABXYButtons
                                              audioOnPC:audioOnPC preferredCodec:(uint32_t)preferredCodec
                                         frameQueueSize:frameQueueSize enableHdr:enableHdr enableYUV444:enableYUV444
                                         btMouseSupport:btMouseSupport absoluteTouchMode:absoluteTouchMode
                                           statsOverlay:statsOverlay enableGraphs:enableGraphs graphOpacity:graphOpacity];
}

+ (NSObject *)legacyCoreDataSettings {
    return [[[DataManager alloc] init] getSettings];
}

@end
