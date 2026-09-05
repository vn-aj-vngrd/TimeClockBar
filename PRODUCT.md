# Time Clock Bar product

A small macOS companion for one workday flow: **clock in → take and end breaks → file the Full Scale report → clock out**.

## Confirmed scope — 2026-09-05

The user simplified the earlier expansion to three pages:

- **Today:** a native dashboard showing the next action, break countdown, and shift schedule. A day off has no urgent clock-in prompt.
- **Time Clock:** the existing website for clock-in, breaks, and clock-out.
- **Report:** the existing Full Scale website for filing the daily report before clock-out.

Keep the ticking menu-bar status. Use gentle advance reminders and limited repeats, with state-aware cancellation. Near shift end, lead with Report, then direct the user to Time Clock. A break in progress keeps its return reminder prominent.

The app opens destinations; the user performs the actions. Opening Report does not prove submission, and clocking out does not mark a report filed. The native dashboard does not block the website or invent submission status.

## Boundaries

Local drafts, a separate report editor, AI assistance, export/archive controls, and automatic report posting are outside this release. The earlier draft proposal is deferred, not active implementation work.

Preserve native macOS controls, existing settings and website behavior. The app is a reminder and navigation aid, not the authority for attendance or report acceptance.

## Success

Three destinations are immediately visible. On Saturday, the dashboard shows the next scheduled shift without urging a clock-in. During work it makes the next break clear; during break it shows the return deadline; near the end it says “Report, then clock out.” No automatic attendance or report action is performed.

Track implementation and validation in [the checklist](docs/plans/workday-companion-progress.md).
