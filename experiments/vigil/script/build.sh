#!/usr/bin/env bash
# Builds dist/Vigil.app (app + helper + `vigil` CLI), signed ad hoc unless
# VIGIL_SIGN_IDENTITY names a certificate.
#
#   script/build.sh            build and open
#   script/build.sh --build-only
#   VIGIL_BUILD_CONFIGURATION=release VIGIL_UNIVERSAL=1 script/build.sh --build-only
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in run|--build-only) ;; *) echo "usage: $0 [--build-only]" >&2; exit 2 ;; esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${VIGIL_BUILD_CONFIGURATION:-debug}"
SIGN_IDENTITY="${VIGIL_SIGN_IDENTITY:--}"
APP="$ROOT_DIR/dist/Vigil.app"
CONTENTS="$APP/Contents"

cd "$ROOT_DIR"
BUILD_ARGS=(--configuration "$CONFIGURATION")
if [[ "${VIGIL_UNIVERSAL:-0}" == "1" ]]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

if [[ ! -f Resources/Vigil.icns || script/create_icon.swift -nt Resources/Vigil.icns ]]; then
  rm -rf .build/Vigil.iconset
  swift script/create_icon.swift .build/Vigil.iconset
  iconutil -c icns .build/Vigil.iconset -o Resources/Vigil.icns
fi

if [[ "$MODE" == "run" ]]; then pkill -x Vigil >/dev/null 2>&1 || true; fi
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/bin" "$CONTENTS/Library/HelperTools" "$CONTENTS/Library/LaunchDaemons"
cp "$BIN/Vigil" "$CONTENTS/MacOS/Vigil"
cp "$BIN/VigilHelper" "$CONTENTS/Library/HelperTools/VigilHelper"
cp "$BIN/VigilCLI" "$CONTENTS/Resources/bin/vigil"
cp Resources/app.vigil.Vigil.helper.plist "$CONTENTS/Library/LaunchDaemons/"
cp script/helper.sh "$CONTENTS/Resources/helper.sh"
cp Resources/Vigil.icns "$CONTENTS/Resources/"
cp LICENSE "$CONTENTS/Resources/LICENSE.txt"
cp Resources/Info.plist "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist" "$CONTENTS/Library/LaunchDaemons/app.vigil.Vigil.helper.plist" >/dev/null

# Sign nested code first. Ad-hoc signatures are fine for personal use; the
# helper does not depend on a signing team.
SIGN_OPTIONS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then SIGN_OPTIONS+=(--options runtime --timestamp); fi
codesign "${SIGN_OPTIONS[@]}" --identifier app.vigil.Vigil.helper "$CONTENTS/Library/HelperTools/VigilHelper"
codesign "${SIGN_OPTIONS[@]}" --identifier app.vigil.cli "$CONTENTS/Resources/bin/vigil"
codesign "${SIGN_OPTIONS[@]}" --identifier app.vigil.Vigil "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
if [[ "$MODE" == "run" ]]; then open "$APP"; fi
