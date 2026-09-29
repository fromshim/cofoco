#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s /path/to/CofocoRuntimeSpike.app\n' "$0" >&2
  exit 64
fi

APP_BUNDLE="$1"
if [[ ! -d "$APP_BUNDLE" || "$APP_BUNDLE" != *.app ]]; then
  printf 'Not an app bundle: %s\n' "$APP_BUNDLE" >&2
  exit 66
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUILD_ROOT="$REPO_ROOT/experiments/macos-runtime/.build"
APP_EXECUTABLE="CofocoRuntimeSpike"
HELPER_EXECUTABLE="cofoco-service-spike"
BUNDLE_ID="dev.fromshim.cofoco.spike.runtime"
MINIMUM_MACOS="14.0"
CONTENTS="$APP_BUNDLE/Contents"
PLIST="$CONTENTS/Info.plist"
APP_BINARY="$CONTENTS/MacOS/$APP_EXECUTABLE"
HELPER_BINARY="$CONTENTS/Helpers/$HELPER_EXECUTABLE"

for required in "$PLIST" "$APP_BINARY" "$HELPER_BINARY"; do
  if [[ ! -f "$required" ]]; then
    printf 'Missing bundle item: %s\n' "$required" >&2
    exit 1
  fi
done

mkdir -p "$BUILD_ROOT"
SERVICE_PROCESS_TEST="$REPO_ROOT/experiments/macos-runtime/service/test_runtime.py"
SMOKE_WRAPPER="$SCRIPT_DIR/bounded_smoke.py"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

printf '[PKG-01] bundle and Info.plist\n'
plutil -lint "$PLIST"
[[ "$(plist_value "$PLIST" CFBundleExecutable)" == "$APP_EXECUTABLE" ]]
[[ "$(plist_value "$PLIST" CFBundleIdentifier)" == "$BUNDLE_ID" ]]
[[ "$(plist_value "$PLIST" CFBundlePackageType)" == APPL ]]
[[ "$(plist_value "$PLIST" LSMinimumSystemVersion)" == "$MINIMUM_MACOS" ]]
[[ "$(plist_value "$PLIST" LSUIElement)" == true ]]
[[ -x "$APP_BINARY" && -x "$HELPER_BINARY" ]]
printf '  executable=%s helper=%s min_macos=%s LSUIElement=true\n' \
  "$APP_EXECUTABLE" "$HELPER_EXECUTABLE" "$MINIMUM_MACOS"

printf '[PKG-02] code signature\n'
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$HELPER_BINARY"
SIGNATURE_DETAILS="$(codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1)"
if ! grep -q '^Signature=adhoc$' <<< "$SIGNATURE_DETAILS"; then
  printf 'Expected local ad-hoc signature; signature metadata did not report one.\n' >&2
  exit 1
fi
printf '  verified=deep+strict signature=ad-hoc identity=none\n'

printf '[PKG-03] architecture and minimum OS load commands\n'
EXPECTED_ARCH="$(uname -m)"
for binary in "$APP_BINARY" "$HELPER_BINARY"; do
  ARCHES="$(lipo -archs "$binary")"
  [[ " $ARCHES " == *" $EXPECTED_ARCH "* ]]
  MINOS="$(vtool -show-build "$binary" | awk '$1 == "minos" { print $2; exit }')"
  if [[ "$MINOS" != "$MINIMUM_MACOS" ]]; then
    printf 'Unexpected minimum OS in %s: %s\n' "$binary" "$MINOS" >&2
    exit 1
  fi
  printf '  %s arch=%s minos=%s\n' "$(basename "$binary")" "$ARCHES" "$MINOS"
done

check_system_dependencies() {
  local binary="$1"
  local dependencies
  local line
  local dependency
  dependencies="$(otool -L "$binary" | sed '1d')"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    dependency="${line%% (compatibility version*}"
    dependency="${dependency#"${dependency%%[![:space:]]*}"}"
    case "$dependency" in
      /System/Library/*|/usr/lib/*) ;;
      *)
        printf 'Non-system dependency in %s: %s\n' "$binary" "$dependency" >&2
        return 1
        ;;
    esac
    case "$dependency" in
      *"/opt/homebrew/"*|*"/usr/local/Cellar/"*|*"/usr/local/opt/"*|*"node_modules"*|*"/libnode"*)
        printf 'Homebrew/Node dependency in %s: %s\n' "$binary" "$dependency" >&2
        return 1
        ;;
    esac
  done <<< "$dependencies"
}

printf '[PKG-04] dynamic dependencies\n'
for binary in "$APP_BINARY" "$HELPER_BINARY"; do
  check_system_dependencies "$binary"
  printf '  %s uses system dependencies only\n' "$(basename "$binary")"
  otool -L "$binary" | sed '1d; s/^\t/    /'
done

printf '[PKG-05] window geometry and accessibility self-test\n'
APP_SELFTEST="$("$APP_BINARY" --self-test)"
printf '%s\n' "$APP_SELFTEST"
if ! grep -q '^PASS ' <<< "$APP_SELFTEST" || grep -q '^FAIL ' <<< "$APP_SELFTEST"; then
  printf 'App self-test did not pass all reported checks.\n' >&2
  exit 1
fi

printf '[PKG-06] SQLite service self-test (isolated internal temporary fixtures)\n'
SERVICE_SELFTEST="$("$HELPER_BINARY" --self-test)"
printf '%s\n' "$SERVICE_SELFTEST"
if ! grep -Eq '"status"[[:space:]]*:[[:space:]]*"passed"' <<< "$SERVICE_SELFTEST"; then
  printf 'Service self-test did not report a pass.\n' >&2
  exit 1
fi

printf '[PKG-07] bundled helper process and app smoke tests\n'
python3 "$SMOKE_WRAPPER" --service-test "$SERVICE_PROCESS_TEST" "$HELPER_BINARY"
APP_SMOKE="$(python3 "$SMOKE_WRAPPER" "$APP_BINARY")"
printf '%s\n' "$APP_SMOKE"
if ! grep -Eq '"panel_visible"[[:space:]]*:[[:space:]]*true' <<< "$APP_SMOKE" \
  || ! grep -Eq '"helper_ready"[[:space:]]*:[[:space:]]*true' <<< "$APP_SMOKE"; then
  printf 'Bundled smoke test did not verify panel visibility and helper readiness.\n' >&2
  exit 1
fi

printf '[PKG-08] verified app path\n%s\n' "$APP_BUNDLE"
printf '[PKG-09] scope: local ad-hoc package only; Developer ID signing and notarization untested\n'
