# PR Guidelines

## Summary

Describe the user-visible change and the files or flows touched.

## Checks

Include the exact command run, usually:

```sh
xcodebuild -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug build
```

Also list manual checks for menu-bar, popover, WebKit, notification, hotkey, or launch-at-login changes.

## Review Focus

- State ownership stays in the existing controller or delegate owner.
- Preferences remain backward compatible.
- Menu-bar and popover UI remain compact and native.
- Notification, hotkey, network, and sleep/wake behavior do not regress.
- Docs are updated when setup, architecture, behavior, commands, or release process changes.

