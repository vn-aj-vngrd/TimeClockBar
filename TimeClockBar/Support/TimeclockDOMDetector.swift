import Foundation

struct TimeclockDOMDetection {
    let state: String
    let timer: String
    let currentTimer: String
    let dayTimer: String
    let weekTimer: String

    init?(_ dictionary: [String: Any]?) {
        guard let dictionary else { return nil }

        state = dictionary["state"] as? String ?? "unknown"
        timer = dictionary["timer"] as? String ?? ""
        currentTimer = dictionary["currentTimer"] as? String ?? ""
        dayTimer = dictionary["dayTimer"] as? String ?? ""
        weekTimer = dictionary["weekTimer"] as? String ?? ""
    }
}

enum TimeclockDOMDetector {
    static func timers(from detection: TimeclockDOMDetection?) -> TimeclockTimers {
        guard let detection else { return .empty }

        return TimeclockTimers(
            current: detection.currentTimer,
            day: detection.dayTimer,
            week: detection.weekTimer,
            fallback: detection.timer
        )
    }

    // DOM detection is intentionally text-based so selectors can be tuned after inspecting the live page.
    static let detectionScript = """
    (() => {
      const normalize = (value) =>
        (value || "").replace(/\\s+/g, " ").trim();

      const bodyText = normalize(document.body?.innerText || "");
      const lower = bodyText.toLowerCase();

      const timePattern = /\\b\\d{1,2}:\\d{2}(?:(?::|\\.)\\d{1,2})?\\b/;
      const cleanTimer = (value) => {
        const match = normalize(value).match(timePattern);
        return match ? match[0] : "";
      };
      const metricTime = (label) => {
        const match = bodyText.match(new RegExp("\\\\b" + label + "\\\\s+(\\\\d{1,2}:\\\\d{2}(?:(?::|\\\\.)\\\\d{1,2})?)", "i"));
        return match ? match[1] : "";
      };

      const timerSelectors = [
        '[data-testid="timer"]',
        '[data-testid*="timer"]',
        '[data-testid*="elapsed"]',
        '[data-testid*="duration"]',
        '[class*="timer"]',
        '[class*="duration"]',
        '[class*="elapsed"]',
        '[id*="timer"]'
      ];

      const findSidebarTimer = () => {
        const elements = Array.from(document.querySelectorAll("body *"));

        for (const element of elements) {
          const text = normalize(element.innerText || element.textContent || "");
          const timer = cleanTimer(text);

          if (!timer || text !== timer) {
            continue;
          }

          let parent = element.parentElement;

          for (let depth = 0; parent && depth < 5; depth += 1) {
            const parentText = normalize(parent.innerText || parent.textContent || "").toLowerCase();

            if (parentText.includes("time clock")) {
              return timer;
            }

            parent = parent.parentElement;
          }
        }

        return "";
      };

      const currentTimer = metricTime("Current");
      const dayTimer = metricTime("Day");
      const weekTimer = metricTime("Week");
      let timer = currentTimer || dayTimer || weekTimer;

      for (const selector of timerSelectors) {
        if (timer) {
          break;
        }

        const el = document.querySelector(selector);
        const text = cleanTimer(el?.innerText || el?.textContent || "");
        if (text) {
          timer = text;
          break;
        }
      }

      if (!timer) {
        timer = findSidebarTimer();
      }

      if (!timer) {
        const match = bodyText.match(timePattern);
        timer = match ? match[0] : "";
      }

      const hasLogin =
        lower.includes("login") ||
        lower.includes("log in") ||
        lower.includes("sign in");

      const hasClockIn = lower.includes("clock in");
      const hasClockOut = lower.includes("clock out");

      const hasStartBreak =
        lower.includes("start break") ||
        lower.includes("take break");

      const hasEndBreak =
        lower.includes("end break") ||
        lower.includes("resume") ||
        lower.includes("back from break");

      const hasOnBreak =
        lower.includes("on break") ||
        lower.includes("currently on break");

      const hasSidebarTimer =
        Boolean(timer) &&
        lower.includes("time clock") &&
        !hasClockIn;

      let state = "unknown";

      if (hasLogin) {
        state = "loginRequired";
      } else if (hasEndBreak || hasOnBreak) {
        state = "onBreak";
      } else if (hasClockOut || hasStartBreak) {
        state = "active";
      } else if (hasSidebarTimer) {
        state = "active";
      } else if (hasClockIn) {
        state = "clockedOut";
      }

      return {
        state,
        timer,
        currentTimer,
        dayTimer,
        weekTimer,
        bodyPreview: bodyText.slice(0, 300)
      };
    })();
    """
}
