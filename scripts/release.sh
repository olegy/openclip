#!/bin/bash
# Publish an OpenClip Lite update: build a universal Release app, sign it with the Apple
# Development certificate from keys/signing.env, sign the zip with the Sparkle key in the login
# Keychain, and attach the zip and appcast.xml to a GitHub Release v<version>. Installed copies
# read the appcast at SUFeedURL (…/releases/latest/download/appcast.xml) and update themselves.
#
# The builds are not notarized: a Mac that installs one by hand runs
#   xattr -dr com.apple.quarantine /Applications/OpenClip.app
# once; Sparkle updates after that need nothing.
#
# Usage:
#   ./scripts/release.sh                     build and publish (tree clean, HEAD pushed, new version)
#   ./scripts/release.sh --no-upload         build into build/release only
#   ./scripts/release.sh export-key <dir>    back up the Sparkle private key into <dir>
#
# Each release needs a new version (bump OPENCLIP_LITE_REVISION in project.yml) and a
# `## <version>` section in CHANGELOG.md: it becomes the release notes on GitHub and in the update
# window.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SPARKLE_ACCOUNT="openclip-lite"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
OUT_DIR="$PROJECT_DIR/build/release"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/OpenClip.app"
SPARKLE_BIN="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"

fail() { echo "error: $*" >&2; exit 1; }

sparkle_bin() {
    if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
        echo "Resolving Swift packages to obtain the Sparkle tools..." >&2
        xcodegen generate >/dev/null
        xcodebuild -resolvePackageDependencies -project OpenClip.xcodeproj \
            -derivedDataPath "$DERIVED_DATA" >/dev/null
    fi
    [ -x "$SPARKLE_BIN/sign_update" ] || fail "Sparkle tools not found under $SPARKLE_BIN"
    printf '%s\n' "$SPARKLE_BIN"
}

if [ "${1:-}" = "export-key" ]; then
    DEST="${2:-}"
    [ -n "$DEST" ] || fail "usage: $0 export-key <dir>"
    mkdir -p "$DEST"
    KEY_FILE="$DEST/openclip-lite-sparkle-private-key"
    [ ! -e "$KEY_FILE" ] || fail "$KEY_FILE already exists"
    "$(sparkle_bin)/generate_keys" --account "$SPARKLE_ACCOUNT" -x "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "Saved the Sparkle private key to $KEY_FILE."
    echo "Restore on another Mac: generate_keys --account $SPARKLE_ACCOUNT -f <file>"
    exit 0
fi

UPLOAD=true
for arg in "$@"; do
    case "$arg" in
        --no-upload) UPLOAD=false ;;
        --help|-h) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) fail "unknown argument: $arg" ;;
    esac
done

command -v xcodegen >/dev/null || fail "xcodegen is not installed (brew install xcodegen)"
if [ "$UPLOAD" = true ]; then
    command -v gh >/dev/null || fail "gh is not installed (brew install gh)"
    [ -z "$(git status --porcelain)" ] || fail "the working tree is not clean; every release must match a commit"
fi

# Signing: a certificate with a Team ID, so the app is hardened and keeps one designated
# requirement across releases (the Accessibility grant and Sparkle's update check both rely on it).
OC_PROJECT_DIR="$PROJECT_DIR"
# shellcheck source=scripts/signing_config.sh
. "$PROJECT_DIR/scripts/signing_config.sh"
oc_load_signing_env
IDENTITY="$(oc_resolve_identity "")"
TEAM_ID="$(oc_team_from_identity "$IDENTITY")"
[ -n "$TEAM_ID" ] || fail "\"$IDENTITY\" has no Team ID; set OPENCLIP_SIGN_IDENTITY in keys/signing.env to your Apple Development certificate"

# The key in the Keychain must be the one the app trusts, or no installed copy accepts the update.
BIN="$(sparkle_bin)"
KEYCHAIN_KEY="$("$BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null)" \
    || fail "no Sparkle key \"$SPARKLE_ACCOUNT\" in the login Keychain (restore it with generate_keys -f)"
APP_KEY="$(sed -n 's/^ *SUPublicEDKey: *//p' project.yml)"
[ "$KEYCHAIN_KEY" = "$APP_KEY" ] || fail "SUPublicEDKey in project.yml does not match the Keychain key \"$SPARKLE_ACCOUNT\""

FEED_URL="$(sed -n 's/^ *SUFeedURL: *//p' project.yml)"
REPO="$(printf '%s\n' "$FEED_URL" | sed -n 's#^https://github.com/\([^/]*/[^/]*\)/releases/latest/download/appcast.xml$#\1#p')"
[ -n "$REPO" ] || fail "SUFeedURL is not a GitHub latest-release appcast URL: $FEED_URL"

echo "Generating Xcode project..."
xcodegen generate >/dev/null

echo "Building OpenClip (Release, universal)..."
LOG="$(mktemp "${TMPDIR:-/tmp}/openclip-release.XXXXXX")"
if ! xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -configuration Release \
    -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES CLANG_ENABLE_CODE_COVERAGE=NO \
    -derivedDataPath "$DERIVED_DATA" build >"$LOG" 2>&1; then
    grep 'error:' "$LOG" | sort -u || true
    fail "build failed; full output: $LOG"
fi
rm -f "$LOG"

"$PROJECT_DIR/scripts/sign_artifact.sh" "$BUILT_APP"
"$PROJECT_DIR/scripts/verify_universal.sh" "$BUILT_APP" "OpenClip.app"
"$PROJECT_DIR/scripts/verify_signing.sh" "$BUILT_APP" --require any

PLIST="$BUILT_APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
TAG="v$VERSION"

# The version's CHANGELOG.md section: everything under `## <version>` up to the next `## `.
NOTES="$(awk -v heading="## $VERSION" '
    $0 == heading { found = 1; next }
    found && /^## / { exit }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"
[ -n "$NOTES" ] || fail "CHANGELOG.md has no \"## $VERSION\" section; describe this release there first"

if [ "$UPLOAD" = true ]; then
    git fetch --quiet --tags origin
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
        && fail "$TAG is already released; bump OPENCLIP_LITE_REVISION in project.yml"
    COMMIT="$(git rev-parse HEAD)"
    git merge-base --is-ancestor "$COMMIT" origin/main \
        || fail "HEAD is not on origin/main; push it before releasing"
fi

mkdir -p "$OUT_DIR"
ZIP_NAME="OpenClip-$VERSION.zip"
ZIP="$OUT_DIR/$ZIP_NAME"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$BUILT_APP" "$ZIP"

# sign_update prints `sparkle:edSignature="…" length="…"`, the enclosure's attributes as-is.
SIGNATURE="$("$BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$ZIP")"
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$PLIST")"
cat >"$OUT_DIR/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>OpenClip Lite</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM</sparkle:minimumSystemVersion>
      <description sparkle:format="plain-text"><![CDATA[$NOTES]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$ZIP_NAME" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML

echo "Built $VERSION (build $BUILD, team $TEAM_ID):"
echo "  $ZIP"
echo "  $OUT_DIR/appcast.xml"

if [ "$UPLOAD" = false ]; then
    echo "Not uploaded (--no-upload)."
    exit 0
fi

echo "Publishing $TAG to $REPO..."
gh release create "$TAG" "$ZIP" "$OUT_DIR/appcast.xml" \
    --repo "$REPO" --target "$COMMIT" --title "OpenClip Lite $VERSION" \
    --notes "$NOTES"
git fetch --quiet --tags origin
echo "Released $TAG. Installed copies pick it up from $FEED_URL."
