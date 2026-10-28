#include "PocketJEnvironment.h"
#include <stdlib.h>
#include <string.h>
#include <errno.h>

typedef struct { const char *canonical, *legacy; } EnvAlias;
static const EnvAlias aliases[] = {
    {"POCKETJ_HOME", "POJAV_HOME"},
    {"POCKETJ_GAME_DIR", "POJAV_GAME_DIR"},
    {"POCKETJ_RENDERER", "POJAV_RENDERER"},
    {"POCKETJ_DETECTEDINST", "POJAV_DETECTEDINST"},
    {"POCKETJ_SKIP_JNI_GLFW", "POJAV_SKIP_JNI_GLFW"},
    {"POCKETJ_NATIVEDIR", "POJAV_NATIVEDIR"},
};
static const EnvAlias *aliasFor(const char *name) {
    if (!name) return NULL;
    for (size_t i = 0; i < sizeof(aliases) / sizeof(*aliases); i++)
        if (!strcmp(name, aliases[i].canonical) || !strcmp(name, aliases[i].legacy)) return &aliases[i];
    return NULL;
}
const char *PocketJCanonicalEnvName(const char *name) {
    const EnvAlias *alias = aliasFor(name);
    return alias ? alias->canonical : name;
}
const char *PocketJGetEnv(const char *name) {
    if (!name) return NULL;
    const EnvAlias *alias = aliasFor(name);
    if (!alias) return getenv(name);
    const char *value = getenv(alias->canonical);
    return value ? value : getenv(alias->legacy);
}
int PocketJSetEnv(const char *name, const char *value, int overwrite) {
    if (!name || !value) { errno = EINVAL; return -1; }
    const EnvAlias *alias = aliasFor(name);
    if (!alias) return setenv(name, value, overwrite);
    const char *existing = PocketJGetEnv(alias->canonical);
    // getenv pointers may be invalidated by setenv; own the chosen value first.
    char *chosen = strdup(!overwrite && existing ? existing : value);
    if (!chosen) return -1;
    int result = setenv(alias->canonical, chosen, 1);
    if (result == 0) result = setenv(alias->legacy, chosen, 1);
    free(chosen);
    return result;
}
int PocketJUnsetEnv(const char *name) {
    if (!name) { errno = EINVAL; return -1; }
    const EnvAlias *alias = aliasFor(name);
    if (!alias) return unsetenv(name);
    int first = unsetenv(alias->canonical);
    int second = unsetenv(alias->legacy);
    return first ? first : second;
}
void PocketJInitializeEnvironment(void) {
    for (size_t i = 0; i < sizeof(aliases) / sizeof(*aliases); i++) {
        const char *value = PocketJGetEnv(aliases[i].canonical);
        // Do not invent a native-library path or enable an absent skip flag.
        if (value) PocketJSetEnv(aliases[i].canonical, value, 1);
    }
}
int PocketJApplyEnvironment(const char *const *names, const char *const *values, size_t count) {
    if (count && (!names || !values)) { errno = EINVAL; return -1; }
    for (size_t i = 0; i < count; i++) {
        if (!names[i] || !values[i]) { errno = EINVAL; return -1; }
        const char *canonical = PocketJCanonicalEnvName(names[i]);
        if (strcmp(canonical, names[i])) {
            int hasCanonical = 0;
            for (size_t j = 0; j < count; j++)
                if (names[j] && !strcmp(names[j], canonical)) { hasCanonical = 1; break; }
            if (hasCanonical) continue;
        }
        if (PocketJSetEnv(names[i], values[i], 1)) return -1;
    }
    return 0;
}
