# Testing

The checking-loop regression uses `TimeclockPageRecoveryTests` and a local WebKit fixture that renders attendance controls after navigation finishes. It verifies that a pending fallback reload allows a new read, fresh state cancels recovery, failed/provisional navigations remain blocked, committed documents can be read while secondary resources load, and repeated unknown reads do not postpone the deadline. Disabled controls during hydration must not confirm clock-in/out or break state. A floating-panel fixture mirrors the publicly served Full Scale component's separate seconds span, which must parse `02:55. 45` as `02:55.45`.

`TimeclockObservationTests` also verifies that routine refresh display preserves clocked-out, active, and break states without changing the observation timestamp. Missing/old observations, backwards clock changes, ended refresh grace, and login-required state must not display cached attendance. Runtime reminder planning continues to receive the unverified `state`, never `displayState`.

The project has a hosted macOS XCTest bundle named `TimeClockBarTests`.

Automated tests cover deterministic Swift behavior, reminder planning, menu-title formatting, hotkey labels, timer math, and local WebKit DOM detection with inline HTML. Platform service flows still need manual verification because they depend on macOS services, live WebKit state, notification permissions, global hotkeys, launch-at-login, network state, and sleep/wake behavior.

Reminder delivery tests use an in-memory notification center and controlled async boundaries to verify cancellation, snooze ownership, and late callbacks. They do not demonstrate OS delivery. Planner tests cover overnight break rollover, clock-state eligibility, and second-precision break deadlines. The [implementation checklist](../plans/workday-companion-progress.md) records the current test result and outstanding platform checks.

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

## Production website boundary

The user explicitly requires Time Clock and Full Scale Report to stay usable while agents leave live attendance and reporting data untouched. Loading/read-only inspection is allowed. Tests must not clock in/out, start/end a break, enter or edit report content, use website Improve, or submit reports. Use local fixtures and the test-host preview mode to exercise those flows. General QA/release authorization is not permission to perform real actions.

The shared XCTest scheme sets `TIMECLOCKBAR_PREVIEW=1`; controller load/poll/notification methods return without touching live sites. `testTestHostNeverLoadsWebsites` verifies this boundary. Normal app launches retain ordinary website access; `--preview-today` is only an optional native UI preview.

## Local sound checks

Use `make dev APP_ARGS=--preview-today` to rebuild and reopen the Debug app with website access and automatic reminders paused. The header shows one **DEV** badge; it is compiled out of Release builds. This does not replace the installed release or publish anything.

In Debug preview, Settings → Notification Tests can explicitly send a real macOS notification after five seconds. XCTest still disables these buttons. All test messages identify themselves as tests and require no attendance/report action. Use the delay to switch to another app for a background check. Permission/sound settings, queue errors, and notification delegate feedback are visible in Settings. Queuing or reaching the notification delegate does not prove sound was audible: check macOS playback logs and ask the listener to confirm.

The sound preview button plays through AVAudioPlayer; a notification test uses UNUserNotificationCenter, the same delivery path as scheduled reminders. Keep these checks distinct. Apple requires custom notification sound files to be under 30 seconds; bundled PCM WAVs are ten seconds, with optional twenty-second overdue variants. [Apple sound requirements](https://developer.apple.com/documentation/usernotifications/unnotificationsound)

## Reliability regressions — 2026-09-10

The DOM fixtures cover incidental login text, hidden authentication content, unrelated resume text, and history times. `TimeclockObservationTests` exercises read overlap, timeout invalidation, late callbacks, retained observations, frozen timers, and break display extrapolation without advancing work totals. Delivery tests cover queue failure acknowledgement/retry, lost future requests, obsolete dated-stage removal, and sound duration preservation through snooze. Workday tests verify refresh-before-catch-up and overdue-break priority.

`TimeclockReminderEligibilityTests` connects the runtime workday planner to the in-memory notification center. It verifies early clock-in before a 14:50 shift, pending/delivered/snooze cancellation on completion, unreadable break timers and separate second-break deadlines, return-from-break eligibility, stale-state/relaunch persistence, legacy ledger decoding, and work-date boundaries. These tests confirm that next-shift clock-in and still-applicable clock-out reminders remain queued; they do not send OS notifications.

Temporary performance comparison on a 2,000-row local fixture measured mean extraction at 7.30 ms before and 1.25 ms after (20 evaluations each, same WKWebView). This measures extraction only, not end-to-end app latency, live-page classification, or full-shift energy/memory. The temporary benchmark was removed after retaining its evidence in the validation record.

Physical visual, Focus, sleep/wake, real sound receipt, and working-day gates remain unverified. Computer Use access to Time Clock Bar was not approved in this session. Automated tests still never send real notifications or load/mutate production websites.
