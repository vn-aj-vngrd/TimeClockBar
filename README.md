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

For developers who have Xcode and source access, the easiest no-signing-key path is to build and install locally:

```sh
make install-local
```

That builds the Release app on the developer's Mac, copies it to `~/Applications`, and opens it. This avoids Developer ID key sharing because each developer gets a local Xcode-signed app. It does not make a shared zip warning-free on other Macs.

## Package The App

Build a Release app and zip it for internal sharing:

```sh
make release
```

The package is written to `dist/TimeClockBar-1.0-internal.zip`. To build a different package version name:

```sh
make release VERSION=1.1
```

## Development

Open the project in Xcode:

```sh
make dev
```

Build from the command line:

```sh
make build
```

Build and run the Debug app without opening Xcode:

```sh
make run
```

Run tests from the command line:

```sh
make test
```

There is no separate package manager, backend service, database, or web build step in this repository. The app currently uses Apple frameworks only.

## Make Commands

- `make help` lists the available commands.
- `make dev` opens the Xcode project.
- `make build` builds the Debug app.
- `make run` builds the Debug app and opens it.
- `make test` runs the macOS XCTest suite.
- `make package` builds Release and creates the internal zip.
- `make verify` validates the Release app code signature.
- `make quit-local` quits the locally running app if needed.
- `make install-local` builds Release, installs it to `~/Applications`, and opens it.
- `make release` cleans, packages, and verifies the internal zip.
- `make clean` removes build artifacts.
- `make distclean` removes build artifacts and packaged zips.

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
