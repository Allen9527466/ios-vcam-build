#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#include <objc/runtime.h>

// ========== 前置声明 ==========
@class FloatBallTarget;
void showVirtualCamPanel(void);
static UIViewController* getTopViewController(void);

@interface NSObject (HookAdditions)
- (void)hook_setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue;
@end

@implementation NSObject (HookAdditions)
- (void)hook_setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {}
@end

#pragma mark - 全局状态
static BOOL g_virtualCamEnable = NO;
static UIWindow *_floatWindow;
static FloatBallTarget *floatTarget;

@interface FloatBallTarget : NSObject
@end
@implementation FloatBallTarget
- (void)floatBallTap:(UIButton *)sender {
    showVirtualCamPanel();
}
@end

#pragma mark - 获取顶层ViewController（iOS13+ Scene兼容）
static UIViewController* getTopViewController(void)
{
    UIViewController *topVC = nil;
    UIWindowScene *scene = nil;
    for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive) {
            scene = s;
            break;
        }
    }
    if (!scene) return nil;
    UIWindow *win = scene.windows.firstObject;
    topVC = win.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

#pragma mark - 帧代理
@interface VirtualCamProxyDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@end

@implementation VirtualCamProxyDelegate
- (instancetype)initWithOrig:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)orig {
    self = [super init];
    if(self) {
        _originalDelegate = orig;
    }
    return self;
}

- (void)captureOutput:(AVCaptureVideoDataOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (!g_virtualCamEnable) {
        // 关闭：透传真实摄像头
        [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }

    // 开启模式：直接修改原始pixelbuffer填充蓝色，复用原始缓冲区、尺寸、时间戳
    CVPixelBufferRef pixelBuf = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuf) {
        [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }

    CVPixelBufferLockBaseAddress(pixelBuf,0);
    void *baseAddr = CVPixelBufferGetBaseAddress(pixelBuf);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuf);
    size_t height = CVPixelBufferGetHeight(pixelBuf);

    // BGRA 蓝色填充 B=255 G=0 R=0 A=255
    for(size_t y = 0; y < height; y++){
        uint8_t *row = (uint8_t*)baseAddr + y * bytesPerRow;
        for(size_t x = 0; x < bytesPerRow; x +=4){
            row[x+0] = 255;
            row[x+1] = 0;
            row[x+2] = 0;
            row[x+3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuf,0);

    // 直接发送修改后的原始sampleBuffer
    [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
}
@end

id VirtualCamProxyDelegate_alloc(id orig) {
    return [[VirtualCamProxyDelegate alloc] initWithOrig:orig];
}

#pragma mark - swizzle工具
static void safe_swizzle(Class cls, SEL origSel, SEL newSel)
{
    if (!cls) return;
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    if (!origMethod || !newMethod) return;
    BOOL addOK = class_addMethod(cls, origSel, method_getImplementation(newMethod), method_getTypeEncoding(newMethod));
    if(addOK){
        class_replaceMethod(cls, newSel, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    }else{
        method_exchangeImplementations(origMethod, newMethod);
    }
}

#pragma mark - Hook setSampleBufferDelegate
static void hook_setSampleBufferDelegate(id self, SEL _cmd, id delegate, dispatch_queue_t queue)
{
    NSLog(@"[VirtualCam] ✅ hook_setSampleBufferDelegate 触发");
    if(delegate){
        id proxy = VirtualCamProxyDelegate_alloc(delegate);
        [self hook_setSampleBufferDelegate:proxy queue:queue];
        objc_setAssociatedObject(self, @"vc_proxy", proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }else{
        [self hook_setSampleBufferDelegate:nil queue:queue];
        objc_setAssociatedObject(self, @"vc_proxy", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - 虚拟相机弹窗面板
void showVirtualCamPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = getTopViewController();
        if (!topVC) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"虚拟相机【测试模式‑蓝色画面】"
                                                                         message:@"点击开启，摄像头画面填充蓝色\n出现蓝色即代表Hook链路正常"
                                                                  preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *actionEnable = [UIAlertAction actionWithTitle:@"✅开启虚拟相机" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            g_virtualCamEnable = YES;
            NSLog(@"[VirtualCam] ✅ 测试模式开启，画面填充蓝色");
        }];

        UIAlertAction *actionDisable = [UIAlertAction actionWithTitle:@"❌关闭虚拟相机" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            g_virtualCamEnable = NO;
            NSLog(@"[VirtualCam] ✅ 关闭，恢复真实摄像头");
        }];

        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"关闭弹窗" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:actionEnable];
        [alert addAction:actionDisable];
        [alert addAction:cancel];
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - 悬浮球
static void setupFloatBall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_floatWindow) {
            NSLog(@"[FloatBall] 悬浮窗口已经存在，跳过创建");
            return;
        }

        CGFloat ballSize = 50;
        CGRect frame = CGRectMake([UIScreen mainScreen].bounds.size.width - ballSize - 20, 200, ballSize, ballSize);

        _floatWindow = [[UIWindow alloc] initWithFrame:frame];
        _floatWindow.windowLevel = UIWindowLevelAlert + 100;
        _floatWindow.backgroundColor = [UIColor clearColor];

        UIButton *floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        floatBtn.frame = _floatWindow.bounds;
        floatBtn.layer.cornerRadius = ballSize/2;
        floatBtn.clipsToBounds = YES;
        floatBtn.backgroundColor = [UIColor colorWithRed:0.22 green:0.48 blue:1 alpha:0.9];
        [floatBtn setTitle:@"VC" forState:UIControlStateNormal];
        [floatBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        floatBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];

        [floatBtn addTarget:floatTarget action:@selector(floatBallTap:) forControlEvents:UIControlEventTouchUpInside];

        _floatWindow.rootViewController = [[UIViewController alloc] init];
        [_floatWindow.rootViewController.view addSubview:floatBtn];
        _floatWindow.hidden = NO;

        NSLog(@"[FloatBall] ✅ 悬浮球创建完成");
    });
}

#pragma mark - 初始化入口
static void delayed_init()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[VirtualCam] ✅ delayed_init running");
        Class avCaptureClass = objc_getClass("AVCaptureVideoDataOutput");
        if(avCaptureClass){
            safe_swizzle(avCaptureClass, @selector(setSampleBufferDelegate:queue:), @selector(hook_setSampleBufferDelegate:queue:));
            NSLog(@"[VirtualCam] ✅ Hook AVCaptureVideoDataOutput success");
        }else{
            NSLog(@"[VirtualCam] ❌ AVCaptureVideoDataOutput not found");
        }

        floatTarget = [[FloatBallTarget alloc] init];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            setupFloatBall();
        });
    });
}

__attribute__((constructor))
static void init_plugin() {
    NSLog(@"[VirtualCam] ✅ Dylib loaded — TrollFools ready【测试蓝色帧】");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        delayed_init();
    });
}
