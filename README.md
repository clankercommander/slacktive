# Slacktive

A tiny macOS menu bar app that keeps you looking "active" on Slack. No more going "away" because you stepped away from your keyboard for 5 minutes.

<!-- ![Slacktive screenshot](assets/screenshot.png) -->

## What it does

Slacktive prevents Slack (and other apps) from detecting you as idle by:

1. **Preventing system sleep** — stops macOS from going idle, which is what Slack uses to determine your away status
2. **Simulating subtle mouse activity** — imperceptible 1-2px mouse movements at randomized intervals (30-120 seconds)

That's it. It sits quietly in your menu bar and does its job.

## Features

- **One-click toggle** — green dot = active, gray = inactive
- **Work schedule** — auto-activate during your work hours (e.g., Mon-Fri 9am-5pm)
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

On first launch, macOS will ask you to grant **Accessibility** access (System Settings > Privacy & Security > Accessibility). This is required for the mouse simulation to work.

## Building a DMG for distribution

```bash
./scripts/build-dmg.sh
```

This creates a `dist/Slacktive.dmg` ready to share.

## How it works

Slack determines your "away" status based on macOS system idle time. If your computer reports no user activity for ~10 minutes, Slack marks you as away.

Slacktive prevents this by:
- Creating an IOKit power assertion to prevent display/system idle sleep
- Posting tiny `CGEvent` mouse movements at random intervals, which resets the system idle timer

The movements are randomized in both timing (30-120s) and direction (1-2px) to appear natural. The cursor moves slightly, then immediately returns to its original position.

## License

MIT
