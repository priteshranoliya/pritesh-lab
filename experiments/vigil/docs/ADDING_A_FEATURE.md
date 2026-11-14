# Adding a feature

Every feature (Awake today; Claude usage next) is a module the app shell
knows only through `FeatureModule` (`Sources/VigilKit/FeatureModule.swift`).

## Steps — example: Claude usage

1. Create the targets:

   ```
   Sources/Features/ClaudeUsage/ClaudeUsageCore/   # parsing, aggregation — no UI
   Sources/Features/ClaudeUsage/ClaudeUsageUI/     # model, views, ClaudeUsageFeature
   Tests/ClaudeUsageCoreTests/
   ```

2. Add them to `Package.swift`, next to the Awake targets:

   ```swift
   .target(name: "ClaudeUsageCore", path: "Sources/Features/ClaudeUsage/ClaudeUsageCore"),
   .target(name: "ClaudeUsageUI", dependencies: ["ClaudeUsageCore", "VigilKit", "DesignSystem"],
           path: "Sources/Features/ClaudeUsage/ClaudeUsageUI"),
   .testTarget(name: "ClaudeUsageCoreTests", dependencies: ["ClaudeUsageCore"]),
   ```

   and add `"ClaudeUsageUI"` to the `Vigil` app target's dependencies.

3. Implement `FeatureModule` in `ClaudeUsageFeature`: an id, title, SF Symbol,
   `makeMenuBarSection()` for the popover, and optionally `makeSettingsPage()`.

4. Register it in `Apps/Vigil/FeatureRegistry.swift`.

The popover stacks each feature's section by `order`; settings get one tab per
feature with a settings page; the menu-bar dot shows while any feature
`isActive`.

## Rules

- Logic goes in `<Name>Core` and is unit-tested; views stay thin.
- Only the Awake feature talks to the root helper. New features never need
  root — keep it that way so the helper stays small and auditable.
- Use `DesignSystem` components (`SettingsScrollPage`, `SettingsGlassSection`,
  `.vigilGlassSurface()`) so features look consistent.
- `VIGIL_SNAPSHOT=/tmp/snap dist/Vigil.app/Contents/MacOS/Vigil` renders the
  popover and settings offscreen to PNGs (glass surfaces render as blank
  blocks there; check those in the real menu bar).

## Claude usage — notes for later

Claude Code writes per-session JSONL logs under `~/.claude/projects/`; token
counts per message are in those files. A `ClaudeUsageCore` parser can
aggregate tokens/cost per day and per 5-hour window and the popover can show
the current window. Verify the log format against a current Claude Code
version before building on it.
