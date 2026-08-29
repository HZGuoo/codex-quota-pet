#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_BUNDLE="$PROJECT_DIR/dist/Codex Quota Pet.app"
TASK_VERSION=$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")
DMG_PATH="$PROJECT_DIR/dist/CodexQuotaPet-$TASK_VERSION.dmg"

: "${APPLE_DEVELOPER_ID:?Set APPLE_DEVELOPER_ID to a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"

"$SCRIPT_DIR/build-app.sh"

codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$APPLE_DEVELOPER_ID" \
  "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

hdiutil create \
  -volname "Codex Quota Pet" \
  -srcfolder "$APP_BUNDLE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

echo "$DMG_PATH"
