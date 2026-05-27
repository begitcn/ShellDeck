#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================
# Configuration
# ============================================================
PROJECT_NAME="ShellDeck"
SCHEME="ShellDeck"
APP_VERSION="${APP_VERSION:-$(cat "$SCRIPT_DIR/VERSION")}"
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_DIR="$SCRIPT_DIR/build"
ARCHIVE_PATH="$DIST_DIR/$PROJECT_NAME.xcarchive"

# ============================================================
# Helpers
# ============================================================
usage() {
    echo "Usage: $0 [--help]"
    echo ""
    echo "Builds $PROJECT_NAME and produces a DMG in $DIST_DIR"
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --help) usage ;;
    esac
done

# ============================================================
# Step 1: Build Archive
# ============================================================
echo "==> $PROJECT_NAME Build v$APP_VERSION"
echo ""

echo "Building archive..."
rm -rf "$ARCHIVE_PATH" "$BUILD_DIR"

xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    MARKETING_VERSION="$APP_VERSION" \
    CURRENT_PROJECT_VERSION="1" \
    ${MACOSX_DEPLOYMENT_TARGET:+MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET} \
    ${CODE_SIGN_IDENTITY:+CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY} \
    ${CODE_SIGNING_REQUIRED:+CODE_SIGNING_REQUIRED=$CODE_SIGNING_REQUIRED} \
    ${CODE_SIGNING_ALLOWED:+CODE_SIGNING_ALLOWED=$CODE_SIGNING_ALLOWED}

echo "   Archive built at $ARCHIVE_PATH"

# ============================================================
# Step 2: Export App Bundle
# ============================================================
echo ""
echo "Exporting app bundle..."

EXPORT_DIR="$DIST_DIR/.export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
    # CI build: skip signing entirely, export as raw app
    xcodebuild \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist /dev/stdin <<< '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingDisabled</key>
    <true/>
</dict>
</plist>'
else
    xcodebuild \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist /dev/stdin <<< '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>'
fi

# Find the exported .app
APP_BUNDLE=$(find "$EXPORT_DIR" -name "*.app" -maxdepth 1 -type d | head -1)
if [ -z "$APP_BUNDLE" ]; then
    echo "Error: exported .app not found"
    exit 1
fi

echo "   Exported: $APP_BUNDLE"

# ============================================================
# Step 3: Create DMG
# ============================================================
echo ""
echo "Creating DMG..."

mkdir -p "$DIST_DIR"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH_NAME="x86_64" ;;
    arm64)  ARCH_NAME="aarch64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

DMG_NAME="${PROJECT_NAME}-${ARCH_NAME}-v${APP_VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TEMP_DMG="$DIST_DIR/.tmp-${DMG_NAME}"

rm -f "$TEMP_DMG" "$DMG_PATH"

DMG_CONTENTS="$DIST_DIR/.dmg-contents"
rm -rf "$DMG_CONTENTS"
mkdir -p "$DMG_CONTENTS"
cp -R "$APP_BUNDLE" "$DMG_CONTENTS/"
ln -s /Applications "$DMG_CONTENTS/Applications"

hdiutil create \
    -volname "$PROJECT_NAME" \
    -srcfolder "$DMG_CONTENTS" \
    -ov \
    -format UDZO \
    "$TEMP_DMG"

mv "$TEMP_DMG" "$DMG_PATH"
rm -rf "$DMG_CONTENTS"

echo "   DMG created: $DMG_PATH"

# ============================================================
# Step 4: Cleanup
# ============================================================
rm -rf "$EXPORT_DIR" "$ARCHIVE_PATH"

echo ""
echo "Done!"
