# Development

## Local Workflow

Use Xcode for day-to-day development:

```sh
open TimeClockBar.xcodeproj
```

Use `xcodebuild` for command-line validation:

```sh
xcodebuild -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug build
```

## Debugging Notes

- Check `TimeclockController` first for state, persistence, reminders, polling, and WebKit extraction behavior.
- Check `AppDelegate` first for menu-bar behavior, popover lifecycle, hotkeys, app activation, network monitoring, and sleep/wake behavior.
- Check `PopoverView` first for settings UI, page switching, and user interactions.
- Prefer focused fixes in the owner above before adding new types.

## Dependencies

The app currently uses Apple frameworks only. Do not add dependencies unless the standard frameworks cannot reasonably cover the task.

