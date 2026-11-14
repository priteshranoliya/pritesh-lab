#!/bin/bash
# Installs or removes Vigil's keep-awake helper. Runs as root: the app calls it
# through macOS's administrator prompt. Paths mirror Sources/VigilIPC/VigilIdentity.swift.
#
#   helper.sh install   /Applications/Vigil.app
#   helper.sh uninstall
set -euo pipefail

LABEL="app.vigil.Vigil.helper"
HELPER="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
SOCKET="/var/run/app.vigil.helper.sock"
STATE_DIR="/private/var/db/app.vigil.helper"
CLI="/usr/local/bin/vigil"

[[ $EUID -eq 0 ]] || { echo "helper.sh must run as root" >&2; exit 1; }

# The helper restores sleep itself when stopped. If that ever failed, apply the
# value from its recovery journal so a removed helper never leaves sleep disabled.
restore_from_journal() {
  local previous
  previous="$(/usr/bin/plutil -extract previousSleepDisabled raw -o - "$STATE_DIR/state.json" 2>/dev/null || true)"
  case "$previous" in
    true) /usr/bin/pmset -a disablesleep 1 ;;
    false) /usr/bin/pmset -a disablesleep 0 ;;
  esac
}

stop_helper() {
  /bin/launchctl bootout "system/$LABEL" 2>/dev/null || true
}

case "${1:-}" in
  install)
    BUNDLE="${2:?usage: helper.sh install /path/to/Vigil.app}"
    SOURCE_HELPER="$BUNDLE/Contents/Library/HelperTools/VigilHelper"
    SOURCE_PLIST="$BUNDLE/Contents/Library/LaunchDaemons/$LABEL.plist"
    SOURCE_CLI="$BUNDLE/Contents/Resources/bin/vigil"
    [[ -f "$SOURCE_HELPER" && -f "$SOURCE_PLIST" ]] || { echo "Helper files are missing from $BUNDLE" >&2; exit 1; }
    /usr/bin/plutil -lint "$SOURCE_PLIST" >/dev/null

    # Upgrading keeps a running session: the new helper reloads it from its state file.
    stop_helper
    /usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
    /usr/bin/install -o root -g wheel -m 755 "$SOURCE_HELPER" "$HELPER"
    /usr/bin/install -o root -g wheel -m 644 "$SOURCE_PLIST" "$PLIST"
    # Root-owned copies; drop download quarantine so launchd will run them.
    /usr/bin/xattr -c "$HELPER" "$PLIST" 2>/dev/null || true
    if [[ -f "$SOURCE_CLI" ]]; then
      /usr/bin/install -d -m 755 /usr/local/bin
      /usr/bin/install -o root -g wheel -m 755 "$SOURCE_CLI" "$CLI"
      /usr/bin/xattr -c "$CLI" 2>/dev/null || true
    fi
    /bin/launchctl bootstrap system "$PLIST"
    ;;
  uninstall)
    stop_helper
    restore_from_journal
    /bin/rm -f "$PLIST" "$HELPER" "$SOCKET" "$CLI"
    /bin/rm -rf "$STATE_DIR"
    ;;
  *)
    echo "usage: helper.sh install /path/to/Vigil.app | uninstall" >&2
    exit 2
    ;;
esac
