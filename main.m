#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

#pragma mark - 全局配置

static BOOL g_replaceEnabled = NO;
static NSURL *g_selectedVideoURL = nil;
static AVAssetReader *g_assetReader = nil;
static dispatch_queue_t g_videoQueue = nil;

#pragma mark - 导出给 UI 调用的接口

void setVirtualVideoEnabled(BOOL enabled) {
    g_replaceEnabled = enabled;
    NSLog(@"[VirtualVideo] setVirtualVideoEnabled: %@", enabled ? @"ON" : @"OFF");
}

BOOL isVirtualVideoEnabled(void) {
    return g_replaceEnabled;
}

void setSelectedVideoPath(NSString *videoPath) {
    if (!videoPath) {
        g_selectedVideoURL = nil;
        return;
    }
    g_selectedVideoURL = [NSURL fileURLWithPath:videoPath];
    NSLog(@"[VirtualVideo] setSelectedVideoPath: %@", videoPath);
}

NSString *getSelectedVideoPath(void) {
    return g_selectedVideoURL.path;
}

#pragma mark - 视频帧读取

static CMSampleBufferRef createBlackSampleBuffer(CMSampleBufferRef originalBuffer) {
    if (!originalBuffer) return NULL;

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(originalBuffer);
    if (!pixelBuffer) return NULL;

    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);

    CVPixelBufferRef newPixelBuffer = NULL;
    NSDictionary *attrs = @{
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };

    CVReturn ret = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attrs,
        &newPixelBuffer
    );

    if (ret != kCVReturnSuccess) return NULL;

    CVPixelBufferLockBaseAddress(newPixelBuffer, 0);
    void *baseAddr = CVPixelBufferGetBaseAddress(newPixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(newPixelBuffer);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        baseAddr,
        width,
        height,
        8,
        bytesPerRow,
        colorSpace,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
    );
    CGColorSpaceRelease(colorSpace);

    if (ctx) {
        CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
        CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
        CGContextRelease(ctx);
    }

    CVPixelBufferUnlockBaseAddress(newPixelBuffer, 0);

    CMVideoFormatDescriptionRef fmtDesc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault,
        newPixelBuffer,
        &fmtDesc
    );

    CMSampleTimingInfo timing;
    CMSampleBufferGetSampleTimingInfo(originalBuffer, 0, &timing);

    CMSampleBufferRef newSampleBuffer = NULL;
    CMSampleBufferCreateForImageBuffer(
        kCFAllocatorDefault,
        newPixelBuffer,
        YES,
        NULL,
        NULL,
        fmtDesc,
        &timing,
        &newSampleBuffer
    );

    CFRelease(fmtDesc);
    CVPixelBufferRelease(newPixelBuffer);

    return newSampleBuffer;
}

static CMSampleBufferRef readNextVideoFrame(void) {
    if (!g_selectedVideoURL) return NULL;

    if (!g_assetReader) {
        AVAsset *asset = [AVAsset assetWithURL:g_selectedVideoURL];
        AVAssetTrack *track = [asset.tracks filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"mediaType == %@", AVMediaTypeVideo]].firstObject;
        if (!track) return NULL;

        NSDictionary *outputSettings = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
        };

        NSError *error = nil;
        g_assetReader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
        if (!g_assetReader || error) return NULL;

        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:outputSettings];
        [g_assetReader addOutput:output];
        [g_assetReader startReading];
    }

    AVAssetReaderTrackOutput *output = g_assetReader.outputs.firstObject;
    CMSampleBufferRef sampleBuffer = [output copyNextSampleBuffer];

    if (!sampleBuffer) {
        [g_assetReader cancelReading];
        g_assetReader = nil;
    }

    return sampleBuffer;
}

#pragma mark - AVCaptureOutput Hook

static void (*orig_captureOutput)(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection);

static void vcam_captureOutput(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) {
    if (!g_replaceEnabled || !g_selectedVideoURL) {
        if (orig_captureOutput) {
            orig_captureOutput(self, _cmd, output, sampleBuffer, connection);
        }
        return;
    }

    CMSampleBufferRef videoFrame = readNextVideoFrame();

    if (videoFrame) {
        if (orig_captureOutput) {
            orig_captureOutput(self, _cmd, output, videoFrame, connection);
        }
        CFRelease(videoFrame);
    } else {
        CMSampleBufferRef blackFrame = createBlackSampleBuffer(sampleBuffer);
        if (blackFrame) {
            if (orig_captureOutput) {
                orig_captureOutput(self, _cmd, output, blackFrame, connection);
            }
            CFRelease(blackFrame);
        } else {
            if (orig_captureOutput) {
                orig_captureOutput(self, _cmd, output, sampleBuffer, connection);
            }
        }
    }
}

#pragma mark - Hook 入口

__attribute__((constructor))
static void initVirtualVideo(void) {
    @autoreleasepool {
        NSLog(@"[VirtualVideo] loaded");

        g_videoQueue = dispatch_queue_create("com.virtualvideo.queue", DISPATCH_QUEUE_SERIAL);

        Class cls = objc_getClass("AVCaptureOutput");
        if (!cls) return;

        SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
        Method orig = class_getInstanceMethod(cls, sel);

        if (orig) {
            IMP newImp = (IMP)vcam_captureOutput;
            orig_captureOutput = (void (*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))method_getImplementation(orig);
            method_setImplementation(orig, newImp);
            NSLog(@"[VirtualVideo] hooked captureOutput");
        }
    }
}
