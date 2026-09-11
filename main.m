#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>
#include <stdatomic.h>

static atomic_bool g_vcamEnable = ATOMIC_VAR_INIT(0);
static id<MTLTexture> g_imageTex = nil;
static id<MTLDevice> g_mtlDev = nil;
static id<MTLCommandQueue> g_cmdQueue = nil;
static id<MTLRenderPipelineState> g_pipeline = nil;

static const char* shaderSource =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct VertexIn {\n"
"    float2 pos [[attribute(0)]];\n"
"    float2 uv [[attribute(1)]];\n"
"};\n"
"struct VertexOut {\n"
"    float4 pos [[position]];\n"
"    float2 uv;\n"
"};\n"
"vertex VertexOut vtx(VertexIn in [[stage_in]]) {\n"
"    VertexOut out;\n"
"    out.pos = float4(in.pos, 0, 1);\n"
"    out.uv = in.uv;\n"
"    return out;\n"
"}\n"
"fragment float4 frag(VertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {\n"
"    return tex.sample(sampler(coord::clamp_to_edge, filter::linear), in.uv);\n"
"}";

static void swizzle(Class cls, SEL origSel, SEL newSel)
{
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    method_exchangeImplementations(origMethod, newMethod);
}

static void buildPipeline()
{
    NSError *err = nil;
    id<MTLLibrary> lib = [g_mtlDev newLibraryWithSource:@(shaderSource) options:nil error:&err];
    if(err) {
        NSLog(@"shader compile error: %@", err);
        return;
    }
    id<MTLFunction> vtxFunc = [lib newFunctionWithName:@"vtx"];
    id<MTLFunction> fragFunc = [lib newFunctionWithName:@"frag"];
    
    MTLRenderPipelineDescriptor *pipeDesc = [MTLRenderPipelineDescriptor new];
    pipeDesc.vertexFunction = vtxFunc;
    pipeDesc.fragmentFunction = fragFunc;
    pipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    g_pipeline = [g_mtlDev newRenderPipelineStateWithDescriptor:pipeDesc error:&err];
    if(err) NSLog(@"pipeline error: %@", err);
}

static id<MTLTexture> createTextureFromImage(UIImage *img, id<MTLDevice> dev)
{
    if(!img || !dev) return nil;
    CGImageRef cgImg = img.CGImage;
    if(!cgImg) return nil;
    
    size_t w = CGImageGetWidth(cgImg);
    size_t h = CGImageGetHeight(cgImg);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    void *bitmapData = malloc(w * h * 4);
    if(!bitmapData)
    {
        CGColorSpaceRelease(colorSpace);
        return nil;
    }
    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast;
    CGContextRef ctx = CGBitmapContextCreate(bitmapData, w, h, 8, w*4, colorSpace, bitmapInfo);
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

static void loadBackgroundImage()
{
    @autoreleasepool {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docPath = paths.firstObject;
        NSString *imgPath = [docPath stringByAppendingPathComponent:@"vcam_bg.png"];
        UIImage *img = [UIImage imageWithContentsOfFile:imgPath];
        if(!img)
        {
            NSLog(@"vcam_bg.png not found at %@", imgPath);
            return;
        }
        if(!g_mtlDev) {
            g_mtlDev = MTLCreateSystemDefaultDevice();
            if(!g_mtlDev) {
                NSLog(@"Metal device not supported");
                return;
            }
            g_cmdQueue = [g_mtlDev newCommandQueue];
            buildPipeline();
        }
        if(g_imageTex) g_imageTex = nil;
        g_imageTex = createTextureFromImage(img, g_mtlDev);
        NSLog(@"load image texture ok");
    }
}

static BOOL isCameraRecordingPage()
{
    @autoreleasepool {
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
}

@interface CAMetalLayer (VCamHook)
- (id<CAMetalDrawable>)vcam_nextDrawable;
@end

@implementation CAMetalLayer (VCamHook)
- (id<CAMetalDrawable>)vcam_nextDrawable
{
    @autoreleasepool {
        id<CAMetalDrawable> drawable = [self vcam_nextDrawable];
        if(!atomic_load(&g_vcamEnable) || !drawable) return drawable;
        if(!isCameraRecordingPage()) return drawable;
        if(!g_imageTex || !g_cmdQueue || !g_pipeline) return drawable;
        
        MTLRenderPassDescriptor *rpDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        rpDesc.colorAttachments[0].texture = drawable.texture;
        rpDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
        rpDesc.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,1);
        rpDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        id<MTLCommandBuffer> cmdBuf = [g_cmdQueue commandBuffer];
        id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpDesc];
        [enc setRenderPipelineState:g_pipeline];
        
        // 全屏三角带，覆盖整个屏幕
        float quad[] = {
            -1,-1, 0,1,
             1,-1, 1,1,
            -1, 1, 0,0,
             1, 1, 1,0,
        };
        [enc setVertexBytes:quad length:sizeof(quad) atIndex:0];
        [enc setFragmentTexture:g_imageTex atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [enc endEncoding];
        
        [cmdBuf commit];
        [cmdBuf waitUntilCompleted];
        return drawable;
    }
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
    atomic_bool old = atomic_load(&g_vcamEnable);
    atomic_store(&g_vcamEnable, !old);
    NSLog(@"VirtualCam toggle: %@", atomic_load(&g_vcamEnable) ? @"ON" : @"OFF");
    self.backgroundColor = atomic_load(&g_vcamEnable) ? [UIColor systemRedColor] : [UIColor systemBlueColor];
    if(atomic_load(&g_vcamEnable)) loadBackgroundImage();
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
