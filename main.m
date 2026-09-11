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
    if (!g_vcamEnable)
    {
        // 关闭状态，直接放行原始画面
        [self vcam_captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer)
    {
        [self vcam_captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }

    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);

    CVPixelBufferRef newPixelBuffer = NULL;
    CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_32BGRA, NULL, &newPixelBuffer);
    CVPixelBufferLockBaseAddress(newPixelBuffer, 0);
    void *baseAddr = CVPixelBufferGetBaseAddress(newPixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(newPixelBuffer);

    // BGRA 蓝色：B=255 G=0 R=0 A=255
    uint8_t *p = (uint8_t *)baseAddr;
    for(size_t y=0; y<height; y++){
        for(size_t x=0; x<width*4; x+=4){
            p[x+0] = 255;
            p[x+1] = 0;
            p[x+2] = 0;
            p[x+3] = 255;
        }
        p += bytesPerRow;
    }
    CVPixelBufferUnlockBaseAddress(newPixelBuffer,0);

    CMSampleBufferRef newSampleBuffer = NULL;
    CMVideoFormatDescriptionRef fmtDesc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, newPixelBuffer, &fmtDesc);

    CMSampleTimingInfo timing;
    CMSampleBufferGetSampleTimingInfo(sampleBuffer,0,&timing);
    CMSampleBufferCreateForImageBuffer(NULL, newPixelBuffer, YES, NULL, NULL, fmtDesc, &timing, &newSampleBuffer);

    [self vcam_captureOutput:output didOutputSampleBuffer:newSampleBuffer fromConnection:connection];

    CFRelease(newSampleBuffer);
    CFRelease(fmtDesc);
    CVPixelBufferRelease(newPixelBuffer);
}

@end

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
    NSLog(@"VirtualCam toggle: %@", g_vcamEnable ? @"ON" : @"OFF");
    self.backgroundColor = g_vcamEnable ? [UIColor systemRedColor] : [UIColor systemBlueColor];
}
@end

static VCamFloatWindow *g_floatWin = nil;

__attribute__((constructor))
void lib_main()
{
    Class cls = objc_getClass("AVCaptureOutput");
    SEL origSel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
    SEL newSel  = @selector(vcam_captureOutput:didOutputSampleBuffer:fromConnection:);
    swizzle(cls, origSel, newSel);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        g_floatWin = [[VCamFloatWindow alloc] init];
    });
}
