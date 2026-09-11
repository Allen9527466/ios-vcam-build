#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#include <objc/runtime.h>
#include <dlfcn.h>

// 全部用void*，不再定义CVPixelBufferRef
typedef void (*LockFunc)(void*, int);
typedef void (*UnlockFunc)(void*, int);
typedef void* (*GetBaseAddrFunc)(void*);
typedef size_t (*GetBPRFunc)(void*);
typedef size_t (*GetHeightFunc)(void*);

static LockFunc fpLock = NULL;
static UnlockFunc fpUnlock = NULL;
static GetBaseAddrFunc fpBaseAddr = NULL;
static GetBPRFunc fpBPR = NULL;
static GetHeightFunc fpHeight = NULL;

static void loadCV(void)
{
    void *h = dlopen("/System/Library/Frameworks/CoreVideo.framework/CoreVideo", RTLD_LAZY);
    if(!h) return;
    fpLock = dlsym(h, "CVPixelBufferLockBaseAddress");
    fpUnlock = dlsym(h, "CVPixelBufferUnlockBaseAddress");
    fpBaseAddr = dlsym(h, "CVPixelBufferGetBaseAddress");
    fpBPR = dlsym(h, "CVPixelBufferGetBytesPerRow");
    fpHeight = dlsym(h, "CVPixelBufferGetHeight");
}

@class FloatBallTarget;
void showVirtualCamPanel(void);
static UIViewController* getTopViewController(void);

@interface NSObject (HookAdditions)
- (void)hook_setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue;
@end
@implementation NSObject (HookAdditions)
- (void)hook_setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {}
@end

static BOOL g_virtualCamEnable = NO;
static UIWindow *_floatWindow;
static FloatBallTarget *floatTarget;

@interface FloatBallTarget : NSObject
@end
@implementation FloatBallTarget
- (void)floatBallTap:(UIButton *)sender { showVirtualCamPanel(); }
@end

static UIViewController* getTopViewController(void)
{
    UIViewController *topVC = nil;
    for(UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes){
        if(scene.activationState == UISceneActivationStateForegroundActive){
            UIWindow *win = scene.windows.firstObject;
            topVC = win.rootViewController;
            while(topVC.presentedViewController) topVC = topVC.presentedViewController;
            break;
        }
    }
    return topVC;
}

@interface VirtualCamProxyDelegate : NSObject
@property (nonatomic, strong) id originalDelegate;
@end
@implementation VirtualCamProxyDelegate
- (instancetype)initWithOrig:(id)orig {
    self = [super init];
    if(self) _originalDelegate = orig;
    return self;
}
- (void)captureOutput:(id)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(id)connection {
    if (!g_virtualCamEnable || !fpLock) {
        [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    // 返回值直接存入void*，不再写CVPixelBufferRef
    void *pixelBuf = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuf) {
        [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    fpLock(pixelBuf,0);
    uint8_t *base = fpBaseAddr(pixelBuf);
    size_t bpr = fpBPR(pixelBuf);
    size_t h = fpHeight(pixelBuf);
    for(size_t y=0;y<h;y++){
        uint8_t *row = base + y*bpr;
        for(size_t x=0;x<bpr;x+=4){
            row[x+0]=255; row[x+1]=0; row[x+2]=0; row[x+3]=255;
        }
    }
    fpUnlock(pixelBuf,0);
    [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
}
@end

id proxyAlloc(id orig) { return [[VirtualCamProxyDelegate alloc] initWithOrig:orig]; }

static void swizzle(Class cls, SEL orig, SEL new)
{
    Method mOrig = class_getInstanceMethod(cls, orig);
    Method mNew = class_getInstanceMethod(cls, new);
    BOOL ok = class_addMethod(cls, orig, method_getImplementation(mNew), method_getTypeEncoding(mNew));
    if(ok) class_replaceMethod(cls, new, method_getImplementation(mOrig), method_getTypeEncoding(mOrig));
    else method_exchangeImplementations(mOrig,mNew);
}

static void hook_setSampleBufferDelegate(id self, SEL _cmd, id delegate, dispatch_queue_t queue)
{
    if(delegate){
        id p = proxyAlloc(delegate);
        [self hook_setSampleBufferDelegate:p queue:queue];
        objc_setAssociatedObject(self, @"vc_proxy", p, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }else{
        [self hook_setSampleBufferDelegate:nil queue:queue];
        objc_setAssociatedObject(self, @"vc_proxy", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

void showVirtualCamPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = getTopViewController();
        if(!vc) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"虚拟相机" message:@"开启后画面填充蓝色" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"✅开启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){g_virtualCamEnable=YES;}]];
        [alert addAction:[UIAlertAction actionWithTitle:@"❌关闭" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){g_virtualCamEnable=NO;}]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:alert animated:YES completion:nil];
    });
}

static void createFloatBall(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if(_floatWindow) return;
        CGFloat sz = 50;
        CGRect r = CGRectMake([UIScreen mainScreen].bounds.size.width-sz-20, 200, sz, sz);
        _floatWindow = [[UIWindow alloc] initWithFrame:r];
        _floatWindow.windowLevel = UIWindowLevelAlert+100;
        _floatWindow.backgroundColor = [UIColor clearColor];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = _floatWindow.bounds;
        btn.layer.cornerRadius = sz/2;
        btn.clipsToBounds = YES;
        btn.backgroundColor = [UIColor systemBlueColor];
        [btn setTitle:@"VC" forState:UIControlStateNormal];
        [btn addTarget:floatTarget action:@selector(floatBallTap:) forControlEvents:UIControlEventTouchUpInside];
        _floatWindow.rootViewController = [UIViewController new];
        [_floatWindow.rootViewController.view addSubview:btn];
        _floatWindow.hidden = NO;
    });
}

static void delayedInit()
{
    loadCV();
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = objc_getClass("AVCaptureVideoDataOutput");
        if(cls) swizzle(cls, @selector(setSampleBufferDelegate:queue:), @selector(hook_setSampleBufferDelegate:queue:));
        floatTarget = [[FloatBallTarget alloc] init];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            createFloatBall();
        });
    });
}

__attribute__((constructor))
static void pluginLoad()
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        delayedInit();
    });
}
