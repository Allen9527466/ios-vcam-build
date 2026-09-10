#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

extern Unmanaged<CMSampleBuffer> * _Nullable GetGlobalVirtualSampleBuffer(void);

@interface VirtualCamProxyDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
- (instancetype)initWithOriginal:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)orig;
@end

@implementation VirtualCamProxyDelegate

- (instancetype)initWithOriginal:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)orig {
    self = [super init];
    if(self) {
        _originalDelegate = orig;
    }
    return self;
}

- (void)captureOutput:(AVCaptureVideoDataOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CMSampleBufferRef frame = sampleBuffer;
    Unmanaged<CMSampleBuffer> *ret = GetGlobalVirtualSampleBuffer();
    if(ret) {
        frame = ret.takeRetainedValue;
    }
    if ([self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        [self.originalDelegate captureOutput:output didOutputSampleBuffer:frame fromConnection:connection];
    }
}

@end

// C导出，Swift调用
void* VirtualCamProxyDelegate_alloc(void* orig) {
    id obj = (__bridge id)orig;
    VirtualCamProxyDelegate *inst = [[VirtualCamProxyDelegate alloc] initWithOriginal:obj];
    return (__bridge_retained void*)inst;
}
