#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_BUNDLE="$PROJECT_DIR/dist/Codex Quota Pet.app"
TASK_VERSION=$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")
ARCHIVE_NAME="CodexQuotaPet-$TASK_VERSION-macos-universal.zip"
ARCHIVE_PATH="$PROJECT_DIR/dist/$ARCHIVE_NAME"
UPLOAD_PATH="$PROJECT_DIR/dist/CodexQuotaPet-$TASK_VERSION-notarization-upload.zip"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

: "${APPLE_DEVELOPER_ID:?Set APPLE_DEVELOPER_ID to a Developer ID Application identity}"
: "${APPLE_API_KEY_ID:?Set APPLE_API_KEY_ID to an App Store Connect API key ID}"
: "${APPLE_API_ISSUER_ID:?Set APPLE_API_ISSUER_ID to an App Store Connect issuer ID}"
: "${APPLE_API_KEY_FILE:?Set APPLE_API_KEY_FILE to the AuthKey .p8 path}"

CODEX_SIGN_IDENTITY="$APPLE_DEVELOPER_ID" "$SCRIPT_DIR/build-app.sh"

rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH" "$UPLOAD_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$UPLOAD_PATH"

xcrun notarytool submit "$UPLOAD_PATH" \
  --key "$APPLE_API_KEY_FILE" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait

xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"
(
  cd "$PROJECT_DIR/dist"
  shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)
rm -f "$UPLOAD_PATH"

echo "$ARCHIVE_PATH"
echo "$CHECKSUM_PATH"
