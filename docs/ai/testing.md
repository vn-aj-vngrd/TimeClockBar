# Testing

The project has a hosted macOS XCTest bundle named `TimeClockBarTests`.

Automated tests cover deterministic Swift behavior, reminder planning, menu-title formatting, hotkey labels, timer math, and local WebKit DOM detection with inline HTML. Platform service flows still need manual verification because they depend on macOS services, live WebKit state, notification permissions, global hotkeys, launch-at-login, network state, and sleep/wake behavior.

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
