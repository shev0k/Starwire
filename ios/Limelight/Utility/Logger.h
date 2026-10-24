//
//  Logger.h
//  Moonlight
//
//  Created by Diego Waxemberg on 2/10/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//
//  Starwire: Log() now goes to the unified system log (os_log) in every build, with a category
//  per area, so a Release build on the iPad has an app log. LOG_D lines are only written when
//  verbose logging is on: always in Debug, and in Release when the "Verbose logging" setting
//  (StarwireVerboseLogging) is on.
//

#ifndef Limelight_Logger_h
#define Limelight_Logger_h

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <stdarg.h>
#import <os/log.h>
#import <QuartzCore/QuartzCore.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LOG_D,
    LOG_I,
    LOG_W,
    LOG_E
} LogLevel;

// One os_log category per area. Read them on the Mac with, for example:
//   log stream --device <udid> --predicate 'subsystem == "io.github.shev0k.starwire" && category == "pacing"'
typedef enum {
    LOGCAT_APP,
    LOGCAT_STREAM,
    LOGCAT_VIDEO,
    LOGCAT_PACING,
    LOGCAT_NETWORK,
    LOGCAT_INPUT,
    LOGCAT_AUDIO,
    LOGCAT_COUNT
} LogCategory;

#define PRFX_DEBUG @"<DEBUG>"
#define PRFX_INFO @"<INFO>"
#define PRFX_WARN @"<WARN>"
#define PRFX_ERROR @"<ERROR>"

#define LOG_SUBSYSTEM "io.github.shev0k.starwire"

void LogTag(LogLevel level, NSString* tag, NSString* fmt, ...);
void LogCat(LogCategory category, LogLevel level, NSString* fmt, ...) NS_FORMAT_FUNCTION(3, 4);

// The os_log handle for a category, also used for signposts
os_log_t LogHandle(LogCategory category);

// Whether a line at this level is written. LOG_D needs verbose logging.
BOOL LogLevelEnabled(LogLevel level);
BOOL LogVerboseEnabled(void);
// Reads StarwireVerboseLogging from the user defaults. Called at launch and before each stream.
void LogReloadSettings(void);

#ifdef __cplusplus
}
#endif

// A file picks its category by defining LOG_FILE_CATEGORY after its imports:
//   #undef LOG_FILE_CATEGORY
//   #define LOG_FILE_CATEGORY LOGCAT_VIDEO
#ifndef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_APP
#endif

// The arguments are only evaluated when the line will be written
#define Log(level, fmt, ...)                                        \
  do {                                                              \
    if (LogLevelEnabled(level)) {                                   \
      LogCat(LOG_FILE_CATEGORY, level, fmt, ##__VA_ARGS__);         \
    }                                                               \
  } while (0)

// LogOnce() is a one-time log message for use in hot areas of the code
#define CONCAT(a,b)   CONCAT2(a,b)
#define CONCAT2(a,b)  a##b

#define LogOnce(level, fmt, ...)                                    \
  do {                                                              \
    static dispatch_once_t CONCAT(_onceToken_, __LINE__);           \
    dispatch_once(&CONCAT(_onceToken_, __LINE__), ^{                \
      Log(level, fmt, ##__VA_ARGS__);                               \
    });                                                             \
  } while (0)

// FrameQueue log helpers FQLog() is a no-op unless FRAME_QUEUE_VERBOSE is defined

static inline NSString *FQQoSString(qos_class_t qos) {
    switch (qos) {
        case QOS_CLASS_USER_INTERACTIVE: return @"UI-25";
        case QOS_CLASS_USER_INITIATED:   return @"IN-19";
        case QOS_CLASS_DEFAULT:          return @"DF-15";
        case QOS_CLASS_UTILITY:          return @"UT-11";
        case QOS_CLASS_BACKGROUND:       return @"BG-09";
        default:                         return [NSString stringWithFormat:@"??-%d", qos];
    }
}

static inline NSString *FQLogPrefix(void) {
    CFTimeInterval now = CACurrentMediaTime();
    NSString *qos = FQQoSString(qos_class_self());
    return [NSString stringWithFormat:@"[%.3f] [%@]", now, qos];
}

#if defined(FRAME_QUEUE_VERBOSE)
  #define FQLog(level, fmt, ...) \
    Log(level, @"%@ " fmt, FQLogPrefix(), ##__VA_ARGS__)
#else
  #define FQLog(level, fmt, ...) do {} while(0)
#endif

#endif
