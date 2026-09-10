import Foundation

struct WorkdaySchedule {
    var timeZone: TimeZone
    var weekdays: Set<Int>
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    var breakDuration: Int

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    struct Shift: Equatable {
        let id: String
        let workDate: String
        let start: Date
        let end: Date
        let preferredBreak: Date?
    }

    func shifts(around now: Date) -> [Shift] {
        let day = calendar.startOfDay(for: now)
        return (-1...7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: day),
                  weekdays.contains(calendar.component(.weekday, from: date)),
                  let start = time(startMinutes, on: date),
                  let endDay = calendar.date(byAdding: .day, value: endMinutes <= startMinutes ? 1 : 0, to: date),
                  let end = time(endMinutes, on: endDay) else { return nil }
            let breakDay = calendar.date(byAdding: .day, value: breakMinutes < startMinutes ? 1 : 0, to: date) ?? date
            let preferredBreak = time(breakMinutes, on: breakDay)
            let workDate = Self.dateString(date, timeZone: timeZone)
            return Shift(id: "\(timeZone.identifier)|\(workDate)", workDate: workDate, start: start, end: end,
                         preferredBreak: preferredBreak.flatMap { $0 >= start && $0 < end && breakDuration > 0 ? $0 : nil })
        }
    }

    func currentShift(at now: Date) -> Shift? {
        let shifts = shifts(around: now)
        return shifts.first { now >= $0.start && now < $0.end.addingTimeInterval(4 * 3600) }
            ?? shifts.first { $0.start > now }
    }

    static func dateString(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func time(_ minutes: Int, on day: Date) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
}

/// A confirmed completed work date. The timestamp records observation, not a website receipt.
struct WorkdayCompletion: Equatable {
    let id: String
    let workDate: String
    let observedAt: Date?
}

struct WorkdayCheckpoint: Identifiable, Equatable {
    let id: String
    let kind: TimeclockReminderKind
    let title: String
    let due: Date
    let leadMinutes: Int
    let isComplete: Bool
    let isSilenced: Bool

    var offsets: [Int] {
        let advance = leadMinutes > 0 ? [-leadMinutes] : []
        return advance + (kind == .breakOver ? [0, 2, 5] : [0, 5, 15])
    }
}
