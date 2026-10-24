//
//  Logger.m
//  Moonlight
//
//  Created by Diego Waxemberg on 2/10/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Logger.h"

// The user default that turns on LOG_D lines in Release builds
static NSString *const kVerboseLoggingKey = @"StarwireVerboseLogging";

static const char *const kCategoryNames[LOGCAT_COUNT] = {
    [LOGCAT_APP] = "app",
    [LOGCAT_STREAM] = "stream",
    [LOGCAT_VIDEO] = "video",
    [LOGCAT_PACING] = "pacing",
    [LOGCAT_NETWORK] = "network",
    [LOGCAT_INPUT] = "input",
    [LOGCAT_AUDIO] = "audio",
};

static os_log_t LoggerHandles[LOGCAT_COUNT];

#if defined(DEBUG)
static volatile BOOL LoggerVerbose = YES;
#else
static volatile BOOL LoggerVerbose = NO;
#endif

static void LoggerInitOnce(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (int i = 0; i < LOGCAT_COUNT; i++) {
            LoggerHandles[i] = os_log_create(LOG_SUBSYSTEM, kCategoryNames[i]);
        }
#if !defined(DEBUG)
        LoggerVerbose = [[NSUserDefaults standardUserDefaults] boolForKey:kVerboseLoggingKey];
#endif
    });
}

os_log_t LogHandle(LogCategory category) {
    LoggerInitOnce();
    if (category < 0 || category >= LOGCAT_COUNT) {
        category = LOGCAT_APP;
    }
    return LoggerHandles[category];
}

void LogReloadSettings(void) {
    LoggerInitOnce();
#if !defined(DEBUG)
    LoggerVerbose = [[NSUserDefaults standardUserDefaults] boolForKey:kVerboseLoggingKey];
#endif
}

BOOL LogVerboseEnabled(void) {
    LoggerInitOnce();
    return LoggerVerbose;
}

BOOL LogLevelEnabled(LogLevel level) {
    return level != LOG_D || LogVerboseEnabled();
}

static void LogWritev(LogCategory category, LogLevel level, NSString* tag, NSString* fmt, va_list args) {
    if (!LogLevelEnabled(level)) {
        return;
    }

    NSString* levelPrefix;
    os_log_type_t type;
    switch (level) {
        case LOG_D:
            levelPrefix = PRFX_DEBUG;
            type = OS_LOG_TYPE_DEBUG;
            break;
        case LOG_I:
            levelPrefix = PRFX_INFO;
            // DEFAULT rather than INFO, so the line is kept and shown without extra log flags
            type = OS_LOG_TYPE_DEFAULT;
            break;
        case LOG_W:
            levelPrefix = PRFX_WARN;
            type = OS_LOG_TYPE_DEFAULT;
            break;
        case LOG_E:
        default:
            levelPrefix = PRFX_ERROR;
            type = OS_LOG_TYPE_ERROR;
            break;
    }

    NSString* message = [[NSString alloc] initWithFormat:fmt arguments:args];
    os_log_t handle = LogHandle(category);
    // The app's own messages are public so they can be read from the Mac. They must never
    // contain keys, PINs or certificates.
    if (tag) {
        os_log_with_type(handle, type, "%{public}@ (%{public}@) %{public}@", levelPrefix, tag, message);
    } else {
        os_log_with_type(handle, type, "%{public}@ %{public}@", levelPrefix, message);
    }
}

void LogCat(LogCategory category, LogLevel level, NSString* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    LogWritev(category, level, nil, fmt, args);
    va_end(args);
}

void LogTag(LogLevel level, NSString* tag, NSString* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    LogWritev(LOGCAT_APP, level, tag, fmt, args);
    va_end(args);
}
