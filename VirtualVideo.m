#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreGraphics/CoreGraphics.h>

static BOOL g_replaceEnabled = NO;
static NSURL *g_selectedVideoURL = nil;
static AVAssetReader *g_assetReader = nil;
static dispatch_queue_t g_videoQueue = nil;

// 对外接口，UI继续调用，状态正常保存，只是没有实际hook逻辑
__attribute__((visibility("default")))
void setVirtualVideoEnabled(BOOL enabled) {
    g_replaceEnabled = enabled;
    NSLog(@"[VirtualVideo] setVirtualVideoEnabled:%d", enabled);
}

__attribute__((visibility("default")))
BOOL isVirtualVideoEnabled(void) {
    return g_replaceEnabled;
}

__attribute__((visibility("default")))
void setSelectedVideoPath(NSString *videoPath) {
    if (!videoPath) {
        g_selectedVideoURL = nil;
        g_assetReader = nil;
        return;
    }
    g_selectedVideoURL = [NSURL fileURLWithPath:videoPath];
    g_assetReader = nil;
    NSLog(@"[VirtualVideo] video path set: %@", videoPath);
}

__attribute__((visibility("default")))
NSString *getSelectedVideoPath(void) {
    return g_selectedVideoURL.path;
}

// 帧处理工具函数保留，后续有正确hook点再调用
static CMSampleBufferRef createBlackSampleBuffer(CMSampleBufferRef originalBuffer) {
    if (!originalBuffer) return NULL;
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(originalBuffer);
    if (!pixelBuffer) return NULL;

    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    CVPixelBufferRef newPixelBuffer = NULL;
    NSDictionary *attrs = @{(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVReturn ret = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs, &newPixelBuffer);
    if (ret != kCVReturnSuccess) return NULL;

    CVPixelBufferLockBaseAddress(newPixelBuffer,0);
    void *baseAddr = CVPixelBufferGetBaseAddress(newPixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(newPixelBuffer);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(baseAddr, width, height, 8, bytesPerRow, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if(ctx){
        CGContextSetRGBFillColor(ctx,0,0,0,1);
        CGContextFillRect(ctx,CGRectMake(0,0,width,height));
        CGContextRelease(ctx);
    }
    CVPixelBufferUnlockBaseAddress(newPixelBuffer,0);

    CMVideoFormatDescriptionRef fmt = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, newPixelBuffer, &fmt);
    CMSampleTimingInfo timing;
    CMSampleBufferGetSampleTimingInfo(originalBuffer,0,&timing);
    CMSampleBufferRef sbOut = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, newPixelBuffer, YES, NULL, NULL, fmt, &timing, &sbOut);
    CFRelease(fmt);
    CVPixelBufferRelease(newPixelBuffer);
    return sbOut;
}

static void resetAssetReader(void) {
    if(!g_selectedVideoURL) return;
    AVAsset *asset = [NSURL fileURLWithPath:g_selectedVideoURL];
    AVAssetTrack *track = [[asset.tracks filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"mediaType == %@",AVMediaTypeVideo]] firstObject];
    if(!track) return;
    NSDictionary *outSetting = @{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
    NSError *err;
    g_assetReader = [[AVAssetReader alloc] initWithAsset:asset error:&err];
    if(!g_assetReader || err) return;
    AVAssetReaderTrackOutput *out = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:outSetting];
    [g_assetReader addOutput:out];
    [g_assetReader startReading];
}

static CMSampleBufferRef readNextVideoFrame(void) {
    if(!g_selectedVideoURL) return NULL;
    __block CMSampleBufferRef buf = NULL;
    dispatch_sync(g_videoQueue, ^{
        if(!g_assetReader){
            resetAssetReader();
        }
        if(!g_assetReader) return;
        AVAssetReaderTrackOutput *out = (AVAssetReaderTrackOutput *)g_assetReader.outputs.firstObject;
        buf = [out copyNextSampleBuffer];
        if(!buf){
            [g_assetReader cancelReading];
            g_assetReader = nil;
            resetAssetReader();
            if(g_assetReader){
                AVAssetReaderTrackOutput *out2 = (AVAssetReaderTrackOutput *)g_assetReader.outputs.firstObject;
                buf = [out2 copyNextSampleBuffer];
            }
        }
    });
    return buf;
}

// 空函数！！！现在不做任何hook，避免闪退，接口保留给UI调用
void virtualVideoSetupHook(void)
{
    @autoreleasepool {
        g_videoQueue = dispatch_queue_create("com.virtualvideo.queue",DISPATCH_QUEUE_SERIAL);
        NSLog(@"[VirtualVideo] hook function stub, skip AVCaptureOutput swizzle for crash safety");
    }
}
