#include "PocketJEnvironment.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static void equal(const char *name, const char *value) {
    assert(getenv(name) && !strcmp(getenv(name), value));
}
int main(void) {
    const char *suffixes[] = {"HOME", "GAME_DIR", "RENDERER", "DETECTEDINST", "SKIP_JNI_GLFW", "NATIVEDIR"};
    for (size_t i = 0; i < 6; i++) {
        char modern[64], legacy[64];
        snprintf(modern, sizeof(modern), "POCKETJ_%s", suffixes[i]);
        snprintf(legacy, sizeof(legacy), "POJAV_%s", suffixes[i]);
        unsetenv(modern); unsetenv(legacy);
        assert(PocketJGetEnv(modern) == NULL);
        PocketJInitializeEnvironment();
        assert(getenv(modern) == NULL && getenv(legacy) == NULL);
        setenv(legacy, "old-only", 1);
        assert(!strcmp(PocketJGetEnv(modern), "old-only"));
        PocketJInitializeEnvironment();
        equal(modern, "old-only"); equal(legacy, "old-only");
        setenv(modern, "canonical", 1); setenv(legacy, "conflict", 1);
        PocketJInitializeEnvironment();
        equal(modern, "canonical"); equal(legacy, "canonical");
        assert(PocketJSetEnv(legacy, "replacement", 0) == 0);
        equal(modern, "canonical"); equal(legacy, "canonical");
        assert(PocketJSetEnv(modern, "", 1) == 0);
        equal(modern, ""); equal(legacy, "");
        assert(PocketJUnsetEnv(legacy) == 0);
        assert(getenv(modern) == NULL && getenv(legacy) == NULL);
        const char *names[] = {legacy, modern}, *values[] = {"old", "new"};
        assert(PocketJApplyEnvironment(names, values, 2) == 0);
        equal(modern, "new"); equal(legacy, "new");
        const char *reverse[] = {modern, legacy}, *reverseValues[] = {"winner", "loser"};
        assert(PocketJApplyEnvironment(reverse, reverseValues, 2) == 0);
        equal(modern, "winner"); equal(legacy, "winner");
        assert(PocketJUnsetEnv(modern) == 0);
    }
    assert(PocketJSetEnv("POCKETJ_TEST_UNMAPPED", "unchanged", 1) == 0);
    equal("POCKETJ_TEST_UNMAPPED", "unchanged");
    PocketJUnsetEnv("POCKETJ_TEST_UNMAPPED");
    assert(PocketJGetEnv(NULL) == NULL);
    assert(PocketJSetEnv(NULL, "bad", 1) == -1);
    puts("PASS: six environment aliases, absent/empty values, overwrite, legacy input and canonical precedence in either order.");
    return 0;
}
