#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PACKAGE="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVICE_PACKAGE="$(cd "$APP_PACKAGE/../cofoco-service" && pwd)"
BUILD_ROOT="$APP_PACKAGE/.build/local-bundles"
mkdir -p "$BUILD_ROOT"
RUN_DIR="$(mktemp -d "$BUILD_ROOT/run.XXXXXX")"
APP_BUNDLE="$RUN_DIR/Cofoco.app"
CONTENTS="$APP_BUNDLE/Contents"
CONFIGURATION="${COFOCO_BUILD_CONFIGURATION:-release}"
case "$CONFIGURATION" in debug|release) ;; *) exit 64 ;; esac
APP_SCRATCH="${COFOCO_APP_SCRATCH:-$APP_PACKAGE/.build}"
SERVICE_SCRATCH="${COFOCO_SERVICE_SCRATCH:-$SERVICE_PACKAGE/.build}"

swift build --disable-sandbox --package-path "$SERVICE_PACKAGE" --scratch-path "$SERVICE_SCRATCH" --configuration "$CONFIGURATION"
swift build --disable-sandbox --package-path "$APP_PACKAGE" --scratch-path "$APP_SCRATCH" --configuration "$CONFIGURATION"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers"
cp "$APP_SCRATCH/$CONFIGURATION/Cofoco" "$CONTENTS/MacOS/Cofoco"
cp "$SERVICE_SCRATCH/$CONFIGURATION/cofoco-service" "$CONTENTS/Helpers/cofoco-service"

PLIST="$CONTENTS/Info.plist"
plutil -create xml1 "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Cofoco' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Cofoco' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.fromshim.cofoco' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Cofoco' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1.0' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$PLIST"
printf 'APPL????' > "$CONTENTS/PkgInfo"

codesign --force --sign - --timestamp=none --identifier com.fromshim.cofoco.service "$CONTENTS/Helpers/cofoco-service"
codesign --force --sign - --timestamp=none --identifier com.fromshim.cofoco "$APP_BUNDLE"
printf '%s\n' "$APP_BUNDLE"
