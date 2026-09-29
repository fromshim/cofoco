#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EXPERIMENT_DIR="$REPO_ROOT/experiments/macos-runtime"
BUILD_ROOT="$EXPERIMENT_DIR/.build"
MINIMUM_MACOS="14.0"
BUNDLE_ID="dev.fromshim.cofoco.spike.runtime"
APP_EXECUTABLE="CofocoRuntimeSpike"
HELPER_EXECUTABLE="cofoco-service-spike"

WINDOW_SOURCE="$EXPERIMENT_DIR/window/main.swift"
SERVICE_SOURCE="$EXPERIMENT_DIR/service/main.swift"

for source in "$WINDOW_SOURCE" "$SERVICE_SOURCE"; do
  if [[ ! -f "$source" ]]; then
    printf 'Missing spike source: %s\n' "$source" >&2
    exit 1
  fi
done

case "$(uname -m)" in
  arm64|x86_64) HOST_ARCH="$(uname -m)" ;;
  *) printf 'Unsupported host architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)"
TARGET="$HOST_ARCH-apple-macosx$MINIMUM_MACOS"
mkdir -p "$BUILD_ROOT"
RUN_DIR="$(mktemp -d "$BUILD_ROOT/run.XXXXXX")"
APP_BUNDLE="$RUN_DIR/packaging output with spaces/CofocoRuntimeSpike.app"
CONTENTS="$APP_BUNDLE/Contents"
APP_BINARY="$CONTENTS/MacOS/$APP_EXECUTABLE"
HELPER_BINARY="$CONTENTS/Helpers/$HELPER_EXECUTABLE"
PLIST="$CONTENTS/Info.plist"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers"

printf '[PKG-BUILD-01] host=%s sdk=%s minimum_macos=%s target=%s\n' \
  "$HOST_ARCH" "$SDK_VERSION" "$MINIMUM_MACOS" "$TARGET" >&2
printf '[PKG-BUILD-02] compiling native SwiftUI/AppKit app\n' >&2
xcrun --sdk macosx swiftc \
  -parse-as-library -O \
  -target "$TARGET" \
  -sdk "$SDK_ROOT" \
  -module-cache-path "$RUN_DIR/module-cache" \
  -framework SwiftUI \
  -framework AppKit \
  "$WINDOW_SOURCE" \
  -o "$APP_BINARY"

printf '[PKG-BUILD-03] compiling Foundation + system SQLite3 helper\n' >&2
xcrun --sdk macosx swiftc \
  -parse-as-library -O \
  -target "$TARGET" \
  -sdk "$SDK_ROOT" \
  -module-cache-path "$RUN_DIR/module-cache" \
  -framework Foundation \
  -lsqlite3 \
  "$SERVICE_SOURCE" \
  -o "$HELPER_BINARY"

plutil -create xml1 "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string CofocoRuntimeSpike' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Cofoco Runtime Spike' "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_EXECUTABLE" "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1.0' "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MINIMUM_MACOS" "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$PLIST"
printf 'APPL????' > "$CONTENTS/PkgInfo"

printf '[PKG-BUILD-04] applying local ad-hoc signature\n' >&2
codesign --force --sign - --timestamp=none --identifier "$BUNDLE_ID.service" "$HELPER_BINARY"
codesign --force --sign - --timestamp=none --identifier "$BUNDLE_ID" "$APP_BUNDLE"

printf '[PKG-BUILD-05] bundle ready\n' >&2
printf '%s\n' "$APP_BUNDLE"
