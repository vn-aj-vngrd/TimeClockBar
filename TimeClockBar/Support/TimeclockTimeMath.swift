import Foundation

enum TimeclockTimeMath {
    static func normalizedMinutes(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }

    static func normalizedDurationMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), 24 * 60)
    }

    static func timerMinutes(from value: String) -> Int? {
        timerSeconds(from: value).map { $0 / 60 }
    }

    static func timerSeconds(from value: String) -> Int? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: ":")
            .split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let hours = Int(parts[0]), hours <= (Int.max - 3599) / 3600,
              let minutes = Int(parts[1]), (0..<60).contains(minutes) else { return nil }

        let seconds = parts.count == 3 ? Int(parts[2]) : 0
        guard let seconds, (0..<60).contains(seconds) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    static func shiftDurationMinutes(start: Int, end: Int) -> Int {
        let duration = normalizedMinutes(end - start)
        return duration == 0 ? 24 * 60 : duration
    }

    static func remainingWorkMinutes(dayMinutes: Int, start: Int, end: Int, breakDuration: Int) -> Int {
        let targetMinutes = max(0, shiftDurationMinutes(start: start, end: end) - normalizedDurationMinutes(breakDuration))
        return targetMinutes - dayMinutes
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
