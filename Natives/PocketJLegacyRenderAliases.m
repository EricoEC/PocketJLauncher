#include "PocketJRenderBridge.h"

// Historical native ABI only. New Java/GLFW code resolves pocketj* exclusively.
// Keep real typed forwarding functions, not independent renderer state.
int pojavInit(BOOL useStackQueue) { return pocketjInit(useStackQueue); }
int pojavInitOpenGL(void) { return pocketjInitOpenGL(); }
void *pojavCreateContext(basic_render_window_t *shared) { return pocketjCreateContext(shared); }
void *pojavGetCurrentContext(void) { return pocketjGetCurrentContext(); }
void pojavMakeCurrent(basic_render_window_t *window) { pocketjMakeCurrent(window); }
void pojavTerminate(void) { pocketjTerminate(); }
void pojavSetWindowHint(int hint, int value) { pocketjSetWindowHint(hint, value); }
void pojavSwapBuffers(void) { pocketjSwapBuffers(); }
void pojavSwapInterval(int interval) { pocketjSwapInterval(interval); }
void pojavPumpEvents(void *window) { pocketjPumpEvents(window); }
void pojavRewindEvents(void) { pocketjRewindEvents(); }
