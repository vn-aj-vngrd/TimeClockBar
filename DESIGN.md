# Time Clock Bar design

## Navigation

Keep a visible segmented control: **Today · Time Clock · Report**. Settings is a separate utility reached from the gear. Preserve Cmd-1 for Time Clock and Cmd-2 for Report; Cmd-0 opens Today. Use “Report” consistently for the Full Scale website.

## Today

Keep the existing 460 × 640 popover. Use a short dashboard with:

1. Today and the date in the configured work timezone.
2. One next-action headline, a useful countdown, and its destination button.
3. A compact shift schedule, with “File report” before “Clock out.”
4. Brief clock-status feedback when needed.

On a day off, show “No shift today” and the next shift without a primary clock-in button. While on break, prioritize returning from break. Within 30 minutes of shift end, show “Report, then clock out,” with Open Report first and Time Clock second. Report submission remains owned by Full Scale. The user confirms the website requires filing it before clock-out, so a confirmed completed shift can show its report checked; opening Report never establishes completion.

After confirmed clock-out, make the next scheduled shift the main content immediately, with a fresh checklist. Keep the previous work date's report/clock-out confirmation in a compact secondary summary, including the observation time when known. Label overnight shifts with both dates. Midnight and temporary Checking states must not complete an unfinished shift. The menu bar continues to reflect actual attendance independently of which shift Today displays.

## Native conventions

Reuse `ChromeColor`, the system font, semantic colors, native buttons and segmented controls. Use monospaced digits for countdowns. Pair colors with text/icons, retain keyboard focus and accessibility labels, and respect Reduce Motion. Avoid per-row action menus and repeated controls that turn the dashboard into another task manager.

Debug builds show one compact **DEV** chip in the header on every page, including Settings. Do not add a second Preview chip; the dashboard/page body explains paused website access. Release builds omit DEV. Align the Work timezone menu with the trailing edge of the other settings controls.

The websites own their forms, AI controls, and page styling. This release adds no native report window.

## Verification

Use `--preview-today` to inspect the native shell without loading either website or scheduling notifications. The preview must say website access is paused. Unit tests cover Saturday, breaks, and report-before-clock-out routing with local data.
