//
//  StreamManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamManager.h"
#import "Moonlight-Swift.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Plot.h"
#import "Utils.h"

#import "StreamView.h"
#import "ServerInfoResponse.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"
#import "FrameQueue.h"
#import "PacingStats.h"
#import "PacingPolicy.h"

#include <Limelight.h>

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_STREAM

@implementation StreamManager {
    StreamConfiguration* _config;

    UIView* _renderView;
    id<ConnectionCallbacks> _callbacks;
    Connection* _connection;
    // Set by stopStream: a stream left while it was still launching doesn't connect afterwards.
    // From daniel-zn's Artemis iOS (commit 696ffae).
    volatile BOOL _stopped;
    // Full or Lite (StarwireOverlay), read once per stream
    StatsOverlayLevel _overlayLevel;
}

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _config = config;
    _renderView = view;
    _callbacks = callbacks;
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    _overlayLevel = [PacingSettings current].overlayLevel;
    return self;
}

- (void)main {
    [CryptoManager generateKeyPairUsingSSL];

    HttpManager* hMan = [[HttpManager alloc] initWithAddress:_config.host httpsPort:_config.httpsPort
                                                     serverCert:_config.serverCert];

    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                       fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
    NSString* pairStatus = [serverInfoResp getStringTag:@"PairStatus"];
    NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
    NSString* gfeVersion = [serverInfoResp getStringTag:@"GfeVersion"];
    NSString* serverState = [serverInfoResp getStringTag:@"state"];
    if (![serverInfoResp isStatusOk]) {
        [_callbacks launchFailed:serverInfoResp.statusMessage];
        return;
    }
    else if (pairStatus == NULL || appversion == NULL || serverState == NULL) {
        [_callbacks launchFailed:@"Failed to connect to PC"];
        return;
    }

    if (![pairStatus isEqualToString:@"1"]) {
        // Not paired
        [_callbacks launchFailed:@"Device not paired to PC"];
        return;
    }

    // Only perform this check on GFE (as indicated by MJOLNIR in state value)
    if ((_config.width > 4096 || _config.height > 4096) && [serverState containsString:@"MJOLNIR"]) {
        // Pascal added support for 8K HEVC encoding support. Maxwell 2 could encode HEVC but only up to 4K.
        // We can't directly identify Pascal, but we can look for HEVC Main10 which was added in the same generation.
        NSString* codecSupport = [serverInfoResp getStringTag:@"ServerCodecModeSupport"];
        if (codecSupport == nil || !([codecSupport intValue] & 0x200)) {
            [_callbacks launchFailed:@"Your host PC's GPU doesn't support streaming video resolutions over 4K."];
            return;
        }
    }

    // Populate the config's version fields from serverinfo
    _config.appVersion = appversion;
    _config.gfeVersion = gfeVersion;

    // resumeApp and launchApp handle calling launchFailed
    NSString* sessionUrl;
    // Starwire: Vibeshine's control tiles are always launched; /resume would join the game
    BOOL controlTile = [StarwireLaunchFlow isControlTile:_config.appID];
    if ([serverState hasSuffix:@"_SERVER_BUSY"] && !controlTile) {
        // App already running, resume it
        if (![self resumeApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    } else {
        // Start app
        if (![self launchApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    }

    // Populate RTSP session URL from launch/resume response
    _config.rtspSessionUrl = sessionUrl;

    if (_stopped) {
        Log(LOG_I, @"Stream was closed while launching; not connecting");
        return;
    }

    // Initializing the renderer must be done on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_stopped) {
            Log(LOG_I, @"Stream was closed while launching; not connecting");
            return;
        }
        VideoDecoderRenderer* renderer = [[VideoDecoderRenderer alloc] initWithView:self->_renderView callbacks:self->_callbacks streamAspectRatio:(float)self->_config.width / (float)self->_config.height];
        self->_connection = [[Connection alloc] initWithConfig:self->_config renderer:renderer connectionCallbacks:self->_callbacks];
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:self->_connection];
    });
}

- (void) stopStream
{
    // Called on the main thread, like the block that creates the connection
    _stopped = YES;
    [_connection terminate];
}

- (BOOL) launchApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* launchResp;
    // Starwire: Vibeshine may answer 410 to ask for confirmation; the same request again within
    // 60 seconds confirms (StarwireLaunchFlow, at most one question per launch)
    StarwireLaunchFlow* flow = [[StarwireLaunchFlow alloc] init];
    for (;;) {
        launchResp = [[HttpResponse alloc] init];
        [hMan executeRequestSynchronously:[HttpRequest requestForResponse:launchResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"launch" config:_config]]];
        StarwireLaunchStep step = [flow nextWithStatusCode:launchResp.statusCode message:launchResp.statusMessage];
        if (step == StarwireLaunchStepAsk) {
            Log(LOG_I, @"The PC asks to confirm: %@", launchResp.statusMessage);
            if ([_callbacks respondsToSelector:@selector(launchNeedsConfirmation:)] &&
                [_callbacks launchNeedsConfirmation:launchResp.statusMessage] && !_stopped) {
                continue;
            }
            Log(LOG_I, @"Not confirmed");
            [self finishLaunch:@""];
            return FALSE;
        }
        if (step == StarwireLaunchStepFinished) {
            Log(LOG_I, @"The PC says: %@", launchResp.statusMessage);
            [self finishLaunch:launchResp.statusMessage];
            return FALSE;
        }
        break;
    }
    NSString *gameSession = [launchResp getStringTag:@"gamesession"];
    if (![launchResp isStatusOk]) {
        [_callbacks launchFailed:launchResp.statusMessage];
        Log(LOG_E, @"Failed Launch Response: %@", launchResp.statusMessage);
        return FALSE;
    } else if (gameSession == NULL || [gameSession isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to launch app"];
        Log(LOG_E, @"Failed to parse game session");
        return FALSE;
    }

    *sessionUrl = [launchResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

// A launch that ended without a stream on purpose: say so (an empty message says nothing)
- (void) finishLaunch:(NSString*)message {
    if ([_callbacks respondsToSelector:@selector(launchFinished:)]) {
        [_callbacks launchFinished:message];
    } else if (message.length > 0) {
        [_callbacks launchFailed:message];
    }
}

- (BOOL) resumeApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* resumeResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:resumeResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"resume" config:_config]]];
    NSString* resume = [resumeResp getStringTag:@"resume"];
    if (![resumeResp isStatusOk]) {
        [_callbacks launchFailed:resumeResp.statusMessage];
        Log(LOG_E, @"Failed Resume Response: %@", resumeResp.statusMessage);
        return FALSE;
    } else if (resume == NULL || [resume isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to resume app"];
        Log(LOG_E, @"Failed to parse resume response");
        return FALSE;
    }

    *sessionUrl = [resumeResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

// quick hack for both stats
#define COLUMN_WIDTH 30
static NSString *interleaveStrings(NSString *str1, NSString *str2) {
    // Split the strings into arrays of lines
    NSArray *lines1 = [str1 componentsSeparatedByString:@"\n"];
    NSArray *lines2 = [str2 componentsSeparatedByString:@"\n"];

    NSUInteger maxLines = MAX(lines1.count, lines2.count);
    NSMutableString *result = [NSMutableString string];

    for (NSUInteger i = 0; i < maxLines; i++) {
        NSString *line1 = (i < lines1.count) ? lines1[i] : @"";
        NSString *line2 = (i < lines2.count) ? lines2[i] : @"";

        NSString *formattedLine = [NSString stringWithFormat:@"%-*s%@\n", COLUMN_WIDTH, [line1 UTF8String], line2];

        [result appendString:formattedLine];
    }

    return [result copy];
}

// One line on why frames were dropped, from the last 5 second pacing window (PacingStats)
- (NSString*) pacingOverlayLine {
    PacingStats* pacingStats = [FrameQueue sharedInstance].pacingStats;
    if (pacingStats == nil) {
        return @"";
    }
    PacingWindow window = [pacingStats lastWindow];
    if (window.arrivals == 0) {
        return @"";
    }
    // The summary since the stream started is what the device-run tests read last
    return [NSString stringWithFormat:@"\n%@\n%@", [pacingStats overlayLineForWindow:window],
            [pacingStats summaryLineForWindow:[pacingStats totalWindow]]];
}

- (NSString*) getStatsOverlayText {
    video_stats_t stats;

    if (!_connection) {
        return nil;
    }

    if (![_connection getVideoStats:&stats]) {
        return nil;
    }

    uint32_t rtt, variance;
    NSString* latencyString;
    if (LiGetEstimatedRttInfo(&rtt, &variance)) {
        latencyString = [NSString stringWithFormat:@"%u ms (variance: %u ms)", rtt, variance];
    }
    else {
        latencyString = @"N/A";
    }

    NSString* hostProcessingString;
    if (stats.framesWithHostProcessingLatency != 0) {
        hostProcessingString = [NSString stringWithFormat:@"Host processing latency min/max/avg: %.1f/%.1f/%.1f ms\n",
                                stats.minHostProcessingLatency / 10.f,
                                stats.maxHostProcessingLatency / 10.f,
                                (float)stats.totalHostProcessingLatency / stats.framesWithHostProcessingLatency / 10.f];
    }
    else {
        // If all frames are duplicates this can happen, but let's avoid having the whole stats area change height
        hostProcessingString = @"Host processing latency min/max/avg: -/-/- ms\n";
    }

    float interval = stats.endTime - stats.startTime;
    float scalePlotMetrics = stats.frameDropMetrics.nsamples > 0 ? ((float)stats.frameDropMetrics.nsamples / stats.totalFrames) : 1.0f;
    float fps = (stats.totalFrames - stats.networkDroppedFrames - (stats.frameDropMetrics.total / scalePlotMetrics)) / interval;
    double networkDropPercent = (stats.networkDroppedFrames / stats.totalFrames) * 100.0;
    double pacingDropPercent = stats.frameDropMetrics.nsamples > 0 ? (stats.frameDropMetrics.total / stats.frameDropMetrics.nsamples) * 100.0 : 0.0;

    if (_overlayLevel == StatsOverlayLevelLite) {
        PacingWindow window = [[FrameQueue sharedInstance].pacingStats lastWindow];
        double refreshMs = window.refresh.total > 0 ? window.refresh.sumSeconds * 1000.0 / window.refresh.total : 0;
        return PacingLiteOverlayLine(fps, window.onePercentLowFps, networkDropPercent, pacingDropPercent,
                                     LiGetEstimatedRttInfo(&rtt, &variance) ? (int)rtt : -1,
                                     stats.decodeMetrics.avg, refreshMs > 0 ? 1000.0 / refreshMs : 0);
    }

    BandwidthTracker *bwTracker = [_connection getBwTracker];
    double avgVideoMbps = bwTracker.averageMbps;
    double peakVideoMbps = bwTracker.peakMbps;

    NSString *videoStatsStr = [NSString stringWithFormat:@"Video stream: %dx%d %.2f FPS (Codec: %@)\n"
            "Bitrate: %.1f Mbps, Peak: %.1f, Frame queue: %.1f\n"
            "%@"
            "Frames dropped by network/pacing jitter: %.1f%% / %.1f%%\n"
            "Average network latency: %@\n"
            "Decode time: %.2f/%.2f/%.2f ms%@",
            _config.width,
            _config.height,
            fps,
            [_connection getActiveCodecName],
            avgVideoMbps, peakVideoMbps, stats.frameQueueMetrics.avg,
            hostProcessingString,
            networkDropPercent,
            pacingDropPercent,
            latencyString,
            stats.decodeMetrics.min, stats.decodeMetrics.max, stats.decodeMetrics.avg,
            [self pacingOverlayLine]];

    NSString *audioStatsStr = [_connection getAudioStatsString];
    if (audioStatsStr) {
        return interleaveStrings(videoStatsStr, audioStatsStr); // XXX clean up
    }
    else {
        return videoStatsStr;
    }
}

@end
