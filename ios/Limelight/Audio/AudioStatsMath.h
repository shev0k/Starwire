//
//  AudioStatsMath.h
//  Starwire
//
//  The arithmetic behind the overlay's audio line, apart from the audio unit so it can be tested.
//  Plain C, so Objective-C tests can call it.
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Shorter windows than this aren't sampled: the overlay can be read twice in a few
// milliseconds, and dividing a packet's bytes by that gave bitrates in the billions of kbps
#define AUDIO_STATS_MIN_WINDOW 0.25

// Kilobits per second for `bytes` over `seconds`, or -1 when the window is too short to say
double AudioStatsKbps(double bytes, double seconds);
// Mean milliseconds per packet, or -1 when there were no packets (it was "nan" before)
double AudioStatsMeanMs(double totalMs, int packets);

#ifdef __cplusplus
}
#endif
