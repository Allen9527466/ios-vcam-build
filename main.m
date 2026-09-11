#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#include <objc/runtime.h>

static BOOL g_vcamEnable = NO;
static id<MTLTexture> g_blueTex = nil;

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
    
    id<MTLTexture> tex = drawable.texture;
    if(!g_blueTex){
        id<MTLDevice> dev = tex.device;
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:tex.pixelFormat width:tex.width height:tex.height mipmapped:NO];
        g_blueTex = [dev newTextureWithDescriptor:desc];
        uint8_t blue[4] = {255,0,0,255};
        [g_blueTex replaceRegion:MTLRegionMake2D(0,0,tex.width,tex.height) mipmapLevel:0 withBytes:blue bytesPerRow:4];
    }
    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = tex;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0,0,1,1);
    id<MTLCommandBuffer> cmd = [tex.device commandQueue].commandBuffer;
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
