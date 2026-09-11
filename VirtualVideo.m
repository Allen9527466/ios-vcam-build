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
static IMP origCaptureOutputImp = NULL;

// ========= 对外导出C接口，给你原来的CustomMenuView UI直接调用 =========
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

// ========= 内部视频处理 =========
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

static CMSampleBufferRef readNextVideoFrame(void) {
    if(!g_selectedVideoURL) return NULL;
    if(!g_assetReader){
        AVAsset *asset = [AVAsset assetWithURL:g_selectedVideoURL];
        AVAssetTrack *track = [[asset.tracks filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"mediaType == %@",AVMediaTypeVideo]] firstObject];
        if(!track) return NULL;
        NSDictionary *outSetting = @{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
        NSError *err;
        g_assetReader = [[AVAssetReader alloc] initWithAsset:asset error:&err];
        if(!g_assetReader || err) return NULL;
        AVAssetReaderTrackOutput *out = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:outSetting];
        [g_assetReader addOutput:out];
        [g_assetReader startReading];
    }
    AVAssetReaderTrackOutput *out = g_assetReader.outputs.firstObject;
    CMSampleBufferRef buf = [out copyNextSampleBuffer];
    if(!buf){
        [g_assetReader cancelReading];
        g_assetReader = nil;
    }
    return buf;
}

static void vcam_captureOutput(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) {
    if (!g_replaceEnabled || !g_selectedVideoURL) {
        ((void(*)(id,SEL,id,CMSampleBufferRef,id))origCaptureOutputImp)(self,_cmd,output,sampleBuffer,connection);
        return;
    }
    CMSampleBufferRef newFrame = readNextVideoFrame();
    if(newFrame){
        ((void(*)(id,SEL,id,CMSampleBufferRef,id))origCaptureOutputImp)(self,_cmd,output,newFrame,connection);
        CFRelease(newFrame);
    }else{
        CMSampleBufferRef black = createBlackSampleBuffer(sampleBuffer);
        if(black){
            ((void(*)(id,SEL,id,CMSampleBufferRef,id))origCaptureOutputImp)(self,_cmd,output,sampleBuffer,connection);
            CFRelease(black);
        }else{
            ((void(*)(id,SEL,id,CMSampleBufferRef,id))origCaptureOutputImp)(self,_cmd,output,sampleBuffer,connection);
        }
    }
}

// 初始化Hook，**把这个调用放到你原来项目已有的constructor入口里面，不要新建__attribute__((constructor))**
void virtualVideoSetupHook(void)
{
    @autoreleasepool {
        g_videoQueue = dispatch_queue_create("com.virtualvideo.queue",DISPATCH_QUEUE_SERIAL);
        Class cls = objc_getClass("AVCaptureOutput");
        if(!cls) return;
        SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
        Method m = class_getInstanceMethod(cls, sel);
        if(m && !origCaptureOutputImp){
            origCaptureOutputImp = method_getImplementation(m);
            method_setImplementation(m, (IMP)vcam_captureOutput);
            NSLog(@"VirtualVideo hook installed");
        }
    }
}
