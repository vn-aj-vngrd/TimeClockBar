# Architecture

Time Clock Bar is a single-target macOS SwiftUI app with AppKit integration for menu-bar behavior.

## Main Flow

- `App/TimeClockBarApp.swift` starts the app and installs `AppDelegate`.
- `App/AppDelegate.swift` owns app lifecycle, `NSStatusItem`, popover setup, global hotkey registration, network and sleep monitoring, and right-click menu actions.
- `Controllers/TimeclockController.swift` owns published app state, WebKit navigation, polling coordination, launch-at-login state, and persisted preferences.
- `Support/TimeclockDOMDetector.swift` owns the JavaScript extraction contract and DOM detection payload.
- `Support/TimeclockReminderScheduler.swift` owns notification categories, reminder scheduling, snooze/test notifications, and legacy reminder cleanup.
- `Support/HotkeyFormatting.swift` owns keyboard shortcut labels.
- `Views/About/AboutView.swift` renders open-source app identity, repository link, and bundle version/build metadata.
- `Views/Popover/PopoverView.swift` renders the popover chrome, embedded pages, page switching, fixed popover shortcuts, and settings popover entry point.
- `Views/Popover/SettingsPopover.swift` renders settings UI and binds preferences into `TimeclockController`.
- `Views/Popover/PreferenceRows.swift`, `HotkeyRecorderButton.swift`, `IconButton.swift`, and `PopoverStyle.swift` contain focused popover UI components and styling.
- `Views/Web/WebView.swift` wraps a shared `WKWebView` for SwiftUI.
- `Models/TimeclockState.swift` contains status and menu-title domain types.

## State And Persistence

Runtime state is exposed from `TimeclockController` with `@Published` properties. User preferences are stored in `UserDefaults` with static key constants in the controller.

## External Integrations

- WebKit loads the time clock and daily report pages.
- UserNotifications schedules local reminders and action buttons.
- ServiceManagement controls launch at login.
- Carbon registers the global hotkey.
- Network and workspace notifications pause polling when offline or asleep.

Keep new behavior in the smallest owner that already controls the related state, lifecycle, UI, or platform integration.
