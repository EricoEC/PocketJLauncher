#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif
// Internal names are canonical. Legacy names exist only at this boundary for
// shipped third-party binaries and saved user environment configurations.
const char *PocketJCanonicalEnvName(const char *name);
const char *PocketJGetEnv(const char *name);
int PocketJSetEnv(const char *name, const char *value, int overwrite);
int PocketJUnsetEnv(const char *name);
void PocketJInitializeEnvironment(void);
int PocketJApplyEnvironment(const char *const *names, const char *const *values, size_t count);
#ifdef __cplusplus
}
#endif
