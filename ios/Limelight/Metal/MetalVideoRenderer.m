#import "MetalVideoRenderer.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>
#import "ImGuiPlots.h"
#import "FrameQueue.h"
#import "PacingPolicy.h"
#import "VideoFormatPolicy.h"
#import <os/signpost.h>

#include <Limelight.h>

#undef LOG_FILE_CATEGORY
#define LOG_FILE_CATEGORY LOGCAT_VIDEO

#define MAX_VIDEO_PLANES 3

struct CscParams {
    vector_float3 matrix[3];
    vector_float3 offsets;
};

struct ParamBuffer {
    struct CscParams cscParams;
};

static const struct CscParams k_CscParams_Bt601Lim = {
    // CSC Matrix
    {{1.1644f, 0.0f, 1.5960f}, {1.1644f, -0.3917f, -0.8129f}, {1.1644f, 2.0172f, 0.0f}},

    // Offsets
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt601Full = {
    {
        {1.0f, 0.0f, 1.4020f},
        {1.0f, -0.3441f, -0.7141f},
        {1.0f, 1.7720f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt709Lim = {
    {
        {1.1644f, 0.0f, 1.7927f},
        {1.1644f, -0.2132f, -0.5329f},
        {1.1644f, 2.1124f, 0.0f},
    },
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt709Full = {
    {
        {1.0f, 0.0f, 1.5748f},
        {1.0f, -0.1873f, -0.4681f},
        {1.0f, 1.8556f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt2020Lim_10bit = {
    {
        {1.1644f, 0.0f, 1.6781f},
        {1.1644f, -0.1874f, -0.6505f},
        {1.1644f, 2.1418f, 0.0f},
    },
    {64.0f / 1023.0f, 512.0f / 1023.0f, 512.0f / 1023.0f},
};
static const struct CscParams k_CscParams_Bt2020Full_10bit = {
    {
        {1.0f, 0.0f, 1.4746f},
        {1.0f, -0.1646f, -0.5714f},
        {1.0f, 1.8814f, 0.0f},
    },
    {0.0f, 512.0f / 1023.0f, 512.0f / 1023.0f},
};

struct Vertex {
    vector_float4 position;
    vector_float2 texCoord;
};

static const NSUInteger MaxFramesInFlight = 3;

MetalLayerMode MetalLayerModeForFrame(BOOL isPQ, BOOL edrAvailable) {
    if (!isPQ) {
        return MetalLayerModeSDR;
    }
    return edrAvailable ? MetalLayerModeEDR : MetalLayerModePQ;
}

// The layer's colorspace name, for the stats overlay. Guarded by @synchronized on the class,
// because a new renderer can start while the old one is being freed (from VoidLink).
static NSString *__currentColorSpace;

static void SetCurrentColorSpaceName(CFStringRef name) {
    @synchronized([MetalVideoRenderer class]) {
        __currentColorSpace = name ? [(__bridge NSString *)name copy] : nil;
    }
}

typedef struct {
    CVMetalTextureRef textures[MAX_VIDEO_PLANES];
} FrameTextures;

static void ReleaseTextures(CVMetalTextureRef *textures, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (textures[i]) {
            CFRelease(textures[i]);
            textures[i] = NULL;
        }
    }
}

@implementation MetalVideoRenderer {
    dispatch_queue_t _sq;
    id<MTLDevice> _device;
    float _framerate;
    id<ConnectionCallbacks> _callbacks;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _shaderLibrary;
    id<MTLRenderPipelineState> _videoPipelineState[MAX_VIDEO_PLANES];
    MTLRenderPassDescriptor *_renderPassDescriptor;
    CVMetalTextureCacheRef _textureCache;

    float _currentEDRHeadroom;
    int _lastColorSpace;
    BOOL _lastFullRange;
    size_t _lastFrameWidth;
    size_t _lastFrameHeight;
    size_t _lastDrawableWidth;
    size_t _lastDrawableHeight;
    id<MTLBuffer> _CscParamsBuffer;
    id<MTLBuffer> _VideoVertexBuffer;

    // https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work?language=objc
    dispatch_semaphore_t _inFlightSemaphore;
}

- (instancetype)initWithMetalDevice:(id<MTLDevice>)device drawablePixelFormat:(MTLPixelFormat)drawablePixelFormat framerate:(float)framerate {
    self = [super init];
    if (self) {
        _sq = dispatch_queue_create("com.moonlight.MetalVideoRenderer",
                                    dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
        _averageGPUTime = (1.0f / framerate) / 2;
        _device = device;
        _colorPixelFormat = MTLPixelFormatBGR10A2Unorm;
        _framerate = framerate;
        _commandQueue = [_device newCommandQueue];
        _currentEDRHeadroom = 1.0f;
        _lastColorSpace = -1;
        _lastFullRange = NO;
        _lastPresented = 0.0f;
        _inFlightSemaphore = dispatch_semaphore_create(MaxFramesInFlight);
        _isStopping = NO;
        _minimumPresentDuration = PacingMinimumPresentDuration(PresentTimingNearestRefresh, framerate, framerate);

        CFStringRef keys[1] = {kCVMetalTextureUsage};
        NSUInteger values[1] = {MTLTextureUsageShaderRead};
        CFDictionaryRef cacheAttributes = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 1, NULL, NULL);
        CVMetalTextureCacheCreate(kCFAllocatorDefault, cacheAttributes, _device, NULL, &_textureCache);
        CFRelease(cacheAttributes);

        _renderPassDescriptor = [MTLRenderPassDescriptor new];
        _renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        _renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    }
    return self;
}

- (void)dealloc {
    Log(LOG_I, @"MetalVideoRenderer dealloc");

    if (_commandQueue) {
        _commandQueue = nil;
    }
    if (_CscParamsBuffer) {
        _CscParamsBuffer = nil;
    }
    if (_VideoVertexBuffer) {
        _VideoVertexBuffer = nil;
    }
    for (int i = 0; i < MAX_VIDEO_PLANES; i++) {
        if (_videoPipelineState[i]) {
            _videoPipelineState[i] = nil;
        }
    }
    if (_renderPassDescriptor) {
        _renderPassDescriptor = nil;
    }
    if (_textureCache) {
        // A CF object: setting it to nil leaked it
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
    // __currentColorSpace isn't cleared here: the next renderer may already have set it
}

// Layer properties can only be changed on the main thread. The render thread used to
// dispatch_sync there, which deadlocked when the main thread was waiting for the render thread
// to finish (MetalView shutdown). This waits in short steps and gives up once the renderer is
// stopping, cancelling the block if it hasn't started.
- (BOOL)performOnMainAndWait:(dispatch_block_t)work {
    if ([NSThread isMainThread]) {
        work();
        return YES;
    }
    dispatch_block_t block = dispatch_block_create(0, work);
    dispatch_async(dispatch_get_main_queue(), block);
    while (dispatch_block_wait(block, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC)) != 0) {
        if (self.isStopping) {
            dispatch_block_cancel(block);
            Log(LOG_W, @"[MetalVideoRenderer] stopping, layer change on the main thread abandoned");
            return NO;
        }
    }
    return YES;
}

#if !TARGET_OS_TV
- (void)reportMaxEDRHeadroom {
    CGFloat maxHeadroom = [[UIScreen mainScreen] potentialEDRHeadroom];
    if (maxHeadroom > 1.0) {
        LogOnce(LOG_I, @"Display supports EDR with a max headroom of %.1f", maxHeadroom);
    } else {
        LogOnce(LOG_I, @"Display does not support EDR");
    }
}

- (void)pollCurrentEDRHeadroom {
    CGFloat headroom = [[UIScreen mainScreen] currentEDRHeadroom];
    if (headroom != _currentEDRHeadroom) {
        Log(LOG_I, @"EDR headroom changed to %.1f", headroom);
        _currentEDRHeadroom = (float)headroom;
    }
}

- (void)setInitialEDRMetadata {
}

- (void)applyEDRFromFrame:(Frame *)frame withColorspace:(int)colorspace toLayer:(CAMetalLayer *)layer {
    // Guards from VoidLink. Used for PQ frames only (MetalLayerModeForFrame).
    if (!frame || !layer) {
        Log(LOG_E, @"applyEDRFromFrame called with nil frame or layer");
        return;
    }
    [self reportMaxEDRHeadroom];
    [self setInitialEDRMetadata];

    CFDictionaryRef ext = [frame getFormatDescExtensions];
    CFStringRef frame_trc = ext ? CFDictionaryGetValue(ext, kCVImageBufferTransferFunctionKey) : NULL;

    // These can only be changed on the main thread
    [self performOnMainAndWait:^{
        layer.wantsExtendedDynamicRangeContent = YES;
        layer.pixelFormat = MTLPixelFormatRGBA16Float;

        CFStringRef name;
        switch (colorspace) {
            case COLORSPACE_REC_2020:
                name = kCGColorSpaceExtendedLinearITUR_2020;
                break;
            case COLORSPACE_REC_601:
                name = kCGColorSpaceExtendedLinearSRGB;
                break;
            case COLORSPACE_REC_709:
            default:
                name = kCGColorSpaceExtendedLinearSRGB;
                break;
        }

        CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(name);
        layer.colorspace = colorspace;
        CGColorSpaceRelease(colorspace);

        CFDataRef masteringDisplayColorVolume = frame.pixelBuffer ? CVBufferCopyAttachment(frame.pixelBuffer, kCVImageBufferMasteringDisplayColorVolumeKey, nil) : NULL;
        CFDataRef contentLightLevel = frame.pixelBuffer ? CVBufferCopyAttachment(frame.pixelBuffer, kCVImageBufferContentLightLevelInfoKey, nil) : NULL;
        if (masteringDisplayColorVolume) {
            // This tone-mapper does receive the host's max nits in MDCV when connecting to Windows,
            // but I think using this for tone-mapping would break apps not using system calibration (most apps).
            layer.EDRMetadata = [CAEDRMetadata HDR10MetadataWithDisplayInfo:(__bridge NSData *)masteringDisplayColorVolume
                                                                contentInfo:contentLightLevel ? (__bridge NSData *)contentLightLevel : nil
                                                         opticalOutputScale:100.0f];
        } else {
            layer.EDRMetadata = [CAEDRMetadata HDR10MetadataWithMinLuminance:0.005f
                                                                maxLuminance:1000.0f
                                                          opticalOutputScale:100.0f];
        }
        // The copies are ours to release (they leaked before)
        if (masteringDisplayColorVolume) {
            CFRelease(masteringDisplayColorVolume);
        }
        if (contentLightLevel) {
            CFRelease(contentLightLevel);
        }
        LogOnce(LOG_I, @"EDRMetadata set to colorspace %@, transfer function %@, %@", layer.colorspace,
                frame_trc ? (__bridge NSString *)frame_trc : @"<none>", layer.EDRMetadata);
    }];
}
#endif

- (int)getFrameColorspaceAndRange:(Frame *)frame isFullRange:(BOOL *)isFullRange {
    CFDictionaryRef ext = [frame getFormatDescExtensions];

    // FQLog(LOG_I, @"%@", ext);

    *isFullRange = NO;
    // The range of the pixels as decoded: VideoToolbox converts to the pixel format's range, so
    // that, not the stream's, is what the colour matrix must undo
    BOOL rangeKnown = NO;
    if (frame.pixelBuffer) {
        *isFullRange = StreamPixelFormatIsFullRange(CVPixelBufferGetPixelFormatType(frame.pixelBuffer), &rangeKnown);
    }

    // No extensions, for example while the decoder is being rebuilt: use the defaults (VoidLink)
    if (!ext) {
        return COLORSPACE_REC_601;
    }

    // Full Range boolean, for a pixel format not listed above
    CFBooleanRef fullRangeRef = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_FullRangeVideo);
    if (!rangeKnown && fullRangeRef && CFGetTypeID(fullRangeRef) == CFBooleanGetTypeID()) {
        *isFullRange = CFBooleanGetValue(fullRangeRef);
    }

    // Colorspace
    CFStringRef frame_color = CFDictionaryGetValue(ext, kCVImageBufferColorPrimariesKey);
    // CFEqual crashes on NULL, and the key can be missing
    if (frame_color && CFEqual(frame_color, kCVImageBufferColorPrimaries_ITU_R_709_2)) {
        return COLORSPACE_REC_709;
    } else if (frame_color && CFEqual(frame_color, kCVImageBufferColorPrimaries_ITU_R_2020)) {
        return COLORSPACE_REC_2020;
    }
    return COLORSPACE_REC_601;
}

- (BOOL)updateColorSpaceForFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer layerDidChange:(BOOL *)layerDidChange {
    BOOL fullRange = NO;
    int colorspace = [self getFrameColorspaceAndRange:frame isFullRange:&fullRange];
    if (colorspace != _lastColorSpace || fullRange != _lastFullRange) {
        CGColorSpaceRef newColorSpace = nil;
        MTLPixelFormat newPixelFormat = layer.pixelFormat;
        BOOL isHDR = NO;
        struct ParamBuffer paramBuffer;

        switch (colorspace) {
            case COLORSPACE_REC_709:
                newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
                newPixelFormat = MTLPixelFormatBGRA8Unorm;
                paramBuffer.cscParams = (fullRange ? k_CscParams_Bt709Full : k_CscParams_Bt709Lim);
                break;
            case COLORSPACE_REC_2020: {
                CFDictionaryRef ext = [frame getFormatDescExtensions];
                CFStringRef frame_trc = ext ? CFDictionaryGetValue(ext, kCVImageBufferTransferFunctionKey) : NULL;
                if (frame_trc && CFEqual(frame_trc, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)) {
                    isHDR = YES;
                    newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
                } else {
                    // SDR 2020, I'm not sure it's possible to stream this though
                    newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020);
                }
                newPixelFormat = MTLPixelFormatBGR10A2Unorm;
                paramBuffer.cscParams = (fullRange ? k_CscParams_Bt2020Full_10bit : k_CscParams_Bt2020Lim_10bit);
                break;
            }
            case COLORSPACE_REC_601:
                newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                newPixelFormat = MTLPixelFormatBGRA8Unorm;
                paramBuffer.cscParams = (fullRange ? k_CscParams_Bt601Full : k_CscParams_Bt601Lim);
        }

        // The CAMetalLayer retains the CGColorSpace
        if (newColorSpace || newPixelFormat != layer.pixelFormat) {
            *layerDidChange = YES;
            if (newColorSpace) {
                Log(LOG_I,
                    @"Frame colorspace %@ - changing MetalLayer's colorspace to %@",
                    colorspace == COLORSPACE_REC_709        ? @"REC_709"
                        : colorspace == COLORSPACE_REC_2020 ? @"REC_2020"
                        : colorspace == COLORSPACE_REC_601  ? @"REC_601 (sRGB)"
                                                            : [NSString stringWithFormat:@"Unknown: %d", colorspace],
                    newColorSpace);
            }
            if (newPixelFormat != layer.pixelFormat) {
                Log(LOG_I,
                    @"Frame pixel format %@ - changing MetalLayer's pixel format to %@",
                    layer.pixelFormat == MTLPixelFormatBGRA8Unorm         ? @"MTLPixelFormatBGRA8Unorm"
                        : layer.pixelFormat == MTLPixelFormatBGR10A2Unorm ? @"MTLPixelFormatBGR10A2Unorm"
                                                                          : [NSString stringWithFormat:@"Unknown: %lu", (unsigned long)layer.pixelFormat],
                    newPixelFormat == MTLPixelFormatBGRA8Unorm         ? @"MTLPixelFormatBGRA8Unorm"
                        : newPixelFormat == MTLPixelFormatBGR10A2Unorm ? @"MTLPixelFormatBGR10A2Unorm"
                                                                       : [NSString stringWithFormat:@"Unknown: %lu", (unsigned long)newPixelFormat]);
            }

#if TARGET_OS_TV
            // These can only be changed on the main thread
            [self performOnMainAndWait:^{
                layer.colorspace = newColorSpace;
                layer.pixelFormat = newPixelFormat;
            }];
#else
            MetalLayerMode mode = MetalLayerModeForFrame(isHDR, [CAEDRMetadata isAvailable]);
            Log(LOG_I, @"Layer mode %@", mode == MetalLayerModeEDR ? @"HDR10 with EDR" : mode == MetalLayerModePQ ? @"HDR10 as PQ" : @"SDR");
            if (mode == MetalLayerModeEDR) {
                [self applyEDRFromFrame:frame withColorspace:colorspace toLayer:layer];
            } else {
                // These can only be changed on the main thread. Leaving HDR clears what EDR set.
                [self performOnMainAndWait:^{
                    layer.wantsExtendedDynamicRangeContent = isHDR;
                    layer.EDRMetadata = nil;
                    layer.colorspace = newColorSpace;
                    layer.pixelFormat = newPixelFormat;
                }];
            }
#endif
            if (newColorSpace) {
                SetCurrentColorSpaceName(CGColorSpaceGetName(newColorSpace));
            }
            CGColorSpaceRelease(newColorSpace);
        }

        // Create the new colorspace parameter buffer for our fragment shader
        MTLResourceOptions bufferOptions = MTLResourceStorageModeShared;
        // Keep the old buffer if this fails (VoidLink)
        id<MTLBuffer> cscBuffer = [_device newBufferWithBytes:(void *)&paramBuffer length:sizeof(paramBuffer) options:bufferOptions];
        if (!cscBuffer) {
            Log(LOG_E, @"Failed to create CSC parameters buffer");
            return NO;
        }
        _CscParamsBuffer = cscBuffer;

        _lastColorSpace = colorspace;
        _lastFullRange = fullRange;
    }

    return YES;
}

- (void)scaleSource:(CGRect *)src toDest:(CGRect *)dst {
    int dstH = ceilf((float)dst->size.width * src->size.height / src->size.width);
    int dstW = ceilf((float)dst->size.height * src->size.width / src->size.height);

    if (dstH > dst->size.height) {
        dst->origin.x += (dst->size.width - dstW) / 2;
        dst->size.width = dstW;
    } else {
        dst->origin.y += (dst->size.height - dstH) / 2;
        dst->size.height = dstH;
    }
}

- (void)screenSpace:(CGRect *)src toNormalizedDeviceCoords:(CGRect *)dst withDrawableWidth:(int)viewportWidth drawableHeight:(int)viewportHeight {
    dst->origin.x = ((float)src->origin.x / (viewportWidth / 2.0f)) - 1.0f;
    dst->origin.y = ((float)src->origin.y / (viewportHeight / 2.0f)) - 1.0f;
    dst->size.width = (float)src->size.width / (viewportWidth / 2.0f);
    dst->size.height = (float)src->size.height / (viewportHeight / 2.0f);
}

- (BOOL)updateVideoRegionSizeForFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer {
    int drawableWidth = layer.drawableSize.width;
    int drawableHeight = layer.drawableSize.height;

    // Check if anything has changed since the last vertex buffer upload
    if (_VideoVertexBuffer && [frame width] == _lastFrameWidth && [frame height] == _lastFrameHeight && drawableWidth == _lastDrawableWidth &&
        drawableHeight == _lastDrawableHeight) {
        // Nothing to do
        return YES;
    }

    // Determine the correct scaled size for the video region
    CGRect src = CGRectMake(0.0, 0.0, [frame width], [frame height]);
    CGRect dst = CGRectMake(0.0, 0.0, drawableWidth, drawableHeight);
    [self scaleSource:&src toDest:&dst];

    // Convert screen space to normalized device coordinates
    CGRect renderRect;
    [self screenSpace:&dst toNormalizedDeviceCoords:&renderRect withDrawableWidth:drawableWidth drawableHeight:drawableHeight];

    struct Vertex verts[] = {
        {{renderRect.origin.x, renderRect.origin.y, 0.0f, 1.0f}, {0.0f, 1.0f}},
        {{renderRect.origin.x, renderRect.origin.y + renderRect.size.height, 0.0f, 1.0f}, {0.0f, 0}},
        {{renderRect.origin.x + renderRect.size.width, renderRect.origin.y, 0.0f, 1.0f}, {1.0f, 1.0f}},
        {{renderRect.origin.x + renderRect.size.width, renderRect.origin.y + renderRect.size.height, 0.0f, 1.0f}, {1.0f, 0}},
    };

    MTLResourceOptions bufferOptions = MTLResourceStorageModeShared;
    _VideoVertexBuffer = [_device newBufferWithBytes:verts length:sizeof(verts) options:bufferOptions];
    if (!_VideoVertexBuffer) {
        Log(LOG_E, @"Failed to create video vertex buffer");
        return NO;
    }

    _lastFrameWidth = [frame width];
    _lastFrameHeight = [frame height];
    _lastDrawableWidth = drawableWidth;
    _lastDrawableHeight = drawableHeight;

    return YES;
}

- (BOOL)renderFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer {
    return [self renderFrame:frame layer:layer givenDrawable:nil targetTime:0];
}

- (BOOL)renderFrame:(Frame *)frame intoDrawable:(id<CAMetalDrawable>)drawable ofLayer:(CAMetalLayer *)layer targetTime:(CFTimeInterval)targetTime {
    return [self renderFrame:frame layer:layer givenDrawable:drawable targetTime:targetTime];
}

// givenDrawable nil: the render loop, which takes the layer's next drawable. Otherwise the
// display presenter's drawable.
- (BOOL)renderFrame:(Frame *)frame layer:(CAMetalLayer *)layer givenDrawable:(id<CAMetalDrawable>)givenDrawable targetTime:(CFTimeInterval)targetTime {
    @autoreleasepool {
        if (self.isStopping) {
            return NO;
        }
        if (self.isPaused) {
            // Inactive (Control Center, the app switcher): no GPU work. The frame is let go, so
            // the queue doesn't fill up while we wait.
            return NO;
        }

        // Handle changes to the frame's colorspace from last time we rendered
        BOOL layerDidChange = NO;
        if (![self updateColorSpaceForFrame:frame toLayer:layer layerDidChange:&layerDidChange]) {
            return NO;
        }
        // A display link drawable made before the layer's pixel format changed doesn't match the
        // new pipeline. Skip this refresh; the next drawable has the new format.
        if (givenDrawable && givenDrawable.texture.pixelFormat != layer.pixelFormat) {
            Log(LOG_I, @"Drawable is from before the pixel format change, skipping frame %d", frame.frameNumber);
            return NO;
        }

        // Handle changes to the video size or drawable size
        if (![self updateVideoRegionSizeForFrame:frame toLayer:layer]) {
            return NO;
        }

        FQLog(LOG_I, @"[%d / %.3f ms] Metal frame rendering", frame.frameNumber, frame.pts);

        CVPixelBufferRef pixelBuffer = frame.pixelBuffer;
        if (!pixelBuffer) {
            Log(LOG_W, @"Frame %d has no pixel buffer, skipping it", frame.frameNumber);
            return NO;
        }

        size_t planes = CVPixelBufferGetPlaneCount(pixelBuffer);
        if (planes == 0 || planes > MAX_VIDEO_PLANES) {
            LogOnce(LOG_E, @"Unsupported plane count: %zu", planes);
            return NO;
        }

        if (layerDidChange && frame.frameNumber > 1) {
            Log(LOG_I, @"Metal frame changed layer's colorspace and/or pixel format");
            _videoPipelineState[planes] = nil;
        }

        // This is created once and cached based on the planes value
        if (!_videoPipelineState[planes]) {
            MTLRenderPipelineDescriptor *pipelineDesc = [MTLRenderPipelineDescriptor new];
            id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

            // RGB shaders
            id<MTLFunction> vertexVsDraw = [defaultLibrary newFunctionWithName:@"vs_draw"];
            id<MTLFunction> fragmentBiplanar = [defaultLibrary newFunctionWithName:@"ps_draw_biplanar"];
            id<MTLFunction> fragmentTriplanar = [defaultLibrary newFunctionWithName:@"ps_draw_triplanar"];

            // linear shaders
            id<MTLFunction> yuvToLinear = [defaultLibrary newFunctionWithName:@"yuvToLinear"];

            pipelineDesc.colorAttachments[0].pixelFormat = layer.pixelFormat;
            pipelineDesc.vertexBuffers[0].mutability = MTLMutabilityImmutable;

            if (layer.pixelFormat == MTLPixelFormatRGBA16Float) {
                // 4:2:0 or 4:4:4 YUV -> BT.2020 RGB -> linear float
                pipelineDesc.vertexFunction = vertexVsDraw;
                pipelineDesc.fragmentFunction = yuvToLinear;
            } else {
                // 4:2:0 or 4:4:4 YUV -> BT.2020 RGB
                pipelineDesc.vertexFunction = vertexVsDraw;
                pipelineDesc.fragmentFunction = (planes == 2) ? fragmentBiplanar : fragmentTriplanar;
            }

            NSError *error = nil;
            _videoPipelineState[planes] = [_device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
            if (!_videoPipelineState[planes]) {
                Log(LOG_E, @"Failed to create video pipeline state: %@", error);
                return NO;
            }
        }

        // The textures belong to this frame and are released when its command buffer completes.
        // They used to live in an ivar that the next frame overwrote, which only worked while
        // every frame waited for the GPU (waitUntilCompleted).
        CVMetalTextureRef textures[MAX_VIDEO_PLANES] = {NULL};
        for (size_t i = 0; i < planes; i++) {
            MTLPixelFormat fmt;

            switch (CVPixelBufferGetPixelFormatType(pixelBuffer)) {
                case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
                case kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange:
                case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
                case kCVPixelFormatType_444YpCbCr8BiPlanarFullRange:
                    fmt = (i == 0) ? MTLPixelFormatR8Unorm : MTLPixelFormatRG8Unorm;
                    break;

                case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
                case kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:
                case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
                case kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange:
                    fmt = (i == 0) ? MTLPixelFormatR16Unorm : MTLPixelFormatRG16Unorm;
                    break;

                default:
                    // %@ with an integer crashed here
                    Log(LOG_E, @"Unknown pixel format: 0x%08x", (unsigned int)CVPixelBufferGetPixelFormatType(pixelBuffer));
                    ReleaseTextures(textures, planes);
                    return NO;
            }

            CVReturn err = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                     _textureCache,
                                                                     pixelBuffer,
                                                                     NULL,
                                                                     fmt,
                                                                     CVPixelBufferGetWidthOfPlane(pixelBuffer, i),
                                                                     CVPixelBufferGetHeightOfPlane(pixelBuffer, i),
                                                                     i,
                                                                     &textures[i]);
            if (err != kCVReturnSuccess || !textures[i]) {
                Log(LOG_E, @"CVMetalTextureCacheCreateTextureFromImage() failed: %d", err);
                ReleaseTextures(textures, planes);
                return NO;
            }
        }

        // Bound the frames in flight. The slot is taken only when a frame is about to be drawn,
        // and given back by the command buffer's completion handler or on any failure below, so
        // a frame that isn't drawn can't leak it (VoidLink tracked this by hand).
        if (dispatch_semaphore_wait(_inFlightSemaphore, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) != 0) {
            Log(LOG_W, @"[MetalVideoRenderer] no free frame slot after 100 ms, skipping frame %d", frame.frameNumber);
            ReleaseTextures(textures, planes);
            return NO;
        }
        if (self.isStopping) {
            dispatch_semaphore_signal(_inFlightSemaphore);
            ReleaseTextures(textures, planes);
            return NO;
        }

        PacingStats *pacingStats = [FrameQueue sharedInstance].pacingStats;
        id<CAMetalDrawable> drawable = givenDrawable;
        if (!drawable) {
            // How long the loop waits here shows whether drawables, not frames, set its pace
            CFTimeInterval waitStart = CACurrentMediaTime();
            drawable = [layer nextDrawable];
            [pacingStats noteDrawableWait:CACurrentMediaTime() - waitStart];
        }
        if (!drawable) {
            Log(LOG_E, @"Failed to get nextDrawable");
            dispatch_semaphore_signal(_inFlightSemaphore);
            ReleaseTextures(textures, planes);
            return NO;
        }
        _renderPassDescriptor.colorAttachments[0].texture = drawable.texture;

        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> renderEncoder = commandBuffer ? [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDescriptor] : nil;
        if (!renderEncoder) {
            Log(LOG_E, @"Failed to create a command buffer or encoder");
            dispatch_semaphore_signal(_inFlightSemaphore);
            ReleaseTextures(textures, planes);
            return NO;
        }

        [renderEncoder setRenderPipelineState:_videoPipelineState[planes]];
        for (size_t i = 0; i < planes; i++) {
            [renderEncoder setFragmentTexture:CVMetalTextureGetTexture(textures[i]) atIndex:i];
        }

        [renderEncoder setVertexBuffer:_VideoVertexBuffer offset:0 atIndex:0];
        [renderEncoder setFragmentBuffer:_CscParamsBuffer offset:0 atIndex:0];
#if !TARGET_OS_TV
        if (layer.pixelFormat == MTLPixelFormatRGBA16Float) {
            [self pollCurrentEDRHeadroom];
            [renderEncoder setFragmentBytes:&_currentEDRHeadroom length:sizeof(float) atIndex:1];
        }
#endif
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [renderEncoder endEncoding];

        // Signposts: one "present" interval per frame, from commit until the compositor shows it
        os_log_t pacingLog = LogHandle(LOGCAT_PACING);
        os_signpost_id_t presentId = os_signpost_id_generate(pacingLog);
        os_signpost_interval_begin(pacingLog, presentId, "present", "frame %d", frame.frameNumber);

#if !TARGET_OS_SIMULATOR
        // Why can't the simulator support this?
        __weak MetalVideoRenderer *weakSelf = self;
        int frameNumber = frame.frameNumber;
        CFTimeInterval decodedAt = frame.decodedAt;
        CFTimeInterval receivedAt = frame.receivedAt;
        [drawable addPresentedHandler:^(id<MTLDrawable> d) {
            CFTimeInterval presentedTime = d.presentedTime;
            os_signpost_interval_end(pacingLog, presentId, "present", "frame %d shown %d", frameNumber, presentedTime > 0);
            // presentedTime is 0 when the compositor skipped this drawable
            [pacingStats notePresentedAt:presentedTime target:targetTime decodedAt:decodedAt receivedAt:receivedAt];
            MetalVideoRenderer *strongSelf = weakSelf;
            if (!strongSelf || presentedTime <= 0) {
                return;
            }
            if (strongSelf.lastPresented > 0.0f) {
                CFTimeInterval frametime = presentedTime - strongSelf.lastPresented;
                [[ImGuiPlots sharedInstance] observeFloat:PLOT_FRAMETIME value:(frametime * 1000.0)];
            }
            strongSelf.lastPresented = presentedTime;
        }];
#endif

        // Signal the semaphore, compute GPU time average, and release this frame's textures.
        // The frame is kept alive until the GPU is done with its pixel buffer.
        dispatch_semaphore_t block_semaphore = _inFlightSemaphore;
        CVMetalTextureCacheRef textureCache = _textureCache;
        CFRetain(textureCache);
        // A struct, because a block can't capture a C array
        FrameTextures frameTextures = {{NULL}};
        for (size_t i = 0; i < planes; i++) {
            frameTextures.textures[i] = textures[i];
        }
        __weak MetalVideoRenderer *weakRenderer = self;
        Frame *retainedFrame = frame;
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> cb) {
            const CFTimeInterval GPUTime = cb.GPUEndTime - cb.GPUStartTime;
            MetalVideoRenderer *renderer = weakRenderer;
            if (renderer && GPUTime > 0) {
                const double alpha = 0.25f;
                renderer.averageGPUTime = (GPUTime * alpha) + (renderer.averageGPUTime * (1.0 - alpha));
            }

            // Free textures after completion of rendering
            FrameTextures done = frameTextures;
            ReleaseTextures(done.textures, MAX_VIDEO_PLANES);
            CVMetalTextureCacheFlush(textureCache, 0);
            CFRelease(textureCache);
            (void)retainedFrame;

            dispatch_semaphore_signal(block_semaphore);
        }];

#if TARGET_OS_SIMULATOR
        [commandBuffer presentDrawable:drawable];
#else
        if (givenDrawable) {
            // The display link picked the refresh this drawable is for; a minimum duration
            // would only let the compositor move it later
            [commandBuffer presentDrawable:drawable];
        } else {
            // Present for a minimum duration for frame pacing. See PacingMinimumPresentDuration:
            // the old 1/fps hold sat exactly on a refresh boundary at 120 FPS on a 120 Hz display.
            [commandBuffer presentDrawable:drawable afterMinimumDuration:_minimumPresentDuration];
        }
#endif

        // No waitUntilCompleted: the in-flight semaphore already bounds the work queued on the GPU,
        // and waiting here held the render thread for the whole GPU pass of every frame.
        [commandBuffer commit];
        return YES;
    }
}

- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer {
    // The frame slot is now taken in renderFrame, once there is a frame to draw
}

- (void)shutdown {
    if (!self.isStopping) {
        self.isStopping = YES;
        Log(LOG_I, @"[MetalVideoRenderer] shutdown");

        // Ensure no rendering is in flight
        for (NSUInteger i = 0; i < MaxFramesInFlight; i++) {
            dispatch_semaphore_signal(_inFlightSemaphore);
        }

        // Drop cached textures (VoidLink). The pipelines go with the renderer, since the render
        // thread may still be using them.
        if (_textureCache) {
            CVMetalTextureCacheFlush(_textureCache, 0);
        }
    }
}

/// Responds to the drawable's size or orientation changes.
- (void)drawableResize:(CGSize)drawableSize {
    [self resize:drawableSize];
}

- (void)resize:(CGSize)size {
}

+ (NSString *)currentColorSpace {
    @synchronized([MetalVideoRenderer class]) {
        return __currentColorSpace;
    }
}

@end
