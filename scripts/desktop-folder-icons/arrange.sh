#!/bin/zsh
# Places Desktop icons as described in layout.conf. Only icon positions change; nothing moves on disk.
#   ./arrange.sh            arrange (turns off Desktop Stacks and Sort By, which would override positions)
#   ./arrange.sh --dry-run  print where each item would go, change nothing
#   ./arrange.sh --undo     restore the Finder settings saved before the first arrange
set -e
cd "${0:A:h}"
D=${DESKTOP_DIR:-~/Desktop}
CONF=${LAYOUT_CONF:-layout.conf}
BACKUP=finder-prefs-backup.plist

if [[ $1 == --undo ]]; then
  [[ -f $BACKUP ]] || { echo "no backup to restore"; exit 1; }
  defaults import com.apple.finder $BACKUP
  killall Finder
  echo "restored Finder settings from $BACKUP"
  exit 0
fi
[[ -f $CONF ]] || { echo "no $CONF: copy layout.example.conf to $CONF and edit it"; exit 1; }
DRY=0; [[ $1 == --dry-run ]] && DRY=1

# Grid in points from the top-left of the screen; columns run leftwards from the right edge.
# X0 is the rightmost column: set it to roughly your screen width minus 100.
X0=${X0:-1400} DX=${DX:-118} Y0=${Y0:-70} DY=${DY:-112}

# 1. Turn layout.conf into one AppleScript that sets every position.
script='tell application "Finder"'
col=0 row=0 placed=()
while IFS= read -r line || [[ -n $line ]]; do
  [[ $line == \#* ]] && continue
  if [[ -z ${line// } ]]; then (( row > 0 )) && { col=$((col+1)); row=0 }; continue; fi
  for f in $D/${~line}(N); do
    name=${f:t}
    (( ${placed[(Ie)$name]} )) && continue
    placed+=$name
    x=$(( X0 - col*DX )) y=$(( Y0 + row*DY ))
    (( DRY )) && echo "col $((col+1)) row $((row+1))  {$x, $y}  $name"
    script+=$'\n'"  set desktop position of item \"${name//\"/\\\"}\" of desktop to {$x, $y}"
    row=$((row+1))
  done
done < $CONF
script+=$'\nend tell'

if (( ! DRY )); then
  # 2. Save the current Finder settings once, then switch off Stacks and auto-sorting.
  [[ -f $BACKUP ]] || defaults export com.apple.finder $BACKUP
  tmp=$(mktemp -t finder).plist
  defaults export com.apple.finder $tmp
  /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:GroupBy None" \
                          -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy none" $tmp
  defaults import com.apple.finder $tmp
  rm -f $tmp
  killall Finder; sleep 3
  osascript -e "$script"
fi
echo "placed ${#placed} items in $(( col + 1 )) columns"

# 3. Anything on the Desktop that layout.conf doesn't mention.
for f in $D/*(N); do (( ${placed[(Ie)${f:t}]} )) || echo "not in $CONF: ${f:t}"; done
