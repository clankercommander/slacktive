# Contributing to Slacktive

Thanks for your interest in contributing! Slacktive is a small project but we welcome bug reports, feature requests, and pull requests.

## Getting Started

### Requirements

- macOS 13.0+
- Xcode 15+
- Swift 5

### Build

```bash
git clone https://github.com/clankercommander/slacktive.git
cd slacktive

# Debug build
xcodebuild -project Slacktive.xcodeproj -scheme Slacktive -configuration Debug build

# Or open in Xcode
open Slacktive.xcodeproj
```

The built app ends up in `~/Library/Developer/Xcode/DerivedData/Slacktive-*/Build/Products/Debug/Slacktive.app`.

### Run

```bash
open ~/Library/Developer/Xcode/DerivedData/Slacktive-*/Build/Products/Debug/Slacktive.app
```

Or press ⌘R in Xcode.

### Permissions

Slacktive needs **Accessibility** permission to simulate mouse movements and key events. After each rebuild, macOS may revoke this permission because the binary hash changes.

To re-grant after a rebuild:
1. Open **System Settings → Privacy & Security → Accessibility**
2. Remove the old Slacktive entry (if present)
3. Click **+** and navigate to the built `.app` in DerivedData
4. Toggle it ON

> **Tip:** `tccutil reset Accessibility com.slacktive.app` will clear old entries.

## Testing

### Verification Script

The `verify.sh` script monitors all three anti-idle mechanisms in real-time:

```bash
# Default 5-minute test
./scripts/verify.sh

# Custom duration (seconds)
./scripts/verify.sh 600
```

Toggle Slacktive ON, step away from the keyboard, and let the script run. It checks:
- **HIDIdleTime** — should reset when the mouse jiggle fires (~every 4-5 min)
- **Power assertions** — should stay active throughout
- **Mouse position** — should detect micro-movements

### Watching Logs

All logging uses `os.log` with subsystem `com.slacktive.app`:

```bash
# Stream all Slacktive logs
log stream --predicate 'subsystem == "com.slacktive.app"' --info --debug

# Filter to just ActivityManager
log stream --predicate 'subsystem == "com.slacktive.app" AND category == "ActivityManager"' --info --debug

# Check historical logs
log show --predicate 'subsystem == "com.slacktive.app"' --last 10m --info --debug
```

### Manual Checks

```bash
# Is Slacktive running?
pgrep -x Slacktive

# Are power assertions active?
pmset -g assertions | grep Slacktive

# Current system idle time (seconds)
echo $(ioreg -c IOHIDSystem -d 4 | grep HIDIdleTime | head -1 | awk '{print $NF}') / 1000000000 | bc
```

## Code Style

- **Logging:** Use `os.log` (`Logger`), never `print()`. Categories: `App`, `ActivityManager`, `ScheduleManager`, `SettingsView`.
- **Threading:** Mutate `@Published` properties on main thread only. Timer and IOKit work goes on `timerQueue`.
- **Error handling:** No `try!` or `fatalError` — handle errors gracefully with logging.

## Submitting Changes

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes
4. Verify with `./scripts/verify.sh` and a clean Release build
5. Open a pull request with a clear description

## Building a DMG

To create a distributable `.dmg`:

```bash
./scripts/build-dmg.sh
```

Output: `dist/Slacktive.dmg`

## Reporting Issues

When filing a bug, please include:
- macOS version (`sw_vers`)
- Slacktive version or commit hash
- Output of `pmset -g assertions | grep Slacktive`
- Relevant log output (`log show --predicate 'subsystem == "com.slacktive.app"' --last 10m --info`)
