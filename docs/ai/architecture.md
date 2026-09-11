# Architecture

Clock-page reload backoff is owned by `TimeclockPageRecovery`. A queued reload must not block reads: the site's attendance controls render asynchronously. Read the new document after commit even if secondary resources are still loading; provisional/failed navigations cannot reuse the previous document. A fresh verified observation cancels both the fallback reload and navigation watchdog. Unknown content gets at least thirty seconds to render while reads continue. Disabled attendance controls do not establish completion during session hydration. `ClockMonitoring` logs recovery transitions without page content, account identifiers, or timer values.

Routine refreshes separate presentation from verification. `state` becomes unverified immediately and remains the sole input to reminder decisions. The menu bar and Today use `displayState`, which may preserve the last confirmed attendance during a healthy refresh for at most thirty seconds from the original observation. The popover labels this “Refreshing”; source freshness is never advanced by displaying cached state. Login, navigation/read errors, offline/sleep, or expiry end that display grace immediately. A retry after an actual failure cannot revive cached attendance. A known but unverified status is labeled “Unavailable,” rather than an endless “Checking.”

Time Clock Bar is a single-target macOS SwiftUI app with AppKit integration for menu-bar behavior.

## Main Flow

- `App/TimeClockBarApp.swift` starts the app and installs `AppDelegate`.
- `App/AppDelegate.swift` owns app lifecycle, `NSStatusItem`, popover setup, global hotkey registration, network and sleep monitoring, and right-click menu actions.
- `Controllers/TimeclockController.swift` owns published app state, WebKit navigation, polling coordination, launch-at-login state, and persisted preferences.
- `Support/TimeclockDOMDetector.swift` owns the JavaScript extraction contract and DOM detection payload.
- Recorded action history comes from bounded time-log cards, using their separate timestamp spans because the range arrows are SVG. Only break/work type and start/end text cross the bridge; client names are excluded. Where the site displays two timezone pairs, the local pair is selected along with the browser timezone. `TimeclockAttendanceHistory` resolves newest-first ranges within the selected shift and rejects inconsistent state, dates, or bounds.
- The website unmounts history when its details panel closes. Hidden-page reads may open its exact Time Clock navigation launcher after reload, with input protection, an already-open metrics check, and a 15-second debounce. Visible pages are left under user control; attendance and report buttons are never invoked.
- Break observations use the counter immediately following “You are on a break,” including seconds in a separate span. The Current work metric is never a break-time fallback. The detector also maps its payload to authoritative clock state; unavailable break elapsed time renders Break without a fabricated work timer.
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

Snoozes carry a stable source identifier in OS notification metadata. Runtime schedules use dated checkpoints over the next two shifts, with persisted completion, silence, and queue reservations. Reconciliation removes obsolete dated stages and preserves eligible snoozes. The weekly planner is retained only for existing policy regressions. Queue success is not delivery or attendance completion.

`TimeclockObservation` bounds page reads to one in flight, rejects results invalidated by navigation/recovery, and retains the last valid attendance observation separately from unavailable/login state. `TimeclockController` performs fallback extraction every ten seconds and receives debounced visible-control changes through a weak WebKit message handler. Native one-second display estimates use timestamped observations and never refresh source timestamps. Menu-bar titles use a dedicated Combine subject so their ticks do not publish changes to the whole popover.

While a fresh work session is observed, a scoped `ProcessInfo` activity prevents App Nap while allowing idle system sleep. It ends on unavailable status, logout, clock-out, or polling stop. The native watchdog handles ten-second read timeouts, thirty-second navigation timeouts, and content-process termination with capped retries. Hidden Time Clock pages get a safe overview GET approximately every sixty seconds, unless input has been edited or a field is focused. Report is never part of this refresh path. Visible pages continue observation without disruptive periodic reloads; changes from another browser are not guaranteed current until remote refresh.

Reminder queue acknowledgements reach the caller only after successful notification-center addition. The hours-target budget uses `overtimeQueued.v2.<work-date>` instead of the old flag written before scheduling. Failed attempts retry at most once a minute while eligible. Existing explicit hours-target preferences remain; new installs default to a quiet target indicator. Past scheduled shift end is a separate status indicator.

All ordinary sounds are ten seconds; `longOverdueSounds` selects twenty-second assets only for overdue break-return and clock-out stages. Snoozes retain sound duration and ownership. Settings shows actual queued timing and reconciliation status. Time Sensitive capability remains deferred because the current local signing configuration lacks a development certificate.

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

TodayDashboard projects the current or next shift independently of the reminder engine's four-hour recovery window. Confirmed clock-out advances the displayed schedule immediately; checkpoints are filtered to that displayed shift ID. An unfinished overnight shift stays associated with its start date across midnight. The controller's existing ledger also retains an optional first clock-out observation timestamp and publishes the most recent completed work date for a compact previous-shift summary, including after restart. Legacy completion records remain readable without inventing a timestamp.

The previous-shift summary checks its report using the user-confirmed website prerequisite that a report must be filed before clock-out. The next shift's report stays pending. Opening Report alone never completes it. Dashboard projection never changes authoritative clock state or reminder eligibility.

`TimeclockObservationLabel` formats the existing successful-read timestamp for Today's compact footer. It consumes authoritative status, refresh state, current time, and the work timezone, with full details available through native help and accessibility. It does not mutate observation history, timers, polling intervals, or reminder state. Missing observations never receive a fabricated timestamp; failed reads and routine refreshes retain the last successful one.

Successful clock observations also pass recorded history into the workday ledger. Optional Codable attendance timestamps preserve upgrade compatibility and survive refresh/restart. Checkpoints retain planned `due` values for policy and separate `actualDate` values for completed-row display. History can restore a completed break observed after returning to work; logged-out history alone cannot establish an unobserved work session. A recorded break start can correct the return deadline in either direction; the more precise elapsed-counter anchor is retained within one displayed minute. Date changes reconcile reminders immediately through the existing serialized delivery path.
