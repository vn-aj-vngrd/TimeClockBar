import Foundation

/// One observation at a time; display estimates never advance source freshness.
struct TimeclockObservation {
    private(set) var token: UUID?
    private(set) var startedAt: Date?
    private(set) var lastState: TimeclockState?
    private(set) var timers = TimeclockTimers.empty
    private(set) var observedAt: Date?
    private var runningValue = ""
    private var runningChangedAt: Date?
    private var timerAnchors: [String: Date] = [:]

    mutating func begin(at now: Date) -> UUID? {
        guard token == nil else { return nil }
        let id = UUID()
        token = id
        startedAt = now
        return id
    }

    mutating func finish(_ id: UUID) -> Bool {
        guard token == id else { return false }
        invalidate()
        return true
    }

    mutating func invalidate() { token = nil; startedAt = nil }

    func isTimedOut(at now: Date) -> Bool {
        startedAt.map { now.timeIntervalSince($0) >= 10 } ?? false
    }

    mutating func accept(_ state: TimeclockState, timers: TimeclockTimers, at now: Date) -> Bool {
        let running: String
        switch state {
        case .active: running = timers.current.isEmpty ? timers.fallback : timers.current
        case .onBreak(let timer): running = timer
        case .clockedOut: running = ""
        case .loading, .loginRequired, .stale, .unknown: return false
        }
        if running != runningValue || runningChangedAt == nil {
            runningValue = running
            runningChangedAt = now
        }
        // A responsive JS process with a frozen clock still needs recovery.
        if !running.isEmpty, let changed = runningChangedAt, now.timeIntervalSince(changed) >= 120 { return false }
        let phaseChanged: Bool
        switch (lastState, state) {
        case (.active?, .active), (.onBreak?, .onBreak), (.clockedOut?, .clockedOut): phaseChanged = false
        default: phaseChanged = true
        }
        let values = [("current", self.timers.current, timers.current), ("day", self.timers.day, timers.day),
                      ("week", self.timers.week, timers.week), ("fallback", self.timers.fallback, timers.fallback)]
        for (key, previous, next) in values where previous != next || phaseChanged || timerAnchors[key] == nil {
            timerAnchors[key] = now
        }
        lastState = state
        self.timers = timers
        observedAt = now
        return true
    }

    mutating func resetMotion() { runningValue = ""; runningChangedAt = nil }

    func displayTimers(at now: Date) -> TimeclockTimers {
        guard let observedAt, let lastState else { return timers }
        func advance(_ text: String, key: String) -> String {
            guard let seconds = TimeclockTimeMath.timerSeconds(from: text) else { return text }
            let delta = max(0, min(120, Int(now.timeIntervalSince(timerAnchors[key] ?? observedAt))))
            let total = seconds + delta
            return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
        switch lastState {
        case .active:
            return TimeclockTimers(current: advance(timers.current, key: "current"), day: advance(timers.day, key: "day"),
                                   week: advance(timers.week, key: "week"), fallback: advance(timers.fallback, key: "fallback"))
        case .onBreak:
            return TimeclockTimers(current: timers.current, day: timers.day, week: timers.week,
                                   fallback: advance(timers.fallback, key: "fallback"))
        default: return timers
        }
    }
}
