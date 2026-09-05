# Time Clock Bar improvement plan

Status: scope simplified by the user on 2026-09-05. This plan replaces the earlier draft/AI expansion. The [execution checklist](workday-companion-progress.md) records evidence.

## Product flow

**Today dashboard → Time Clock for clock-in and breaks → Report on Full Scale → Time Clock for clock-out.**

Use three visible pages: Today, Time Clock, Report. Preserve the websites. Keep the native dashboard concise and let the user perform all attendance and reporting actions.

## Delivery sequence

1. Simplify navigation and remove the native draft/editor/AI expansion from this release.
2. Make Today state-aware: quiet on days off, next break while working, return countdown on break, Report first near clock-out.
3. Keep reliable reminders: second-precision break return, dated shifts, stable snoozes, limited escalation, cancellation, and report-first advance clock-out routing.
4. Verify the native shell and routing using offline fixtures. Loading and read-only website access are allowed; tests must never perform attendance actions or enter/edit/submit reports.
5. Build/test/package, commit and push, publish the new internal version, then install and open it locally with normal website access. Existing release authorization remains in effect.

## Out of scope

Local draft storage, a second report window, AI assistance, export/archive flows, automatic form filling, and direct submission. Existing temporary draft data is left untouched. The earlier [draft proposal](../product/report-drafts.md) is historical/deferred and does not authorize future implementation.

## Acceptance

- Three pages are always visible and keyboard reachable.
- Saturday with no scheduled shift shows no clock-in CTA.
- Break return remains the primary action while on break.
- Near shift end, Today and the advance reminder lead to Report; the due clock-out reminder leads to Time Clock and reminds the user to file first.
- Opening a website or clocking out never marks a report submitted.
- Automated verification uses local fixtures; any read-only live inspection performs no report or attendance action.
- Release checks and remaining physical notification limitations are recorded honestly. A long personal-use pilot is follow-up validation, not a reason to add more product surfaces.
