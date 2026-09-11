#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreGraphics/CoreGraphics.h>
#include <objc/runtime.h>

static BOOL g_replaceEnabled = NO;
static NSURL *g_selectedVideoURL = nil;
static AVAssetReader *g_assetReader = nil;
static dispatch_queue_t g_videoQueue = nil;

@interface AVCaptureOutput (VCamHook)
- (void)vcam_captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
@end

@implementation AVCaptureOutput (VCamHook)

- (void)vcam_captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    NSLog(@"[VirtualVideo] captureOutput called, replace=%d", g_replaceEnabled);
    if (!g_replaceEnabled || !g_selectedVideoURL) {
        // 调用原始实现
        [self vcam_captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }

    CMSampleBufferRef newFrame = readNextVideoFrame();
    if(newFrame){
        [self vcam_captureOutput:output didOutputSampleBuffer:newFrame fromConnection:connection];
        CFRelease(newFrame);
    }else{
        CMSampleBufferRef black = createBlackSampleBuffer(sampleBuffer);
        if(black){
            [self vcam_captureOutput:output didOutputSampleBuffer:black fromConnection:connection];
            CFRelease(black);
        }else{
            [self vcam_captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}

@end

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
    AVAsset *asset = [AVAsset assetWithURL:g_selectedVideoURL];
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

        AVAssetReaderTrackOutput *out = g_assetReader.outputs.firstObject;
        buf = [out copyNextSampleBuffer];

        if(!buf){
            [g_assetReader cancelReading];
            g_assetReader = nil;
            resetAssetReader();
            if(g_assetReader){
                AVAssetReaderTrackOutput *out2 = g_assetReader.outputs.firstObject;
                buf = [out2 copyNextSampleBuffer];
            }
        }
    });
    return buf;
}

// ✅ PAC安全交换方法，不用直接改写IMP指针
void virtualVideoSetupHook(void)
{
    @autoreleasepool {
        g_videoQueue = dispatch_queue_create("com.virtualvideo.queue",DISPATCH_QUEUE_SERIAL);
        Class cls = objc_getClass("AVCaptureOutput");
        if(!cls) return;

        SEL origSel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
        SEL newSel = @selector(vcam_captureOutput:didOutputSampleBuffer:fromConnection:);

        Method origM = class_getInstanceMethod(cls, origSel);
        Method newM = class_getInstanceMethod(cls, newSel);
        if(origM && newM){
            method_exchangeImplementations(origM, newM);
            NSLog(@"VirtualVideo hook installed (method_exchangeImplementations)");
        }
    }
}
