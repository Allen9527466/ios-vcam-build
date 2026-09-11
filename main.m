#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>

static BOOL g_vcamEnable = NO;

static void swizzle(Class cls, SEL origSel, SEL newSel)
{
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    method_exchangeImplementations(origMethod, newMethod);
}

@interface CAMetalLayer (VCamHook)
- (id<CAMetalDrawable>)vcam_nextDrawable;
@end

@implementation CAMetalLayer (VCamHook)
- (id<CAMetalDrawable>)vcam_nextDrawable
{
    id<CAMetalDrawable> drawable = [self vcam_nextDrawable];
    if(!g_vcamEnable || !drawable) return drawable;

    // ====== 核心过滤：只处理大于 400x400 的大画布（相机预览），小UI图层直接跳过 ======
    CGRect layerBounds = self.bounds;
    CGFloat w = layerBounds.size.width;
    CGFloat h = layerBounds.size.height;
    if(w < 400 || h < 400)
    {
        return drawable;
    }

    id<MTLTexture> tex = drawable.texture;
    id<MTLDevice> dev = tex.device;
    id<MTLCommandQueue> queue = [dev newCommandQueue];
    id<MTLCommandBuffer> cmd = [queue commandBuffer];
    
    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = tex;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    // 蓝色背景 RGBA
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1.0, 1.0);
    
    id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:rpd];
    [enc endEncoding];
    [cmd commit];
    
    return drawable;
}
@end

@interface VCamFloatWindow : UIWindow
@end

@implementation VCamFloatWindow
- (instancetype)init
{
    self = [super init];
    if(self){
        self.frame = CGRectMake(50,200,70,70);
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 35;
        self.clipsToBounds = YES;
        self.hidden = NO;
        
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = self.bounds;
        [btn setTitle:@"VC" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [btn addTarget:self action:@selector(tapBtn) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
    }
    return self;
}

- (void)tapBtn
{
    g_vcamEnable = !g_vcamEnable;
    NSLog(@"VirtualCam toggle: %@", g_vcamEnable ? @"ON" : @"OFF");
    self.backgroundColor = g_vcamEnable ? [UIColor systemRedColor] : [UIColor systemBlueColor];
}
@end

static VCamFloatWindow *g_floatWin = nil;

__attribute__((constructor))
void lib_main()
{
    Class metalLayerCls = objc_getClass("CAMetalLayer");
    SEL origSel = @selector(nextDrawable);
    SEL newSel = @selector(vcam_nextDrawable);
    swizzle(metalLayerCls, origSel, newSel);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        g_floatWin = [[VCamFloatWindow alloc] init];
    });
}
