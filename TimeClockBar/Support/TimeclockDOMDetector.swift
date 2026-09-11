import Foundation

struct TimeclockDOMDetection {
    let state: String
    let timer: String
    let currentTimer: String
    let dayTimer: String
    let weekTimer: String
    let history: [TimeclockHistoryEntry]
    let historyTimeZone: TimeZone?

    init?(_ dictionary: [String: Any]?) {
        guard let dictionary else { return nil }

        state = dictionary["state"] as? String ?? "unknown"
        timer = dictionary["timer"] as? String ?? ""
        currentTimer = dictionary["currentTimer"] as? String ?? ""
        dayTimer = dictionary["dayTimer"] as? String ?? ""
        weekTimer = dictionary["weekTimer"] as? String ?? ""
        history = (dictionary["history"] as? [[String: Any]] ?? []).compactMap { row in
            guard let isBreak = row["isBreak"] as? Bool, let start = row["start"] as? String,
                  let end = row["end"] as? String else { return nil }
            return TimeclockHistoryEntry(isBreak: isBreak, start: start, end: end)
        }
        historyTimeZone = (dictionary["historyTimeZone"] as? String).flatMap(TimeZone.init(identifier:))
    }
}

enum TimeclockDOMDetector {
    static func readScript(revealClockPanel: Bool) -> String {
        (revealClockPanel ? openClockPanelScript + ";\n" : "") + detectionScript
    }

    // The website unmounts history when details close. Reveal that read-only panel
    // after a background reload; never activate an attendance or report action.
    private static let openClockPanelScript = #"""
    (() => {
      if (window.__timeclockLastInput || document.activeElement?.matches('input, textarea, [contenteditable="true"]')) return;
      const visible = el => el && !el.closest('[hidden], [aria-hidden="true"]') &&
        getComputedStyle(el).display !== 'none' && getComputedStyle(el).visibility !== 'hidden' && el.getClientRects().length > 0;
      const text = el => (el.innerText || '').replace(/\s+/g, ' ').trim();
      const spans = [...document.querySelectorAll('span')].filter(visible);
      // These metrics belong to the open details panel, including while its data loads.
      if (['Current', 'Day', 'Week'].every(label => spans.some(el => text(el) === label))) return;
      if (Date.now() - (window.__timeclockPanelRequestedAt || 0) < 15000) return;
      const launchers = [...document.querySelectorAll('button')].filter(el => visible(el) &&
        !el.disabled && el.getAttribute('aria-disabled') !== 'true' &&
        [...el.querySelectorAll('span')].some(span => visible(span) && text(span) === 'Time Clock'));
      if (launchers.length !== 1) return;
      window.__timeclockPanelRequestedAt = Date.now();
      launchers[0].click();
    })()
    """#

    static func state(from detection: TimeclockDOMDetection?) -> TimeclockState {
        guard let detection else { return .unknown(nil) }
        let workTimer = detection.currentTimer.isEmpty ? detection.timer : detection.currentTimer
        switch detection.state {
        case "loginRequired": return .loginRequired
        case "clockedOut": return .clockedOut
        case "active": return .active(workTimer)
        // Current is the work counter and often resets to zero during a break.
        case "onBreak": return .onBreak(detection.timer)
        default: return .unknown(workTimer.isEmpty ? nil : workTimer)
        }
    }

    static func timers(from detection: TimeclockDOMDetection?) -> TimeclockTimers {
        guard let detection else { return .empty }

        return TimeclockTimers(
            current: detection.currentTimer,
            day: detection.dayTimer,
            week: detection.weekTimer,
            fallback: detection.timer
        )
    }


    // Observe controls and navigation; timer-only text mutations do not cross the bridge.
    static let observationScript = #"""
    (() => {
      if (window.__timeclockObserver) return;
      window.__timeclockObserver = true;
      let pending;
      const notify = () => {
        clearTimeout(pending);
        pending = setTimeout(() => window.webkit.messageHandlers.timeclockChanged.postMessage(null), 250);
      };
      const controls = 'button, [role="button"], input, a';
      new MutationObserver(records => {
        if (records.some(r => {
          const el = r.target.nodeType === 1 ? r.target : r.target.parentElement;
          return el?.closest(controls) || [...r.addedNodes, ...r.removedNodes].some(n =>
            n.nodeType === 1 && (n.matches(controls) || n.querySelector(controls)));
        })) notify();
      }).observe(document.body, {childList:true, subtree:true, characterData:true, attributes:true,
                               attributeFilter:['hidden','disabled','aria-hidden']});
      document.addEventListener('click', event => {
        if (event.target.closest(controls)) { notify(); setTimeout(notify, 1000); }
      }, true);
      document.addEventListener('input', () => { window.__timeclockLastInput = Date.now(); }, true);
    })();
    """#

    static let detectionScript = #"""
    (() => {
      const normalize = value => (value || '').replace(/\s+/g, ' ').trim()
        .replace(/(\d{1,3}:\d{2}\.)\s+(\d{1,2})\b/g, '$1$2');
      const visible = el => {
        if (!el || el.closest('[hidden], [aria-hidden="true"]')) return false;
        const style = getComputedStyle(el);
        return style.display !== 'none' && style.visibility !== 'hidden' && el.getClientRects().length > 0;
      };
      const timePattern = /\b\d{1,3}:\d{2}(?:(?::|\.)\d{1,2})?\b/;
      const cleanTimer = value => normalize(value).match(timePattern)?.[0] || '';
      const controls = [...document.querySelectorAll('button, [role="button"], input[type="submit"], a')]
        .filter(visible);
      const label = el => normalize(el.innerText || el.value || el.getAttribute('aria-label')).toLowerCase();
      const find = pattern => controls.find(el => pattern.test(label(el)));
      const enabled = el => !el.disabled && el.getAttribute('aria-disabled') !== 'true';
      const findAttendance = pattern => controls.find(el => enabled(el) && pattern.test(label(el)));
      const pendingAttendance = controls.some(el => !enabled(el) &&
        /^(clock\s*(in|out)|(start|take)\s+(a\s+)?break|end break|resume|resume work|back from break)$/.test(label(el)));
      const clockIn = findAttendance(/^clock\s*in$/);
      const clockOut = findAttendance(/^clock\s*out$/);
      const startBreak = findAttendance(/^(start|take)\s+(a\s+)?break$/);
      const endBreak = findAttendance(/^(end break|resume|resume work|back from break)$/);
      const attendance = endBreak || clockOut || startBreak || clockIn;
      const login = find(/^(log\s*in|sign\s*in)( with .+)?$/);
      const password = [...document.querySelectorAll('input[type="password"]')].some(visible);
      const authRoute = /\/(login|sign-in|signin)(\/|$)/i.test(location.pathname);
      // Keep extraction within the clock panel where possible. No body-wide wildcard traversal.
      const root = attendance?.closest('[data-testid="time-clock"], [data-testid="timeclock"], aside, main, form')
        || document.querySelector('aside') || document.querySelector('main') || document.body;
      const text = normalize(root?.innerText);
      const metric = name => text.match(new RegExp('\\b' + name + '\\s+(\\d{1,3}:\\d{2}(?:(?::|\\.)\\d{1,2})?)', 'i'))?.[1] || '';
      const currentTimer = metric('Current'), dayTimer = metric('Day'), weekTimer = metric('Week');
      const hasBreakNotice = /\byou are on a break\b/i.test(text);
      const breakTimer = text.match(/\byou are on a break\s+(\d{1,3}:\d{2}(?:(?::|\.)\d{1,2})?)\b/i)?.[1] || '';
      let timer = '';
      const candidates = root?.querySelectorAll('[data-testid*="timer"], [data-testid*="elapsed"], [class*="timer"], [class*="duration"], [class*="elapsed"], [id*="timer"]') || [];
      for (const el of candidates) {
        if (visible(el) && (timer = cleanTimer(el.innerText))) break;
      }
      const sidebar = document.querySelector('aside');
      if (!timer && sidebar && /time clock/i.test(sidebar.innerText)) {
        // Only a standalone value in the actual sidebar can provide the legacy fallback.
        const el = [...sidebar.querySelectorAll('span, time, p')].find(el => visible(el) &&
          cleanTimer(el.innerText) && normalize(el.innerText) === cleanTimer(el.innerText));
        timer = el ? cleanTimer(el.innerText) : '';
      }
      let state = 'unknown';
      if ((password || authRoute) && login) state = 'loginRequired';
      else if (endBreak) state = 'onBreak';
      else if (clockOut || startBreak) state = 'active';
      else if (clockIn) state = 'clockedOut';
      else if (login) state = 'loginRequired';
      else if (!pendingAttendance && timer && sidebar && /time clock/i.test(sidebar.innerText)) state = 'active';
      // Read only time-log cards. Their arrows are SVG, so text alone loses range boundaries.
      // If the website shows both a log timezone and local time, the second pair is local.
      const rows = [...root.querySelectorAll('div.group.relative.flex.cursor-default')];
      const history = rows.length > 64 ? [] : rows.flatMap(row => {
        if (!visible(row)) return [];
        const title = row.querySelector('div.truncate');
        const range = row.querySelector('span.flex-1.truncate');
        if (!title || !range) return [];
        const times = [...range.querySelectorAll('span.truncate')].filter(visible).map(el => normalize(el.innerText))
          .filter(value => /^(?:(?:[A-Za-z]{3})\s+\d{1,2},?\s+(?:\d{4},?\s+)?)?\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?$|^Present$/i.test(value));
        if (times.length !== 2 && times.length !== 4) return [];
        const [start, end] = times.slice(-2);
        if (/^Present$/i.test(start)) return [];
        return [{isBreak: /^(taking|took) a break$/i.test(normalize(title.innerText)), start, end}];
      });
      return {state, timer: state === 'onBreak' ? (hasBreakNotice ? breakTimer : timer) : (currentTimer || timer),
              currentTimer, dayTimer, weekTimer, history, historyTimeZone: Intl.DateTimeFormat().resolvedOptions().timeZone};
    })();
    """#
}
