//
//  HttpManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/16/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "HttpManager.h"
#import "HttpRequest.h"
#import "CryptoManager.h"
#import "TemporaryApp.h"
#import "ServerInfoResponse.h"
#import "Moonlight-Swift.h"

#include <libxml2/libxml/xmlreader.h>
#include <string.h>

#include <Limelight.h>

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_NETWORK

#define SHORT_TIMEOUT_SEC 2
#define NORMAL_TIMEOUT_SEC 5
#define LONG_TIMEOUT_SEC 60
#define EXTRA_LONG_TIMEOUT_SEC 180

@implementation HttpManager {
    NSString* _urlSafeHostName;
    NSString* _baseHTTPURL;
    NSString* _uniqueId;
    NSString* _deviceName;
    NSData* _serverCert;
    
    TemporaryHost *_host; // May be nil
    NSString* _baseHTTPSURL;
}

+ (NSData*) fixXmlVersion:(NSData*) xmlData {
    NSString* dataString = [[NSString alloc] initWithData:xmlData encoding:NSUTF8StringEncoding];
    NSString* xmlString = [dataString stringByReplacingOccurrencesOfString:@"UTF-16" withString:@"UTF-8" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [dataString length])];
    
    return [xmlString dataUsingEncoding:NSUTF8StringEncoding];
}

- (void) setServerCert:(NSData*) serverCert {
    _serverCert = serverCert;
}

- (id) initWithHost:(TemporaryHost*) host {
    self = [self initWithAddress:host.activeAddress httpsPort:host.httpsPort serverCert:host.serverCert];
    _host = host;
    return self;
}

- (id) initWithAddress:(NSString*) hostAddressPortString httpsPort:(unsigned short)httpsPort serverCert:(NSData*) serverCert {
    self = [super init];
    // Use the same UID for all Moonlight clients to allow them
    // quit games started on another Moonlight client.
    _uniqueId = @"0123456789ABCDEF";
    // Starwire: the name in the settings (or "Starwire on iPad"), not upstream's "roth". Vibeshine
    // takes the name its owner types with the PIN; other hosts show this one.
    _deviceName = [HttpManager urlEncode:[StarwireSettings clientName]];
    _serverCert = serverCert;
    
    NSString* address = [Utils addressPortStringToAddress:hostAddressPortString];
    unsigned short port = [Utils addressPortStringToPort:hostAddressPortString];
    
    // If this is an IPv6 literal, we must properly enclose it in brackets
    if ([address containsString:@":"]) {
        _urlSafeHostName = [NSString stringWithFormat:@"[%@]", address];
    } else {
        _urlSafeHostName = address;
    }
    
    _baseHTTPURL = [NSString stringWithFormat:@"http://%@:%u", _urlSafeHostName, port];
    
    if (httpsPort) {
        _baseHTTPSURL = [NSString stringWithFormat:@"https://%@:%u", _urlSafeHostName, httpsPort];
    }
    
    return self;
}

- (BOOL) ensureHttpsUrlPopulated:(bool)fastFail {
    if (!_baseHTTPSURL) {
        // Use the caller's provided port if one was specified
        if (_host && _host.httpsPort != 0) {
            _baseHTTPSURL = [NSString stringWithFormat:@"https://%@:%u", _urlSafeHostName, _host.httpsPort];
        }
        else {
            // Query the host to retrieve the HTTPS port. Starwire: honor fastFail here too, so a
            // poll that has to ask over HTTP waits 2 seconds, not 5.
            ServerInfoResponse* serverInfoResponse = [[ServerInfoResponse alloc] init];
            [self executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResponse withUrlRequest:[self newHttpServerInfoRequest:fastFail]]];
            TemporaryHost* dummyHost = [[TemporaryHost alloc] init];
            if (![serverInfoResponse isStatusOk]) {
                return NO;
            }
            [serverInfoResponse populateHost:dummyHost];
            
            // Pass the port back if the caller provided storage for it
            if (_host) {
                _host.httpsPort = dummyHost.httpsPort;
            }
            
            _baseHTTPSURL = [NSString stringWithFormat:@"https://%@:%u", _urlSafeHostName, dummyHost.httpsPort];
        }
    }
    
    return YES;
}

+ (NSString*) urlEncode:(NSString*)text {
    NSMutableCharacterSet* allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-._~"];
    // alphanumericCharacterSet has letters beyond ASCII; keep only the RFC 3986 unreserved ones
    NSCharacterSet* ascii = [NSCharacterSet characterSetWithRange:NSMakeRange(0, 128)];
    [allowed formIntersectionWithCharacterSet:ascii];
    return [text stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

// Logs now reach Release builds, so the stream's input key never goes into them
+ (NSString*) redactSecrets:(NSString*)text {
    static NSRegularExpression* rikey;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rikey = [NSRegularExpression regularExpressionWithPattern:@"rikey=[0-9A-Fa-f]+" options:0 error:nil];
    });
    if (text == nil) {
        return nil;
    }
    return [rikey stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"rikey=<redacted>"];
}

- (void) executeRequestSynchronously:(HttpRequest*)request {
    // This is a special case to handle failure of HTTPS port fetching
    if (!request.request) {
        if (request.response) {
            request.response.statusCode = EHOSTDOWN;
            request.response.statusMessage = @"Host is unreachable";
        }
        
        return;
    }

    __block NSData* requestResp = nil;
    __block NSError* respError = nil;
    __block dispatch_semaphore_t requestLock = dispatch_semaphore_create(0);
    
    Log(LOG_D, @"Making Request: %@", [HttpManager redactSecrets:request.request.URL.absoluteString]);
    NSURLSession* urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:self delegateQueue:nil];
    [[urlSession dataTaskWithRequest:request.request completionHandler:^(NSData * __nullable data, NSURLResponse * __nullable response, NSError * __nullable error) {
        
        if (error != NULL) {
            Log(LOG_W, @"Request to %@ failed: %@ (%ld)", [HttpManager redactSecrets:request.request.URL.absoluteString],
                error.domain, (long)error.code);
            respError = error;
        }
        else {
            Log(LOG_D, @"Received response: %@", response);

            if (data != NULL) {
#if defined(DEBUG)
                Log(LOG_D, @"\n\nReceived data: %@\n\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
#else
                // Pairing responses carry the pairing secrets, so Release logs only the size
                Log(LOG_D, @"Received %lu bytes", (unsigned long)data.length);
#endif
                if ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] != nil) {
                    requestResp = [HttpManager fixXmlVersion:data];
                } else {
                    requestResp = data;
                }
            }
        }
        
        dispatch_semaphore_signal(requestLock);
    }] resume];
    
    dispatch_semaphore_wait(requestLock, DISPATCH_TIME_FOREVER);
    [urlSession invalidateAndCancel];
    
    if (!respError && request.response) {
        [request.response populateWithData:requestResp];
        if ([(NSObject*)request.response isKindOfClass:[ServerInfoResponse class]]) {
            // From daniel-zn's Artemis iOS: HTTPS here means our pinned certificate matched (the
            // session delegate checks it); a fallback request below sets this again for its plain
            // HTTP answer, where the host always says "not paired"
            ((ServerInfoResponse*)request.response).authenticated =
                _serverCert != nil && [request.request.URL.scheme isEqualToString:@"https"];
        }
        
        // If the fallback error code was detected, issue the fallback request
        if (request.response.statusCode == request.fallbackError && request.fallbackRequest != NULL) {
            Log(LOG_D, @"Request failed with fallback error code: %d", request.fallbackError);
            request.request = request.fallbackRequest;
            request.fallbackError = 0;
            request.fallbackRequest = NULL;
            [self executeRequestSynchronously:request];
        }
    }
    else if (respError && [respError code] == NSURLErrorServerCertificateUntrusted) {
        // We must have a pinned cert for HTTPS. If we fail, it must be due to
        // a non-matching cert, not because we had no cert at all.
        assert(_serverCert != nil);
        
        if (request.fallbackRequest) {
            // This will fall back to HTTP on serverinfo queries to allow us to pair again
            // and get the server cert updated.
            Log(LOG_D, @"Attempting fallback request after certificate trust failure");
            request.request = request.fallbackRequest;
            request.fallbackError = 0;
            request.fallbackRequest = NULL;
            [self executeRequestSynchronously:request];
        }
    }
    else if (respError && request.response) {
        request.response.statusCode = [respError code];
        request.response.statusMessage = [respError localizedDescription];
    }
}

- (NSURLRequest*) createRequestFromString:(NSString*) urlString timeout:(int)timeout {
    NSURL* url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    [request setTimeoutInterval:timeout];
    return request;
}

- (NSURLRequest*) newPairRequest:(NSData*)salt clientCert:(NSData*)clientCert {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=getservercert&salt=%@&clientcert=%@",
                           _baseHTTPURL, _uniqueId, _deviceName, [self bytesToHex:salt], [self bytesToHex:clientCert]];
    // This call blocks while waiting for the user to input the PIN on the PC
    return [self createRequestFromString:urlString timeout:EXTRA_LONG_TIMEOUT_SEC];
}

- (NSURLRequest*) newUnpairRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/unpair?uniqueid=%@", _baseHTTPURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*) newChallengeRequest:(NSData*)challenge {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientchallenge=%@",
                           _baseHTTPURL, _uniqueId, _deviceName, [self bytesToHex:challenge]];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*) newChallengeRespRequest:(NSData*)challengeResp {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&serverchallengeresp=%@",
                           _baseHTTPURL, _uniqueId, _deviceName, [self bytesToHex:challengeResp]];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*) newClientSecretRespRequest:(NSString*)clientPairSecret {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientpairingsecret=%@", _baseHTTPURL, _uniqueId, _deviceName, clientPairSecret];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*) newPairChallenge {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }
    
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=pairchallenge", _baseHTTPSURL, _uniqueId, _deviceName];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest *)newAppListRequest {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }
    
    NSString* urlString = [NSString stringWithFormat:@"%@/applist?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest *)newServerInfoRequest:(bool)fastFail {
    if (_serverCert == nil) {
        // Use HTTP if the cert is not pinned yet
        return [self newHttpServerInfoRequest:fastFail];
    }
    
    if (![self ensureHttpsUrlPopulated:fastFail]) {
        return nil;
    }
    
    NSString* urlString = [NSString stringWithFormat:@"%@/serverinfo?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:(fastFail ? SHORT_TIMEOUT_SEC : NORMAL_TIMEOUT_SEC)];
}

- (NSURLRequest *)newHttpServerInfoRequest:(bool)fastFail {
    NSString* urlString = [NSString stringWithFormat:@"%@/serverinfo", _baseHTTPURL];
    return [self createRequestFromString:urlString timeout:(fastFail ? SHORT_TIMEOUT_SEC : NORMAL_TIMEOUT_SEC)];
}

- (NSURLRequest *)newHttpServerInfoRequest {
    return [self newHttpServerInfoRequest:false];
}

- (NSURLRequest*) newLaunchOrResumeRequest:(NSString*)verb config:(StreamConfiguration*)config {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }
    
    // Using an FPS value over 60 causes SOPS to default to 720p60,
    // so force it to 0 to ensure the correct resolution is set. We
    // used to use 60 here but that locked the frame rate to 60 FPS
    // on GFE 3.20.3. We do not do this hack for Sunshine (which is
    // indicated by a negative version in the last field.
    int fps = (config.frameRate > 60 && ![config.appVersion containsString:@".-"]) ? 0 : config.frameRate;
    
    // Starwire: Vibeshine's launch options from the settings (virtualDisplay, scaleFactor,
    // clientVrrRequested, clientName), and an exact rate such as 119.88 in mode when the settings
    // ask for one (StarwireSettings.swift)
    NSString* mode = fps == config.frameRate
        ? [StarwireSettings launchModeWithWidth:config.width height:config.height frameRate:config.frameRate]
        : [NSString stringWithFormat:@"%dx%dx%d", config.width, config.height, fps];
    NSString* vibeshineOptions = [StarwireSettings launchQueryExtrasWithWidth:config.width height:config.height frameRate:config.frameRate];
    Log(LOG_I, @"Launch options: %@", [StarwireSettings launchSummaryWithWidth:config.width height:config.height frameRate:config.frameRate]);
    NSString* urlString = [NSString stringWithFormat:@"%@/%@?uniqueid=%@&appid=%@&mode=%@&additionalStates=1&sops=%d&rikey=%@&rikeyid=%d%@&localAudioPlayMode=%d&surroundAudioInfo=%d&remoteControllersBitmap=%d&gcmap=%d&gcpersist=%d%@%s",
                           _baseHTTPSURL, verb, _uniqueId,
                           config.appID,
                           mode,
                           config.optimizeGameSettings ? 1 : 0,
                           [Utils bytesToHex:config.riKey], config.riKeyId,
                           (config.supportedVideoFormats & VIDEO_FORMAT_MASK_10BIT) ? @"&hdrMode=1&clientHdrCapVersion=0&clientHdrCapSupportedFlagsInUint32=0&clientHdrCapMetaDataId=NV_STATIC_METADATA_TYPE_1&clientHdrCapDisplayData=0x0x0x0x0x0x0x0x0x0x0": @"",
                           config.playAudioOnPC ? 1 : 0,
                           SURROUNDAUDIOINFO_FROM_AUDIO_CONFIGURATION(config.audioConfiguration),
                           config.gamepadMask, config.gamepadMask,
                           !config.multiController ? 1 : 0,
                           vibeshineOptions,
                           LiGetLaunchUrlQueryParameters()];
    Log(LOG_I, @"Requesting: %@", [HttpManager redactSecrets:urlString]);
    // This blocks while the app is launching
    return [self createRequestFromString:urlString timeout:LONG_TIMEOUT_SEC];
}

- (NSURLRequest*) newQuitAppRequest {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }
    
    NSString* urlString = [NSString stringWithFormat:@"%@/cancel?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:LONG_TIMEOUT_SEC];
}

- (NSURLRequest*) newAppAssetRequestWithAppId:(NSString *)appId {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }
    
    NSString* urlString = [NSString stringWithFormat:@"%@/appasset?uniqueid=%@&appid=%@&AssetType=2&AssetIdx=0", _baseHTTPSURL, _uniqueId, appId];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSString*) bytesToHex:(NSData*)data {
    const unsigned char* bytes = [data bytes];
    NSMutableString *hex = [[NSMutableString alloc] init];
    for (int i = 0; i < [data length]; i++) {
        [hex appendFormat:@"%02X" , bytes[i]];
    }
    return hex;
}

// Returns an array containing the certificate
- (NSArray*)getCertificate:(SecIdentityRef) identity {
    SecCertificateRef certificate = nil;
    
    SecIdentityCopyCertificate(identity, &certificate);
    
    return [[NSArray alloc] initWithObjects:(__bridge_transfer id)certificate, nil];
}

// Returns the identity
- (SecIdentityRef)getClientCertificate {
    SecIdentityRef identityApp = nil;
    CFDataRef p12Data = (__bridge CFDataRef)[CryptoManager readP12FromFile];

    CFStringRef password = CFSTR("limelight");
    const void *keys[] = { kSecImportExportPassphrase };
    const void *values[] = { password };
    CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    CFArrayRef items = nil;
    OSStatus securityError = SecPKCS12Import(p12Data, options, &items);

    if (securityError == errSecSuccess) {
        //Log(LOG_D, @"Success opening p12 certificate. Items: %ld", CFArrayGetCount(items));
        CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
        identityApp = (SecIdentityRef)CFRetain(CFDictionaryGetValue(identityDict, kSecImportItemIdentity));
        CFRelease(items);
    } else {
        Log(LOG_E, @"Error opening Certificate.");
    }
    
    CFRelease(options);
    CFRelease(password);
    
    return identityApp;
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(nonnull void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * __nullable))completionHandler {
    // Allow untrusted server certificates
    if([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        if (SecTrustGetCertificateCount(challenge.protectionSpace.serverTrust) != 1) {
            Log(LOG_E, @"Server certificate count mismatch");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }
        
        SecCertificateRef actualCert = SecTrustGetCertificateAtIndex(challenge.protectionSpace.serverTrust, 0);
        if (actualCert == nil) {
            Log(LOG_E, @"Server certificate parsing error");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }
        
        CFDataRef actualCertData = SecCertificateCopyData(actualCert);
        if (actualCertData == nil) {
            Log(LOG_E, @"Server certificate data parsing error");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }
        
        if (!CFEqual(actualCertData, (__bridge CFDataRef)_serverCert)) {
            Log(LOG_E, @"Server certificate mismatch");
            CFRelease(actualCertData);
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }
        
        CFRelease(actualCertData);
        
        // Allow TLS handshake to proceed
        completionHandler(NSURLSessionAuthChallengeUseCredential,
                          [NSURLCredential credentialForTrust: challenge.protectionSpace.serverTrust]);
    }
    // Respond to client certificate challenge with our certificate
    else if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate])
    {
        SecIdentityRef identity = [self getClientCertificate];
        NSArray* certArray = [self getCertificate:identity];
        NSURLCredential* newCredential = [NSURLCredential credentialWithIdentity:identity certificates:certArray persistence:NSURLCredentialPersistencePermanent];
        CFRelease(identity);
        completionHandler(NSURLSessionAuthChallengeUseCredential, newCredential);
    }
    else
    {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
    }
}

@end
