import Foundation
import UserNotifications

enum TimeclockReminderScheduler {
    static let loginRequiredNotificationIdentifier = "login-required"
    static let openTimeclockActionIdentifier = "open-timeclock"
    static let openDailyReportActionIdentifier = "open-daily-report"
    static let snooze5ActionIdentifier = "snooze-5"
    static let snooze10ActionIdentifier = "snooze-10"
    static let snooze15ActionIdentifier = "snooze-15"
    static let loginRequiredCategoryIdentifier = "login-required-actions"
    static let reminderCategoryIdentifier = "timeclock-reminder-actions"
    static let reportReminderCategoryIdentifier = "timeclock-report-reminder-actions"

    private static let weekdays = Array(1...7)
    private static let workReminderIdentifier = "work-start-reminder"
    private static let breakReminderIdentifier = "break-reminder"
    private static let clockOutReminderIdentifier = "clock-out-reminder"

    static func schedule(
        state: TimeclockState,
        workingWeekdays: Set<Int>,
        workReminderEnabled: Bool,
        workStartMinutes: Int,
        workReminderLeadMinutes: Int,
        breakReminderEnabled: Bool,
        breakReminderMinutes: Int,
        clockOutReminderEnabled: Bool,
        workEndMinutes: Int,
        clockOutReminderLeadMinutes: Int
    ) {
        let identifiers =
            [
                workReminderIdentifier,
                breakReminderIdentifier,
                clockOutReminderIdentifier
            ] +
            notificationIdentifiers(prefix: workReminderIdentifier) +
            notificationIdentifiers(prefix: breakReminderIdentifier) +
            notificationIdentifiers(prefix: clockOutReminderIdentifier)

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)

        guard !workingWeekdays.isEmpty,
              workReminderEnabled || breakReminderEnabled || clockOutReminderEnabled else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { isAllowed, _ in
            guard isAllowed else { return }

            for weekday in workingWeekdays {
                if workReminderEnabled && !isWorking(state: state) {
                    let reminderMinutes = workStartMinutes - workReminderLeadMinutes

                    scheduleWeeklyNotification(
                        identifier: notificationIdentifier(prefix: workReminderIdentifier, weekday: weekday),
                        title: "Shift starts soon",
                        body: "Your work shift starts in \(workReminderLeadMinutes) minutes.",
                        minutes: reminderMinutes,
                        weekday: shiftedWeekday(weekday, byDays: dayOffset(forMinutes: reminderMinutes)),
                        categoryIdentifier: reminderCategoryIdentifier
                    )
                }

                if breakReminderEnabled && !isOnBreak(state: state) {
                    scheduleWeeklyNotification(
                        identifier: notificationIdentifier(prefix: breakReminderIdentifier, weekday: weekday),
                        title: "Break reminder",
                        body: "Time for your preferred break.",
                        minutes: breakReminderMinutes,
                        weekday: weekday,
                        categoryIdentifier: reminderCategoryIdentifier
                    )
                }

                if clockOutReminderEnabled && !isClockedOut(state: state) {
                    let reminderMinutes = workEndMinutes - clockOutReminderLeadMinutes
                    let endWeekday = shiftedWeekday(
                        weekday,
                        byDays: (workEndMinutes <= workStartMinutes ? 1 : 0) + dayOffset(forMinutes: reminderMinutes)
                    )

                    scheduleWeeklyNotification(
                        identifier: notificationIdentifier(prefix: clockOutReminderIdentifier, weekday: weekday),
                        title: "Clock out reminder",
                        body: "Your shift ends in \(clockOutReminderLeadMinutes) minutes. Submit your report before clocking out.",
                        minutes: reminderMinutes,
                        weekday: endWeekday,
                        categoryIdentifier: reportReminderCategoryIdentifier
                    )
                }
            }
        }
    }

    static func registerNotificationCategories() {
        let openTimeclock = UNNotificationAction(
            identifier: openTimeclockActionIdentifier,
            title: "Open TimeClock Bar",
            options: [.foreground]
        )
        let openReport = UNNotificationAction(
            identifier: openDailyReportActionIdentifier,
            title: "Open Report",
            options: [.foreground]
        )
        let snooze5 = UNNotificationAction(identifier: snooze5ActionIdentifier, title: "Snooze 5 min", options: [])
        let snooze10 = UNNotificationAction(identifier: snooze10ActionIdentifier, title: "Snooze 10 min", options: [])
        let snooze15 = UNNotificationAction(identifier: snooze15ActionIdentifier, title: "Snooze 15 min", options: [])

        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: loginRequiredCategoryIdentifier,
                actions: [openTimeclock],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: reminderCategoryIdentifier,
                actions: [openTimeclock, snooze5, snooze10, snooze15],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: reportReminderCategoryIdentifier,
                actions: [openReport, openTimeclock, snooze5, snooze10, snooze15],
                intentIdentifiers: []
            )
        ])
    }

    static func removeLegacyReportReminders() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("daily-report-") }

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    static func sendNotification(identifier: String, title: String, body: String, categoryIdentifier: String, delaySeconds: TimeInterval? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { isAllowed, _ in
            guard isAllowed else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier

            let trigger = delaySeconds.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private static func scheduleWeeklyNotification(identifier: String, title: String, body: String, minutes: Int, weekday: Int, categoryIdentifier: String) {
        let normalized = normalizedMinutes(minutes)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: normalized / 60, minute: normalized % 60, weekday: weekday),
            repeats: true
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func notificationIdentifiers(prefix: String) -> [String] {
        weekdays.map { notificationIdentifier(prefix: prefix, weekday: $0) }
    }

    private static func notificationIdentifier(prefix: String, weekday: Int) -> String {
        "\(prefix)-\(weekday)"
    }

    private static func normalizedMinutes(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }

    private static func dayOffset(forMinutes minutes: Int) -> Int {
        if minutes < 0 {
            return -1
        }

        if minutes >= 1440 {
            return 1
        }

        return 0
    }

    private static func shiftedWeekday(_ weekday: Int, byDays offset: Int) -> Int {
        ((weekday - 1 + offset + 7) % 7) + 1
    }

    private static func isWorking(state: TimeclockState) -> Bool {
        switch state {
        case .active, .onBreak:
            return true
        case .loading, .loginRequired, .stale, .clockedOut, .unknown:
            return false
        }
    }

    private static func isOnBreak(state: TimeclockState) -> Bool {
        switch state {
        case .onBreak:
            return true
        case .loading, .loginRequired, .stale, .clockedOut, .active, .unknown:
            return false
        }
    }

    private static func isClockedOut(state: TimeclockState) -> Bool {
        switch state {
        case .clockedOut:
            return true
        case .loading, .loginRequired, .stale, .active, .onBreak, .unknown:
            return false
        }
    }
}
