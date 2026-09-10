#include <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

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
    // 这里替换画面，暂时原样透传，先保证插件菜单能出来
    [_originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
}
@end

CMSampleBufferRef GetVirtualSampleBuffer(void);
void* VirtualCamProxyDelegate_alloc(id orig){
    VirtualCamProxyDelegate *p = [[VirtualCamProxyDelegate alloc] initWithOrig:orig];
    return (__bridge void*)p;
}

// ===================== 设置页面Hook占位（重点，日志会打印类名） =====================
static NSString * const SETTING_VC_CLASS_NAME = @"AwemeSettingsViewController";

static void (*orig_tableView_didSelectRow)(id, SEL, id, NSIndexPath*);
static NSInteger (*orig_numberOfRows)(id, SEL, id, NSInteger);
static UITableViewCell* (*orig_cellForRow)(id, SEL, id, NSIndexPath*);

void hook_didSelectRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    orig_tableView_didSelectRow(self, _cmd, tableView, indexPath);
    if(indexPath.section == 1 && indexPath.row == 0){
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"虚拟摄像头" message:@"插件设置面板" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

NSInteger hook_numberOfRows(id self, SEL _cmd, UITableView *tableView, NSInteger section) {
    NSInteger cnt = orig_numberOfRows(self, _cmd, tableView, section);
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
        return orig_cellForRow(self, _cmd, tableView, oldIdx);
    }
    return orig_cellForRow(self, _cmd, tableView, indexPath);
}

// ===================== AVCapture Hook占位 =====================
static void (*orig_setSampleBufferDelegate)(id, SEL, id, dispatch_queue_t);
void hook_setSampleBufferDelegate(id self, SEL _cmd, id delegate, dispatch_queue_t queue)
{
    NSLog(@"[VirtualCam] hook_setSampleBufferDelegate 触发");
    if(delegate){
        void* ptr = VirtualCamProxyDelegate_alloc(delegate);
        id proxy = (__bridge_transfer id)ptr;
        orig_setSampleBufferDelegate(self, _cmd, proxy, queue);
    }else{
        orig_setSampleBufferDelegate(self, _cmd, delegate, queue);
    }
}

// ===================== Constructor入口 =====================
__attribute__((constructor))
static void init_plugin() {
    NSLog(@"[VirtualCam] ✅ Dylib loaded! 插件已加载");

    // 尝试Hook设置页面
    Class settingVC = objc_getClass([SETTING_VC_CLASS_NAME UTF8String]);
    if(settingVC){
        MSHookMessageEx(settingVC, @selector(tableView:numberOfRowsInSection:), (IMP)hook_numberOfRows, (IMP *)&orig_numberOfRows);
        MSHookMessageEx(settingVC, @selector(tableView:cellForRowAtIndexPath:), (IMP)hook_cellForRow, (IMP *)&orig_cellForRow);
        MSHookMessageEx(settingVC, @selector(tableView:didSelectRowAtIndexPath:), (IMP)hook_didSelectRow, (IMP *)&orig_tableView_didSelectRow);
        NSLog(@"[VirtualCam] ✅ Hook 设置页面成功！");
    }else{
        NSLog(@"[VirtualCam] ❌ 找不到类：%@，需要替换SETTING_VC_CLASS_NAME", SETTING_VC_CLASS_NAME);
    }

    // Hook AVCaptureVideoDataOutput
    Class avCaptureClass = objc_getClass("AVCaptureVideoDataOutput");
    if(avCaptureClass){
        MSHookMessageEx(avCaptureClass, @selector(setSampleBufferDelegate:queue:), (IMP)hook_setSampleBufferDelegate, &orig_setSampleBufferDelegate);
        NSLog(@"[VirtualCam] ✅ Hook AVCaptureVideoDataOutput成功");
    }else{
        NSLog(@"[VirtualCam] ❌ AVCaptureVideoDataOutput class not found");
    }
}
