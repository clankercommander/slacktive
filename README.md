# Slacktive

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](https://swift.org/)

A free, open-source macOS menu bar app that keeps you looking "active" on Slack. No more going "away" because you stepped away from your keyboard for 5 minutes.

<!-- ![Slacktive screenshot](assets/screenshot.png) -->

## What it does

Slacktive prevents Slack (and other apps) from detecting you as idle by:

1. **Preventing system sleep** — IOKit power assertions stop macOS from going idle
2. **Declaring user activity** — `IOPMAssertionDeclareUserActivity` every 30 seconds prevents the system from marking the session as idle
3. **Smart mouse jiggle** — a tiny 4px circle pattern every 4–5 minutes, **only when you're actually away** (skipped entirely during active use). Resets HIDIdleTime so Slack sees you as present

That's it. It sits quietly in your menu bar and does its job.

## Features

- **One-click toggle** — green dot = active, gray = inactive
- **Work schedule** — auto-activate during your work hours (e.g., Mon–Fri 9 AM–5 PM)
- **Launch at Login** — start automatically with macOS
- **Zero footprint** — no Dock icon, minimal CPU/memory usage

## Install

### Download

Download the latest `.dmg` from [Releases](../../releases), open it, and drag Slacktive to your Applications folder.

### Build from source

Requires Xcode 15+ and macOS 13+.

```bash
git clone https://github.com/clankercommander/slacktive.git
cd slacktive
xcodebuild -project Slacktive.xcodeproj -scheme Slacktive -configuration Release build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/Slacktive-*/Build/Products/Release/Slacktive.app`.

Or just open `Slacktive.xcodeproj` in Xcode and hit Run.

## Permissions

On first launch, macOS will ask you to grant **Accessibility** access (System Settings > Privacy & Security > Accessibility). This is required for the mouse and keyboard simulation to work. Without this permission, the app will still prevent system sleep via power assertions, but application-level idle detection (like Slack's own checks) may not be reset.

## Building a DMG for distribution

```bash
./scripts/build-dmg.sh
```

This creates a `dist/Slacktive.dmg` ready to share.

## How it works

Slack determines your "away" status based on macOS system idle time. If your computer reports no user activity for ~10 minutes, Slack marks you as away.

Slacktive prevents this with a three-layer approach:
1. **IOKit power assertion** (`PreventUserIdleDisplaySleep`) — prevents the system from entering idle or display sleep
2. **`IOPMAssertionDeclareUserActivity`** — declares user activity every 30 seconds, preventing the session from being marked idle
3. **CGEvent mouse circle + F16 keypress** — every 4–5 minutes (randomized), Slacktive performs a tiny 4px circle movement and returns the cursor to its exact original position. An F16 key tap is also sent to reset app-level idle timers. **This only happens when you've been idle for 30+ seconds** — if you're actively using the computer, the jiggle is skipped entirely so your mouse is never disrupted

## Verification

To verify Slacktive is working, toggle it on, step away from your computer, and run:

```bash
./scripts/verify.sh      # 5-minute test (default)
./scripts/verify.sh 600  # 10-minute test
```

The script monitors HIDIdleTime, power assertions, and mouse position in real-time. A passing test means idle time never reaches Slack's 600-second away threshold.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

MIT — see [LICENSE](LICENSE) for details.

