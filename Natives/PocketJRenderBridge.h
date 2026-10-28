#pragma once
#include <objc/objc.h>
#include <stdbool.h>
#include "ctxbridges/bridge_tbl.h"

int pocketjInit(BOOL useStackQueue);
int pocketjInitOpenGL(void);
void *pocketjCreateContext(basic_render_window_t *shared);
void *pocketjGetCurrentContext(void);
void pocketjMakeCurrent(basic_render_window_t *window);
void pocketjTerminate(void);
void pocketjSetWindowHint(int hint, int value);
void pocketjSwapBuffers(void);
void pocketjSwapInterval(int interval);
void pocketjPumpEvents(void *window);
void pocketjRewindEvents(void);
