# Time Clock Bar design

## Navigation

Keep a visible segmented control: **Today · Time Clock · Report**. Settings is a separate utility reached from the gear. Preserve Cmd-1 for Time Clock and Cmd-2 for Report; Cmd-0 opens Today. Use “Report” consistently for the Full Scale website.

## Today

Keep the existing 460 × 640 popover. Use a short dashboard with:

1. Today and the date in the configured work timezone.
2. One next-action headline, a useful countdown, and its destination button.
3. A compact shift schedule, with “File report” before “Clock out.”
4. Brief clock-status feedback when needed.

On a day off, show “No shift today” and the next shift without a primary clock-in button. While on break, prioritize returning from break. Within 30 minutes of shift end, show “Report, then clock out,” with Open Report first and Time Clock second. Report submission status is owned by Full Scale; do not show a fabricated completion check.

## Native conventions

Reuse `ChromeColor`, the system font, semantic colors, native buttons and segmented controls. Use monospaced digits for countdowns. Pair colors with text/icons, retain keyboard focus and accessibility labels, and respect Reduce Motion. Avoid per-row action menus and repeated controls that turn the dashboard into another task manager.

The websites own their forms, AI controls, and page styling. This release adds no native report window.

## Verification

Use `--preview-today` to inspect the native shell without loading either website or scheduling notifications. The preview must say website access is paused. Unit tests cover Saturday, breaks, and report-before-clock-out routing with local data.
