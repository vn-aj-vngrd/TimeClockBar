# Code Structure

## Folder Layout

```txt
TimeClockBar/
  App/
  Controllers/
  Models/
  Resources/
  Support/
  Views/
    Popover/
    Web/
```

## Ownership

- `App/`: app entry point and AppKit lifecycle glue.
- `Controllers/`: stateful coordinators that publish app state to SwiftUI.
- `Models/`: small domain values shared by controllers and views.
- `Resources/`: asset catalogs and entitlements.
- `Support/`: focused non-UI helpers for platform or parsing concerns.
- `Views/Popover/`: popover screens, controls, and styling.
- `Views/Web/`: SwiftUI/AppKit WebKit bridge.

## Current Boundaries

- `TimeclockController` keeps published state, persisted preferences, polling coordination, and WebKit navigation ownership.
- `TimeclockDOMDetector` owns the JavaScript detection script and result mapping.
- `TimeclockReminderScheduler` owns notification category registration, reminder scheduling, and notification sending.
- `HotkeyFormatting` owns shortcut labels.
- `PopoverView` owns top-level popover chrome and page switching.
- `SettingsPopover` owns settings layout and preference bindings.

## Split Rules

- Split when a file has a real standalone job, not just because it is long.
- Prefer existing folders before adding new ones.
- Do not add `Services`, `Managers`, `ViewModels`, or dependency-injection layers unless there are multiple real implementations or test seams that need them.
- Keep Apple framework integrations thin and boring.

## Validation

After structural or behavior changes, run:

```sh
xcodebuild -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug build
```
