#!/usr/bin/env bash
# Packages a release build into dist/Vigil-<version>.dmg for sharing.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VIGIL_BUILD_CONFIGURATION=release VIGIL_UNIVERSAL="${VIGIL_UNIVERSAL:-1}" script/build.sh --build-only
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Vigil.app/Contents/Info.plist)"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

ditto dist/Vigil.app "$STAGING/Vigil.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/READ ME FIRST.txt" <<'EOF'
Installing Vigil
================
1. Drag Vigil into Applications.
2. Open Vigil. macOS will say it can't verify the developer
   (this build is not notarized). Click Done, then open
   System Settings → Privacy & Security and click "Open Anyway".

   Or run once in Terminal:
     xattr -dr com.apple.quarantine /Applications/Vigil.app

3. Click the eye in the menu bar → Closed-lid mode → "Set up…"
   and enter your Mac password once. This installs the helper that
   keeps sessions running even if Vigil quits.
EOF

DMG="dist/Vigil-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Vigil $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "Created $DMG"
