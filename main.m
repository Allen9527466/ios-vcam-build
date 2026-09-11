#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>

static BOOL g_vcamEnable = NO;
static id<MTLTexture> g_imageTex = nil;
static id<MTLDevice> g_mtlDev = nil;

static void swizzle(Class cls, SEL origSel, SEL newSel)
{
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    method_exchangeImplementations(origMethod, newMethod);
}

// UIImage转Metal Texture
static id<MTLTexture> createTextureFromImage(UIImage *img, id<MTLDevice> dev)
{
    if(!img || !dev) return nil;
    CGImageRef cgImg = img.CGImage;
    if(!cgImg) return nil;
    
    size_t w = CGImageGetWidth(cgImg);
    size_t h = CGImageGetHeight(cgImg);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGBA();
    void *bitmapData = malloc(w * h * 4);
    CGContextRef ctx = CGContextCreate(bitmapData, w, h, 8, w*4, colorSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if(!ctx)
    {
        free(bitmapData);
        return nil;
    }
    CGContextDrawImage(ctx, CGRectMake(0,0,w,h), cgImg);
    
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
    id<MTLTexture> tex = [dev newTextureWithDescriptor:texDesc];
    [tex replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0 withBytes:bitmapData bytesPerRow:w*4];
    
    CGContextRelease(ctx);
    free(bitmapData);
    return tex;
}

// 加载图片（路径：Documents/vcam_bg.png）
static void loadBackgroundImage()
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docPath = paths.firstObject;
    NSString *imgPath = [docPath stringByAppendingPathComponent:@"vcam_bg.png"];
    UIImage *img = [UIImage imageWithContentsOfFile:imgPath];
    if(!img)
    {
        NSLog(@"vcam_bg.png not found at %@", imgPath);
        return;
    }
    if(!g_mtlDev) g_mtlDev = MTLCreateSystemDefaultDevice();
    g_imageTex = createTextureFromImage(img, g_mtlDev);
    NSLog(@"load image texture ok");
}

// 判断当前页面是否是抖音拍摄页
static BOOL isCameraRecordingPage()
{
    UIWindow *keyWin = nil;
    for(UIWindow *w in [UIApplication sharedApplication].windows)
    {
        if(w.isKeyWindow)
        {
            keyWin = w;
            break;
        }
    }
    if(!keyWin) return NO;
    NSString *pageStr = [keyWin.rootViewController description];
    if([pageStr containsString:@"Recorder"] || [pageStr containsString:@"Capture"])
    {
        return YES;
    }
    return NO;
}

@interface CAMetalLayer (VCamHook)
- (id<CAMetalDrawable>)vcam_nextDrawable;
@end

@implementation CAMetalLayer (VCamHook)
- (id<CAMetalDrawable>)vcam_nextDrawable
{
    id<CAMetalDrawable> drawable = [self vcam_nextDrawable];
    if(!g_vcamEnable || !drawable) return drawable;
    if(!isCameraRecordingPage()) return drawable;
    
    CGRect layerBounds = self.bounds;
    CGFloat w = layerBounds.size.width;
    CGFloat h = layerBounds.size.height;
    if(w < 400 || h < 400) return drawable;
    
    if(!g_imageTex)
    {
        loadBackgroundImage();
    }
    if(!g_imageTex) return drawable;
    
    id<MTLTexture> dstTex = drawable.texture;
    id<MTLCommandQueue> queue = [g_mtlDev newCommandQueue];
    id<MTLCommandBuffer> cmd = [queue commandBuffer];
    
    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = dstTex;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,1);
    
    id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:rpd];
    // 简单贴图：直接拷贝纹理到画布（拉伸铺满预览画面）
    [enc copyTextureFrom:g_imageTex sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(g_imageTex.width, g_imageTex.height,1) toTexture:dstTex destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
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
    // 每次切换开关，重新加载图片
    if(g_vcamEnable) loadBackgroundImage();
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
