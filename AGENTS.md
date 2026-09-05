# AGENTS.md

## Purpose

Use this file as the starting context for code, docs, tests, reviews, and release work in TimeClockBar.

## Read First

- `README.md` for product scope, setup, and validation commands.
- `docs/ai/architecture.md` for app structure and data flow.
- `docs/ai/code-structure.md` for consolidation boundaries and when to split files.
- `docs/ai/development.md` for local workflow and debugging notes.
- `docs/ai/testing.md` for the current testing strategy.
- `docs/ai/release.md` for release checks.
- `docs/ai/coding-standards.md` for Swift and UI conventions.

## Product Work

- Product scope or feature prioritization: read `PRODUCT.md` and the applicable phase in `docs/plans/workday-companion.md`.
- Implementation or handoff: read `docs/plans/workday-companion-progress.md`; update its checklist and validation log before finishing an increment. Check off only verified work and leave unobserved platform gates pending.
- Domain naming: read `CONTEXT.md` before introducing shift, checkpoint, or report concepts.
- UI work: read `DESIGN.md` for native conventions and accessibility requirements.
- Reminder behavior: read `docs/product/reminders.md`; use `docs/product/audit-2026-09-05.md` for the audited failure paths.
- Report is the existing Full Scale website. Native drafts, AI, export, and submission automation are deferred; revisit `docs/product/report-drafts.md` only if the user explicitly reintroduces that scope.

The product specifications describe proposed behavior. Verify current implementation in source; update architecture/testing docs as each phase ships.

## Live website safety

Time Clock and Report are live production websites. Keep them accessible in the app.

- During testing, perform attendance/report behavior checks with local fixtures and the test-host preview mode.
- Explicitly requested sound checks may use Settings → Notification Tests in a Debug preview. These send labeled local notifications only; keep automatic reminders and website actions paused. XCTest must not send real notifications.
- Never clock in or out, start or end a break, fill or edit report fields, invoke website Improve, or submit a report as a test. Do not use real website mutations to prove a feature works.
- Read-only inspection and loading the websites are allowed. Opening a page does not authorize operating its controls.
- A real attendance or report action requires a separate, explicit user request for that specific action; general build, release, testing, or UX instructions are insufficient.

## Working Rules

- Understand the relevant SwiftUI, AppKit, WebKit, notification, and defaults flow before editing.
- Make the smallest safe change that preserves the existing menu-bar app shape.
- Reuse the existing `App`, `Controllers`, `Models`, `Support`, `Views`, and `Resources` folders before adding new folders.
- Reuse existing controller, support helper, view, state, and UserDefaults patterns before adding new abstractions.
- Keep controller, support, and view ownership aligned with `docs/ai/code-structure.md`.
- Keep UI changes consistent with the current compact popover and native macOS controls.
- Update docs when setup, commands, architecture, release behavior, or user-visible behavior changes.
- Run the smallest relevant Xcode build or test command before finishing, or state exactly why it was not run.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in this repository's GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the default canonical triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

Uses a single-context layout: root `CONTEXT.md` and `docs/adr/`. See `docs/agents/domain.md`.
