//
//  VideoFormatPolicy.h
//  Starwire
//
//  Which pixel format VideoToolbox decodes into, and which colour range the Metal renderer
//  converts from. Kept apart from the decoder so it can be tested without one.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

// The user default, and launch argument, for Android's "Force full range video" (checkbox_full_range)
extern NSString *const StreamFullRangeKey;

// Whether to ask the host for full range video (COLOR_RANGE_FULL)
BOOL StreamUsesFullRange(NSUserDefaults *defaults);

// The colour space to ask the host for (COLORSPACE_*): "601" or "709" in StreamColorSpaceKey.
// The protocol's default is Rec. 601, which the app always got before batch 1.
extern NSString *const StreamColorSpaceKey;
int StreamColorSpaceFromDefaults(NSUserDefaults *defaults);

// The pixel format to decode a stream of `videoFormat` (VIDEO_FORMAT_*) into. 4:4:4 streams keep
// their chroma and bit depth; 4:2:0 streams use 10 bits, as Andy Grundman's renderer does, which
// holds 8-bit video without loss. The range follows what was asked of the host.
OSType StreamDecoderPixelFormat(int videoFormat, BOOL fullRange);

// Whether a decoded pixel format is full range. `known` is NO for formats this doesn't list, so
// the caller can fall back to the format description.
BOOL StreamPixelFormatIsFullRange(OSType pixelFormat, BOOL *_Nullable known);

NS_ASSUME_NONNULL_END
