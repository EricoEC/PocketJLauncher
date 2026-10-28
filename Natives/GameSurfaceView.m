#import "GameSurfaceView.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"
#import "PocketJGameStartup.h"
#import <objc/runtime.h>

static void PocketJObserveStartupDrawable(id<CAMetalDrawable> drawable) {
    PJStartupSnapshot state = PocketJGameStartupSnapshot();
    if (!drawable || !state.active || state.hasFrame) return;
    PocketJGameStartupRendering(true);
    uint64_t session = state.session;
    [drawable addPresentedHandler:^(id<MTLDrawable> presented) {
        PocketJGameStartupPresented(session);
    }];
}

// SDL3 creates its own SDL_uikitmetalview/CAMetalLayer, not GameSurfaceView.
// Observe that layer's real presentations too; allocating a window/swapchain
// alone is not proof of a frame. Never replace the drawable or renderer.
@interface CAMetalLayer (PocketJSDLStartup)
- (id<CAMetalDrawable>)pocketj_startupNextDrawable;
@end
@implementation CAMetalLayer (PocketJSDLStartup)
- (id<CAMetalDrawable>)pocketj_startupNextDrawable {
    id<CAMetalDrawable> drawable = [self pocketj_startupNextDrawable];
    if ([NSStringFromClass([self.delegate class]) hasPrefix:@"SDL_"]) {
        PocketJObserveStartupDrawable(drawable);
    }
    return drawable;
}
@end

static void PocketJInstallSDLStartupObservation(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method original = class_getInstanceMethod(CAMetalLayer.class, @selector(nextDrawable));
        Method observer = class_getInstanceMethod(CAMetalLayer.class, @selector(pocketj_startupNextDrawable));
        if (original && observer) method_exchangeImplementations(original, observer);
    });
}

// GLFW/ANGLE use our own layer. SDL/Vulkan are observed separately above.
@interface PocketJStartupMetalLayer : CAMetalLayer
@end
@implementation PocketJStartupMetalLayer
- (id<CAMetalDrawable>)nextDrawable {
    id<CAMetalDrawable> drawable = [super nextDrawable];
    PocketJObserveStartupDrawable(drawable);
    return drawable;
}
@end

@interface GameSurfaceView()
@end

@implementation GameSurfaceView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    PocketJInstallSDLStartupObservation();
    self.layer.drawsAsynchronously = YES;
    self.layer.opaque = YES;

    return self;
}

+ (Class)layerClass {
    if ([[PLProfiles resolveKeyForCurrentProfile:@"renderer"] hasPrefix:@"libOSMesa"]) {
        return CALayer.class;
    } else {
        return PocketJStartupMetalLayer.class;
    }
}

@end
