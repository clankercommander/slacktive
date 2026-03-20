# Architecture

This document explains how Slacktive works under the hood. If you're looking to contribute or just curious about the internals, start here.

## Overview

Slacktive is a macOS menu bar app built with SwiftUI. It prevents Slack (and other apps) from detecting you as idle by using three complementary mechanisms that target different layers of macOS idle detection.

```
┌──────────────────────────────────────────────────────────────────────┐
│  SlacktiveApp                                                        │
│  ├── ActivityManager (core engine)                                   │
│  │   ├── IOKit Power Assertion ──────── prevents system/display sleep│
│  │   ├── IOPMAssertionDeclareUserActivity ── declares session active │
│  │   └── Mouse Circle Jiggle + F16 Key ── resets HIDIdleTime        │
│  └── ScheduleManager (schedule logic)                                │
│      └── 60s timer → checks schedule → calls ActivityManager         │
│                                                                      │
│  UI: MenuBarView (popover) + SettingsView (window)                   │
└──────────────────────────────────────────────────────────────────────┘
```

## The Three Mechanisms

### 1. IOKit Power Assertion

**What:** Creates a `PreventUserIdleDisplaySleep` assertion via `IOPMAssertionCreateWithName`.

**Why:** Prevents macOS from turning off the display or entering system sleep due to idle timeout. Falls back to `PreventUserIdleSystemSleep` if the display assertion fails.

**Lifecycle:** Created when Slacktive activates, released when it deactivates or the process exits.

**Limitation:** Does not affect `HIDIdleTime` — apps that check the HID idle counter (like Slack) will still see rising idle time.

### 2. System Activity Declaration

**What:** Calls `IOPMAssertionDeclareUserActivity` every 30 seconds.

**Why:** Tells the Power Manager that user activity occurred. This is the same mechanism used by `caffeinate` and other system tools.

**Limitation:** On macOS Sequoia+, this does NOT reset `HIDIdleTime` (the IOKit `IOHIDSystem` counter). It did on earlier macOS versions. The behavior change appears to be intentional by Apple — the assertion prevents idle sleep policies but no longer affects the HID input timestamp.

### 3. Mouse Circle Jiggle + F16 Keypress

**What:** Every 4–5 minutes (randomized), performs a tiny circular mouse movement (4px radius, 4 steps) followed by an F16 key tap via `CGEvent`. The cursor returns to its exact original position.

**Why:** CGEvent mouse moves and keypresses DO reset `HIDIdleTime`, which is what Slack uses to determine away status.

**Smart idle detection:** Before jiggling, checks `HIDIdleTime`. If the user has been active in the last 30 seconds (idle time < 30s), the jiggle is skipped entirely. This means the mouse never moves during active computer use.

**Why F16?** It's defined in the USB HID spec (keyCode 106) but has no default behavior on macOS. Unlike modifier keys (Shift, Ctrl), it won't interfere with typing, trigger keyboard shortcuts, or activate accessibility features like Sticky Keys.

**Requires:** Accessibility permission (System Settings → Privacy & Security → Accessibility).

## Slack's Idle Detection

Slack determines your "away" status based on macOS `HIDIdleTime`:

1. Slack periodically reads `HIDIdleTime` from IOKit (`IOHIDSystem` registry)
2. If `HIDIdleTime` exceeds ~600 seconds (10 minutes), Slack marks you as "away"
3. Any HID input event (mouse move, keypress) resets `HIDIdleTime` to zero

Slacktive's mouse jiggle fires every 240–300 seconds, so `HIDIdleTime` never exceeds ~300 seconds — well below Slack's 600-second threshold.

## Thread Model

```
Main Thread (UI)
├── @Published property mutations (isActive, manualOverride, schedule properties)
├── SwiftUI view updates
└── Manual override timer (DispatchWorkItem on main queue)

timerQueue (serial, .utility QoS) — "com.slacktive.jiggle"
├── IOKit assertion create/release
├── IOPMAssertionDeclareUserActivity (30s timer)
├── Mouse jiggle scheduling and execution (4-5 min timer)
├── CGEvent posting
└── F16 key simulation

scheduleQueue (serial, .utility QoS) — "com.slacktive.schedule"
└── Schedule check timer (60s)
```

All `@Published` property changes happen on the main thread. All IOKit and CGEvent work happens on `timerQueue`. The `scheduleQueue` dispatches to main when calling `onScheduleChange`.

## Manual Override

When the user manually toggles Slacktive on or off (via the menu bar), a 5-minute `manualOverride` flag is set on `ActivityManager`. During this window, the schedule callback is blocked from changing the active state.

This solves the problem of the schedule immediately undoing a manual toggle. For example, if a user toggles ON outside their schedule hours, the schedule timer (which fires every 60s) would otherwise turn it right back off.

The override auto-expires after 5 minutes via a `DispatchWorkItem`, allowing the schedule to resume control.

## Schedule System

The `ScheduleManager` stores schedule configuration in `UserDefaults`:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `scheduleEnabled` | Bool | `false` | Whether the schedule is active |
| `startHour` | Int | `9` | Start hour (0–23) |
| `startMinute` | Int | `0` | Start minute (0–59) |
| `endHour` | Int | `17` | End hour (0–23) |
| `endMinute` | Int | `0` | End minute (0–59) |
| `activeDays` | [Int] | `[2,3,4,5,6]` | Weekdays (Calendar format: 1=Sun, 7=Sat) |

The schedule is evaluated every 60 seconds. If the schedule is enabled and the current time/day falls within the configured window, `onScheduleChange(true)` is called. Otherwise, `onScheduleChange(false)`.

Start time must be strictly before end time. If start ≥ end, the schedule is effectively disabled and a warning is shown in the Settings UI.

## Logging

All logging uses Apple's `os.log` framework with subsystem `com.slacktive.app`:

| Category | What's logged |
|----------|--------------|
| `App` | App launch |
| `ActivityManager` | Activation/deactivation, assertion lifecycle, jiggle events, override changes |
| `ScheduleManager` | Schedule validation warnings |
| `SettingsView` | Launch-at-login errors |

Log levels:
- `.info` — State changes (activated, deactivated, assertion created/released)
- `.debug` — Routine events (30s activity declaration, jiggle execution)
- `.warning` — Recoverable issues (invalid schedule, failed assertions)
- `.error` — Failures (assertion creation failed, login registration failed)

## Entitlements

| Entitlement | Value | Why |
|------------|-------|-----|
| `com.apple.security.app-sandbox` | `false` | Required for IOKit power assertions and CGEvent injection. These APIs are not available in sandboxed apps. |

## Key Files

| File | Lines | Description |
|------|-------|-------------|
| `ActivityManager.swift` | ~350 | Core engine — all three mechanisms, manual override, diagnostics |
| `ScheduleManager.swift` | ~160 | Schedule storage, validation, monitoring timer |
| `MenuBarView.swift` | ~130 | Menu bar popover UI |
| `SettingsView.swift` | ~130 | Settings window UI |
| `SlacktiveApp.swift` | ~50 | App entry, inter-manager wiring |
| `Info.plist` | ~10 | LSUIElement = true (no Dock icon) |
| `Slacktive.entitlements` | ~8 | Sandbox disabled |
