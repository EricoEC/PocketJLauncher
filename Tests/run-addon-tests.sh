#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
TEST_BUILD="$(mktemp -d /tmp/pocketj-addon-tests.XXXXXX)"
trap 'rm -rf "$TEST_BUILD"' EXIT
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wno-deprecated-declarations \
  -framework Foundation -I Natives \
  Natives/PocketJEnvironment.c \
  Natives/PocketJModStore.m Natives/PocketJDownloadClient.m \
  Natives/PocketJAddonService.m Tests/AddonCoreTests.m \
  Natives/PocketJModSearchIndex.m Natives/PocketJCrashDiagnostics.m Natives/PocketJInstanceContext.m \
  Natives/authenticator/PocketJAccountIdentity.m \
  -o "$TEST_BUILD/addon-tests"
"$TEST_BUILD/addon-tests"
xcrun --sdk macosx clang -I Natives Natives/touchcontroller/PocketJTouchTransport.c \
  Tests/TouchTransportTests.c -o "$TEST_BUILD/touch-tests"
"$TEST_BUILD/touch-tests"
