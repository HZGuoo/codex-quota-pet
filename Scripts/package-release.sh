#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
TASK_VERSION=$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")
ARCHIVE_NAME="CodexQuotaPet-$TASK_VERSION-macos-universal.zip"
ARCHIVE_PATH="$PROJECT_DIR/dist/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

"$SCRIPT_DIR/build-app.sh"

rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$PROJECT_DIR/dist/Codex Quota Pet.app" \
  "$ARCHIVE_PATH"

(
  cd "$PROJECT_DIR/dist"
  shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)

echo "$ARCHIVE_PATH"
echo "$CHECKSUM_PATH"
