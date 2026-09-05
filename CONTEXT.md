# Time Clock Bar domain

**Today:** the native dashboard for current status, the next action, and the shift schedule.

**Time Clock:** the existing attendance website, where the user clocks in, starts/ends breaks, and clocks out.

**Report:** the Full Scale website, where the user files the daily report before clock-out. Opening this page does not establish submission.

**Shift:** a scheduled work period in a saved work timezone. Overnight shifts belong to their start date, called the **work date**.

**Clock state:** the latest observed page status: clocked out, active, or on break. Loading, login-required, stale, and unknown states do not establish completion.

**Checkpoint:** a scheduled attendance action: clock in, start break, return from break, or clock out. A reminder's opening, dismissal, or snooze does not complete its checkpoint.

**Break session:** an observed break with its own elapsed timer and return deadline, distinct from the preferred break time.

**Wrap-up:** file the Full Scale report, then clock out in Time Clock. This is navigation guidance; the websites retain control of submission and attendance.
