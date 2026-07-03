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

- Check `Controllers/TimeclockController.swift` first for published state, persistence, polling coordination, and WebKit navigation.
- Check `Support/TimeclockDOMDetector.swift` first for DOM extraction behavior.
- Check `Support/TimeclockReminderScheduler.swift` first for reminders and notification actions.
- Check `App/AppDelegate.swift` first for menu-bar behavior, popover lifecycle, global hotkeys, app activation, network monitoring, and sleep/wake behavior.
- Check `Views/Popover/PopoverView.swift` first for page switching and popover chrome.
- Check `Views/Popover/SettingsPopover.swift` first for settings UI and preference bindings.
- Prefer focused fixes in the owner above before adding new types.

## Dependencies

The app currently uses Apple frameworks only. Do not add dependencies unless the standard frameworks cannot reasonably cover the task.
