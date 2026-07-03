import Foundation

enum TimeclockTimeMath {
    static func normalizedMinutes(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }

    static func normalizedDurationMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), 24 * 60)
    }

    static func timerMinutes(from value: String) -> Int? {
        let parts = value.replacingOccurrences(of: ".", with: ":").split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func shiftDurationMinutes(start: Int, end: Int) -> Int {
        let duration = normalizedMinutes(end - start)
        return duration == 0 ? 24 * 60 : duration
    }

    static func durationLabel(minutes: Int) -> String {
        let hours = minutes / 60
        let minutes = minutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }

    static func dayOffset(forMinutes minutes: Int) -> Int {
        if minutes < 0 {
            return -1
        }

        if minutes >= 1440 {
            return 1
        }

        return 0
    }

    static func shiftedWeekday(_ weekday: Int, byDays offset: Int) -> Int {
        ((weekday - 1 + offset + 7) % 7) + 1
    }
}
