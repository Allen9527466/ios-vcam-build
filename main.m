#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/runtime.h>

@interface GetFrame : NSObject
+ (CMSampleBufferRef)replaceSampleBuffer:(CMSampleBufferRef)sampleBuffer mirror:(BOOL)mirror;
+ (instancetype)sharedInstance;
@end

@implementation GetFrame

+ (instancetype)sharedInstance {
    static GetFrame *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GetFrame alloc] init];
    });
    return instance;
}

+ (CMSampleBufferRef)replaceSampleBuffer:(CMSampleBufferRef)sampleBuffer mirror:(BOOL)mirror {
    // 当前占位，后续写视频解码在这里，直接返回原帧
    return sampleBuffer;
}

@end

static BOOL g_replaceEnabled = NO;
static NSString *g_selectedVideoPath = nil;

void setVirtualVideoEnabled(BOOL enabled) {
    g_replaceEnabled = enabled;
}

BOOL isVirtualVideoEnabled(void) {
    return g_replaceEnabled;
}

void setSelectedVideoPath(NSString *path) {
    g_selectedVideoPath = path;
}

NSString *getSelectedVideoPath(void) {
    return g_selectedVideoPath;
}

#pragma mark - AVCaptureOutput Hook
@interface AVCaptureOutput (FakeToolsHook)
- (void)ft_captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
@end

@implementation AVCaptureOutput (FakeToolsHook)

- (void)ft_captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (!g_replaceEnabled || !g_selectedVideoPath) {
        [self ft_captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    
    CMSampleBufferRef newFrame = [GetFrame replaceSampleBuffer:sampleBuffer mirror:NO];
    [self ft_captureOutput:output didOutputSampleBuffer:newFrame fromConnection:connection];
}

@end

#pragma mark - 悬浮菜单窗口（纯UIWindow实现，兼容iOS14，无UIWindowScene）
@interface CustomMenuWindow : UIWindow <UIGestureRecognizerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, weak) UIViewController *menuVC;
@end

@implementation CustomMenuWindow

- (instancetype)init {
    self = [super init];
    if (self) {
        CGFloat btnSize = 44;
        self.frame = CGRectMake(30, 300, btnSize, btnSize);
        self.windowLevel = UIWindowLevelAlert + 999;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = NO;
        
        self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatBtn.frame = self.bounds;
        self.floatBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:1.0 alpha:1];
        self.floatBtn.layer.cornerRadius = btnSize/2;
        [self.floatBtn setTitle:@"X" forState:UIControlStateNormal];
        [self.floatBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.floatBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [self.floatBtn addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.floatBtn];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        pan.delegate = self;
        [self.floatBtn addGestureRecognizer:pan];
    }
    return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)drag:(UIPanGestureRecognizer *)ges {
    CGPoint trans = [ges translationInView:self];
    self.center = CGPointMake(self.center.x + trans.x, self.center.y + trans.y);
    [ges setTranslation:CGPointZero inView:self];
}

- (void)closeMenuPanel {
    if(self.menuVC) {
        [self.menuVC dismissViewControllerAnimated:YES completion:nil];
        self.menuVC = nil;
    }
}

- (void)showMenu {
    UIViewController *vc = [[UIViewController alloc] init];
    self.menuVC = vc;
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    vc.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20, 80, screenW - 40, 380)];
    panel.backgroundColor = [UIColor colorWithRed:0.94 green:0.97 blue:1.0 alpha:0.96];
    panel.layer.cornerRadius = 16;
    [vc.view addSubview:panel];
    
    UILabel *titleLab = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, panel.bounds.size.width, 30)];
    titleLab.text = @"虚拟工具箱";
    titleLab.font = [UIFont boldSystemFontOfSize:18];
    titleLab.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:titleLab];
    
    UIButton *btnClose = [[UIButton alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 75, 20, 60, 30)];
    [btnClose setTitle:@"关闭" forState:UIControlStateNormal];
    [btnClose setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    [btnClose addTarget:self action:@selector(closeMenuPanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btnClose];
    
    UILabel *infoLab = [[UILabel alloc] initWithFrame:CGRectMake(20, 70, panel.bounds.size.width - 40, 90)];
    infoLab.numberOfLines = 0;
    infoLab.text = @"XUUᶻ\n插件版本V5.0\n本插件完全免费分享!\n如因本插件产生的任何利益纠纷将由使用者自行承担!";
    [panel addSubview:infoLab];
    
    UILabel *labVirtualVideo = [[UILabel alloc] initWithFrame:CGRectMake(20, 170, panel.bounds.size.width - 40, 30)];
    labVirtualVideo.text = @"虚拟视频";
    labVirtualVideo.font = [UIFont boldSystemFontOfSize:17];
    [panel addSubview:labVirtualVideo];
    
    UIButton *btnSelectVideo = [[UIButton alloc] initWithFrame:CGRectMake(20, 210, panel.bounds.size.width - 40, 44)];
    btnSelectVideo.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btnSelectVideo.titleLabel.font = [UIFont systemFontOfSize:16];
    [btnSelectVideo setTitle:@"· 选择视频" forState:UIControlStateNormal];
    [btnSelectVideo setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [btnSelectVideo addTarget:self action:@selector(pickVideo) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btnSelectVideo];
    
    UILabel *labelSelectedTip = [[UILabel alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 110, 210, 90, 44)];
    labelSelectedTip.tag = 1001;
    labelSelectedTip.text = g_selectedVideoPath ? @"已选择" : @"未选择";
    labelSelectedTip.textAlignment = NSTextAlignmentRight;
    labelSelectedTip.font = [UIFont systemFontOfSize:14];
    [panel addSubview:labelSelectedTip];
    
    UIButton *btnToggleReplace = [[UIButton alloc] initWithFrame:CGRectMake(20, 260, panel.bounds.size.width - 40, 44)];
    btnToggleReplace.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btnToggleReplace.titleLabel.font = [UIFont systemFontOfSize:16];
    [btnToggleReplace setTitle:@"· 禁用替换" forState:UIControlStateNormal];
    [btnToggleReplace setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [btnToggleReplace addTarget:self action:@selector(toggleReplace) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btnToggleReplace];
    
    UILabel *labelReplaceTip = [[UILabel alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 110, 260, 90, 44)];
    labelReplaceTip.tag = 1002;
    labelReplaceTip.text = g_replaceEnabled ? @"替换中" : @"已禁用";
    labelReplaceTip.textAlignment = NSTextAlignmentRight;
    labelReplaceTip.font = [UIFont systemFontOfSize:14];
    [panel addSubview:labelReplaceTip];
    
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [topVC presentViewController:vc animated:YES completion:nil];
}

- (void)pickVideo {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    picker.delegate = self;
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [topVC presentViewController:picker animated:YES completion:nil];
}

- (void)toggleReplace {
    g_replaceEnabled = !g_replaceEnabled;
    NSLog(@"[FakeTools] replace: %@", g_replaceEnabled ? @"ON" : @"OFF");
}

#pragma mark - UIImagePicker Delegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    NSURL *videoUrl = info[UIImagePickerControllerMediaURL];
    if (videoUrl) {
        g_selectedVideoPath = videoUrl.path;
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

static CustomMenuWindow *g_menuWin = nil;

__attribute__((constructor))
static void fakeToolsEntry(void) {
    @autoreleasepool {
        NSLog(@"FakeTools loaded");
        
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            NSLog(@"FakeTools app launched, init UI + hook");
            g_menuWin = [[CustomMenuWindow alloc] init];
            
            Class cls = objc_getClass("AVCaptureOutput");
            SEL origSel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
            SEL newSel = @selector(ft_captureOutput:didOutputSampleBuffer:fromConnection:);
            Method origM = class_getInstanceMethod(cls, origSel);
            Method newM = class_getInstanceMethod(cls, newSel);
            if (origM && newM) {
                method_exchangeImplementations(origM, newM);
                NSLog(@"FakeTools hook installed");
            }
        }];
    }
}
