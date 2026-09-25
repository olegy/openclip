#!/bin/bash
# Fast local development build & run (No installation to /Applications required)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "⚡️ Building Debug build..."
xcodegen
xcodebuild -scheme OpenClip -configuration Debug -destination 'platform=macOS,arch=arm64' build > /dev/null

# Ask Xcode where it just built, rather than globbing DerivedData: several OpenClip-*
# folders can exist (the hash changes with the project path) and picking the wrong one
# silently launches a stale binary.
BUILT_PRODUCTS_DIR="$(xcodebuild -scheme OpenClip -configuration Debug -destination 'platform=macOS,arch=arm64' -showBuildSettings 2>/dev/null | awk -F' = ' '/[[:space:]]BUILT_PRODUCTS_DIR = /{print $2; exit}')"
APP_PATH="$BUILT_PRODUCTS_DIR/OpenClip.app"

if [ ! -d "$APP_PATH" ]; then
  # Fall back to the most recently built bundle.
  APP_PATH="$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/OpenClip-"*/Build/Products/Debug/OpenClip.app 2>/dev/null | head -n 1)"
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "Error: Could not find built OpenClip.app in DerivedData"
  exit 1
fi

# Re-sign with the configured identity (OPENCLIP_SIGN_IDENTITY or keys/signing.env). With a local
# self-signed certificate the designated requirement no longer changes with every build, so the
# Accessibility grant survives rebuilds. Without one the build stays ad-hoc, as Xcode left it.
OC_PROJECT_DIR="$PROJECT_DIR"
# shellcheck source=scripts/signing_config.sh
. "$PROJECT_DIR/scripts/signing_config.sh"
oc_load_signing_env
SIGN_IDENTITY="$(oc_resolve_identity "")"
if ! oc_is_adhoc "$SIGN_IDENTITY"; then
  if ! SIGN_LOG="$("$PROJECT_DIR/scripts/sign_artifact.sh" "$APP_PATH" 2>&1)"; then
    echo "$SIGN_LOG" >&2
    exit 1
  fi
  echo "Signed with: $SIGN_IDENTITY"
fi

echo "Terminating old instances & launching from DerivedData..."
pkill -f OpenClip || true
sleep 0.3
/usr/bin/python3 -c "import subprocess, sys; subprocess.Popen([sys.argv[1]], stdout=open('/tmp/openclip.log', 'a'), stderr=subprocess.STDOUT, start_new_session=True)" "$APP_PATH/Contents/MacOS/OpenClip"

echo "Running directly from: $APP_PATH (logs at /tmp/openclip.log)"


