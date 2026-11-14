#!/bin/zsh
# Gives Desktop folders custom Finder icons, as listed in icons.conf.
# Purely cosmetic: only the icons change, nothing is moved or renamed. Safe to re-run.
#   ./apply.sh           apply icons.conf
#   ./apply.sh --reset   put back the plain macOS folder icons
set -e
cd "${0:A:h}"
D=${DESKTOP_DIR:-~/Desktop}
CONF=${ICONS_CONF:-icons.conf}
[[ -f $CONF ]] || { echo "no $CONF: copy icons.example.conf to $CONF and edit it"; exit 1; }

# Rebuild the renderer when the source changes.
[[ folder-icon -nt folder-icon.swift ]] || swiftc -O folder-icon.swift -o folder-icon

RESET=0; [[ $1 == --reset ]] && RESET=1

while read -r kind src color rest; do
  [[ -z $kind || $kind == \#* ]] && continue
  words=(${=rest}) tile=()
  if [[ ${words[1]} == tile=* ]]; then tile=(--tile ${words[1]#tile=}); shift words; fi
  dirs=(); for g in $words; do dirs+=($D/${~g}(N/)); done   # keep only folders that exist
  (( ${#dirs} )) || { echo "· nothing matches: $words"; continue; }
  if (( RESET )); then ./folder-icon --reset $dirs; continue; fi
  case $kind in
    logo)  ./folder-icon --logo $src --color $color $dirs ;;          # logo fills the tile
    mark)  ./folder-icon --mark $src --color $color $tile $dirs ;;    # small logo on a coloured tile
    glyph) ./folder-icon --symbol $src --color $color $dirs ;;        # SF Symbol on a coloured tile
    *)     echo "✗ unknown kind '$kind' (use logo, mark or glyph)" ;;
  esac
done < $CONF

killall Dock 2>/dev/null || true   # the Desktop is drawn by the Dock; refresh its icon cache
