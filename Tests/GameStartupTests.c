#include "PocketJGameStartup.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>

static void *lateStages(void *unused) {
    for (int i = 0; i < 10000; i++) {
        PocketJGameStartupAdvance(PJStartupRuntime);
        PocketJGameStartupAdvance(PJStartupJNI);
    }
    return NULL;
}

int main(void) {
    assert(!PocketJGameStartupSnapshot().active);
    PocketJGameStartupAdvance(PJStartupJVM);
    assert(PocketJGameStartupSnapshot().stage == PJStartupWindow);
    uint64_t first = PocketJGameStartupBegin();
    PocketJGameStartupAdvance(PJStartupJVM);
    PocketJGameStartupAdvance(PJStartupRuntime);
    assert(PocketJGameStartupSnapshot().stage == PJStartupJVM);
    PocketJGameStartupRendering(true);
    assert(PocketJGameStartupSnapshot().metal);
    pthread_t worker;
    assert(pthread_create(&worker, NULL, lateStages, NULL) == 0);
    PocketJGameStartupPresented(first - 1);
    assert(!PocketJGameStartupSnapshot().hasFrame);
    PocketJGameStartupPresented(first);
    pthread_join(worker, NULL);
    assert(PocketJGameStartupSnapshot().stage == PJStartupFrame);
    assert(PocketJGameStartupSnapshot().hasFrame);
    PocketJGameStartupFinish(first, 0);
    assert(!PocketJGameStartupSnapshot().active);

    uint64_t second = PocketJGameStartupBegin();
    assert(second > first);
    assert(!PocketJGameStartupSnapshot().hasFrame);
    PocketJGameStartupFinish(first, 1);
    PocketJGameStartupPresented(first);
    assert(PocketJGameStartupSnapshot().stage == PJStartupWindow);
    assert(PocketJGameStartupSnapshot().active);
    PocketJGameStartupRendering(false);
    assert(!PocketJGameStartupSnapshot().metal);
    PocketJGameStartupFinish(second, 42);
    PocketJGameStartupPresented(second);
    PocketJGameStartupAdvance(PJStartupJVM);
    assert(PocketJGameStartupSnapshot().stage == PJStartupFailed);
    assert(PocketJGameStartupSnapshot().exitCode == 42);
    assert(!PocketJGameStartupSnapshot().active);
    assert(!PocketJGameStartupSnapshot().hasFrame);

    uint64_t third = PocketJGameStartupBegin();
    PocketJGameStartupFinish(third, 0);
    assert(PocketJGameStartupSnapshot().stage == PJStartupExited);
    puts("PASS: startup stage order, first frame, stale sessions, failures and concurrent callbacks.");
    return 0;
}
