# Desktop folder icons

Make the project folders on your macOS Desktop recognisable at a glance: each one gets a soft pastel folder icon with a brand logo or an SF Symbol on it, and the Desktop gets a fixed layout grouped into zones.

![example icons](preview/icons.png)

**Purely cosmetic.** Only the Finder icons and Desktop icon positions change. Folders are never moved or renamed, so paths, git repos and running projects are unaffected.

## Files

| File | What it does |
|---|---|
| `folder-icon.swift` | Draws the folder icon and sets it on each folder given. Compiled automatically by `apply.sh`. |
| `apply.sh` | Applies every icon listed in `icons.conf`. `--reset` restores the plain macOS icons. |
| `arrange.sh` | Positions Desktop icons as listed in `layout.conf`. `--dry-run` previews, `--undo` restores Finder settings. |
| `icons.example.conf`, `layout.example.conf` | Templates. Your real `icons.conf`, `layout.conf` and `logos/` stay local (gitignored). |

## Setup

```sh
cp icons.example.conf icons.conf     # map folders → logo / SF Symbol + colour
cp layout.example.conf layout.conf   # columns and zones for the Desktop
mkdir logos                          # square PNGs, e.g. each project's apple-touch-icon
./apply.sh
./arrange.sh --dry-run && ./arrange.sh
```

Requires macOS with the Xcode command line tools (`swiftc`).

## Icon kinds (`icons.conf`)

```
glyph  book.fill         #5B5BD6               learning      # SF Symbol on a colour tile
logo   logos/acme.png    #23A27E               acme-*        # logo fills the tile
mark   logos/leaf.png    #75BA4B tile=#FFFCE9  garden-app    # small logo on a coloured tile
```

The colour sets both the pastel folder and the tile. Folder names can be globs, so `acme-*` themes all of one company's repos in a single line.

## Good to know

- Finder stores a custom icon in a hidden `Icon\r` file inside the folder. For folders that are git repos, `folder-icon` adds `Icon[\r]` to `.git/info/exclude` so it never shows up in `git status`. (Git strips a trailing `\r` from ignore patterns, which is why it needs the brackets.)
- `arrange.sh` turns off Desktop Stacks and Sort By, because either one overrides manual positions. It saves your Finder settings to `finder-prefs-backup.plist` the first time, and `--undo` brings them back.
- In `arrange.sh`, `X0` is the x position of the rightmost column. Set it to about your screen width minus 100, e.g. `X0=1700 ./arrange.sh`.
- New project folder? Add a line to `icons.conf` and `layout.conf` and re-run both scripts.
