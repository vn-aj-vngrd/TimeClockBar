# Testing

The project has a hosted macOS XCTest bundle named `TimeClockBarTests`.

Automated tests cover deterministic Swift behavior, reminder planning, menu-title formatting, hotkey labels, timer math, and local WebKit DOM detection with inline HTML. Platform service flows still need manual verification because they depend on macOS services, live WebKit state, notification permissions, global hotkeys, launch-at-login, network state, and sleep/wake behavior.

Reminder delivery tests use an in-memory notification center and controlled async boundaries to verify cancellation, snooze ownership, and late callbacks. They do not demonstrate OS delivery. Planner tests cover overnight break rollover, clock-state eligibility, and second-precision break deadlines. The [implementation checklist](../plans/workday-companion-progress.md) records the current test result and outstanding platform checks.

## Required Checks

Run the automated test suite:

```sh
xcodebuild test -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug -destination 'platform=macOS'
```

For build-only checks, run:

```sh
xcodebuild -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug build
```

For UI, WebKit, notification, hotkey, launch-at-login, or menu-bar behavior, also verify manually in the running app because those flows depend on macOS services.

## Manual Regression Areas

- Menu-bar title and tooltip updates.
- Left-click popover open and close.
- Right-click menu actions.
- About window opens once, focuses on repeat open, and shows current bundle metadata/link text.
- Popover refresh, page toggle, in-app Time Clock/Daily Report menu actions, and fixed shortcut behavior.
- Settings persistence after app restart.
- Reminder scheduling and notification actions.
- Global hotkey registration and recording.
- Polling pause and resume across offline, sleep, and wake states.

## Production website boundary

The user explicitly requires Time Clock and Full Scale Report to stay usable while agents leave live attendance and reporting data untouched. Loading/read-only inspection is allowed. Tests must not clock in/out, start/end a break, enter or edit report content, use website Improve, or submit reports. Use local fixtures and the test-host preview mode to exercise those flows. General QA/release authorization is not permission to perform real actions.

The shared XCTest scheme sets `TIMECLOCKBAR_PREVIEW=1`; controller load/poll/notification methods return without touching live sites. `testTestHostNeverLoadsWebsites` verifies this boundary. Normal app launches retain ordinary website access; `--preview-today` is only an optional native UI preview.
