#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

void virtualVideoSetupHook(void);
void setVirtualVideoEnabled(BOOL enabled);
BOOL isVirtualVideoEnabled(void);
void setSelectedVideoPath(NSString *videoPath);
NSString *getSelectedVideoPath(void);

static UIWindow *getKeyWindow(void) {
    if (@available(iOS 13, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in scene.windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

@interface CustomMenuWindow : UIWindow <UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate, UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIButton *floatBtn;
@end

@implementation CustomMenuWindow

- (instancetype)init {
    self = [super init];
    if(self){
        CGFloat btnSize = 44;
        self.frame = CGRectMake(30, 300, btnSize, btnSize);
        self.windowLevel = UIWindowLevelStatusBar + 20;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = NO;

        self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatBtn.frame = self.bounds;
        self.floatBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:1.0 alpha:1];
        self.floatBtn.layer.cornerRadius = btnSize/2;
        [self.floatBtn setTitle:@"X" forState:UIControlStateNormal];
        [self.floatBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.floatBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [self.floatBtn addTarget:self action:@selector(showMenuPanel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.floatBtn];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        pan.delegate = self;
        [self.floatBtn addGestureRecognizer:pan];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView) {
        return hitView;
    }
    return nil;
}

#pragma mark - UIGestureRecognizerDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

- (void)drag:(UIPanGestureRecognizer *)ges {
    CGPoint trans = [ges translationInView:self];
    self.center = CGPointMake(self.center.x + trans.x, self.center.y + trans.y);
    [ges setTranslation:CGPointZero inView:self];
}

- (void)showMenuPanel {
    UIViewController *topVC = getKeyWindow().rootViewController;
    NSLog(@"[XUUz] showMenuPanel topVC = %@", topVC);
    if (!topVC) {
        NSLog(@"[XUUz] ERROR: 找不到根控制器，弹窗无法弹出");
        return;
    }

    UIViewController *vc = [[UIViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    vc.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20,80,vc.view.bounds.size.width-40,380)];
    panel.backgroundColor = [UIColor colorWithRed:0.94 green:0.97 blue:1.0 alpha:0.96];
    panel.layer.cornerRadius = 16;
    [vc.view addSubview:panel];

    UILabel *titleLab = [[UILabel alloc] initWithFrame:CGRectMake(0,20,panel.bounds.size.width,30)];
    titleLab.text = @"虚拟工具箱";
    titleLab.font = [UIFont boldSystemFontOfSize:18];
    titleLab.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:titleLab];

    UIButton *btnExit = [[UIButton alloc] initWithFrame:CGRectMake(15,20,60,30)];
    [btnExit setTitle:@"退出" forState:UIControlStateNormal];
    [btnExit setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [btnExit addTarget:vc action:@selector(dismissViewControllerAnimated:completion:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btnExit];

    UIButton *btnClose = [[UIButton alloc] initWithFrame:CGRectMake(panel.bounds.size.width-75,20,60,30)];
    [btnClose setTitle:@"关闭" forState:UIControlStateNormal];
    [btnClose setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    [btnClose addTarget:vc action:@selector(dismissViewControllerAnimated:completion:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btnClose];

    UILabel *infoLab = [[UILabel alloc] initWithFrame:CGRectMake(20,70,panel.bounds.size.width-40,90)];
    infoLab.numberOfLines = 0;
    infoLab.text = @"XUUᶻ\n插件版本V5.0\n本插件完全免费分享!\n如因本插件产生的任何!\n利益纠纷将由使用者自行承担!";
    [panel addSubview:infoLab];

    UILabel *labVirtualVideo = [[UILabel alloc] initWithFrame:CGRectMake(20,170,panel.bounds.size.width-40,30)];
    labVirtualVideo.text = @"虚拟视频";
    labVirtualVideo.font = [UIFont boldSystemFontOfSize:17];
    [panel addSubview:labVirtualVideo];

    UIButton *btnSelectVideo = [[UIButton alloc] initWithFrame:CGRectMake(20,210,panel.bounds.size.width-40,44)];
    btnSelectVideo.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btnSelectVideo.titleLabel.font = [UIFont systemFontOfSize:16];
    [btnSelectVideo setTitle:@"· 选择视频" forState:UIControlStateNormal];
    [btnSelectVideo setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [btnSelectVideo addTarget:self action:@selector(pickVideo:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btnSelectVideo];

    UILabel *labelSelectedTip = [[UILabel alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 110,210,90,44)];
    labelSelectedTip.tag = 1001;
    labelSelectedTip.text = getSelectedVideoPath() ? @"已选择" : @"未选择";
    labelSelectedTip.textAlignment = NSTextAlignmentRight;
    labelSelectedTip.font = [UIFont systemFontOfSize:14];
    [panel addSubview:labelSelectedTip];

    UIButton *btnToggleReplace = [[UIButton alloc] initWithFrame:CGRectMake(20,260,panel.bounds.size.width-40,44)];
    btnToggleReplace.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btnToggleReplace.titleLabel.font = [UIFont systemFontOfSize:16];
    [btnToggleReplace setTitle:@"· 禁用替换" forState:UIControlStateNormal];
    [btnToggleReplace setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [btnToggleReplace addTarget:self action:@selector(toggleReplace:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btnToggleReplace];

    UILabel *labelReplaceTip = [[UILabel alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 110,260,90,44)];
    labelReplaceTip.tag = 1002;
    labelReplaceTip.text = isVirtualVideoEnabled() ? @"替换中" : @"已禁用";
    labelReplaceTip.textAlignment = NSTextAlignmentRight;
    labelReplaceTip.font = [UIFont systemFontOfSize:14];
    [panel addSubview:labelReplaceTip];

    [topVC presentViewController:vc animated:YES completion:nil];
}

- (void)pickVideo:(UIButton *)sender {
    if (@available(iOS 14, *)) {
        PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
        config.filter = [PHPickerFilter videosFilter];
        config.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
        picker.delegate = self;
        UIViewController *topVC = getKeyWindow().rootViewController;
        [topVC presentViewController:picker animated:YES completion:nil];
    } else {
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.mediaTypes = @[(NSString *)kUTTypeMovie];
        picker.delegate = self;
        UIViewController *topVC = getKeyWindow().rootViewController;
        [topVC presentViewController:picker animated:YES completion:nil];
    }
}

- (void)toggleReplace:(UIButton *)sender {
    BOOL current = isVirtualVideoEnabled();
    setVirtualVideoEnabled(!current);
    UIView *panel = sender.superview;
    UILabel *tip = [panel viewWithTag:1002];
    tip.text = isVirtualVideoEnabled() ? @"替换中" : @"已禁用";
}

#pragma mark - PHPicker Delegate (iOS 14+)
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;

    NSItemProvider *provider = result.itemProvider;
    if ([provider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeMovie]) {
        [provider loadFileRepresentationForTypeIdentifier:(NSString *)kUTTypeMovie completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
            if (url) {
                NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vcam_selected.mp4"];
                NSURL *tmpURL = [NSURL fileURLWithPath:tmpPath];
                [[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];
                [[NSFileManager defaultManager] copyItemAtURL:url toURL:tmpURL error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    setSelectedVideoPath(tmpPath);
                });
            }
        }];
    }
}

#pragma mark - UIImagePicker Delegate (iOS 13 及以下)
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    NSURL *videoUrl = info[UIImagePickerControllerMediaURL];
    if(videoUrl){
        setSelectedVideoPath(videoUrl.path);
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

static CustomMenuWindow *g_menuWin = nil;

// ✅ constructor只做监听通知，不做任何UI/hook
__attribute__((constructor))
static void tweakMainEntry(void)
{
    @autoreleasepool {
        NSLog(@"XUUz V5.0 dylib loaded, waiting app launch finish");
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            NSLog(@"XUUz App didFinishLaunching, init UI + hook");
            g_menuWin = [[CustomMenuWindow alloc] init];
            virtualVideoSetupHook();
        }];
    }
}
