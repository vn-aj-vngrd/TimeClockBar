# Time Clock Bar

Time Clock Bar is an open-source macOS menu-bar app for the Full Scale Time Clock web app. It embeds the time clock and daily report pages in a compact popover, shows the current status in the menu bar, and supports reminders, launch at login, a global hotkey, fixed popover shortcuts, and an About window with bundle version details.

## Requirements

- macOS with Xcode installed.
- Network access to:
  - `https://timeclock.fullscale.rocks/overview`
  - `https://fullscale.rocks/daily-report`

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

There is no separate package manager, backend service, database, or web build step in this repository.

## Source Layout

- `TimeClockBar/App/` contains the SwiftUI app entry point and AppKit delegate.
- `TimeClockBar/Controllers/` contains stateful app coordinators.
- `TimeClockBar/Models/` contains shared domain types.
- `TimeClockBar/Support/` contains focused helpers for DOM detection, reminders, and hotkey labels.
- `TimeClockBar/Views/` contains SwiftUI views and AppKit bridges.
- `TimeClockBar/Resources/` contains assets and entitlements.

## Project Docs

- `AGENTS.md` contains agent-facing rules.
- `docs/ai/architecture.md` describes the app structure.
- `docs/ai/code-structure.md` captures the source layout, ownership boundaries, and split rules.
- `docs/ai/development.md` covers local workflow.
- `docs/ai/testing.md` lists validation commands.
- `docs/ai/release.md` covers release checks.
- `docs/ai/coding-standards.md` captures implementation conventions.
