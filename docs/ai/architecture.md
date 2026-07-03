# Architecture

TimeClockBar is a single-target macOS SwiftUI app with AppKit integration for menu-bar behavior.

## Main Flow

- `TimeClockBarApp.swift` starts the app and installs `AppDelegate`.
- `AppDelegate.swift` owns app lifecycle, `NSStatusItem`, popover setup, global hotkey registration, network and sleep monitoring, and right-click menu actions.
- `TimeclockController.swift` owns app state, WebKit navigation, polling, reminders, launch-at-login state, persisted preferences, and notification actions.
- `PopoverView.swift` renders the popover chrome, embedded pages, settings UI, and bindings into `TimeclockController`.
- `WebView.swift` wraps a shared `WKWebView` for SwiftUI.
- `TimeclockState.swift` contains status and menu-title domain types.

## State And Persistence

Runtime state is exposed from `TimeclockController` with `@Published` properties. User preferences are stored in `UserDefaults` with static key constants in the controller.

## External Integrations

- WebKit loads the timeclock and daily report pages.
- UserNotifications schedules local reminders and action buttons.
- ServiceManagement controls launch at login.
- Carbon registers the global hotkey.
- Network and workspace notifications pause polling when offline or asleep.

Keep new behavior in the smallest owner that already controls the related state or lifecycle.

