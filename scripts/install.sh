#!/bin/bash
# Build the Release app and install it to /Applications/OpenClip.app, replacing the running copy.
#
# One app, one bundle ID (com.olegy.openclip): settings, ~/.openclip and the Accessibility grant
# are shared with whatever was installed before, including copies updated by Sparkle. Signing
# follows scripts/signing_config.sh (OPENCLIP_SIGN_IDENTITY or the gitignored keys/signing.env;
# ad-hoc otherwise); sign with the same certificate as release.sh to keep the Accessibility grant.
# Pass --no-launch to skip starting the app. Logs: ~/Library/Logs/OpenClip/openclip.log.

set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

LAUNCH=true
for arg in "$@"; do
  case "$arg" in
    --no-launch) LAUNCH=false ;;
    --help|-h)
      printf 'Usage: ./scripts/install.sh [--no-launch]\n'
      exit 0
      ;;
  esac
done

OC_PROJECT_DIR="$PROJECT_DIR"
# shellcheck source=scripts/signing_config.sh
. "$PROJECT_DIR/scripts/signing_config.sh"

TARGET_APP="/Applications/OpenClip.app"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/OpenClip.app"

echo "Generating Xcode project..."
xcodegen generate >/dev/null

echo "Building OpenClip (Release)..."
LOG="$(mktemp "${TMPDIR:-/tmp}/openclip-build.XXXXXX")"
if ! xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED_DATA" build >"$LOG" 2>&1; then
  grep 'error:' "$LOG" | sort -u || true
  echo "Build failed; full output: $LOG" >&2
  exit 1
fi
rm -f "$LOG"

"$PROJECT_DIR/scripts/sign_artifact.sh" "$BUILT_APP"

echo "Installing to $TARGET_APP..."
pkill -x OpenClip 2>/dev/null || true
sleep 0.5
rm -rf "$TARGET_APP"
ditto "$BUILT_APP" "$TARGET_APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TARGET_APP/Contents/Info.plist")"
echo "Installed OpenClip $VERSION"

if [ "$LAUNCH" = true ]; then
  /usr/bin/open "$TARGET_APP"
fi
