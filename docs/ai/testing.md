# Testing

There is no dedicated test target yet. For behavior changes, prefer adding the smallest useful test target or isolated check if the logic can be tested without driving the app UI.

## Required Checks

For most changes, run:

```sh
xcodebuild -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug build
```

For UI, WebKit, notification, hotkey, launch-at-login, or menu-bar behavior, also verify manually in the running app because those flows depend on macOS services.

## Manual Regression Areas

- Menu-bar title and tooltip updates.
- Popover open, close, refresh, page toggle, and fixed shortcut behavior.
- Settings persistence after app restart.
- Reminder scheduling and notification actions.
- Global hotkey registration and recording.
- Polling pause and resume across offline, sleep, and wake states.
