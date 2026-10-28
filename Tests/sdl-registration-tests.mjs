import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
const root = fileURLToPath(new URL('../', import.meta.url));
const source = readFileSync(join(root, 'Natives/input_bridge_v3.m'), 'utf8');
const production = source.slice(source.indexOf('static void pjSDLResolveFunctions(void)'),
    source.indexOf('static int pjSDLScancode('));
assert(production.includes('void Amethyst_SetSDLWindow(void *window)'));
const surface = readFileSync(join(root, 'Natives/SurfaceViewController.m'), 'utf8');
assert(surface.includes('block:^(NSTimer *timer) { PocketJRefreshSDLGrabState(); }'));
assert(surface.includes('[self.sdlInputTimer invalidate];'));
assert(surface.includes('PocketJRegisterSDLWindow(NULL);'));
const harness = `
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <dlfcn.h>
#define UIWindow PJTestWindow
#define SurfaceViewController PJTestSurface
@interface UIViewController : NSObject @end
@implementation UIViewController @end
@interface SurfaceViewController : UIViewController
@property NSUInteger updates;
- (void)updateGrabState;
@end
@implementation SurfaceViewController
- (void)updateGrabState { self.updates++; }
@end
static SurfaceViewController *testRoot;
@interface UIWindow : NSObject
@property(readonly) UIViewController *rootViewController;
+ (instancetype)mainWindow;
@end
@implementation UIWindow
+ (instancetype)mainWindow { static UIWindow *w; if (!w) w = [self new]; return w; }
- (UIViewController *)rootViewController { return testRoot; }
@end
static void *pjSDLHandle, *GLFW_invoke_CursorPos;
static void **(*pjSDLGetWindows)(int *);
static uint32_t (*pjSDLGetWindowID)(void *);
static bool (*pjSDLPushEvent)(void *);
static const bool *(*pjSDLGetKeyboardState)(int *);
static uint16_t (*pjSDLGetModState)(void);
static void (*pjSDLSetModState)(uint16_t);
static void (*pjSDLFree)(void *);
static bool (*pjSDLGetWindowRelativeMouseMode)(void *);
static atomic_uintptr_t pjSDLRegisteredWindow;
static atomic_uint pjSDLRegisteredWindowID;
static BOOL isGrabbing;
static bool relative;
static unsigned enumerations, idQueries;
static uint32_t getID(void *window) { assert(window == (void *)42); idQueries++; return 7; }
static bool getRelative(void *window) { assert(window == (void *)42); return relative; }
static bool push(void *event) { return true; }
static void **getWindows(int *count) { enumerations++; *count = 0; return NULL; }
static void *fakeOpen(const char *path, int flags) { return (void *)1; }
static void *fakeSymbol(void *handle, const char *name) {
    if (!strcmp(name, "SDL_GetWindowID")) return getID;
    if (!strcmp(name, "SDL_GetWindows")) return getWindows;
    if (!strcmp(name, "SDL_PushEvent")) return push;
    if (!strcmp(name, "SDL_free")) return free;
    if (!strcmp(name, "SDL_GetWindowRelativeMouseMode")) return getRelative;
    return NULL;
}
#define dlopen fakeOpen
#define dlsym fakeSymbol
${production}
int main(void) { @autoreleasepool {
    testRoot = [SurfaceViewController new];
    PocketJRefreshSDLGrabState();
    assert(!pjSDLHandle && !testRoot.updates); // Older GLFW releases do not load SDL.
    Amethyst_SetSDLWindow((void *)42);
    assert(pjSDLWindowID() == 7 && idQueries == 1);
    for (int i = 0; i < 10000; i++) assert(pjSDLWindowID() == 7);
    assert(!enumerations && idQueries == 1);
    relative = true;
    PocketJRefreshSDLGrabState();
    assert(isGrabbing && testRoot.updates == 1);
    PocketJRefreshSDLGrabState();
    assert(testRoot.updates == 1);
    relative = false;
    PocketJRefreshSDLGrabState();
    assert(!isGrabbing && testRoot.updates == 2);
    GLFW_invoke_CursorPos = (void *)1;
    relative = true;
    PocketJRefreshSDLGrabState();
    assert(!isGrabbing && testRoot.updates == 2);
    PocketJRegisterSDLWindow(NULL);
    assert(!atomic_load(&pjSDLRegisteredWindow) && !atomic_load(&pjSDLRegisteredWindowID));
    puts("PASS: SDL binary registration, cached window ID, menu/game transitions, idempotence, GLFW isolation and teardown.");
} }
`;
const dir = mkdtempSync(join(tmpdir(), 'pocketj-sdl-registration-'));
try {
    const input = join(dir, 'test.m'), output = join(dir, 'test');
    writeFileSync(input, harness);
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation', input, '-o', output], { stdio: 'inherit' });
    execFileSync(output, [], { stdio: 'inherit' });
} finally { rmSync(dir, { recursive: true, force: true }); }
