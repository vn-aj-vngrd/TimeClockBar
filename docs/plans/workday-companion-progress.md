# Implementation checklist

Scope corrected on 2026-09-05: **Today · Time Clock · Report**. The earlier native draft/AI phases are superseded, not completed. See [the current plan](workday-companion.md).

## Current work

- [x] Remove the native report editor, draft/AI/export/archive implementation from the app; leave previously saved local data untouched.
- [x] Replace the page menu with three visible tabs; preserve website shortcuts and add Cmd-0 for Today.
- [x] Add dashboard routing for day off, working, break return, and report-before-clock-out.
- [x] Route advance clock-out notifications to Report; retain attendance routing at the clock-out deadline.
- [x] Add a website-free preview and configure the XCTest host to use it.
- [x] Pass the final unit suite and native Saturday preview check.
- [ ] Build and verify the Release package and bundled notification resources.
- [ ] Commit, push, and verify hosted CI.
- [ ] Publish the internal version, install locally, and open Today with normal website access.

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
