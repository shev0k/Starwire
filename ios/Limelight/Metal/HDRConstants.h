//
//  HDRConstants.h
//  Starwire
//
//  Shared by the Metal shaders and the renderer (and its tests), so both use the same numbers and
//  the same curve. Plain C that also compiles as Metal.
//

#ifndef HDRConstants_h
#define HDRConstants_h

#ifdef __METAL_VERSION__
#include <metal_stdlib>
#define STARWIRE_EXP metal::exp
#else
#include <math.h>
#define STARWIRE_EXP expf
#endif

// HDR10 is shown relative to the screen, as Apple's own video layer (picture in picture) shows it:
// this many nits become the screen's normal white (EDR 1.0), which is BT.2408's HDR reference
// white. A Windows HDR desktop puts its white near here. Brighter parts use the screen's spare
// headroom. Shown in absolute nits instead (HDR10 EDR metadata), the desktop looked dim and
// washed out next to picture in picture on the iPad Pro M4.
#define STARWIRE_HDR_REFERENCE_WHITE_NITS 203.0f

// Where the soft roll-off starts, as a share of the headroom (never below normal white)
#define STARWIRE_HDR_KNEE 0.8f

// The brightest channel of a pixel after fitting it into `headroom` (the screen's current EDR
// headroom, at least 1): unchanged up to the knee, then eased toward the headroom so highlights
// keep some detail instead of clipping.
static inline float StarwireHDRRollOff(float value, float headroom) {
    float h = headroom > 1.0f ? headroom : 1.0f;
    float knee = STARWIRE_HDR_KNEE * h;
    if (knee < 1.0f) {
        knee = 1.0f;
    }
    if (value <= knee) {
        return value;
    }
    if (h <= knee) {
        return h;
    }
    float room = h - knee;
    return knee + room * (1.0f - STARWIRE_EXP(-(value - knee) / room));
}

#endif
