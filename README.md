# Time Clock Bar

Time Clock Bar is an open-source macOS menu-bar app for the Full Scale Time Clock web app. It keeps the Time Clock and Daily Report pages one click away, shows the current work status in the menu bar, and adds reminders and shortcuts for daily timekeeping.

## Features

- Menu-bar status for loading, login required, clocked out, active, on break, stale, overtime, and over-break states.
- Optional menu-bar details for status, current timer, day timer, week timer, remaining time, labels, and the FS logo.
- Compact popover with embedded Time Clock and Daily Report pages.
- Left-click menu-bar access and right-click menu actions for settings, About, Time Clock, Daily Report, browser links, refresh, and quit.
- Refresh, open-current-page, page switching, and fixed keyboard shortcuts inside the popover.
- Custom global shortcut to toggle the app, enabled by default.
- Shift settings for work days, start time, end time, and break duration.
- Notifications for shift start, break time, over-break, clock-out, and overtime.
- Notification actions to open Time Clock, open Daily Report, or snooze for 5, 10, or 15 minutes.
- Launch-at-login support.
- System, light, and dark app themes.
- Settings reset for display settings or all app defaults.
- About window with app version, build number, creator link, and repository link.
- Offline and sleep-aware polling pause/resume, with stale status handling and last-refreshed tooltip.

## Requirements

- macOS 26.5 or newer.
- Network access to:
  - `https://timeclock.fullscale.rocks/overview`
  - `https://fullscale.rocks/daily-report`
- Xcode for building, testing, or packaging from source.

## Install For Internal Use

For a quick internal install, download or build `TimeClockBar-1.0-internal.zip`, unzip it, move `Time Clock Bar.app` to `/Applications`, then open it.

The current internal package is ad-hoc signed from the local Xcode project. macOS may show an unsigned/unverified developer warning when sharing the zip outside the build machine. For a company-wide release without that warning, package with an Apple Developer ID, enable hardened runtime, and notarize the app.

## Package The App

Build a Release app and zip it for internal sharing:

```sh
rm -rf build/TimeClockBarPackage
mkdir -p dist
xcodebuild -project TimeClockBar.xcodeproj \
  -scheme TimeClockBar \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/TimeClockBarPackage \
  build
ditto -c -k --keepParent \
  'build/TimeClockBarPackage/Build/Products/Release/Time Clock Bar.app' \
  'dist/TimeClockBar-1.0-internal.zip'
```

Validate the built app bundle:

```sh
codesign --verify --deep --strict --verbose=2 \
  'build/TimeClockBarPackage/Build/Products/Release/Time Clock Bar.app'
```

## Development

Open the project in Xcode:

```sh
open TimeClockBar.xcodeproj
```

Build from the command line:

```sh
xcodebuild -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug build
```

Run tests from the command line:

```sh
xcodebuild test -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug -destination 'platform=macOS'
```

There is no separate package manager, backend service, database, or web build step in this repository. The app currently uses Apple frameworks only.

## Manual Release Check

Before sharing a package internally, open the built app and verify:

- Login works.
- Menu-bar status and tooltip update.
- Time Clock and Daily Report pages load.
- Refresh and browser-opening actions work.
- Settings persist after restart.
- Notifications can be allowed in macOS settings.
- Shift, break, clock-out, overtime, and over-break reminder settings behave as expected.
- Global shortcut and fixed popover shortcuts work.
- Launch at Login can be enabled and disabled.
- About shows the expected version and build.

## Source Layout

- `TimeClockBar/App/` contains the SwiftUI app entry point and AppKit delegate.
- `TimeClockBar/Controllers/` contains stateful app coordinators.
- `TimeClockBar/Models/` contains shared domain types.
- `TimeClockBar/Support/` contains focused helpers for DOM detection, reminders, timer math, menu-title formatting, and hotkey labels.
- `TimeClockBar/Views/` contains SwiftUI views and AppKit bridges.
- `TimeClockBar/Resources/` contains assets and entitlements.
- `TimeClockBarTests/` contains hosted macOS XCTest coverage for deterministic app behavior.

## Project Docs

- `AGENTS.md` contains agent-facing rules.
- `docs/ai/architecture.md` describes the app structure.
- `docs/ai/code-structure.md` captures the source layout, ownership boundaries, and split rules.
- `docs/ai/development.md` covers local workflow.
- `docs/ai/testing.md` lists validation commands.
- `docs/ai/release.md` covers release checks.
- `docs/ai/coding-standards.md` captures implementation conventions.
