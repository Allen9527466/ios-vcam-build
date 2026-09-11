#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>

static BOOL g_virtualCamEnable = NO;
static OSStatus (*orig_CVPixelBufferLockBaseAddress)(CVPixelBufferRef buffer, CVPixelBufferLockFlags lockFlags);

OSStatus hook_CVPixelBufferLockBaseAddress(CVPixelBufferRef buffer, CVPixelBufferLockFlags lockFlags)
{
    OSStatus ret = orig_CVPixelBufferLockBaseAddress(buffer, lockFlags);
    
    if(g_virtualCamEnable && buffer)
    {
        size_t w = CVPixelBufferGetWidth(buffer);
        size_t h = CVPixelBufferGetHeight(buffer);
        if(w >= 320 && h >=320){
            void *base = CVPixelBufferGetBaseAddress(buffer);
            size_t stride = CVPixelBufferGetBytesPerRow(buffer);
            uint32_t *ptr = (uint32_t*)base;
            for(int i=0; i < w*h; i++){
                ptr[i] = 0xFFFF0000; // BGRA蓝色
            }
        }
    }
    return ret;
}

@interface VCWindow : UIWindow
@end
@implementation VCWindow
- (instancetype)init{
    self = [super init];
    if(self){
        self.frame = CGRectMake(300,300,60,60);
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor blueColor];
        self.layer.cornerRadius = 30;
        self.hidden = NO;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = self.bounds;
        [btn setTitle:@"VC" forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onClick) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
    }
    return self;
}
- (void)onClick{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"虚拟相机" message:@"开启后画面填充蓝色" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"开启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        g_virtualCamEnable = YES;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        g_virtualCamEnable = NO;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *topVC = [self topViewController];
    [topVC presentViewController:alert animated:YES completion:nil];
}
- (UIViewController *)topViewController {
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}
@end

static VCWindow *vcWin;

__attribute__((constructor))
void lib_main() {
    // dlsym 动态查找符号，不需要任何hook库
    orig_CVPixelBufferLockBaseAddress = dlsym(RTLD_DEFAULT, "CVPixelBufferLockBaseAddress");
    if (orig_CVPixelBufferLockBaseAddress) {
        // 函数指针交换
        *(void **)&orig_CVPixelBufferLockBaseAddress = hook_CVPixelBufferLockBaseAddress;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        vcWin = [[VCWindow alloc] init];
    });
}
