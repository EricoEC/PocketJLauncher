#!/bin/zsh
set -euo pipefail

# Xcode launched from Finder does not inherit the interactive shell PATH.
# upstream Makefile requires these Homebrew-provided build tools.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SOURCE_ROOT="${SRCROOT}"
WORK_ROOT="/tmp/PocketJLauncher-XcodeBuild"
BOOT_JDK_CACHE="/tmp/PocketJLauncher-BootJDK8"
PRODUCT_APP="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
PAYLOAD_APP="${WORK_ROOT}/artifacts/Payload/PocketJLauncher.app"

mkdir -p "${WORK_ROOT}"
rsync -a --delete \
  --exclude ".git" \
  --exclude "artifacts" \
  --exclude "depends" \
  --exclude "Natives/build" \
  "${SOURCE_ROOT}/" "${WORK_ROOT}/"

# Natives/build is intentionally excluded from rsync because it is large.
# Remove the staged app explicitly so an old Assets.car or AppIcon PNG can
# never survive into a new install.
rm -rf "${WORK_ROOT}/Natives/build/PocketJLauncher.app"

BOOT_JDK=""
JAVA8_HOME=$(/usr/libexec/java_home -v 1.8 2>/dev/null || true)
CACHED_JAVA8=$(find "${BOOT_JDK_CACHE}" -path "*/Contents/Home/bin/javac" -print -quit 2>/dev/null || true)
if [[ -x "${JAVA8_HOME}/bin/javac" ]] &&
   "${JAVA8_HOME}/bin/javac" -version 2>&1 | /usr/bin/grep -q "javac 1.8"; then
  BOOT_JDK="${JAVA8_HOME}/bin"
elif [[ -n "${CACHED_JAVA8}" ]] &&
     "${CACHED_JAVA8}" -version 2>&1 | /usr/bin/grep -q "javac 1.8"; then
  BOOT_JDK="${CACHED_JAVA8%/javac}"
else
  mkdir -p "${BOOT_JDK_CACHE}"
  ARCHIVE="${BOOT_JDK_CACHE}/jdk8.tar.gz"
  curl -L --fail --retry 3 \
    "https://api.adoptium.net/v3/binary/latest/8/ga/mac/x64/jdk/hotspot/normal/eclipse" \
    -o "${ARCHIVE}"
  tar -xzf "${ARCHIVE}" -C "${BOOT_JDK_CACHE}"
  JDK_HOME=$(find "${BOOT_JDK_CACHE}" -path "*/Contents/Home/bin/javac" -print -quit)
  BOOT_JDK="${JDK_HOME%/javac}"
fi

cd "${WORK_ROOT}"
/opt/homebrew/bin/gmake payload \
  JOBS=8 \
  PLATFORM=2 \
  RELEASE=$([[ "${CONFIGURATION}" == "Release" ]] && echo 1 || echo 0) \
  BRANCH=main \
  COMMIT=local \
  BOOTJDK="${BOOT_JDK}" \
  VERBOSE=0

if [[ ! -x "${PAYLOAD_APP}/PocketJLauncher" ]]; then
  echo "error: PocketJ Launcher payload was not generated"
  exit 1
fi

rsync -a --delete \
  --exclude "_CodeSignature" \
  --exclude "embedded.mobileprovision" \
  "${PAYLOAD_APP}/" "${PRODUCT_APP}/"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${PRODUCT_BUNDLE_IDENTIFIER}" \
  "${PRODUCT_APP}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${EXECUTABLE_NAME}" \
  "${PRODUCT_APP}/Info.plist"

if [[ "${EXECUTABLE_NAME}" != "PocketJLauncher" ]]; then
  mv "${PRODUCT_APP}/PocketJLauncher" "${PRODUCT_APP}/${EXECUTABLE_NAME}"
fi

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
find "${PRODUCT_APP}" -type f | while IFS= read -r ITEM; do
  if file "${ITEM}" | /usr/bin/grep -q "Mach-O"; then
    /usr/bin/codesign --force --sign "${SIGN_IDENTITY}" \
      --timestamp=none "${ITEM}"
  fi
done

echo "PocketJ Launcher engine embedded into ${PRODUCT_APP}"
