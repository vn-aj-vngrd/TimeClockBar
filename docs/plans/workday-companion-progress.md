# Implementation checklist

Scope corrected on 2026-09-05: **Today · Time Clock · Report**. The earlier native draft/AI phases are superseded, not completed. See [the current plan](workday-companion.md).

## Current work

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

- [ ] Commit and push the sound diagnostics and settings fixes.
- [ ] Re-run release tests and verify the package and hosted CI.
- [ ] Publish v1.2.1, install it, and open the normal Release app.
- [ ] Keep only the latest installed app; move old and duplicate bundles to Trash without deleting user data.
