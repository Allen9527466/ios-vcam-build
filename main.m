#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <objc/runtime.h>

@interface NSObject (HookAdditions)
- (void)hook_tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSInteger)hook_tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell *)hook_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)hook_setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue;
@end

@implementation NSObject (HookAdditions)
- (void)hook_tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {}
- (NSInteger)hook_tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 0; }
- (UITableViewCell *)hook_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { return nil; }
- (void)hook_setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {}
@end

// ===================== 代理：AVCapture SampleBuffer 替换 =====================
@interface VirtualCamProxyDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@end

@implementation VirtualCamProxyDelegate
- (instancetype)initWithOrig:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)orig{
    self = [super init];
    if(self){
        _originalDelegate = orig;
    }
    return self;
}
- (void)captureOutput:(AVCaptureVideoDataOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    //原样透传画面
    [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
}
@end

id VirtualCamProxyDelegate_alloc(id orig){
    VirtualCamProxyDelegate *p = [[VirtualCamProxyDelegate alloc] initWithOrig:orig];
    return p;
}

// ===================== 方法交换工具函数（安全标准写法） =====================
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

// ===================== AVCaptureVideoDataOutput Hook =====================
static void hook_setSampleBufferDelegate(id self, SEL _cmd, id delegate, dispatch_queue_t queue)
{
    NSLog(@"[VirtualCam] ✅ hook_setSampleBufferDelegate 触发");
    if(delegate){
        id proxy = VirtualCamProxyDelegate_alloc(delegate);
        [self hook_setSampleBufferDelegate:proxy queue:queue];
    }else{
        [self hook_setSampleBufferDelegate:nil queue:queue];
    }
}

// ===================== 设置页面Hook 【暂时全部注释，先保证编译通过】 =====================
/*
static void hook_tableView_didSelectRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    [self hook_tableView:tableView didSelectRowAtIndexPath:indexPath];
    if(indexPath.section == 1 && indexPath.row == 0){
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"虚拟摄像头" message:@"插件面板" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

static NSInteger hook_tableView_numberOfRows(id self, SEL _cmd, UITableView *tableView, NSInteger section) {
    NSInteger cnt = [self hook_tableView:tableView numberOfRowsInSection:section];
    if(section == 1){
        return cnt + 1;
    }
    return cnt;
}

static UITableViewCell* hook_tableView_cellForRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    if(indexPath.section ==1 && indexPath.row ==0){
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"Cell"];
        cell.textLabel.text = @"虚拟摄像头";
        cell.detailTextLabel.text = @"1.0.0";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if(indexPath.section ==1 && indexPath.row >0){
        NSIndexPath *oldIdx = [NSIndexPath indexPathForRow:indexPath.row -1 inSection:indexPath.section];
        return [self hook_tableView:tableView cellForRowAtIndexPath:oldIdx];
    }
    return [self hook_tableView:tableView cellForRowAtIndexPath:indexPath];
}
*/

// ===================== 延迟初始化：放到主线程 =====================
static void delayed_init()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[VirtualCam] ✅ delayed_init 开始执行");
        // Hook AVCaptureVideoDataOutput
        Class avCaptureClass = objc_getClass("AVCaptureVideoDataOutput");
        if(avCaptureClass){
            safe_swizzle(avCaptureClass, @selector(setSampleBufferDelegate:queue:), @selector(hook_setSampleBufferDelegate:queue:));
            NSLog(@"[VirtualCam] ✅ Hook AVCaptureVideoDataOutput成功");
        }else{
            NSLog(@"[VirtualCam] ❌ AVCaptureVideoDataOutput class not found");
        }

        // 设置页面Hook暂时注释，等抓到真实类名再打开
        /*
        Class settingVC = objc_getClass("AwemeSettingsViewController");
        if(settingVC){
            safe_swizzle(settingVC, @selector(tableView:numberOfRowsInSection:), @selector(hook_tableView:numberOfRowsInSection:));
            safe_swizzle(settingVC, @selector(tableView:cellForRowAtIndexPath:), @selector(hook_tableView:cellForRowAtIndexPath:));
            safe_swizzle(settingVC, @selector(tableView:didSelectRowAtIndexPath:), @selector(hook_tableView:didSelectRowAtIndexPath:));
            NSLog(@"[VirtualCam] ✅ Hook 设置页面成功");
        }else{
            NSLog(@"[VirtualCam] ❌ 找不到AwemeSettingsViewController");
        }
        */
    });
}

__attribute__((constructor))
static void init_plugin() {
    NSLog(@"[VirtualCam] ✅ Dylib loaded, wait for main thread...");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        delayed_init();
    });
}
