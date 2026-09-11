#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>

// ========= 声明VirtualVideo.c的导出函数（对接视频替换逻辑） =========
void virtualVideoSetupHook(void);
void setVirtualVideoEnabled(BOOL enabled);
BOOL isVirtualVideoEnabled(void);
void setSelectedVideoPath(NSString *videoPath);
NSString *getSelectedVideoPath(void);

#pragma mark - 悬浮主窗口（可拖动悬浮球，点击弹出虚拟工具箱）
@interface CustomMenuWindow : UIWindow
@property(nonatomic, strong) UIButton *floatBtn;
@end

@implementation CustomMenuWindow
- (instancetype)init {
    self = [super init];
    if(self){
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
        [self.floatBtn addTarget:self action:@selector(showMenuPanel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.floatBtn];
        
        // 拖动悬浮球
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self.floatBtn addGestureRecognizer:pan];
    }
    return self;
}
- (void)drag:(UIPanGestureRecognizer *)ges {
    CGPoint trans = [ges translationInView:self];
    self.center = CGPointMake(self.center.x + trans.x, self.center.y + trans.y);
    [ges setTranslation:CGPointZero inView:self];
}
- (void)showMenuPanel {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    vc.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    
    // === 复刻截图里【虚拟工具箱】面板 ===
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20,80,self.bounds.size.width-40,380)];
    panel.backgroundColor = [UIColor colorWithRed:0.94 green:0.97 blue:1.0 alpha:0.96];
    panel.layer.cornerRadius = 16;
    [vc.view addSubview:panel];
    
    // 标题栏：退出、虚拟工具箱、关闭
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
    
    // XUUz 版本信息
    UILabel *infoLab = [[UILabel alloc] initWithFrame:CGRectMake(20,70,panel.bounds.size.width-40,90)];
    infoLab.numberOfLines = 0;
    infoLab.text = @"XUUᶻ\n插件版本V5.0\n本插件完全免费分享!\n如因本插件产生的任何!\n利益纠纷将由使用者自行承担!";
    [panel addSubview:infoLab];
    
    // ========== 虚拟视频 选项组（和截图完全一致） ==========
    UILabel *labVirtualVideo = [[UILabel alloc] initWithFrame:CGRectMake(20,170,panel.bounds.size.width-40,30)];
    labVirtualVideo.text = @"虚拟视频";
    labVirtualVideo.font = [UIFont boldSystemFontOfSize:17];
    [panel addSubview:labVirtualVideo];
    
    // 1.【选择视频】按钮
    UIButton *btnSelectVideo = [[UIButton alloc] initWithFrame:CGRectMake(20,210,panel.bounds.size.width-40,44)];
    btnSelectVideo.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btnSelectVideo.titleLabel.font = [UIFont systemFontOfSize:16];
    [btnSelectVideo setTitle:@"· 选择视频" forState:UIControlStateNormal];
    [btnSelectVideo setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [btnSelectVideo addTarget:self action:@selector(pickVideo:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btnSelectVideo];
    
    // 右侧文字：已选择
    UILabel *labelSelectedTip = [[UILabel alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 110,210,90,44)];
    labelSelectedTip.tag = 1001;
    labelSelectedTip.text = @"已选择";
    labelSelectedTip.textAlignment = NSTextAlignmentRight;
    labelSelectedTip.font = [UIFont systemFontOfSize:14];
    [panel addSubview:labelSelectedTip];
    
    // 2.【禁用替换】开关行
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
    
    // 弹出窗口
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [topVC presentViewController:vc animated:YES completion:nil];
}

// 相册选择视频
- (void)pickVideo:(UIButton *)sender {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    picker.delegate = self;
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [topVC presentViewController:picker animated:YES completion:nil];
}

// 开关：禁用替换 切换
- (void)toggleReplace:(UIButton *)sender {
    BOOL current = isVirtualVideoEnabled();
    setVirtualVideoEnabled(!current);
    NSLog(@"[XUUz] 虚拟视频替换状态：%@", !current ? @"开启替换" : @"禁用替换");
    
    // 更新UI文字
    UIView *panel = sender.superview;
    UILabel *tip = [panel viewWithTag:1002];
    tip.text = isVirtualVideoEnabled() ? @"替换中" : @"已禁用";
}
@end

#pragma mark - 相册选择回调
@interface CustomMenuWindow (UIImagePickerDelegate)
@end
@implementation CustomMenuWindow (UIImagePickerDelegate)
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    NSURL *videoUrl = info[UIImagePickerControllerMediaURL];
    if(videoUrl){
        NSString *videoPath = videoUrl.path;
        setSelectedVideoPath(videoPath);
        NSLog(@"[XUUz] 选中视频路径：%@", videoPath);
        // 更新UI文字
        UIView *panel = picker.presentingViewController.view.subviews.lastObject;
        UILabel *tip = [panel viewWithTag:1001];
        tip.text = @"已选择";
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
@end

#pragma mark - 全局入口，巨魔注入初始化
static CustomMenuWindow *g_menuWin = nil;

__attribute__((constructor))
static void tweakMainEntry(void)
{
    @autoreleasepool {
        NSLog(@"XUUz V5.0 虚拟工具箱加载成功");
        
        // 创建悬浮X按钮
        dispatch_async(dispatch_get_main_queue(), ^{
            g_menuWin = [[CustomMenuWindow alloc] init];
        });
        
        // 初始化相机Hook（调用VirtualVideo.c里面的函数）
        virtualVideoSetupHook();
    }
}
