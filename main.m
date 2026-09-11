#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#include <objc/runtime.h>

@interface NSObject (HookAdditions)
- (void)hook_setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue;
@end

@implementation NSObject (HookAdditions)
- (void)hook_setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {}
@end

#pragma mark - GetFrame 视频帧读取
@interface GetFrame : NSObject
@property (nonatomic, strong) AVAssetReader *assetReader;
@property (nonatomic, strong) AVAssetReaderTrackOutput *trackOutput;
@property (nonatomic, strong) NSString *videoFilePath;
+ (instancetype)sharedInstance;
- (BOOL)openVideo:(NSString *)filePath;
- (CMSampleBufferRef)copyNextSampleBuffer;
- (void)resetReader;
@end

@implementation GetFrame
static GetFrame *_inst;
+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _inst = [[self alloc] init];
    });
    return _inst;
}

- (BOOL)openVideo:(NSString *)filePath {
    [self resetReader];
    self.videoFilePath = filePath;
    NSURL *url = [NSURL fileURLWithPath:filePath];
    AVAsset *asset = [AVAsset assetWithURL:url];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!track) {
        NSLog(@"[GetFrame] ❌ 找不到视频轨道");
        return NO;
    }
    self.assetReader = [[AVAssetReader alloc] initWithAsset:asset error:nil];
    NSDictionary *outputOpts = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)
    };
    self.trackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:outputOpts];
    if ([self.assetReader canAddOutput:self.trackOutput]) {
        [self.assetReader addOutput:self.trackOutput];
    }
    BOOL startOK = [self.assetReader startReading];
    if (!startOK) {
        NSLog(@"[GetFrame] ❌ assetReader startReading失败");
        return NO;
    }
    return YES;
}

- (CMSampleBufferRef)copyNextSampleBuffer {
    if (!self.assetReader || !self.trackOutput) return NULL;
    if (self.assetReader.status == AVAssetReaderStatusCompleted) {
        [self resetReader];
        [self openVideo:self.videoFilePath];
        return NULL;
    }
    CMSampleBufferRef buf = [self.trackOutput copyNextSampleBuffer];
    return buf;
}

- (void)resetReader {
    if (self.assetReader) {
        [self.assetReader cancelReading];
        self.assetReader = nil;
    }
    self.trackOutput = nil;
}
@end

#pragma mark - 全局状态
static BOOL g_virtualCamEnable = NO;
static UIWindow *_floatWindow; // 全局static强引用，防止释放！

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
        [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    CMSampleBufferRef fakeBuf = [[GetFrame sharedInstance] copyNextSampleBuffer];
    if (fakeBuf) {
        [_originalDelegate captureOutput:output didOutputSampleBuffer:fakeBuf fromConnection:connection];
        CFRelease(fakeBuf);
    } else {
        [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    }
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
        UIViewController *topVC = nil;
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        if (keyWin.rootViewController) {
            topVC = keyWin.rootViewController;
            while (topVC.presentedViewController) {
                topVC = topVC.presentedViewController;
            }
        }
        if (!topVC) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"虚拟相机控制面板"
                                                                         message:@"视频需要放在App有权限访问的目录\n默认路径：/var/mobile/Movie/test.mp4"
                                                                  preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *actionEnable = [UIAlertAction actionWithTitle:@"✅开启虚拟相机" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *videoPath = @"/var/mobile/Movie/test.mp4";
            BOOL ret = [[GetFrame sharedInstance] openVideo:videoPath];
            if(ret){
                g_virtualCamEnable = YES;
                NSLog(@"[VirtualCam] ✅ 虚拟相机已开启");
            }else{
                NSLog(@"[VirtualCam] ❌ 打开视频失败，请检查路径和权限");
            }
        }];

        UIAlertAction *actionDisable = [UIAlertAction actionWithTitle:@"❌关闭虚拟相机" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            g_virtualCamEnable = NO;
            [[GetFrame sharedInstance] resetReader];
            NSLog(@"[VirtualCam] ✅ 虚拟相机关闭，恢复真实摄像头");
        }];

        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"关闭弹窗" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:actionEnable];
        [alert addAction:actionDisable];
        [alert addAction:cancel];
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - 修复版悬浮球
static void setupFloatBall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 已经创建直接返回，防止重复创建多个悬浮窗
        if (_floatWindow) {
            NSLog(@"[FloatBall] 悬浮窗口已经存在，跳过创建");
            return;
        }

        CGFloat ballSize = 50;
        CGRect frame = CGRectMake([UIScreen mainScreen].bounds.size.width - ballSize - 20, 200, ballSize, ballSize);

        _floatWindow = [[UIWindow alloc] initWithFrame:frame];
        // 关键！windowLevel要高于普通App界面，不然被盖住看不见
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

        [floatBtn addTarget:self action:@selector(floatBallTap:) forControlEvents:UIControlEventTouchUpInside];

        _floatWindow.rootViewController = [[UIViewController alloc] init];
        [_floatWindow.rootViewController.view addSubview:floatBtn];
        _floatWindow.hidden = NO; // 必须显示！很多人漏掉这句，窗口创建但是隐藏看不见

        NSLog(@"[FloatBall] ✅ 悬浮球创建完成");
    });
}

// 悬浮球点击回调
@interface FloatBallTarget : NSObject
@end
@implementation FloatBallTarget
- (void)floatBallTap:(UIButton *)sender {
    showVirtualCamPanel();
}
@end
static FloatBallTarget *floatTarget;

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

        // 初始化悬浮球target，持有对象防止释放
        floatTarget = [[FloatBallTarget alloc] init];
        // 延迟再创建悬浮窗口，给App界面完全加载留出时间
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            setupFloatBall();
        });
    });
}

__attribute__((constructor))
static void init_plugin() {
    NSLog(@"[VirtualCam] ✅ Dylib loaded — TrollFools ready");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        delayed_init();
    });
}
