#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface VirtualCamProxyDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@end

@implementation VirtualCamProxyDelegate

- (instancetype)initWithOriginal:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)orig
{
    self = [super init];
    if (self) {
        _originalDelegate = orig;
    }
    return self;
}

- (void)captureOutput:(AVCaptureVideoDataOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    // 调用Swift全局函数获取替换后的buffer
    extern CMSampleBufferRef GetGlobalVirtualSampleBuffer(void);
    CMSampleBufferRef newBuffer = GetGlobalVirtualSampleBuffer();
    
    if (newBuffer) {
        [self.originalDelegate captureOutput:output didOutputSampleBuffer:newBuffer fromConnection:connection];
    } else {
        [self.originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

@end

// 暴露给Swift调用的C函数
void* VirtualCamProxyDelegate_alloc(id orig)
{
    VirtualCamProxyDelegate *inst = [[VirtualCamProxyDelegate alloc] initWithOriginal:orig];
    return (__bridge void*)inst;
}
