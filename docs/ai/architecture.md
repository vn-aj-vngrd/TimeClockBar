# Architecture

Time Clock Bar is a single-target macOS SwiftUI app with AppKit integration for menu-bar behavior.

## Main Flow

- `App/TimeClockBarApp.swift` starts the app and installs `AppDelegate`.
- `App/AppDelegate.swift` owns app lifecycle, `NSStatusItem`, popover setup, global hotkey registration, network and sleep monitoring, and right-click menu actions.
- `Controllers/TimeclockController.swift` owns published app state, WebKit navigation, polling coordination, launch-at-login state, and persisted preferences.
- `Support/TimeclockDOMDetector.swift` owns the JavaScript extraction contract and DOM detection payload.
- `Support/TimeclockReminderScheduler.swift` owns notification categories, reminder scheduling, snooze/test notifications, and legacy reminder cleanup.
- `Support/TimeclockReminderDelivery.swift` owns serialized notification-center operations, schedule revision checks, and source-owned snooze reconciliation; its notification-center protocol provides the deterministic test boundary.
- `Support/HotkeyFormatting.swift` owns keyboard shortcut labels.
- `Views/About/AboutView.swift` renders open-source app identity, repository link, and bundle version/build metadata.
- `Views/Popover/PopoverView.swift` renders the popover chrome, embedded pages, page switching, fixed popover shortcuts, and settings popover entry point.
- `Views/Popover/SettingsPopover.swift` renders settings UI and binds preferences into `TimeclockController`.
- `Views/Popover/PreferenceRows.swift`, `HotkeyRecorderButton.swift`, `IconButton.swift`, and `PopoverStyle.swift` contain focused popover UI components and styling.
- `Views/Web/WebView.swift` wraps a shared `WKWebView` for SwiftUI.
- `Models/TimeclockState.swift` contains status and menu-title domain types.

## State And Persistence

Runtime state is exposed from `TimeclockController` with `@Published` properties. User preferences are stored in `UserDefaults` with static key constants in the controller.

Snoozes carry a stable source identifier in OS notification metadata. Reconciliation cancels state-ineligible requests and preserves applicable neutral snoozes while clock state is unverified. Base schedules still use weekly triggers; the dated checkpoint model and persisted completion/escalation budgets are upcoming work in the [implementation checklist](../plans/workday-companion-progress.md).

## External Integrations

- WebKit loads the time clock and daily report pages.
- UserNotifications schedules local reminders and action buttons.
- ServiceManagement controls launch at login.
- Carbon registers the global hotkey.
- Network and workspace notifications pause polling when offline or asleep.

Keep new behavior in the smallest owner that already controls the related state, lifecycle, UI, or platform integration.

## Workday and report ownership

`WorkdaySchedule` resolves wall-clock preferences to dated shifts in a saved timezone. `WorkdayReminderController` persists observed checkpoint completion, silence, and notification-stage reservations in a versioned UserDefaults ledger. `TimeclockReminderScheduler.schedule` uses this dated runtime model; its original `plans` helper remains covered by legacy policy regressions but is not the runtime schedule. `TimeclockReminderDelivery` serializes OS changes and marks successfully queued stages. Queueing does not prove presentation or attendance completion.

TodayDashboard selects the next destination from local clock/schedule values. TodayView is the native dashboard; Time Clock and Report remain existing WebKit destinations. There is no native draft or AI subsystem. The `--preview-today` launch option and test-host preview environment disable website loading and notification scheduling.
