#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

static id<MTLTexture> createTextureFromImage(UIImage *img, id<MTLDevice> dev)
{
    if (!img || !dev) return nil;
    
    CGImageRef cgImage = img.CGImage;
    if (!cgImage) return nil;
    
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    size_t bytesPerPixel = 4;
    size_t bytesPerRow = width * bytesPerPixel;
    size_t bufferSize = height * bytesPerRow;
    
    uint8_t *bitmapData = malloc(bufferSize);
    if (!bitmapData) return nil;
    memset(bitmapData, 0, bufferSize);
    
    // 创建CG位图上下文
    CGContextRef cgContext = CGBitmapContextCreate(
        bitmapData,
        width,
        height,
        8,
        bytesPerRow,
        CGImageGetColorSpace(cgImage),
        kCGImageAlphaPremultipliedLast
    );
    
    if (!cgContext) {
        free(bitmapData);
        return nil;
    }
    
    // 绘制图片
    CGContextDrawImage(cgContext, CGRectMake(0,0,width,height), cgImage);
    
    // 创建Metal纹理描述
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                         width:width
                                                                                        height:height
                                                                                     mipmapped:NO];
    id<MTLTexture> texture = [dev newTextureWithDescriptor:texDesc];
    [texture replaceRegion:MTLRegionMake2D(0,0,width,height)
                mipmapLevel:0
                  withBytes:bitmapData
                bytesPerRow:bytesPerRow];
    
    // ✅ 释放CG资源！防止内存泄漏
    CGContextRelease(cgContext);
    free(bitmapData);
    
    return texture;
}

// 示例：虚拟摄像头帧生成函数，你可以按需修改
void fillSampleBufferFromImage(UIImage *img, CMSampleBufferRef *outSampleBuffer)
{
    if (!img || !outSampleBuffer) return;
    *outSampleBuffer = NULL;
    
    CGImageRef cgImage = img.CGImage;
    size_t w = CGImageGetWidth(cgImage);
    size_t h = CGImageGetHeight(cgImage);
    
    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *pixelAttr = @{
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    CVReturn ret = CVPixelBufferCreate(
        kCFAllocatorDefault,
        w,
        h,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)pixelAttr,
        &pixelBuffer
    );
    if (ret != kCVReturnSuccess) return;
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    CGContextRef ctx = CGBitmapContextCreate(
        baseAddr, w, h, 8, bytesPerRow,
        CGImageGetColorSpace(cgImage),
        kCGImageAlphaPremultipliedFirst
    );
    CGContextDrawImage(ctx, CGRectMake(0,0,w,h), cgImage);
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    CGContextRelease(ctx); // 释放CGContext
    
    CMVideoFormatDescriptionRef fmtDesc;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &fmtDesc);
    
    CMSampleTimingInfo timing = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = CMTimeMake(0, 1000),
        .decodeTimeStamp = CMTimeMake(0, 1000),
    };
    CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        fmtDesc,
        &timing,
        outSampleBuffer
    );
    
    CFRelease(fmtDesc);
    CVPixelBufferRelease(pixelBuffer);
}

// dylib入口，如果不需要main函数可以删掉
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"VirtualCam dylib loaded");
    }
    return 0;
}
