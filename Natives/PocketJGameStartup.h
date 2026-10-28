#pragma once
#include <stdbool.h>
#include <stdint.h>

// Same stages as VisionPro-PJL/v0.2's pj_game_startup_stage(). These are
// observation only: never drive renderer, JVM, JIT, or input decisions.
typedef enum {
    PJStartupFailed = -1,
    PJStartupWindow = 0,
    PJStartupRuntime = 1,
    PJStartupJVM = 2,
    PJStartupJNI = 3,
    PJStartupRenderer = 4,
    PJStartupFrame = 5,
    PJStartupExited = 6
} PJStartupStage;

typedef struct {
    uint64_t session;
    PJStartupStage stage;
    bool active;
    bool hasFrame;
    bool metal;
    int exitCode;
} PJStartupSnapshot;

uint64_t PocketJGameStartupBegin(void);
PJStartupSnapshot PocketJGameStartupSnapshot(void);
void PocketJGameStartupAdvance(PJStartupStage stage);
void PocketJGameStartupRendering(bool metal);
void PocketJGameStartupPresented(uint64_t session);
void PocketJGameStartupFinish(uint64_t session, int code);

