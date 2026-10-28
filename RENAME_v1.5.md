# PocketJ namespace migration — iOS v1.5

Only this checkout is migrated. Vision v0.2, earlier releases, Git history and
shared dependency originals are not changed. Bundle ID remains
`com.Erico.PocketJLauncher`; no account/keychain service, preference filename,
instance directory, renderer selection or runtime version is migrated.

## Canonical names

- Java: `com.erico.pocketj`; the 23 launcher sources retain their subpackages.
  Entry/class-loader classes are `PocketJLauncher` and `PocketJClassLoader`.
- Native bridge: `pocketjInit`, `pocketjInitOpenGL`, `pocketjCreateContext`,
  `pocketjGetCurrentContext`, `pocketjMakeCurrent`, `pocketjTerminate`,
  `pocketjSetWindowHint`, `pocketjSwapBuffers`, `pocketjSwapInterval`,
  `pocketjPumpEvents`, `pocketjRewindEvents`.
- JNI: `Java_com_erico_pocketj_uikit_UIKit_showError` and
  `Java_com_erico_pocketj_value_MinecraftAccount_getAccessTokenFromKeychain`.
- Runtime environment uses `POCKETJ_HOME`, `POCKETJ_GAME_DIR`,
  `POCKETJ_RENDERER`, `POCKETJ_DETECTEDINST`, `POCKETJ_SKIP_JNI_GLFW` and optional
  `POCKETJ_NATIVEDIR`. Get/set/unset go through `PocketJEnvironment`.
- Forge property: `pocketj.internal.keepForgeSplash`.
- Build overrides: `POCKETJ_BUNDLE_DIR` and `POCKETJ_JRE8_DIR` /
  `POCKETJ_JRE17_DIR` / `POCKETJ_JRE21_DIR` / `POCKETJ_JRE25_DIR`.
- Upload/open rules match the existing `com.Erico.PocketJLauncher` IPA/TIPA
  filenames and `PocketJLauncher.dSYM`; upstream dependency URLs are unchanged.

## Deliberate legacy allowlist

| Location | Retained spelling and reason |
| --- | --- |
| `Natives/PocketJEnvironment.c` | Six `POJAV_*` keys, mirrored at one boundary for external binaries and saved user environment input. |
| `Natives/PocketJLegacyRenderAliases.m` | Eleven historical `pojav*` exports, typed one-line forwarders; no duplicated renderer state. |
| Two JNI implementation files | Historical `Java_net_kdt_pojavlaunch_*` exports forward to the canonical implementation in the same binary. |
| Java entry class | Old Forge property is a read-only fallback; the new property wins when both are supplied. |
| `Makefile` compatibility block | Five old build override names are accepted only if the new variable is undefined. |
| Three native upstream-reference comments | References to the actual original AWT/control implementation, not fictitious renamed classes. |
| `README.md`, `NOTICE.md`, `LICENSE` | Original project attribution, authorship, license text and real links. |
| GitHub workflow dependency repositories | Real upstream repositories, not product branding or artifact names. |
| Tests / migration documentation | Explicit compatibility assertions and migration records. |

Unmodified prebuilt inputs retain `POJAV_NATIVEDIR` in Caciocavallo and
`POJAV_RENDERER` in two LWJGL JARs. `libvirgl_test_server.dylib` also contains the
old absolute `/Applications/PojavLauncher.app/Frameworks/MetalANGLE.framework/MetalANGLE`
path. This change does not binary-patch it or claim to repair that third-party
path. No dependency was upgraded or rebuilt to erase its provenance strings.

## Environment and compatibility behavior

- Native code reads the canonical key first, falling back to its legacy alias.
- Set/unset operations mirror both names; existing values are owned before
  calling `setenv` so invalidated environment pointers are not reused.
- Custom input accepts both spellings. An explicitly supplied canonical key
  wins in either input order, including an explicitly empty value.
- An absent native-directory or GLFW-skip key remains absent; no new default
  path/behavior is invented. Old Makefile overrides remain usable.
- Native/JNI forwarders preserve argument types, results and the existing
  guarded account-token read. No compatibility Java class tree is bundled.

## Clean builds and verification

`JavaApp/Makefile` has a namespace stamp that invalidates obsolete class/JAR
trees. The common Xcode GUI/CLI runner also invalidates only version-local
native staging once when adopting this namespace. Shared JDK/runtime caches
are retained. `_main` remains exported for Java 25's JLI entry contract.

```sh
node Tests/rename-tests.mjs
node Tests/startup-overlay-tests.mjs
node Tests/control-footer-tests.mjs
zsh Tests/run-addon-tests.sh
```

After a clean Release build, inspect the actual embedded app, not the wrapper:

```sh
node Tests/rename-tests.mjs --app /tmp/PocketJ-v15-DerivedData/Build/Products/Release-iphoneos/PocketJLauncher.app
```

This checks new classes, absence of old package descriptors in all three
generated launcher/LWJGL JARs, 22 renderer exports, both pairs of JNI exports,
and `_main`. Hardware acceptance is separate: ancient Minecraft, 1.21.11,
26.2/26.3, loader installation, accounts, keyboard/gamepad and custom variables.
No install, public release, CI dispatch or push is authorized by this migration.

### Verified result — 2026-10-28

Clean Release build succeeded (`/tmp/pocketj-v15-rename-verified.log`). All 114
checked production/configuration inputs matched the staged build by SHA-256.
The actual app passed the JAR namespace and native/JNI export checks above,
including `_main`; its version is `1.5` and Bundle ID is unchanged.
Environment/alias/build-override tests, startup/control/add-on regressions,
localization lint, shell/YAML parsing and diff whitespace checks passed.
Device/game acceptance has not been performed; no installation or publishing
was done.
