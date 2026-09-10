# Time Clock Bar domain

**Today:** the native dashboard for the current or next shift. Midnight does not finish an overnight shift. After confirmed clock-out, Today shows the next shift with its own checklist and a compact previous-shift completion summary; the menu-bar clock status remains clocked out.

**Time Clock:** the existing attendance website, where the user clocks in, starts/ends breaks, and clocks out.

**Report:** the Full Scale website, where the user files the daily report before clock-out. Opening this page does not establish submission. The user confirms that the website requires filing the report before clock-out, so Today checks the completed shift's report in the previous-shift summary. This is inferred from that prerequisite, not a separate report submission receipt. Being out before any observed work does not complete the report, and the next shift's report stays pending.

**Shift:** a scheduled work period in a saved work timezone. Overnight shifts belong to their start date, called the **work date**.

**Clock state:** the latest observed page status: clocked out, active, or on break. Loading, login-required, stale, and unknown states do not establish completion.

**Checkpoint:** a scheduled attendance action: clock in, start break, return from break, or clock out. A reminder's opening, dismissal, or snooze does not complete its checkpoint.

**Break session:** an observed break with its own elapsed timer and return deadline, distinct from the preferred break time.

**Wrap-up:** file the Full Scale report, then clock out in Time Clock. This is navigation guidance; the websites retain control of submission and attendance.
