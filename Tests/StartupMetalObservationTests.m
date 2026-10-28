#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "PocketJGameStartup.h"
#include <assert.h>
#define CAMetalLayer PJTestMetalLayer

// A deterministic drawable/layer model: exercise the production observer and
// Objective-C dispatch without requiring a GPU or claiming device acceptance.
@protocol MTLDrawable <NSObject>
@end
@protocol CAMetalDrawable <MTLDrawable>
- (void)addPresentedHandler:(void (^)(id<MTLDrawable>))handler;
@end
@interface TestDrawable : NSObject <CAMetalDrawable>
@property(nonatomic, copy) void (^handler)(id<MTLDrawable>);
@end
@implementation TestDrawable
- (void)addPresentedHandler:(void (^)(id<MTLDrawable>))handler { self.handler = handler; }
@end
@interface CAMetalLayer : NSObject
@property(nonatomic, strong) id delegate;
@property(nonatomic, strong) TestDrawable *drawable;
@property(nonatomic) NSUInteger requests;
- (id<CAMetalDrawable>)nextDrawable;
@end
@implementation CAMetalLayer
- (id<CAMetalDrawable>)nextDrawable { self.requests++; return self.drawable; }
@end
@interface SDL_uikitmetalview : NSObject
@end
@implementation SDL_uikitmetalview
@end

// POCKETJ_OBSERVATION_IMPLEMENTATION

int main(void) {
    @autoreleasepool {
        PocketJInstallSDLStartupObservation();
        PocketJInstallSDLStartupObservation(); // Must not swap back on reentry.
        CAMetalLayer *sdl = [CAMetalLayer new];
        sdl.delegate = [SDL_uikitmetalview new];
        sdl.drawable = [TestDrawable new];
        uint64_t first = PocketJGameStartupBegin();
        assert([sdl nextDrawable] == sdl.drawable && sdl.requests == 1);
        assert(sdl.drawable.handler && !PocketJGameStartupSnapshot().hasFrame);
        sdl.drawable.handler(sdl.drawable);
        assert(PocketJGameStartupSnapshot().hasFrame);

        PocketJGameStartupBegin();
        sdl.drawable.handler(sdl.drawable); // Previous session must not finish this one.
        assert(!PocketJGameStartupSnapshot().hasFrame);
        assert(PocketJGameStartupSnapshot().session != first);
        CAMetalLayer *unrelated = [CAMetalLayer new];
        unrelated.delegate = [NSObject new];
        unrelated.drawable = [TestDrawable new];
        assert([unrelated nextDrawable] == unrelated.drawable);
        assert(!unrelated.drawable.handler);

        PocketJStartupMetalLayer *glfw = [PocketJStartupMetalLayer new];
        glfw.drawable = [TestDrawable new];
        assert([glfw nextDrawable] == glfw.drawable && glfw.requests == 1);
        assert(glfw.drawable.handler && !PocketJGameStartupSnapshot().hasFrame);
        glfw.drawable.handler(glfw.drawable);
        assert(PocketJGameStartupSnapshot().hasFrame);
        puts("PASS: actual observer dispatch, SDL/GLFW presentation, unrelated layers, install reentry and stale callbacks.");
    }
}
