# TimeClockBar reliability and notification plan

Status: implemented locally, 2026-09-10; final build/test evidence is recorded in the execution checklist. Physical platform gates remain pending. The original recommendations below are retained for traceability.

## Outcome

Keep the menu-bar app responsive, show trustworthy attendance status, recover automatically from temporary failures, and deliver useful reminders with short sounds and limited escalation. Preserve Today, Time Clock, Report, saved settings, and existing sessions.

Recommended order: establish a reproducible baseline → fix observation and recovery → harden reminder delivery → shorten sounds and expose notification health → validate on a real Mac.

This consolidates the current reliability work. It builds on [reminder policy](../product/reminders.md) and [the existing delivery checklist](workday-companion-progress.md). Timing and sound choices below are proposed defaults, not confirmed employer policy.

## What the inspection establishes

The installed bundle at `~/Applications/Time Clock Bar.app` reports version 1.2.1. The checkout is at `31abc6e`. Process inspection was unavailable in this session, so the running binary and the reported live lag/status switching have not been verified. Findings below describe source behavior and risks, not a reproduced diagnosis of the user's incident.

| Area | Current evidence | Implication for the plan |
|---|---|---|
| Frequent page work | `TimeclockController.pollingInterval` is one second. `TimeclockDOMDetector` reads whole-page text and can traverse `body *`. | Measure page extraction and UI cost; replace repeated broad scans with scoped observation. |
| Ambiguous login detection | Any matching login text takes priority over attendance controls. Break detection also uses broad words such as “resume”. | Confirm the actual visible login form or authentication redirect; validate attendance controls in their relevant container. |
| Overlapping reads | `readTimeclockState` has a navigation-generation check but no in-flight guard for reads within the same generation. | Allow one read at a time, bound its wait, and reject outdated results. |
| Misleading freshness | `lastRefreshedAt` changes after a successful JavaScript call, before validating the detection. A running timer unchanged for 120 seconds becomes stale. | Separate page-read time, valid attendance evidence, and estimated display time. A ticking page is not proof of a fresh server response. |
| Recovery gaps | Navigation failure blocks reads until navigation succeeds. Wake/reconnect reloads exist; there is no content-process termination handler or bounded retry policy. | Add deliberate recovery for failed navigation, hung reads, and WebKit termination. |
| Overtime retry loss | `handleOvertimeNotification` persists its daily “notified” flag before attempting notification delivery. | Commit queue success only after the notification center accepts the request; a failure must remain retryable. |
| Queue history vs receipt | Workday stages are recorded when queued and used to suppress past stages. | Reconcile persisted history with actual pending/delivered requests, cancellation, snooze, and wake recovery. Queueing must not mean attendance completion or heard audio. |
| Long sounds | All kinds select the same family of named WAV assets; the inspected `urgent.wav` is 29 seconds. The existing release record reports the same duration for all five. | Package short sound variants and verify every asset before release. |
| Two overtime meanings | The immediate overtime path uses hours worked; clock-out checkpoints use scheduled shift end. | Separate “past shift end” from “hours target reached” and prevent overlapping alerts. |

## 1. Accurate status with less background work

- Capture sanitized local fixtures for active, clocked out, on break, actual login expiry, incidental login text, incomplete navigation, and stalled timers. Reproduce the reported transitions and obtain a performance baseline before choosing fixes.
- Prefer verified, scoped selectors and visible controls. Confirm whether a supported read-only attendance endpoint is available; do not assume one exists. Any later endpoint integration must preserve the website's authentication rules.
- Keep the last valid attendance observation separately from connection and authentication health. Display, for example, “Last known: working · Reconnecting” with its timestamp. When verification expires, make uncertainty prominent and stop current-state assertions.
- Show “Sign in required” only with positive authentication evidence. A transient error, hidden login link, or loading page must not mark the user signed out or complete a checkpoint. Notify once per confirmed expiry episode, resetting only after confirmed authentication recovery.
- Replace full-page extraction every second with scoped, debounced page-change observation plus a fallback read. Start evaluation with a 10–15-second fallback and immediate reads after navigation, app opening, wake, and reconnect; tune using measurements. An observer alone cannot guarantee hidden WebKit activity.
- Tick the visible timer locally from timestamped evidence. Mark extrapolated values as estimates when necessary; do not advance remote freshness just because the display ticks. Re-anchor after sleep or clock changes.
- Publish only changed display values and update only the views that need a timer tick. Preserve the current compact native UI.
- Detect changes made elsewhere using an actually refreshed source. Reading unchanged DOM repeatedly is insufficient. Evaluate a supported read endpoint or safe Time Clock refresh when no interaction is in progress; document the achievable cross-browser detection delay.

## 2. Automatic recovery and staying active

Recommended default: remain responsive while macOS is awake, allow normal Mac sleep, and recover on wake. An optional “Prevent idle sleep during this shift” setting is a separate preference under consideration, disabled by default.

- Use one serialized observation/recovery path, a read timeout, and capped retry backoff. Proposed retry delays: 2, 5, 15, then 60 seconds, paused while offline. Successful verification resets backoff; confirmed login expiry waits for sign-in rather than repeatedly reloading.
- Handle WebKit content-process termination using the navigation delegate. Attempt a safe recovery, retain session storage, and expose a retry action if recovery fails. [Apple delegate API](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webviewwebcontentprocessdidterminate(_:))
- Reconcile on launch, wake, network recovery, fresh attendance evidence, schedule edits, and significant clock/timezone changes. Refresh before creating app-controlled catch-up alerts; if refresh fails, use neutral “Check Time Clock” wording.
- Preserve the existing persistent WebKit data store. Do not clear cookies as a recovery strategy. Server-expired sessions still require legitimate sign-in.
- Limit automatic reloads to safe Time Clock navigation; never reload an in-progress Report form or replay an attendance request. Do not recreate WebViews merely to update native status.
- Measure App Nap behavior before introducing activity assertions. If justified, scope an activity to the work that needs it and release it on success, failure, cancellation, or shift end. Apple distinguishes background maintenance from user-initiated activity and provides options that allow idle sleep. [Apple activity guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html)
- If the optional idle-sleep setting is chosen, show its active state, preserve display sleep, provide a stop control and bounded expiry, and release it when disabled or the shift ends. It is not a guarantee against explicit sleep, lid closure, shutdown, or server logout.

## 3. Reliable native notifications

Use macOS Notification Center banners, history, sound, and actions as the primary delivery surface. The app already uses local notifications; reliability requires fixing its state and delivery lifecycle. Once queued, macOS owns local notification delivery, including when the app is in the background or no longer running. [Apple local notification guide](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html)

True remote push through APNs additionally requires a provider service, push-enabled app identity, and device-token registration. For attendance-aware push while the Mac is offline, that service would also need a supported source of current attendance data. None is established in this repository. Treat APNs or phone delivery as a separately scoped follow-up if required; it cannot repair incorrect local attendance evidence by itself. [Apple provider setup](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server), [app registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)

- Keep the existing dated shift/checkpoint model and serialized notification-center boundary. Avoid a second competing scheduler.
- Track planned, queued, failed, canceled, and observed-delivered outcomes distinctly. Only successful additions consume a queue reservation; failures retry with limits. Neither queue success nor a notification click means the attendance action is done.
- Repair overtime's early success flag and reconcile the older per-day flag during migration so an unverified historical flag cannot silently suppress a current eligible alert. Avoid replaying an entire historical backlog.
- Compare desired dated requests to actual pending requests by event identity and content. Apply differences instead of resetting unchanged timers. Preserve snooze deadlines and source ownership through restart and schedule revision.
- Test pending-request loss and cancellations after queue success. If a past stage lacks delivery evidence, refresh and choose at most one useful catch-up within the remaining budget; absence from Notification Center does not prove a notification was never shown.
- Cancel pending and obsolete delivered notices when fresh evidence completes the checkpoint. Silence and snooze persist for the correct shift and break session and do not create extra repeat budgets.
- Queue a bounded horizon, initially the existing two-shift horizon. If the app stays quit beyond that horizon, coverage ends until it runs again; make that limitation visible and retain launch-at-login support.
- Prequeued alerts use absolute deadlines and neutral copy, such as “Check your break return · Due 20:45”. A terminated app cannot revalidate attendance before local delivery. With fresh evidence while running, the app can show precise overdue wording.
- Prefer an active break return over a simultaneous wrap-up alert. Combine or defer competing messages; use one audible alert at an instant and discard obsolete advance reminders after wake.

## 4. Proposed reminder and sound policy

| Event | Initial reminder | Follow-up while still actionable | Sound proposal |
|---|---|---|---|
| Clock in | Saved advance lead, then shift start | +5 and +15 minutes | 10 seconds maximum |
| Planned break | 5 minutes before, then due | +5 and +15 minutes | 10 seconds maximum |
| Return from break | 5 minutes before when appropriate, then exact return deadline | +2 and +5 minutes | 10 seconds by default; optional 20 seconds for overdue stages |
| Clock out / past shift end | Saved advance lead opens Report; shift-end alert opens Time Clock | +5 and +15 minutes | 10 seconds by default; optional 20 seconds for overdue stages |
| Hours target reached | Quiet Today/menu-bar information | No separate repeating alarm | Silent by default; preserve an explicit existing preference as one bounded alert, coalesced with clock-out |
| Verified login expiry | One “Sign in to restore status” notice | Persistent visible issue, no repeating alarm | Short system sound |

Keep the current maximum of one advance and three due/follow-up stages per checkpoint. Stop after completion or silence; after the final stage, retain a visible overdue indicator. Days off stay quiet unless an actual shift or break remains relevant. Calculate overnight shifts and deadlines in the saved work timezone; do not use the device's current weekday to decide whether an overnight shift is over.

Sound duration is an upper bound on the packaged clip, not a promise of uninterrupted playback: macOS presentation and user dismissal can shorten it. Custom notification sounds must be under 30 seconds. Preserve tone selections while migrating to short variants; do not layer independent app playback over system notification audio. [Apple sound requirements](https://developer.apple.com/documentation/usernotifications/unnotificationsound)

Expose Open Time Clock/Report and Snooze 5 min as the primary notification actions. Keep Silence this checkpoint readily available in the popover. Silence cancels future audible stages; verify what the OS permits for stopping an already playing system sound rather than promising the app controls it.

Offer opt-in Time Sensitive delivery for immediate attendance deadlines after verifying macOS support and app configuration. Users can disable this interruption level, and Focus remains user-controlled. Do not use Critical Alerts for routine work reminders. [Apple Time Sensitive behavior](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive)

Add a compact notification health area in existing Settings: permission, sound setting, last reconciliation, next actual queued reminder, last failure, and a labeled test notification available in Release. Report “Queued with macOS” separately from “Sound heard”; confirm receipt with the user during manual testing.

## 5. Implementation sequence and release gates

Implemented: scoped detection and event bridge, serialized reads, timeout/backoff recovery, last-known status, local timer extrapolation, bounded active-session activity allowing sleep, safe hidden-page refresh, queue acknowledgement/retry, obsolete-stage cleanup, overdue-break priority, short sounds and optional longer overdue sounds, silence/resume, and queue diagnostics.

Time Sensitive mode was attempted but Xcode rejected the capability under the current local signing configuration: a development certificate is required. It is deferred, and no unsupported option is exposed. Remote APNs and forced idle-sleep prevention remain outside the recommended default. Live cross-browser accuracy, popover latency, memory/energy, native visual inspection, Focus, sleep/wake, and heard audio require platform validation; they are not claimed complete.

1. **Reproduction and measurement.** Verify the running build; capture relevant read-only evidence; reproduce false login, stalled reads, and queue failure with fixtures/fakes. Measure popover latency, extraction time, CPU, memory, and energy with the popover open and closed. Record before/after measurements under identical conditions.
2. **Status and recovery.** Change `TimeclockDOMDetector`, `TimeclockController`, and lifecycle handling in `AppDelegate` within their current ownership. Introduce only the small state/observation test seam needed to exercise asynchronous reads and recovery. Preserve last known status without claiming it is current.
3. **Reminder correctness.** Update `WorkdayReminderController`, `TimeclockReminderDelivery`, and `TimeclockReminderScheduler`; fix queue acknowledgement, lost requests, snooze/restart behavior, and overlapping overtime semantics. Extend the existing tests at the real call boundary.
4. **Sound and settings.** Package and verify short assets, preserve selections, add optional longer overdue sounds, and expose notification health/test controls in existing Settings. Update product and architecture docs, including the outdated architecture paragraph describing runtime schedules as weekly.
5. **Validation.** Run the full suite and build; complete the real-Mac matrix before claiming reliability. Record results and leave unobserved platform gates unchecked in the existing checklist.

Proposed measurable acceptance targets, to be tested rather than represented as existing results:

- Warm popover response below 250 ms at the 95th percentile; local visible action changes reflected within 2 seconds under healthy conditions.
- At most one page extraction in flight; no routine whole-page scans every second; lower measured idle work than the baseline and no steady memory growth during a representative shift.
- Navigation failure, invalid DOM, or incidental login text cannot erase valid attendance history or produce a false login alert in fixtures.
- After wake/reconnect, either recover valid observation within 30 seconds under healthy server conditions or show a clear unavailable state with the last valid timestamp and a retry path.
- A failed notification add remains retryable. Completion cancels the checkpoint and its snooze. Restart and wake produce no duplicate cascade or renewed repeat budget.
- Break deadlines preserve seconds; multiple breaks, duration edits, overnight shifts, day-off boundaries, and timezone changes retain correct identity and eligibility.
- Cross-browser changes are verified against refreshed source data; measure and disclose the actual detection delay before declaring this reliable.
- Physical tests cover foreground/background, hidden popover, Focus allowed/blocked, sound disabled, denied permission, offline/reconnect, sleep/wake, quit/relaunch, and notification actions. Record scheduled time, OS evidence, and user-heard audio separately.

Planned commands:

```sh
xcodebuild test -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug -destination 'platform=macOS'
xcodebuild -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug build
make test-version
git diff --check
```

Behavioral tests use local fixtures and the preview test host. Real labeled notification tests are a later explicit sound-check step. No test may clock in/out, start/end a real break, edit Report, invoke Improve, or submit a report. Manual working-day observation can accompany actions the user independently performs.

## Planning verification

Inspected current source, product/reminder specifications, existing tests, installed version metadata, one current sound asset, and Apple platform documentation. Historical release evidence guides the pending platform checks but does not prove current behavior. No app build or XCTest run was performed because this increment changes documentation only; implementation and incident reproduction remain future work.

### Implementation evidence and limits

Three new DOM regressions failed against the original implementation and passed after the scoped-control fix. An obsolete dated-stage regression also failed before its delivery fix. The extraction benchmark measured 7.30 ms before and 1.25 ms after on the same 2,000-row fixture (20 evaluations each). Routine fallback reads moved from one to ten seconds; explicit control events still request prompt observation.

Source freshness means a valid page observation, not confirmation of server receipt. Hidden-page refresh runs approximately every sixty seconds while there is no edited/focused input; visible pages are not periodically reloaded. A sixty-second refresh is therefore not an unconditional cross-browser freshness guarantee. Server-expired sessions still require sign-in. Existing queue reservations conservatively prevent replay of stages that may already have been presented; an absent delivered notification does not establish that it was never heard.

The installed app was not replaced and no release was published in this implementation increment. See the execution checklist for the final local build path and remaining platform gates.
