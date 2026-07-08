import Foundation
import OSLog
import UserNotifications

struct TimeclockReminderPlan: Equatable {
    let identifier: String
    let title: String
    let body: String
    let minutes: Int
    let weekday: Int
    let categoryIdentifier: String
    let delaySeconds: TimeInterval?
}

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
    private static let breakOverReminderIdentifier = "break-over-reminder"
    private static let clockOutReminderIdentifier = "clock-out-reminder"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.vanajvanguardia.TimeClockBar",
        category: "Notifications"
    )

    static func schedule(
        state: TimeclockState,
        workingWeekdays: Set<Int>,
        workReminderEnabled: Bool,
        workStartMinutes: Int,
        workReminderLeadMinutes: Int,
        breakReminderEnabled: Bool,
        breakReminderMinutes: Int,
        breakOverReminderEnabled: Bool,
        breakDurationMinutes: Int,
        clockOutReminderEnabled: Bool,
        workEndMinutes: Int,
        clockOutReminderLeadMinutes: Int
    ) {
        let identifiers =
            [
                workReminderIdentifier,
                breakReminderIdentifier,
                breakOverReminderIdentifier,
                clockOutReminderIdentifier
            ] +
            notificationIdentifiers(prefix: workReminderIdentifier) +
            notificationIdentifiers(prefix: breakReminderIdentifier) +
            notificationIdentifiers(prefix: breakOverReminderIdentifier) +
            notificationIdentifiers(prefix: clockOutReminderIdentifier)

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)

        let plans = plans(
            state: state,
            workingWeekdays: workingWeekdays,
            workReminderEnabled: workReminderEnabled,
            workStartMinutes: workStartMinutes,
            workReminderLeadMinutes: workReminderLeadMinutes,
            breakReminderEnabled: breakReminderEnabled,
            breakReminderMinutes: breakReminderMinutes,
            breakOverReminderEnabled: breakOverReminderEnabled,
            breakDurationMinutes: breakDurationMinutes,
            clockOutReminderEnabled: clockOutReminderEnabled,
            workEndMinutes: workEndMinutes,
            clockOutReminderLeadMinutes: clockOutReminderLeadMinutes
        )

        guard !plans.isEmpty else { return }

        requestAuthorization { isAllowed in
            guard isAllowed else { return }

            for plan in plans {
                if let delaySeconds = plan.delaySeconds {
                    scheduleIntervalNotification(
                        identifier: plan.identifier,
                        title: plan.title,
                        body: plan.body,
                        delaySeconds: delaySeconds,
                        categoryIdentifier: plan.categoryIdentifier
                    )
                } else {
                    scheduleWeeklyNotification(
                        identifier: plan.identifier,
                        title: plan.title,
                        body: plan.body,
                        minutes: plan.minutes,
                        weekday: plan.weekday,
                        categoryIdentifier: plan.categoryIdentifier
                    )
                }
            }
        }
    }

    static func plans(
        state: TimeclockState,
        workingWeekdays: Set<Int>,
        workReminderEnabled: Bool,
        workStartMinutes: Int,
        workReminderLeadMinutes: Int,
        breakReminderEnabled: Bool,
        breakReminderMinutes: Int,
        breakOverReminderEnabled: Bool,
        breakDurationMinutes: Int,
        clockOutReminderEnabled: Bool,
        workEndMinutes: Int,
        clockOutReminderLeadMinutes: Int
    ) -> [TimeclockReminderPlan] {
        guard workReminderEnabled || breakReminderEnabled || breakOverReminderEnabled || clockOutReminderEnabled else { return [] }

        var oneShotPlans: [TimeclockReminderPlan] = []

        if breakOverReminderEnabled && isOnBreak(state: state) {
            let elapsedMinutes = breakElapsedMinutes(state: state) ?? 0
            let remainingMinutes = max(0, breakDurationMinutes - elapsedMinutes)
            oneShotPlans.append(TimeclockReminderPlan(
                identifier: breakOverReminderIdentifier,
                title: "Over break",
                body: "Time to end your break.",
                minutes: breakDurationMinutes,
                weekday: 0,
                categoryIdentifier: reminderCategoryIdentifier,
                delaySeconds: TimeInterval(max(1, remainingMinutes * 60))
            ))
        }

        guard !workingWeekdays.isEmpty else { return oneShotPlans }

        return oneShotPlans + workingWeekdays.sorted().flatMap { weekday in
            var plans: [TimeclockReminderPlan] = []

            if workReminderEnabled && !isWorking(state: state) {
                let reminderMinutes = workStartMinutes - workReminderLeadMinutes

                plans.append(TimeclockReminderPlan(
                    identifier: notificationIdentifier(prefix: workReminderIdentifier, weekday: weekday),
                    title: "Shift starts soon",
                    body: "Your work shift starts in \(workReminderLeadMinutes) minutes.",
                    minutes: reminderMinutes,
                    weekday: TimeclockTimeMath.shiftedWeekday(
                        weekday,
                        byDays: TimeclockTimeMath.dayOffset(forMinutes: reminderMinutes)
                    ),
                    categoryIdentifier: reminderCategoryIdentifier,
                    delaySeconds: nil
                ))
            }

            if breakReminderEnabled && !isOnBreak(state: state) {
                plans.append(TimeclockReminderPlan(
                    identifier: notificationIdentifier(prefix: breakReminderIdentifier, weekday: weekday),
                    title: "Break reminder",
                    body: "Time for your preferred break.",
                    minutes: breakReminderMinutes,
                    weekday: weekday,
                    categoryIdentifier: reminderCategoryIdentifier,
                    delaySeconds: nil
                ))
            }

            if clockOutReminderEnabled && !isClockedOut(state: state) {
                let reminderMinutes = workEndMinutes - clockOutReminderLeadMinutes
                let endWeekday = TimeclockTimeMath.shiftedWeekday(
                    weekday,
                    byDays: (workEndMinutes <= workStartMinutes ? 1 : 0) + TimeclockTimeMath.dayOffset(forMinutes: reminderMinutes)
                )

                plans.append(TimeclockReminderPlan(
                    identifier: notificationIdentifier(prefix: clockOutReminderIdentifier, weekday: weekday),
                    title: "Clock out reminder",
                    body: "Your shift ends in \(clockOutReminderLeadMinutes) minutes. Submit your report before clocking out.",
                    minutes: reminderMinutes,
                    weekday: endWeekday,
                    categoryIdentifier: reportReminderCategoryIdentifier,
                    delaySeconds: nil
                ))
            }

            return plans
        }
    }

    static func registerNotificationCategories() {
        let openTimeclock = UNNotificationAction(
            identifier: openTimeclockActionIdentifier,
            title: "Open Time Clock Bar",
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

    static func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { isAllowed, error in
            if let error {
                logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }

            if !isAllowed {
                logger.notice("Notification authorization is not allowed")
            }

            completion?(isAllowed)
        }
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
        requestAuthorization { isAllowed in
            guard isAllowed else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier

            let trigger = delaySeconds.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            add(request)
        }
    }

    private static func scheduleWeeklyNotification(identifier: String, title: String, body: String, minutes: Int, weekday: Int, categoryIdentifier: String) {
        let normalized = TimeclockTimeMath.normalizedMinutes(minutes)
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
        add(request)
    }

    private static func scheduleIntervalNotification(identifier: String, title: String, body: String, delaySeconds: TimeInterval, categoryIdentifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delaySeconds), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        add(request)
    }

    private static func add(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Notification request \(request.identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.debug("Notification request \(request.identifier, privacy: .public) scheduled")
            }
        }
    }

    private static func notificationIdentifiers(prefix: String) -> [String] {
        weekdays.map { notificationIdentifier(prefix: prefix, weekday: $0) }
    }

    private static func notificationIdentifier(prefix: String, weekday: Int) -> String {
        "\(prefix)-\(weekday)"
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

    private static func breakElapsedMinutes(state: TimeclockState) -> Int? {
        if case .onBreak(let time) = state {
            return TimeclockTimeMath.timerMinutes(from: time)
        }

        return nil
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
