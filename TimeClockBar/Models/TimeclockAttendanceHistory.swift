import Foundation

struct TimeclockHistoryEntry {
    let isBreak: Bool
    let start: String
    let end: String
}

struct WorkdayAttendance: Codable, Equatable {
    var clockIn: Date?
    var breakStart: Date?
    var breakEnd: Date?
    var clockOut: Date?
}

enum TimeclockAttendanceHistory {
    static func resolve(_ entries: [TimeclockHistoryEntry], timeZone: TimeZone,
                        shift: WorkdaySchedule.Shift, schedule: WorkdaySchedule,
                        state: TimeclockState, now: Date) -> WorkdayAttendance? {
        guard !entries.isEmpty else { return nil }
        switch state {
        case .onBreak:
            guard entries[0].isBreak, entries[0].end.lowercased() == "present" else { return nil }
        case .active:
            guard !entries[0].isBreak, entries[0].end.lowercased() == "present" else { return nil }
        case .clockedOut:
            guard !entries.contains(where: { $0.end.lowercased() == "present" }) else { return nil }
        default: return nil
        }
        let earliest = min(schedule.calendar.startOfDay(for: shift.start), shift.start.addingTimeInterval(-3600))
        let latest = min(now, shift.end.addingTimeInterval(4 * 3600))
        var cursor = latest
        var result = WorkdayAttendance()
        var foundBreak = false
        for (index, entry) in entries.enumerated() {
            let ongoing = entry.end.lowercased() == "present"
            guard !ongoing || index == 0 else { return nil }
            guard let end = ongoing ? cursor : date(entry.end, noLaterThan: cursor, timeZone: timeZone),
                  let start = date(entry.start, noLaterThan: end, timeZone: timeZone),
                  start >= earliest, end <= latest, start <= end else { return nil }
            if entry.isBreak {
                if !foundBreak {
                    result.breakStart = start
                    result.breakEnd = ongoing ? nil : end
                    foundBreak = true
                }
            } else {
                result.clockIn = start
            }
            if index == 0, state == .clockedOut { result.clockOut = end }
            cursor = start
        }
        return result
    }

    private static func date(_ text: String, noLaterThan limit: Date, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.isLenient = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        let formats = ["h:mm a", "h:mm:ss a", "HH:mm", "HH:mm:ss"]
        if text.first?.isLetter == true {
            for year in [calendar.component(.year, from: limit), calendar.component(.year, from: limit) - 1] {
                for format in formats {
                    formatter.dateFormat = "MMM d, yyyy, " + format
                    if let value = formatter.date(from: text), value <= limit { return value }
                    formatter.dateFormat = "MMM d, " + format + " yyyy"
                    if let value = formatter.date(from: "\(text) \(year)"), value <= limit { return value }
                }
            }
        } else {
            for format in formats {
                formatter.dateFormat = format
                guard let time = formatter.date(from: text) else { continue }
                let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
                for offset in [0, -1] {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: limit),
                          let value = calendar.date(bySettingHour: parts.hour!, minute: parts.minute!, second: parts.second!, of: day),
                          value <= limit,
                          calendar.dateComponents([.hour, .minute, .second], from: value) == parts else { continue }
                    return value
                }
            }
        }
        return nil
    }
}
