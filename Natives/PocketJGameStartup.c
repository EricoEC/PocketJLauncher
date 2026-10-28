#include "PocketJGameStartup.h"
#include <pthread.h>

static pthread_mutex_t stateLock = PTHREAD_MUTEX_INITIALIZER;
static PJStartupSnapshot state;

uint64_t PocketJGameStartupBegin(void) {
    pthread_mutex_lock(&stateLock);
    uint64_t next = state.session + 1;
    state = (PJStartupSnapshot){.session = next, .active = true, .stage = PJStartupWindow};
    pthread_mutex_unlock(&stateLock);
    return next;
}

PJStartupSnapshot PocketJGameStartupSnapshot(void) {
    pthread_mutex_lock(&stateLock);
    PJStartupSnapshot snapshot = state;
    pthread_mutex_unlock(&stateLock);
    return snapshot;
}

void PocketJGameStartupAdvance(PJStartupStage stage) {
    pthread_mutex_lock(&stateLock);
    if (state.active && state.stage >= PJStartupWindow && state.stage < PJStartupFrame &&
        stage > state.stage && stage <= PJStartupRenderer) state.stage = stage;
    pthread_mutex_unlock(&stateLock);
}

void PocketJGameStartupRendering(bool metal) {
    pthread_mutex_lock(&stateLock);
    if (state.active && state.stage >= PJStartupWindow && state.stage < PJStartupFrame) {
        state.stage = PJStartupRenderer;
        state.metal = metal;
    }
    pthread_mutex_unlock(&stateLock);
}

void PocketJGameStartupPresented(uint64_t session) {
    pthread_mutex_lock(&stateLock);
    if (state.active && state.session == session && state.stage >= PJStartupWindow &&
        state.stage < PJStartupExited) {
        state.hasFrame = true;
        state.stage = PJStartupFrame;
    }
    pthread_mutex_unlock(&stateLock);
}

void PocketJGameStartupFinish(uint64_t session, int code) {
    pthread_mutex_lock(&stateLock);
    if (state.active && state.session == session) {
        state.exitCode = code;
        state.stage = code ? PJStartupFailed : PJStartupExited;
        state.active = false;
    }
    pthread_mutex_unlock(&stateLock);
}

