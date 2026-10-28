#include "PocketJRenderBridge.h"
#include <assert.h>
#include <stdio.h>

#define OLD_ABI(name) extern __typeof__(pocketj##name) pojav##name;
OLD_ABI(Init) OLD_ABI(InitOpenGL) OLD_ABI(CreateContext) OLD_ABI(GetCurrentContext)
OLD_ABI(MakeCurrent) OLD_ABI(Terminate) OLD_ABI(SetWindowHint) OLD_ABI(SwapBuffers)
OLD_ABI(SwapInterval) OLD_ABI(PumpEvents) OLD_ABI(RewindEvents)
static unsigned calls;
static basic_render_window_t context;
int pocketjInit(BOOL flag) { assert(flag); calls |= 1; return 31; }
int pocketjInitOpenGL(void) { calls |= 2; return 32; }
void *pocketjCreateContext(basic_render_window_t *share) { assert(share == &context); calls |= 4; return share; }
void *pocketjGetCurrentContext(void) { calls |= 8; return &context; }
void pocketjMakeCurrent(basic_render_window_t *window) { assert(window == &context); calls |= 16; }
void pocketjTerminate(void) { calls |= 32; }
void pocketjSetWindowHint(int hint, int value) { assert(hint == 17 && value == -3); calls |= 64; }
void pocketjSwapBuffers(void) { calls |= 128; }
void pocketjSwapInterval(int interval) { assert(interval == 2); calls |= 256; }
void pocketjPumpEvents(void *window) { assert(window == &context); calls |= 512; }
void pocketjRewindEvents(void) { calls |= 1024; }
int main(void) {
    assert(pojavInit(YES) == 31);
    assert(pojavInitOpenGL() == 32);
    assert(pojavCreateContext(&context) == &context);
    assert(pojavGetCurrentContext() == &context);
    pojavMakeCurrent(&context); pojavTerminate(); pojavSetWindowHint(17, -3);
    pojavSwapBuffers(); pojavSwapInterval(2); pojavPumpEvents(&context); pojavRewindEvents();
    assert(calls == 2047);
    puts("PASS: all eleven typed legacy renderer aliases forward arguments and results to the canonical implementation.");
    return 0;
}
