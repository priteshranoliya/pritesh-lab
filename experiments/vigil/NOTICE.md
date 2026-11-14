# Notice

Vigil is derived from **WakeBee** by Aditya Jaiswal
(<https://github.com/jswladitya/WakeBee>), using commit `0590044`, the last
revision published under the MIT License. Later WakeBee revisions are
AGPL-3.0 licensed; no code from them is used here.

The original copyright and permission notice is kept in `LICENSE`, as the MIT
License requires.

## What came from WakeBee
- Session timing, duration and end-time logic (`AwakeCore`)
- Power and closed-lid battery policy (`ClosedLidPolicy`, `SessionPowerPolicy`)
- Kernel sleep-setting read/write and power-state readers
- SwiftUI session, duration and settings views; glass design components
- Menu-bar popover controller

## What is new in Vigil
- Helper that owns sessions (survives the app quitting or crashing),
  installed once with an administrator password — no Developer ID needed
- Unix-socket IPC, the `vigil` command-line tool
- Configurable closed-lid time limit (including none)
- Feature-module architecture for future features
- Removed: Polar license activation, Sparkle updates, SMAppService helper,
  WakeBee branding and artwork
