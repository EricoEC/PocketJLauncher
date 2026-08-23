#!/bin/zsh
set -euo pipefail

# Xcode launched from Finder does not inherit the interactive shell PATH.
# upstream Makefile requires these Homebrew-provided build tools.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SOURCE_ROOT="${SRCROOT}"
WORK_ROOT="/tmp/PocketJLauncher-XcodeBuild"
SOURCE_PARENT="${SOURCE_ROOT%/*}"
SHARED_DEPENDENCIES="${POCKETJ_SHARED_DEPENDENCIES:-${SOURCE_PARENT}/SharedDependencies/PocketJ}"
BOOT_JDK_CACHE="${SHARED_DEPENDENCIES}/BootJDK8"
RUNTIME_CACHE="${SHARED_DEPENDENCIES}/Runtimes"
CUSTOM_JDK8="${POCKETJ_BOOT_JDK8:-}"
PRODUCT_APP="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
PAYLOAD_APP="${WORK_ROOT}/artifacts/Payload/PocketJLauncher.app"
COORDINATOR_FRAMEWORK="${BUILT_PRODUCTS_DIR}/PocketJJITCoordinator.framework"
JIT_HELPER="${BUILT_PRODUCTS_DIR}/PocketJJITHelper.appex"

mkdir -p "${WORK_ROOT}" "${SHARED_DEPENDENCIES}" "${RUNTIME_CACHE}"
rsync -a --delete \
  --exclude ".git" \
  --exclude "artifacts" \
  --exclude "depends" \
  --exclude "JavaApp/build" \
  --exclude "Natives/build" \
  "${SOURCE_ROOT}/" "${WORK_ROOT}/"

# Downloaded Minecraft runtimes are version-independent build inputs. Keep
# them beside all launcher versions so copied v1.x folders reuse one cache.
rm -rf "${WORK_ROOT}/depends"
ln -s "${RUNTIME_CACHE}" "${WORK_ROOT}/depends"

# Natives/build is intentionally excluded from rsync because it is large.
# Remove the staged app explicitly so an old Assets.car or AppIcon PNG can
# never survive into a new install.
rm -rf "${WORK_ROOT}/Natives/build/PocketJLauncher.app"

BOOT_JDK=""
JAVA8_HOME=$(/usr/libexec/java_home -v 1.8 2>/dev/null || true)
if [[ -x "${JAVA8_HOME}/bin/javac" ]] &&
   "${JAVA8_HOME}/bin/javac" -version 2>&1 | /usr/bin/grep -q "javac 1.8"; then
  BOOT_JDK="${JAVA8_HOME}/bin"
elif [[ -n "${CUSTOM_JDK8}" && -x "${CUSTOM_JDK8}/bin/javac" ]]; then
  BOOT_JDK="${CUSTOM_JDK8}/bin"
elif [[ -x "${BOOT_JDK_CACHE}/Contents/Home/bin/javac" ]]; then
  BOOT_JDK="${BOOT_JDK_CACHE}/Contents/Home/bin"
else
  mkdir -p "${BOOT_JDK_CACHE}"
  ARCHIVE="${BOOT_JDK_CACHE}/jdk8.tar.gz"
  curl -L --fail --retry 3 \
    "https://api.adoptium.net/v3/binary/latest/8/ga/mac/x64/jdk/hotspot/normal/eclipse" \
    -o "${ARCHIVE}"
  tar -xzf "${ARCHIVE}" -C "${BOOT_JDK_CACHE}"
  rm -f "${ARCHIVE}"
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

# The Swift compiler generates the host extension-point definition directly
# in the wrapper's Extensions directory. Preserve it while the native payload
# replaces that wrapper; without it ExtensionFoundation reports
# "Failed to add observer".
APPEXT_BACKUP="${WORK_ROOT}/host-extension-points"
rm -rf "${APPEXT_BACKUP}"
mkdir -p "${APPEXT_BACKUP}"
find "${PRODUCT_APP}/Extensions" -maxdepth 1 -type f -name "*.appexpt" \
  -exec cp -p {} "${APPEXT_BACKUP}/" \; 2>/dev/null || true

rsync -a --delete \
  --exclude "_CodeSignature" \
  --exclude "embedded.mobileprovision" \
  "${PAYLOAD_APP}/" "${PRODUCT_APP}/"

mkdir -p "${PRODUCT_APP}/Extensions"
if find "${APPEXT_BACKUP}" -maxdepth 1 -type f -name "*.appexpt" -print -quit | /usr/bin/grep -q .; then
  cp -p "${APPEXT_BACKUP}"/*.appexpt "${PRODUCT_APP}/Extensions/"
else
  echo "error: host extension-point definition (.appexpt) was not generated"
  exit 1
fi

# Restore Xcode-built helper products after the native payload replaces the
# wrapper. Generic ExtensionFoundation extensions live in Extensions/.
mkdir -p "${PRODUCT_APP}/Frameworks" "${PRODUCT_APP}/Extensions"
rsync -a --delete "${COORDINATOR_FRAMEWORK}/" \
  "${PRODUCT_APP}/Frameworks/PocketJJITCoordinator.framework/"
rsync -a --delete "${JIT_HELPER}/" \
  "${PRODUCT_APP}/Extensions/PocketJJITHelper.appex/"

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

# Re-seal nested bundles after their Mach-O files have been signed.
/usr/bin/codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none \
  "${PRODUCT_APP}/Frameworks/PocketJJITCoordinator.framework"
if [[ -d "${PRODUCT_APP}/Extensions/PocketJJITHelper.appex/Frameworks/StikJIT.framework" ]]; then
  /usr/bin/codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none \
    "${PRODUCT_APP}/Extensions/PocketJJITHelper.appex/Frameworks/StikJIT.framework"
fi
/usr/bin/codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none \
  "${PRODUCT_APP}/Extensions/PocketJJITHelper.appex"

echo "PocketJ Launcher engine embedded into ${PRODUCT_APP}"
