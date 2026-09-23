#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
UNIVERSAL_BUILD_ROOT="$PROJECT_DIR/.build/universal"
APP_BUNDLE="$PROJECT_DIR/dist/Codex Quota Pet.app"
VERSION_FILE="$PROJECT_DIR/VERSION"

TASK_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
if [[ ! $TASK_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid semantic version in $VERSION_FILE: $TASK_VERSION" >&2
  exit 1
fi

TASK_BUILD_NUMBER=${CODEX_QUOTA_BUILD_NUMBER:-}
if [[ -z "$TASK_BUILD_NUMBER" ]]; then
  TASK_BUILD_NUMBER=$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || true)
fi
if [[ ! $TASK_BUILD_NUMBER =~ ^[1-9][0-9]*$ ]]; then
  TASK_BUILD_NUMBER=1
fi

if [[ -n "${CODEX_QUOTA_SDKROOT:-}" ]]; then
  TASK_SDKROOT="$CODEX_QUOTA_SDKROOT"
elif [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  TASK_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
elif [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
  TASK_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
else
  TASK_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
fi
TASK_BUILD_SYSTEM=${CODEX_QUOTA_BUILD_SYSTEM:-native}

mkdir -p "$UNIVERSAL_BUILD_ROOT" "$PROJECT_DIR/dist"

ARCH_BINARIES=()
for TASK_ARCH in arm64 x86_64; do
  TASK_SCRATCH="$UNIVERSAL_BUILD_ROOT/$TASK_ARCH"
  TASK_MODULE_CACHE="$TASK_SCRATCH/module-cache"
  mkdir -p "$TASK_MODULE_CACHE"

  SDKROOT="$TASK_SDKROOT" \
  CLANG_MODULE_CACHE_PATH="$TASK_MODULE_CACHE" \
  SWIFTPM_MODULECACHE_OVERRIDE="$TASK_MODULE_CACHE" \
  swift build \
    --disable-sandbox \
    --build-system "$TASK_BUILD_SYSTEM" \
    --package-path "$PROJECT_DIR" \
    --scratch-path "$TASK_SCRATCH" \
    --triple "$TASK_ARCH-apple-macosx13.0" \
    -c release \
    --product CodexQuotaPet

  TASK_BIN_DIR=$(SDKROOT="$TASK_SDKROOT" \
    CLANG_MODULE_CACHE_PATH="$TASK_MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$TASK_MODULE_CACHE" \
    swift build \
      --disable-sandbox \
      --build-system "$TASK_BUILD_SYSTEM" \
      --package-path "$PROJECT_DIR" \
      --scratch-path "$TASK_SCRATCH" \
      --triple "$TASK_ARCH-apple-macosx13.0" \
      -c release \
      --show-bin-path)
  ARCH_BINARIES+=("$TASK_BIN_DIR/CodexQuotaPet")
done

if [[ -e "$APP_BUNDLE" ]]; then
  rm -rf "$APP_BUNDLE"
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
lipo -create "${ARCH_BINARIES[@]}" -output "$APP_BUNDLE/Contents/MacOS/CodexQuotaPet"
lipo "$APP_BUNDLE/Contents/MacOS/CodexQuotaPet" -verify_arch arm64
lipo "$APP_BUNDLE/Contents/MacOS/CodexQuotaPet" -verify_arch x86_64
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$TASK_VERSION" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$TASK_BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/MenuIconColor.png" "$APP_BUNDLE/Contents/Resources/MenuIconColor.png"

TASK_SIGN_IDENTITY=${CODEX_SIGN_IDENTITY:--}
if [[ "$TASK_SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$TASK_SIGN_IDENTITY" \
    "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

echo "$APP_BUNDLE"
