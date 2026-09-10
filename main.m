#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <objc/runtime.h>

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
    // 原样透传画面，后续在这里替换成你的虚拟画面
    [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
}
@end

void* VirtualCamProxyDelegate_alloc(id orig){
    VirtualCamProxyDelegate *p = [[VirtualCamProxyDelegate alloc] initWithOrig:orig];
    return (__bridge void*)p;
}

// ===================== 设置页面Hook占位 =====================
static NSString * const SETTING_VC_CLASS_NAME = @"AwemeSettingsViewController";
static IMP orig_tableView_didSelectRow;
static IMP orig_numberOfRows;
static IMP orig_cellForRow;

void hook_didSelectRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    ((void(*)(id,SEL,id,NSIndexPath*))orig_tableView_didSelectRow)(self, _cmd, tableView, indexPath);
    if(indexPath.section == 1 && indexPath.row == 0){
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"虚拟摄像头" message:@"插件设置面板" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

NSInteger hook_numberOfRows(id self, SEL _cmd, UITableView *tableView, NSInteger section) {
    NSInteger cnt = ((NSInteger(*)(id,SEL,id,NSInteger))orig_numberOfRows)(self, _cmd, tableView, section);
    if(section == 1){
        return cnt + 1;
    }
    return cnt;
}

UITableViewCell* hook_cellForRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    if(indexPath.section ==1 && indexPath.row ==0){
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"Cell"];
        cell.textLabel.text = @"虚拟摄像头";
        cell.detailTextLabel.text = @"1.0.0";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if(indexPath.section ==1 && indexPath.row >0){
        NSIndexPath *oldIdx = [NSIndexPath indexPathForRow:indexPath.row -1 inSection:indexPath.section];
        return ((UITableViewCell*(*)(id,SEL,id,NSIndexPath*))orig_cellForRow)(self, _cmd, tableView, oldIdx);
    }
    return ((UITableViewCell*(*)(id,SEL,id,NSIndexPath*))orig_cellForRow)(self, _cmd, tableView, indexPath);
}

// ===================== AVCaptureVideoDataOutput Hook =====================
static IMP orig_setSampleBufferDelegate;
void hook_setSampleBufferDelegate(id self, SEL _cmd, id delegate, dispatch_queue_t queue)
{
    NSLog(@"[VirtualCam] hook_setSampleBufferDelegate 触发");
    if(delegate){
        void* ptr = VirtualCamProxyDelegate_alloc(delegate);
        id proxy = (__bridge_transfer id)ptr;
        ((void(*)(id,SEL,id,dispatch_queue_t))orig_setSampleBufferDelegate)(self, _cmd, proxy, queue);
    }else{
        ((void(*)(id,SEL,id,dispatch_queue_t))orig_setSampleBufferDelegate)(self, _cmd, delegate, queue);
    }
}

// 方法交换工具函数
static void swizzle(Class cls, SEL originalSel, SEL newSel, IMP *outOrigIMP){
    Method origMethod = class_getInstanceMethod(cls, originalSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    if(origMethod && newMethod){
        *outOrigIMP = method_getImplementation(origMethod);
        method_setImplementation(origMethod, newMethod);
    }
}

// ===================== Constructor入口 =====================
__attribute__((constructor))
static void init_plugin() {
    NSLog(@"[VirtualCam] ✅ Dylib loaded! 插件已加载");

    // 尝试Hook设置页面
    Class settingVC = objc_getClass([SETTING_VC_CLASS_NAME UTF8String]);
    if(settingVC){
        swizzle(settingVC, @selector(tableView:numberOfRowsInSection:), @selector(hook_tableView:numberOfRowsInSection:), &orig_numberOfRows);
        swizzle(settingVC, @selector(tableView:cellForRowAtIndexPath:), @selector(hook_tableView:cellForRowAtIndexPath:), &orig_cellForRow);
        swizzle(settingVC, @selector(tableView:didSelectRowAtIndexPath:), @selector(hook_tableView:didSelectRowAtIndexPath:), &orig_tableView_didSelectRow);
        NSLog(@"[VirtualCam] ✅ Hook 设置页面成功！");
    }else{
        NSLog(@"[VirtualCam] ❌ 找不到类：%@，需要替换SETTING_VC_CLASS_NAME", SETTING_VC_CLASS_NAME);
    }

    // Hook AVCaptureVideoDataOutput
    Class avCaptureClass = objc_getClass("AVCaptureVideoDataOutput");
    if(avCaptureClass){
        swizzle(avCaptureClass, @selector(setSampleBufferDelegate:queue:), @selector(hook_setSampleBufferDelegate:queue:), &orig_setSampleBufferDelegate);
        NSLog(@"[VirtualCam] ✅ Hook AVCaptureVideoDataOutput成功");
    }else{
        NSLog(@"[VirtualCam] ❌ AVCaptureVideoDataOutput class not found");
    }
}

// 给类添加hook方法定义
@implementation NSObject (HookAdditions)
- (NSInteger)hook_tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 0; }
- (UITableViewCell *)hook_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { return nil; }
- (void)hook_tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {}
- (void)hook_setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {}
@end
