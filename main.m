#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <objc/runtime.h>

static BOOL g_vcamEnable = NO;

static void swizzle(Class cls, SEL origSel, SEL newSel)
{
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    method_exchangeImplementations(origMethod, newMethod);
}

@interface AVCaptureOutput (VCamHook)
- (void)vcam_captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
@end

@implementation AVCaptureOutput (VCamHook)

- (void)vcam_captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    // 先调用原始方法
    [self vcam_captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    
    if (!g_vcamEnable) return;
    if (!CMSampleBufferIsValid(sampleBuffer)) return;
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    void *baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t width  = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t stride = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    // BGRA 蓝色: 0xFFFF0000
    uint32_t *ptr = (uint32_t *)baseAddr;
    for(size_t y = 0; y < height; y++){
        uint32_t *row = ptr + (y * stride / 4);
        for(size_t x = 0; x < width; x++){
            row[x] = 0xFFFF0000;
        }
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer,0);
}

@end

// 悬浮按钮UI
@interface VCamFloatWindow : UIWindow
@end
@implementation VCamFloatWindow
- (instancetype)init
{
    self = [super init];
    if(self){
        self.frame = CGRectMake(50,200,70,70);
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 35;
        self.clipsToBounds = YES;
        self.hidden = NO;
        
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = self.bounds;
        [btn setTitle:@"VC" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [btn addTarget:self action:@selector(tapBtn) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
    }
    return self;
}

- (void)tapBtn
{
    g_vcamEnable = !g_vcamEnable;
    NSLog(@"VirtualCam: %@", g_vcamEnable ? @"ON" : @"OFF");
    self.backgroundColor = g_vcamEnable ? [UIColor systemRedColor] : [UIColor systemBlueColor];
}
@end

static VCamFloatWindow *g_floatWin = nil;

__attribute__((constructor))
void lib_main()
{
    // swizzle 替换方法
    Class cls = objc_getClass("AVCaptureOutput");
    SEL origSel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
    SEL newSel  = @selector(vcam_captureOutput:didOutputSampleBuffer:fromConnection:);
    swizzle(cls, origSel, newSel);
    
    // 延迟创建悬浮窗，等主线程runloop
    dispatch_async(dispatch_get_main_queue(), ^{
        g_floatWin = [[VCamFloatWindow alloc] init];
    });
}

@end
