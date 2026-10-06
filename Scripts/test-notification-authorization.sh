#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
TASK_SCRATCH="$PROJECT_DIR/.build/notification-authorization-tests"
TASK_BUNDLE="$TASK_SCRATCH/NotificationAuthorizationTests.app"
TASK_SDKROOT=${CODEX_QUOTA_SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}
TASK_BUILD_SYSTEM=${CODEX_QUOTA_BUILD_SYSTEM:-native}
export SDKROOT="$TASK_SDKROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_SCRATCH/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_SCRATCH/module-cache"

swift build --disable-sandbox --build-system "$TASK_BUILD_SYSTEM" \
  --package-path "$PROJECT_DIR" --scratch-path "$TASK_SCRATCH" \
  --product CodexQuotaPetSelfTests
TASK_BIN_DIR=$(swift build --disable-sandbox --build-system "$TASK_BUILD_SYSTEM" \
  --package-path "$PROJECT_DIR" --scratch-path "$TASK_SCRATCH" --show-bin-path)

# Use a separate test bundle so UNUserNotificationCenter has a valid identity.
# The test replaces authorization before any request; no OS permission changes.
mkdir -p "$TASK_BUNDLE/Contents/MacOS"
cp "$PROJECT_DIR/Resources/Info.plist" "$TASK_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string io.github.HZGuoo.NotificationAuthorizationTests "$TASK_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleExecutable -string NotificationAuthorizationTests "$TASK_BUNDLE/Contents/Info.plist"

swiftc -swift-version 6 -parse-as-library -O -sdk "$TASK_SDKROOT" \
  -I "$TASK_BIN_DIR/Modules" \
  "$SCRIPT_DIR/NotificationAuthorizationTests.swift" \
  "$PROJECT_DIR/Sources/CodexQuotaPet/TaskNotificationService.swift" \
  "$TASK_BIN_DIR/CodexQuotaPetCore.build/"*.swift.o \
  -o "$TASK_BUNDLE/Contents/MacOS/NotificationAuthorizationTests"
"$TASK_BUNDLE/Contents/MacOS/NotificationAuthorizationTests"
