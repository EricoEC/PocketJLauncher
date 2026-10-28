# PocketJ v1.5 implementation ledger

Baseline: copied v1.4 including the existing README changes; v1.4 is untouched.
Build inputs: prefer `../SharedDependencies/PocketJ`, retain download fallback.

## Accepted scope

- Native mod management: import/export, enable/disable, permanent deletion with confirmation, filename/alias/notes, single and batch operations, online version change/reinstall/update lock.
- Verified atomic downloads and source-aware metadata; Modrinth and CurseForge updates and dependency planning; Chinese search.
- Resource/world browsing and version selection, modpack import/export and launch-page download consistency.
- Third-party Yggdrasil accounts, opt-in TouchController, local crash diagnostics.
- Preserve iOS 14 support, current UI/navigation, JIT, Java/runtime and renderer compatibility. FSR/AI/plugins/virtual LAN excluded.
- No long-lived old-JAR backups: version rollback downloads that version again. Failed replacement keeps the original file.

## Implementation / evidence

- [x] Created v1.5 without generated build products; retained Git baseline and local README changes.
- [x] Export native `_main` for Java 25; final executable export gate added to the build script.
- [x] Mod store / safe file operations / stable identity / metadata and rollback on write failure.
- [x] Shared verified add-on download client: finite retry, candidate URLs, size/SHA/archive checks and resume data. Main game downloader is preserved, not fully migrated.
- [x] Native mod actions / import / export / local search / batch actions and update locking.
- [x] Provider identity, version history, update and bounded dependency planning with preview.
- [x] Resource/world and MR/CF/local modpack entry integration; portable export formats.
- [x] Third-party authentication implementation and account namespace isolation. Real sign-in still needs device acceptance.
- [x] Optional TouchController native/UDP implementation; fake-JNI tests pass, real mods still need acceptance.
- [x] Local crash hints; no automatic game-setting changes.
- [x] Bilingual strings / v1.5 metadata / documentation and shared Xcode scheme.
- [x] Foundation and C regression tests pass; live Modrinth/CurseForge catalog reads pass (20/19 compatible Sodium versions for MC 1.21.11 + Fabric).
- [x] Final clean Release build after the last source changes: `BUILD SUCCEEDED` on 2026-10-28; log `/tmp/pocketj-v15-build-verified.log`.

Final artifact checks: app and Helper version `1.5`, Bundle ID
`com.Erico.PocketJLauncher`, native `_main` exported, and
`@rpath/libproxy_server_ios.dylib` linked and embedded. The 52 changed/new
production source/configuration files matched the staged build inputs by SHA-256.
The regression harness was rerun after the build and passed; both localization
files pass `plutil -lint`, and `git diff --check` is clean. No phone install or
game execution was performed. The source v1.4 still has only its pre-existing
README modification.

Device/game acceptance remains separate from build success. This ledger must not mark
unimplemented items as delivered. No public release/upload until acceptance.

## Control-page overlap repair (2026-10-28, scheduled 14:00)

- Root cause: in gamepad mode, hidden touch section 0 still returned its long
  footer text despite a height of 0.01, allowing UIKit to draw it over the mode
  selector. Hidden sections now return nil; actual/estimated heights derive
  from the same footer content.
- The native mode selector header refits its width/height on layout and text
  size changes, without repeatedly resetting unchanged font attributes or
  reloading the table. Mode switches end editing and reset to the adjusted
  scroll top; row titles allow wrapping. Existing localization and game input
  behavior are unchanged. No renderer/JRE/dependency version was changed.
- `node Tests/control-footer-tests.mjs` executes the production footer methods
  across repeated switches and passes. Existing add-on/JNI tests, localization
  lint and diff whitespace checks also pass.
- Final clean Release build: `BUILD SUCCEEDED`, log
  `/tmp/pocketj-v15-controls-final-build.log`; staged controller source hash
  matches the working source. No phone install, UIKit visual acceptance,
  public release or push was performed.

## Vision v0.2 first-frame startup layer (2026-10-28)

- Inspected `VisionPro-PJL/v0.2/Sources/UI/GameWindow.swift`,
  `Sources/Diagnostics/GameLaunchLog.swift` and the native stage transitions
  before implementing the iOS counterpart. Vision sources remain unchanged.
- Ported the same black centered layout: spinner, white stage description,
  monospaced elapsed timer, live-log action and session-log export; spacing 12
  and outer padding 24. All shared Chinese/English stage and action strings
  are byte-for-byte equal. UIKit is used to retain iOS 14 support; system button
  material varies by OS. No pixel-identical rendering claim without hardware
  comparison; scrolling is only a fallback for insufficient accessible height.
- Real events report runtime loading, JVM entry, JNI setup and renderer setup.
  OpenGL swap success, software-image assignment and a Metal drawable presented
  callback (including SDL/Vulkan) report the first frame. A session token rejects
  callbacks from older launches; success removes the waiting layer. Exit/error
  stops the spinner. Software rendering does not misleadingly say Metal.
- Existing log UI is reused; user-opened startup logs initially read a bounded
  64-KiB tail, then enable live output. Export shares the current log file with
  an anchored iPad share sheet. JIT/runtime/renderer selection is unchanged.
- `node Tests/startup-overlay-tests.mjs` passed live Vision/iOS source-contract
  comparisons and C state/concurrency tests. Existing add-on/JNI tests and the
  control-footer regression also passed. Localization lint / diff checks pass.
- Final clean Release build: `BUILD SUCCEEDED`, log
  `/tmp/pocketj-v15-startup-final-build.log`; final staged overlay/log sources
  match current source hashes. Device/GPU/visual acceptance was not run; no
  phone install, release or push was performed.

## Pojav to PocketJ namespace migration (2026-10-28)

- Migrated all 23 launcher Java sources to `com.erico.pocketj`, renamed the
  launcher/classloader classes, and updated JVM arguments, GLFW symbol lookups
  and JNI implementations together. The 11 native renderer entry points use
  PocketJ names; historical exports are typed forwarding aliases only.
- Centralized six environment aliases in `PocketJEnvironment`, preserving old
  input and mirroring values for prebuilt dependencies. Explicit canonical
  input wins in either order; absent optional values remain absent. The old
  Forge property and five build overrides remain fallback inputs.
- Updated bilingual JVM startup branding, artifact rules and version-local
  namespace invalidation. Xcode GUI and CLI retain the same build runner.
  Bundle ID, account/keychain data, instance paths, shared dependencies,
  upstream attribution and Vision sources are unchanged by this migration.
- Final clean Release build: `BUILD SUCCEEDED`, log
  `/tmp/pocketj-v15-rename-verified.log`. All 114 changed/new production and
  configuration files checked against staged inputs matched by SHA-256.
- `node Tests/rename-tests.mjs --app
  /tmp/PocketJ-v15-DerivedData/Build/Products/Release-iphoneos/PocketJLauncher.app`
  passed: actual launcher/LWJGL JAR namespaces, `_main`, 22 renderer exports
  and four JNI exports. The environment, typed alias and Makefile precedence
  tests passed, as did startup/control regressions and add-on/JNI tests.
  Localization, shell/YAML syntax and diff whitespace checks passed.
- Final app metadata remains version `1.5`, ID `com.Erico.PocketJLauncher`.
  Remaining legacy spellings are documented in `RENAME_v1.5.md`; no binary
  string patching, dependency upgrade, phone install, runtime acceptance,
  release, CI dispatch or push was performed.

## Live-log close repair (2026-10-28)

- Removed root-view frame animation/visibility inference from the log toggle.
  The navigation controller can reset that frame during layout, making the old
  completion handler show a window the user had closed. Visibility now changes
  synchronously on the container; opening fades in without stale completions.
- Startup regression checks cover the frame-independent close contract. No
  game, renderer, log capture or fatal-error exit behavior is changed.
- Release build and startup regressions passed. At the user's subsequent
  request, a signed Release build also succeeded and was installed over the
  existing app on the connected iPhone 16 Pro Max (`00008140-00044C592213001C`).
  Device build log: `/tmp/pocketj-v15-log-close-device-build.log`. Interactive
  close/reopen acceptance remains for the user; no public release or push.

## Minecraft 26.3 SDL startup overlay repair (2026-10-28)

- The supplied log reaches SDL window creation, a MoltenVK swapchain and Metal
  shader compilation, with no terminal Java exception. Realms connection-reset
  errors do not establish a renderer failure. A separate missing legacy input
  diagnostic symbol is not treated as proof of the freeze's cause.
- Found a concrete first-frame observation gap: SDL3 owns an independent
  `SDL_uikitmetalview` with its own CAMetalLayer, so the original GameSurfaceView
  subclass observer cannot see its presentation. Observe `nextDrawable` for
  SDL-owned layers and attach the same session-protected presented handler.
  The drawable is returned unchanged; no timeout pretends a frame was shown.
  GLFW/ANGLE retain their existing observer and render/input paths.
- Added a deterministic Objective-C harness executing the production observer
  against fake drawables/layers: first presentation, no premature dismissal,
  stale sessions, unrelated layers and repeated installation are covered.
  Real Metal/device acceptance remains separate from these model tests.
- Startup/model tests and whitespace checks passed. Signed Release build
  succeeded (`/tmp/pocketj-v15-sdl-startup-build.log`), and devicectl confirmed
  installation on the connected iPhone 16 Pro Max. GameSurfaceView source and
  staged input SHA-256 matched. No game session was run by the agent; whether
  the observed freeze is fully resolved still requires the user's 26.3 test.

## Minecraft 26.3 SDL camera rollback repair (2026-10-28)

- Root cause: the SDL mouse branch treated every input as an absolute point.
  Touch look and controller/mouse `ACTION_MOVE_MOTION` already carry deltas;
  subtracting consecutive deltas telescoped away accumulated movement and
  generated reverse motion when slowing down or repositioning a finger.
- SDL relative events now forward each delta unchanged and accumulate cursor
  coordinates. Absolute gestures keep an independent anchor; finger down/up
  while grabbed reanchor without rotating the camera. Menu absolute motion
  remains absolute. The GLFW branch is unchanged.
- `node Tests/sdl-mouse-tests.mjs` compiles and executes the actual production
  SDL branch with a mock event sink: 1000 rapid moves, direction reversal,
  finger reanchor and menu coordinates pass. Startup regressions also pass.
- Signed Release build succeeded (`/tmp/pocketj-v15-sdl-mouse-build.log`) and
  devicectl confirmed overlay installation on the connected iPhone 16 Pro Max.
  The staged input bridge matches the source SHA-256. Rapid camera movement
  on hardware remains for user acceptance; no publishing or push performed.

## Minecraft 26.3 SDL input registration/state repair (2026-10-28)

- New log contains a concrete `VK_ERROR_DEVICE_LOST` after Metal reports
  `BackgroundExecutionNotPermitted`. This proves a background GPU failure, not
  the cause of earlier menu non-responsiveness; the two are not conflated.
- Found the SDL binary's missing `Amethyst_SetSDLWindow` host callback and no
  synchronization of SDL relative mouse mode into the launcher's grab state.
  Added canonical `PocketJRegisterSDLWindow` plus the required thin binary
  callback alias. Registered window IDs are cached, avoiding enumeration and
  allocation for every touch. No third-party SDL binary was changed.
- Poll relative mouse mode on the UIKit main thread at 30 Hz and immediately
  before touch coordinate conversion. This keeps menu/game state, gestures
  and cursor visibility aligned even though SDL does not call the GLFW/JNI
  grab setter. Old GLFW input and pre-SDL launches return without loading SDL.
  The timer and registered pointer are cleared on controller teardown.
- `sdl-registration-tests.mjs` executes the actual registration/query/state
  implementation with fake SDL functions: binary callback, 10000 cached ID
  lookups, enter/leave game, idempotence, GLFW exclusion and teardown pass.
  Mouse-delta and startup regression suites also pass. Real menu responsiveness
  and background Vulkan device-loss recovery are not claimed verified.
- Signed Release build succeeded (`/tmp/pocketj-v15-sdl-registration-build.log`)
  and devicectl confirmed installation on the connected iPhone 16 Pro Max.
  Final native exports contain the binary callback, both canonical functions
  and `_main`. No public release or push was performed.

## Update detection and prompt policy (2026-10-28)

- Compared v1.4 with the pre-change v1.5 checker: identical `/releases/latest`
  path. Retained the repository/cache state contract, replacing latest-only
  selection with paged stable numeric launcher filtering. Pairing-tool,
  prerelease and draft releases cannot become launcher update candidates.
- Added a shared native three-action dialog and the requested fixed GitHub /
  123 Cloud Drive source selector. Three-hour deferral and per-version skip
  persist; manual checks bypass both. Automatic failed checks preserve cached
  state silently; manual failure/current/update results provide feedback.
- Foreground checks, offline cached prompts and modal presentation are routed
  through the launcher; no automatic alert appears over a detached game UI.
  Chinese/English copy and iPad anchoring are included.
- `node Tests/update-tests.mjs --live` passed policy/network/cache tests and
  source/UI contracts. The actual unauthenticated API selected launcher v1.4,
  not pairing-tool-v1.0. Localization lint and whitespace checks passed.
  See `UPDATE_v1.5.md` for the existing-v1.4 Latest requirement and acceptance
  limits. No claim that the last 26.3 freeze or UI interactions are verified.
- Final clean signed Release build passed at
  `/tmp/PocketJ-v15-DerivedData/Build/Products/Release-iphoneos/PocketJLauncher.app`;
  `codesign --verify --deep --strict` passed. The built staging copies of the
  update checker, prompt coordinator and root controller match the working
  sources. The first device transfer timed out at 120 seconds; retrying with
  verbose logging and a 300-second timeout completed in 4.9 seconds. `devicectl`
  confirmed installation of `com.Erico.PocketJLauncher` on the connected iPhone
  16 Pro Max.

## Deferred rather than claimed complete

- A full main-game transport migration and user-facing mirror policy. Existing
  launch/offline/integrity behavior is retained; modpacks share the launch-page UI.
- A fully general JAR dependency constraint solver. Current planning honors
  provider exact version IDs, loader/MC compatibility, required/optional edges,
  cycle/conflict limits and installed-version checks.
- A comprehensive external Chinese database. The bundled index is small and
  extensible by user CSV, with no unlicensed dataset copied in.
- Hardware acceptance, real third-party login and actual TouchController mod ABI
  execution. See V1.5_TESTING.md; this is not yet a public release.

## Release packaging (2026-10-28)

- Built the signed Release app for `com.Erico.PocketJLauncher` version `1.5`.
- Packaged `PocketJLauncher-v1.5-iOS.ipa` and
  `PocketJLauncher-v1.5-iOS-TrollStore.tipa` under
  `../ReleaseArchive/PocketJ/v1.5/v1.5/`, with `SHA256SUMS.txt`.
- Both archives passed ZIP integrity and SHA-256 checks. The packages omit
  embedded provisioning profiles and personal device UDIDs; IPA and TrollStore
  entitlements were applied separately.
- Device installation succeeded on the connected iPhone 16 Pro Max. The 26.3
  menu interaction and update-dialog behavior remain pending user acceptance;
  no public release or push was performed.
