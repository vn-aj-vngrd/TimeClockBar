# Time Clock Bar

Time Clock Bar is an open-source macOS menu-bar app for the Full Scale Time Clock web app. It keeps the Time Clock and Daily Report pages one click away, shows the current work status in the menu bar, and adds reminders and shortcuts for daily timekeeping.

## Features

- Menu-bar status for loading, login required, clocked out, active, on break, stale, overtime, and over-break states.
- Optional menu-bar details for status, current timer, day timer, week timer, remaining time, labels, and the FS logo.
- Three visible pages: Today dashboard, Time Clock, and Report on Full Scale.
- Left-click menu-bar access and right-click menu actions for settings, About, Time Clock, Daily Report, browser links, refresh, and quit.
- Refresh, open-current-page, page switching, and fixed keyboard shortcuts inside the popover.
- Custom global shortcut to toggle the app, enabled by default.
- Shift settings for work days, start time, end time, and break duration.
- Notifications for shift start, break time, over-break, clock-out, and overtime, each with a selectable alarm sound.
- Break-start reminders require an active clock, and clock-out reminders require an active/break state. Overnight break dates and second-precision return reminders respect the configured shift and elapsed timer.
- Snoozes retain their source and are canceled when that reminder no longer applies. Advance clock-out alerts open Report; due alerts open Time Clock and remind you to file first.
- Notification actions to open Time Clock or Report, snooze, or silence the current checkpoint. Ordinary notification sounds use macOS presentation rules in foreground and background.
- Launch-at-login support.
- System, light, and dark app themes.
- Settings reset for display settings or all app defaults.
- About window with app version, build number, creator link, and repository link.
- Scoped status detection with ten-second fallback reads, locally ticking timers, and last-known status during reconnects.
- Automatic recovery from failed navigation, stalled reads, and WebKit restarts; active-session monitoring allows normal Mac sleep.
- Ten-second sounds by default, optional twenty-second overdue break/clock-out sounds, and visible notification queue health.
- Offline and sleep-aware polling pause/resume, with stale status handling and last-observed tooltip.

## Requirements

- macOS 26.0 or newer.
- Network access to:
  - `https://timeclock.fullscale.rocks/overview`
  - `https://fullscale.rocks/daily-report`
- Xcode for building, testing, or packaging from source.

## Install For Internal Use

For a quick internal install, download or build `TimeClockBar-<version>-internal.zip`, unzip it, move `Time Clock Bar.app` to `/Applications`, then open it.

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

The package is written to `dist/TimeClockBar-<version>-internal.zip`. The app version is computed from conventional commits since the latest `v*` git tag, and the build number is generated from the current git commit count.

Check the current version info:

```sh
make version
```

Version bump rules:

- `BREAKING CHANGE` or `type!:` bumps major.
- `feat:` bumps minor.
- `fix:` and `perf:` bump patch.
- No matching conventional commits keeps the previous version.

The bump rules live in `scripts/next-version.sh`.

`make release` runs the version checks, XCTest suite, package build, and signature verification. For local releases, tag the accepted release so the next version starts from that point:

```sh
make tag-version
```

For shared releases, run the `Release` workflow in GitHub Actions after the release changes are on `main`. It computes the version from commits, creates the `v<version>` tag, and uploads the zip to the GitHub Release.

## Development

Build the Debug app and open it:

```sh
make dev
```

Open the project in Xcode:

```sh
make xcode
```

Build the Debug app from the command line:

```sh
make build
```

Build and open the Debug app directly:

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
- `make version` shows app, build, and git version info.
- `make dev` builds the Debug app and opens it.
- `make xcode` opens the Xcode project.
- `make build` builds the Debug app.
- `make run` builds the Debug app and opens it.
- `make test` runs the macOS XCTest suite.
- `make test-version` runs the version script checks.
- `make package` builds Release and creates the internal zip.
- `make verify` validates the Release app code signature.
- `make quit-local` quits the locally running app if needed.
- `make install-local` builds Release, installs it to `~/Applications`, and opens it.
- `make tag-version` tags the current commit as `v<version>`.
- `make release` cleans, tests, packages, and verifies the internal zip.
- `make clean` removes build artifacts.
- `make distclean` removes build artifacts and packaged zips.

## GitHub Releases

The repository includes two GitHub Actions workflows:

- `CI` runs version checks and hosted XCTest on pushes to `main` and pull requests.
- `Release` is started manually from GitHub Actions. It computes the next version from commits, builds the zip, creates the `v<version>` tag, and attaches the zip to a GitHub Release. If the computed version is already the latest tag, it skips the release.

Run `make test` locally before release changes. The deployment target is macOS 26.0; CI and Release run hosted XCTest on macOS 26. Physical notification, Focus, sleep/wake, and personal-use checks remain local gates.

Use GitHub Releases for shared packages. Use `make install-local` for local development installs.

## Manual Release Check

Before sharing a package internally, open the built app and verify:

- Login works.
- Menu-bar status and tooltip update.
- Time Clock and Daily Report pages load.
- Refresh and browser-opening actions work.
- Settings persist after restart.
- Notifications can be allowed in macOS settings.
- Shift, break, clock-out, overtime, and over-break reminder settings behave as expected.
- Reminder sounds are distinct by default, configurable per reminder, and previewable.
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

- [Product direction](PRODUCT.md) defines the workday companion and confirmed priorities.
- [Improvement plan](docs/plans/workday-companion.md) defines the simplified Today → Time Clock → Report → clock-out flow. Implementation is in progress; use the checklist for completed capabilities.
- [Implementation checklist](docs/plans/workday-companion-progress.md) tracks completed work, validation evidence, remaining release gates, and where to resume.
- [Product audit](docs/product/audit-2026-09-05.md) records source findings and validation limits.
- [Design](DESIGN.md) and [domain language](CONTEXT.md) guide implementation.
- `AGENTS.md` contains agent-facing rules.
- `docs/ai/architecture.md` describes the app structure.
- `docs/ai/code-structure.md` captures the source layout, ownership boundaries, and split rules.
- `docs/ai/development.md` covers local workflow.
- `docs/ai/testing.md` lists validation commands.
- `docs/ai/release.md` covers release checks.
- `docs/ai/coding-standards.md` captures implementation conventions.

## Daily flow

Clock in on **Time Clock**, follow break/return reminders, file your report on **Report**, then return to **Time Clock** to clock out. **Today** shows the next useful step. It stays quiet on days off.

Use Cmd-0 for Today, Cmd-1 for Time Clock, and Cmd-2 for Report. Report remains the Full Scale website; there is no separate native editor or submission automation.

For local UI verification without loading websites or scheduling notifications:

```sh
open 'build/TimeClockBarPackage/Build/Products/Release/Time Clock Bar.app' --args --preview-today
```

The preview is labeled and website pages remain paused until a normal relaunch. XCTest uses this mode automatically. See the [persistent checklist](docs/plans/workday-companion-progress.md) for release evidence.
