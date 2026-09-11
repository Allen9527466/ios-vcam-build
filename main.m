#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// 外部接口声明，供调试/外部工具调用
void virtualVideoSetupHook(void);
void setVirtualVideoEnabled(BOOL enabled);
BOOL isVirtualVideoEnabled(void);
void setSelectedVideoPath(NSString *videoPath);
NSString *getSelectedVideoPath(void);

__attribute__((constructor))
static void tweakMainEntry(void)
{
    @autoreleasepool {
        NSLog(@"XUUz V5.0 dylib loaded, NO UI, background only");
        // 只打印日志，不创建任何窗口、不监听UI通知、不调用hook
    }
}
