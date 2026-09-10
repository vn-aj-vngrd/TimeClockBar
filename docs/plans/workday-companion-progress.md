# Implementation checklist

Scope corrected on 2026-09-05: **Today · Time Clock · Report**. The earlier native draft/AI phases are superseded, not completed. See [the current plan](workday-companion.md).

## Current work

Reliability implementation — 2026-09-10: [status, performance, recovery, and notification plan](reliability-2026-09-10.md). Implemented locally with passing fixture regressions and an extraction benchmark. See the latest validation record below; native visual and physical notification gates remain pending. Earlier checked items describe the previous release.

- [x] Remove the native report editor, draft/AI/export/archive implementation from the app; leave previously saved local data untouched.
- [x] Replace the page menu with three visible tabs; preserve website shortcuts and add Cmd-0 for Today.
- [x] Add dashboard routing for day off, working, break return, and report-before-clock-out.
- [x] Route advance clock-out notifications to Report; retain attendance routing at the clock-out deadline.
- [x] Add a website-free preview and configure the XCTest host to use it.
- [x] Pass the final unit suite and native Saturday preview check.
- [x] Build and verify the Release package and bundled notification resources.
- [x] Commit, push, and verify hosted CI.
- [x] Publish the internal version, install locally, and open Today with normal website access.

## Verification record

2026-09-10 planning increment: inspected current observation/recovery and reminder code, existing tests, installed bundle version metadata (1.2.1), a current 29-second sound asset, and Apple documentation. Added the proposed reliability plan without changing application behavior. No build or XCTest run for this documentation-only increment; no real notification or website action performed. Running-process inspection was unavailable, so the running binary and reported incident are unverified.

The prior reminder slice passed 81 tests. The broader experimental implementation reached 98 tests before scope was corrected; removed draft/AI tests are not evidence for the simplified product. Final counts and release evidence are recorded below after verification.

Automated verification uses local fixtures and the native shell. The user clarified that normal website access and read-only inspection are allowed; tests must never operate attendance controls or enter/edit/submit reports. This rule is persisted in AGENTS.md and docs/ai/testing.md. No real attendance or report action is performed.

## Follow-up validation

Physical Focus/sleep/wake notification presentation and ordinary working-day use still require real conditions. Full Scale remains the authority for report submission. The app does not claim a report receipt or automatically perform clock actions.

### Simplified flow validation — 2026-09-05

- `xcodebuild test -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/TimeClockBarSimple`: 95 tests passed, zero failures/skips. The suite includes day-off/no-clock-in CTA, break priority, report-first routing, and a test proving the test host cannot load either website.
- `make test-version` and `git diff --check` passed.
- Native preview showed the three visible pages and Saturday's “No shift today” state with Monday's next shift. No primary clock-in action was shown. Website controls were not operated.
- Agent safety guidance is saved in AGENTS.md and the testing guide. Normal app launches retain website access.

### Released — 2026-09-05

- Release commit: `57f41d6153dc56af82d9d4cd37d02d6534802ebe`; tag `v1.2.0`; build 27.
- [Hosted CI passed](https://github.com/vn-aj-vngrd/TimeClockBar/actions/runs/33951857741), including XCTest on macOS 26.
- `make package verify VERSION=1.2.0` passed. All five named WAV resources are bundled; the package signature is valid. Minimum OS is 26.0.
- `make install-local VERSION=1.2.0` installed and opened `~/Applications/Time Clock Bar.app`. Installed executable matches the verified build. The previous local app is retained in `dist/TimeClockBar-previous-local.zip` when present.
- Native AX/screenshot verification of the installed Release app showed Today, Time Clock, Report; Saturday's no-shift message; the next Monday shift; and normal website access (no preview restriction). No website controls were operated.
- [Published internal release](https://github.com/vn-aj-vngrd/TimeClockBar/releases/tag/v1.2.0). Asset SHA-256: `cd22981f95957e2882c882289455564bcff7c91a5ae7f7cc400620b7cf8cf83c`; GitHub's uploaded asset digest matches the local zip.
- The release uses local signing, not Developer ID notarization. Physical notification behavior under Focus and sleep/wake remains follow-up validation; no live attendance/report action was used as a test.

### Development iteration — sound verification and settings polish (2026-09-05)

User direction: keep iterating in Debug; do not publish, push, or replace the installed release in this round.

- [x] Replace the centered, width-constrained Work timezone picker with the existing trailing settings menu; preserve its accessible label and selected value.
- [x] Show a single DEV chip in Debug headers, including Settings. Remove the redundant Preview chip; preserve the paused-website message in page content.
- [x] Enable explicit, labeled, five-second notification tests in Debug preview while retaining XCTest's real-notification guard and disabling automatic reminders/websites.
- [x] Surface manual notification queue failures and denied permission. Regression test reproduced a swallowed error before the fix.
- [x] Run the full hosted suite: 97 passed, zero failures/skips (`/tmp/TimeClockBarSoundTests/Logs/Test/Test-TimeClockBar-2026.09.05_15-32-18-+0800.xcresult`).
- [x] Verify all five bundled WAV files: 29 seconds, mono, 16-bit PCM, nonzero RMS.
- [x] Exercise real local notification delivery: macOS logged playback of pulse.wav (15:26:44), urgent.wav (15:29:03), and siren.wav (15:30:17). The user explicitly confirmed hearing Pulse.
- [x] Background check: send Over Break, activate Finder and verify Finder is frontmost before the five-second delay expires. macOS logged urgent.wav playback at 15:34:34. This establishes OS playback; listener confirmation is recorded separately if supplied.
- [x] Make `make dev APP_ARGS=--preview-today` rebuild, quit the prior running app, and open the fresh Debug binary. It does not install or publish a release.

Evidence limits: macOS stopped one sound when the banner closed after roughly five seconds. The test verifies ordinary awake-device delivery under current settings, not Focus/sleep/wake coverage or the cause of a historical missed reminder. No live attendance/report control was operated. Queue feedback and notification delegate callbacks are not evidence that audio was heard.

Final native verification: rebuilt through `make dev APP_ARGS=--preview-today`, confirmed the running executable is the repository Debug app, and inspected screenshots of Today and Settings. Only DEV remains in the header. Asia/Manila is aligned at the trailing edge alongside the other settings menus. `git diff --check` passed. Changes remain local and uncommitted; the installed v1.2.0 release is unchanged.

### v1.2.1 release — authorized 2026-09-05

The user has now authorized committing all changes, pushing, publishing, installing the new release, and removing older app copies. This supersedes the development-only restriction above.

- [x] Commit and push the sound diagnostics and settings fixes.
- [x] Re-run release tests and verify the package and hosted CI.
- [x] Publish v1.2.1, install it, and open the normal Release app.
- [x] Keep only the latest installed app; move old and duplicate bundles to Trash without deleting user data.

Release verification:

- Release commit `ba9c6a3205106574cf571d094f34a2e38e4658cc`, tag `v1.2.1`, build 29.
- Local release validation: 97 tests passed, zero failures/skips; version-script checks and signature verification passed. Release executable omits the DEV label; all five sound resources are bundled and under 30 seconds.
- [Hosted CI passed](https://github.com/vn-aj-vngrd/TimeClockBar/actions/runs/33959776313).
- [Published v1.2.1](https://github.com/vn-aj-vngrd/TimeClockBar/releases/tag/v1.2.1). Uploaded archive SHA-256 matches the local artifact: `df7f9a6dde1b56aaa9ad305d3ab206a5f3add9efd3d1fee2d5f6aaab20954755`.
- Installed and signature-verified `~/Applications/Time Clock Bar.app`; its executable matches the packaged Release build. Native inspection confirms normal Today, Time Clock, and Report navigation with no DEV/Preview label. No website controls were operated.
- Moved four app bundles to Trash: previous installed v1.2.0, repository Debug, temporary XCTest host, and duplicate Release build. Only the installed v1.2.1 app remains in the inspected app/build locations. Settings, sessions, and local data were preserved; the current release zip is retained.

### Reliability implementation — 2026-09-10

- [x] Reproduce incidental-login, unrelated-resume, and history-timer classification failures against the original detector; fix with scoped visible-control extraction.
- [x] Add debounced page-control observation, ten-second fallback reads, single-flight tokens, timeout invalidation, and capped navigation/content-process recovery.
- [x] Keep last-known attendance separate from unavailable state; estimate display seconds without resetting minute-only timers or advancing observation freshness.
- [x] Isolate menu-bar ticks from popover publication and bound active-session activity while allowing normal Mac sleep.
- [x] Refresh hidden Time Clock pages by safe GET, preserving edited/focused input and leaving Report untouched.
- [x] Reproduce/fix obsolete dated-stage retention and delayed-authorization catch-up scheduling. A dated catch-up now remains schedulable if authorization outlasts its original fire time.
- [x] Acknowledge successful queue additions before consuming the hours-target budget; retry failures, preserve snooze sounds, and prioritize an overdue break over simultaneous clock-out.
- [x] Add ten-second sound assets, optional twenty-second overdue variants, actual queue timing in Settings, and checkpoint silence/resume controls.
- [x] Pass 114 tests, zero failures, in `/tmp/TimeClockBarReliability/Logs/Test/Test-TimeClockBar-2026.09.10_23-20-53-+0800.xcresult`.
- [x] Pass version-script and whitespace checks. Version-script fixtures ran with commit/tag signing disabled only in that command's environment because global GPG signing was unavailable in the sandbox; repository signing preferences were unchanged.

Performance evidence: the same 2,000-row WKWebView fixture averaged **7.30 ms before / 1.25 ms after**, twenty detector evaluations each. The retained benchmark attachment is `/tmp/timeclock-benchmark-attachments/AA3FB2BB-0467-427F-9200-FF7FD452CCDB.txt`; the temporary comparison test was removed. This is a detector benchmark, not a full-app latency or energy claim.

Remaining gates:

- [ ] Native visual/interaction inspection, blocked because Computer Use access to Time Clock Bar was not approved.
- [ ] Real notification receipt/audio, foreground/background and Focus combinations, sleep/wake and quit/relaunch presentation.
- [ ] Authenticated live-page classification, cross-browser detection latency, warm popover timing, and a representative shift's memory/energy use.
- [ ] Optional Time Sensitive capability: Xcode requires a development signing certificate absent from the current local signing configuration. Standard local notifications remain available; no unsupported setting is exposed.

No production attendance/report controls were operated, no real notification test was sent, and the installed application was not replaced or published. Source changes remain local and uncommitted.

Final local build verification:

- [x] Release build completed successfully with the repository-computed version **1.2.1, build 30** (a local modified build, not a new published release).
- [x] `codesign --verify --deep --strict` passed; all ten bundled WAV assets were verified at their expected ten/twenty-second durations.
- Built app: `build/TimeClockBarReliability/Build/Products/Release/Time Clock Bar.app`.
- Final build log: `/tmp/timeclock-reliability-release.log`; final tests: `/tmp/timeclock-reliability-final-tests.log`.

### Attendance-state reminder follow-up — 2026-09-10

- [x] Reproduce early clock-in failure with a 12:00 observation before a 14:50 shift: pending alerts, snooze, delivered notice, and relaunch completion assertions failed before the fix.
- [x] Associate early attendance with the selected work date, preserving the pre-midnight window and the next shift's reminders.
- [x] Reproduce unreadable on-break timer failure: break-start reminders and snooze remained eligible. Persist break-start confirmation separately from its timer; retain known deadlines and give later breaks their own session identity.
- [x] Verify already clocked-out and returned-from-break cancellation through the runtime planner and fake notification center, including obsolete banner snooze actions and completion after restart.
- [x] Add ten regression tests covering state eligibility, 14:50 timing, unreadable/second breaks, legacy history, stale observations, off days, and midnight boundaries.
- [x] Full XCTest suite: **124 passed**, zero test failures. Result: `/tmp/TimeClockBarReliability/Logs/Test/Test-TimeClockBar-2026.09.10_23-33-49-+0800.xcresult`; log: `/tmp/timeclock-state-eligibility-full-tests.log`.
- [x] Release rebuilt at the same local **1.2.1, build 30** path above; signature and whitespace checks passed. Build log: `/tmp/timeclock-state-eligibility-release.log`.

The installed app remains unchanged. Completion-aware cancellation requires a fresh observation while the app runs; the existing physical notification/Focus/sleep-wake gates remain pending. No real notifications or production website actions were used by these tests.

### Version 1.2.2 local release and installation — 2026-09-10

- [x] Commit and push the reliability changes: `04af3cef94e7969e38576a86000027b1e2a65144` on `main`.
- [x] Resolve the new version through conventional commits: **1.2.2, build 31**.
- [x] Pass version-script checks and the committed release's full local XCTest suite: **124 passed, zero failures/skips**. Result: `~/Library/Developer/Xcode/DerivedData/TimeClockBar-dddcpniyqsyqsfdzpmslfbqiedme/Logs/Test/Test-TimeClockBar-2026.09.10_23-36-25-+0800.xcresult`.
- [x] Hosted CI build/test step passed for the release commit: [run 34496852246](https://github.com/vn-aj-vngrd/TimeClockBar/actions/runs/34496852246).
- [x] Build and signature-verify `dist/TimeClockBar-1.2.2-internal.zip`. SHA-256: `84e3ffbcaf019d6f05f118a54b6dcddd252aef566c3ab702315ad0a9c3dcec35`. Verify version/build metadata and all ten sound resources in the archive.
- [x] Quit the old app before replacement; install and open `~/Applications/Time Clock Bar.app` normally with Today visible requested. Confirm running executable path, installed version/build, valid signature, and executable equality with the packaged Release build.
- [x] Replace the installed 1.2.1 bundle, retaining the installer-created backup zip; move the two obsolete reliability/test app bundles to Trash. Settings and website data are preserved.
- [ ] GitHub Release binary publication was not performed: automatic approval review rejected dispatching the release workflow because binary publication was considered separate authorization from committing, pushing, and installing locally. The local 1.2.2 package and installation are complete.

Logs: `/tmp/timeclock-v122-tests.log`, `/tmp/timeclock-v122-package.log`, `/tmp/timeclock-v122-install.log`. Native visual/Focus/sleep-wake and listener-confirmed sound gates remain unobserved; no production attendance/report controls were operated.

### Checking-loop hotfix — 2026-09-11

- [x] Reproduce the installed failure from WebKit logs: seven reload cycles each performed only one JavaScript read. The pending reload guard blocked reading controls rendered after the initial document load.
- [x] Reproduce the same recovery-policy failure locally, then allow reads during reload backoff. Verified observations cancel fallback reloads; provisional/failed navigations still cannot reuse old documents.
- [x] Read committed documents while secondary resources load and cancel the navigation watchdog once clock state is verified. Give unknown asynchronous content at least thirty seconds to render while reads continue.
- [x] Reproduce/fix split-seconds parsing using the publicly served clock-component structure. `02:55. 45` now becomes `02:55.45`.
- [x] Reproduce/fix disabled attendance controls being treated as confirmed state during session hydration. They cannot confirm clock-out, clock-in, or break completion.
- [x] Final suite: **133 passed, zero failures/skips**. Result: `/tmp/TimeClockBarChecking/Logs/Test/Test-TimeClockBar-2026.09.11_00-12-55-+0800.xcresult`; log: `/tmp/timeclock-checking-stable-tests.log`.
- [x] Commit and push code fixes `86791f9` and `16e94f1`; install and open **1.2.3, build 34** at `~/Applications/Time Clock Bar.app`. Used explicit `VERSION=1.2.3` because the prior local 1.2.2 was not tagged/published.
- [x] Verify installed signature and package. Archive SHA-256: `6d0b4ff946ac6809d3fdf894f19c401058b3afbacf78e3e7f2710a64d809edf9`; install log: `/tmp/timeclock-v123-final-install.log`.
- [x] Verify the installed final process reports `Clock observation recovered: active` at 00:14:35 and again at 00:15:01 after a background refresh, with continuing successful reads. Evidence: `/tmp/timeclock-v123-final-runtime.log`. The earlier false clocked-out hydration transition is absent in this final observed interval.

Computer Use inspection remained unapproved; verification used user screenshots, public frontend source, local fixtures, and bounded runtime diagnostics. No production attendance/report actions were operated. These observations establish recovery from this loop, not full-shift or Focus/sleep-wake coverage. GitHub binary publication remains outside the approved release action.

### Stable status during routine refresh — 2026-09-11

- [x] Reproduce the display regression for clocked-out, active, and break states. Preserve last-confirmed presentation during healthy refreshes while keeping reminder state unverified.
- [x] Add a separate Refreshing label and retain the original last-observed timestamp. A thirty-second age limit, login expiry, offline/sleep, or actual read/navigation failure immediately ends cached presentation; known unavailable state is labeled Unavailable.
- [x] Verify that missing/old observations, a backwards clock change, ended grace, and login-required status cannot display cached attendance. Existing reminder tests continue to use authoritative state.
- [x] Full local suite: **135 passed, zero failures/skips**. Result: `/tmp/TimeClockBarChecking/Logs/Test/Test-TimeClockBar-2026.09.11_01-21-39-+0800.xcresult`.
- [x] Commit and push `d41e3d9`; build, signature-verify, install, and open **1.2.4, build 36** using explicit `VERSION=1.2.4` because the intervening local versions remain untagged.
- [x] Package SHA-256: `4a3dd96e3e1fb844b4f8e2c3ac0f86c63a6f2d0a17a5a25a7f78d72150638756`. Install log: `/tmp/timeclock-v124-install.log`.
- [x] Installed runtime recorded `Refresh keeps last confirmed display: clockedOut` at 01:24:12 and verified `clockedOut` again at 01:24:26. No unavailable transition occurred during that observed refresh. Evidence: `/tmp/timeclock-v124-runtime.log`.

Native visual inspection remains unapproved; these checks use the shared display policy and installed runtime diagnostics. No production attendance/report controls or test notifications were operated.
