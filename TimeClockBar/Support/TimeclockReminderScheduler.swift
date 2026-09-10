import Foundation
import OSLog
import UserNotifications

enum TimeclockReminderKind: String, CaseIterable {
    case workStart
    case breakStart
    case breakOver
    case clockOut
    case overtime
}

enum TimeclockReminderSound: String, CaseIterable {
    case pulse
    case beacon
    case urgent
    case siren
    case signal

    var label: String {
        switch self {
        case .pulse: return "Pulse"
        case .beacon: return "Beacon"
        case .urgent: return "Urgent"
        case .siren: return "Siren"
        case .signal: return "Signal"
        }
    }

    var fileName: String { "\(rawValue).wav" }

    var notificationSound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(fileName))
    }

    static func defaultSound(for kind: TimeclockReminderKind) -> Self {
        switch kind {
        case .workStart: return .pulse
        case .breakStart: return .beacon
        case .breakOver: return .urgent
        case .clockOut: return .siren
        case .overtime: return .signal
        }
    }
}

struct TimeclockReminderPlan: Equatable {
    let identifier: String
    let title: String
    let body: String
    let minutes: Int
    let weekday: Int
    let categoryIdentifier: String
    let delaySeconds: TimeInterval?
    let sound: TimeclockReminderSound
    var fireDate: Date? = nil
    var ownerIdentifier: String? = nil
    var soundSeconds = 10
}

enum TimeclockReminderScheduler {
    static let loginRequiredNotificationIdentifier = "login-required"
    static let openTimeclockActionIdentifier = "open-timeclock"
    static let openDailyReportActionIdentifier = "open-daily-report"
    static let snooze5ActionIdentifier = "snooze-5"
    static let snooze10ActionIdentifier = "snooze-10"
    static let snooze15ActionIdentifier = "snooze-15"
    static let stopAlarmActionIdentifier = "stop-alarm"
    static let loginRequiredCategoryIdentifier = "login-required-actions"
    static let reminderCategoryIdentifier = "timeclock-reminder-actions"
    static let reportReminderCategoryIdentifier = "timeclock-report-reminder-actions"
    static let reminderSoundUserInfoKey = "timeclockReminderSound"

    private static let workReminderIdentifier = "work-start-reminder"
    private static let breakReminderIdentifier = "break-reminder"
    private static let breakOverReminderIdentifier = "break-over-reminder"
    private static let clockOutReminderIdentifier = "clock-out-reminder"
    static let workday = WorkdayReminderController()
    static let delivery = TimeclockReminderDelivery(center: SystemTimeclockNotificationCenter())

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
        clockOutReminderLeadMinutes: Int,
        workReminderSound: TimeclockReminderSound,
        breakReminderSound: TimeclockReminderSound,
        breakOverReminderSound: TimeclockReminderSound,
        clockOutReminderSound: TimeclockReminderSound,
        allowsOvertime: Bool = false,
        overtimeReminderEnabled: Bool = false
    ) {
        let enabledKinds = Set([
            (TimeclockReminderKind.workStart, workReminderEnabled),
            (.breakStart, breakReminderEnabled && breakDurationMinutes > 0),
            (.breakOver, breakOverReminderEnabled && breakDurationMinutes > 0),
            (.clockOut, clockOutReminderEnabled)
        ].compactMap { $0.1 ? $0.0 : nil })
        let schedule = WorkdaySchedule(
            timeZone: TimeZone(identifier: UserDefaults.standard.string(forKey: "workTimeZone") ?? "") ?? .current,
            weekdays: workingWeekdays, startMinutes: workStartMinutes, endMinutes: workEndMinutes,
            breakMinutes: breakReminderMinutes, breakDuration: breakDurationMinutes
        )
        var result = workday.plans(schedule: schedule, state: state, enabled: enabledKinds,
            sounds: [.workStart: workReminderSound, .breakStart: breakReminderSound,
                     .breakOver: breakOverReminderSound, .clockOut: clockOutReminderSound],
            workLead: workReminderLeadMinutes, endLead: clockOutReminderLeadMinutes)
        for index in result.plans.indices {
            let id = result.plans[index].identifier
            let overdue = id.hasSuffix("|due-2") || id.hasSuffix("|due-5") || id.hasSuffix("|due-15")
            let urgentKind = id.contains("|breakOver-") || id.contains("|clockOut|")
            result.plans[index].soundSeconds = overdue && urgentKind && UserDefaults.standard.bool(forKey: "longOverdueSounds") ? 20 : 10
        }
        delivery.reconcile(plans: result.plans, allowsOvertime: allowsOvertime,
                           unverifiedSnoozeOwners: result.owners, activeOwners: result.owners,
                           onScheduled: { workday.markScheduled($0) })
    }

    static func unverifiedSnoozeOwners(
        state: TimeclockState, weekdays: Set<Int>, enabledKinds: Set<TimeclockReminderKind>
    ) -> Set<String>? {
        switch state {
        case .clockedOut, .active: return nil
        case .onBreak(let timer):
            guard TimeclockTimeMath.timerSeconds(from: timer) == nil else { return nil }
            return unverifiedSnoozeOwners(
                state: .unknown(nil), weekdays: weekdays,
                enabledKinds: enabledKinds.intersection([.breakOver, .clockOut, .overtime])
            )
        case .loading, .loginRequired, .stale, .unknown: break
        }
        // Keep neutral, user-requested snoozes through startup/offline until a fresh state resolves them.
        var owners: Set<String> = []
        for kind in enabledKinds {
            switch kind {
            case .breakOver: owners.insert(breakOverReminderIdentifier)
            case .overtime: owners.insert(TimeclockReminderDelivery.overtimeOwner)
            case .workStart, .breakStart, .clockOut:
                let prefix = kind == .workStart ? workReminderIdentifier : kind == .breakStart ? breakReminderIdentifier : clockOutReminderIdentifier
                owners.formUnion(weekdays.map { notificationIdentifier(prefix: prefix, weekday: $0) })
            }
        }
        return owners
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
        clockOutReminderLeadMinutes: Int,
        workReminderSound: TimeclockReminderSound = .defaultSound(for: .workStart),
        breakReminderSound: TimeclockReminderSound = .defaultSound(for: .breakStart),
        breakOverReminderSound: TimeclockReminderSound = .defaultSound(for: .breakOver),
        clockOutReminderSound: TimeclockReminderSound = .defaultSound(for: .clockOut)
    ) -> [TimeclockReminderPlan] {
        guard workReminderEnabled || breakReminderEnabled || breakOverReminderEnabled || clockOutReminderEnabled else { return [] }

        var oneShotPlans: [TimeclockReminderPlan] = []

        if breakOverReminderEnabled, breakDurationMinutes > 0,
           let elapsedSeconds = breakElapsedSeconds(state: state) {
            let remainingSeconds = max(0, breakDurationMinutes * 60 - elapsedSeconds)
            oneShotPlans.append(TimeclockReminderPlan(
                identifier: breakOverReminderIdentifier,
                title: "Over break",
                body: "Time to end your break.",
                minutes: breakDurationMinutes,
                weekday: 0,
                categoryIdentifier: reminderCategoryIdentifier,
                delaySeconds: TimeInterval(max(1, remainingSeconds)),
                sound: breakOverReminderSound
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
                    delaySeconds: nil,
                    sound: workReminderSound
                ))
            }

            let breakOffset = TimeclockTimeMath.normalizedMinutes(breakReminderMinutes - workStartMinutes)
            let shiftDuration = TimeclockTimeMath.shiftDurationMinutes(start: workStartMinutes, end: workEndMinutes)
            if breakReminderEnabled, breakDurationMinutes > 0, isActive(state: state), breakOffset < shiftDuration {
                plans.append(TimeclockReminderPlan(
                    identifier: notificationIdentifier(prefix: breakReminderIdentifier, weekday: weekday),
                    title: "Break reminder",
                    body: "Time for your preferred break.",
                    minutes: breakReminderMinutes,
                    weekday: TimeclockTimeMath.shiftedWeekday(weekday, byDays: (workStartMinutes + breakOffset) / 1440),
                    categoryIdentifier: reminderCategoryIdentifier,
                    delaySeconds: nil,
                    sound: breakReminderSound
                ))
            }

            if clockOutReminderEnabled && isWorking(state: state) {
                let reminderMinutes = workEndMinutes - clockOutReminderLeadMinutes
                let endWeekday = TimeclockTimeMath.shiftedWeekday(
                    weekday,
                    byDays: (workEndMinutes <= workStartMinutes ? 1 : 0) + TimeclockTimeMath.dayOffset(forMinutes: reminderMinutes)
                )

                plans.append(TimeclockReminderPlan(
                    identifier: notificationIdentifier(prefix: clockOutReminderIdentifier, weekday: weekday),
                    title: "Clock out reminder",
                    body: "Your shift ends in \(clockOutReminderLeadMinutes) minutes. Open Time Clock to clock out on time.",
                    minutes: reminderMinutes,
                    weekday: endWeekday,
                    categoryIdentifier: reminderCategoryIdentifier,
                    delaySeconds: nil,
                    sound: clockOutReminderSound
                ))
            }

            return plans
        }
    }

    static func registerNotificationCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(notificationCategories())
    }

    static func notificationCategories() -> Set<UNNotificationCategory> {
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
        let stopAlarm = UNNotificationAction(identifier: stopAlarmActionIdentifier, title: "Silence reminder", options: [])

        return [
            UNNotificationCategory(
                identifier: loginRequiredCategoryIdentifier,
                actions: [openTimeclock],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: reminderCategoryIdentifier,
                actions: [openTimeclock, snooze5, stopAlarm, snooze10, snooze15],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: reportReminderCategoryIdentifier,
                actions: [openReport, snooze5, stopAlarm, openTimeclock, snooze10, snooze15],
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ]
    }

    static func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        Task { @MainActor in
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                completion?(allowed)
            } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vanajvanguardia.TimeClockBar", category: "Notifications")
                    .error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                completion?(false)
            }
        }
    }

    static func snooze(_ request: UNNotificationRequest, minutes: Int) {
        delivery.snooze(request, minutes: minutes)
    }

    static func popoverPage(for action: String, category: String) -> PopoverPage? {
        switch action {
        case openTimeclockActionIdentifier: return .timeclock
        case openDailyReportActionIdentifier: return .dailyReport
        case UNNotificationDefaultActionIdentifier:
            return category == reportReminderCategoryIdentifier ? .dailyReport : .timeclock
        default: return nil
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

    static func sendNotification(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        delaySeconds: TimeInterval? = nil,
        reminderSound: TimeclockReminderSound? = nil,
        soundSeconds: Int = 10,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let reminderSound {
            apply(reminderSound, to: content, seconds: soundSeconds)
        } else {
            content.sound = .default
        }
        content.categoryIdentifier = categoryIdentifier
        if identifier == TimeclockReminderDelivery.overtimeOwner {
            content.userInfo[TimeclockReminderDelivery.ownerKey] = identifier
        }
        let trigger = delaySeconds.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false) }
        delivery.send(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger), completion: completion)
    }

    static func request(for plan: TimeclockReminderPlan, plannedAt: Date, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.categoryIdentifier = plan.categoryIdentifier
        content.userInfo[TimeclockReminderDelivery.ownerKey] = plan.ownerIdentifier ?? plan.identifier
        apply(plan.sound, to: content, seconds: plan.soundSeconds)

        let trigger: UNNotificationTrigger
        if let date = plan.fireDate {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            // Authorization and queue work may outlive a one-second catch-up deadline.
            let deliverAt = max(date, now.addingTimeInterval(1))
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: deliverAt)
            components.timeZone = calendar.timeZone
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else if let delay = plan.delaySeconds {
            let remaining = plannedAt.addingTimeInterval(delay).timeIntervalSince(now)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)
        } else {
            let minutes = TimeclockTimeMath.normalizedMinutes(plan.minutes)
            trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60, weekday: plan.weekday),
                repeats: true
            )
        }
        return UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
    }

    static func apply(_ sound: TimeclockReminderSound, to content: UNMutableNotificationContent, seconds: Int = 10) {
        let duration = seconds == 20 ? 20 : 10
        let name = duration == 20 ? "\(sound.rawValue)-20.wav" : sound.fileName
        content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        content.userInfo[reminderSoundUserInfoKey] = sound.rawValue
        content.userInfo["soundSeconds"] = duration
    }

    static func reminderSound(from content: UNNotificationContent) -> TimeclockReminderSound? {
        guard let rawValue = content.userInfo[reminderSoundUserInfoKey] as? String else {
            return nil
        }

        return TimeclockReminderSound(rawValue: rawValue)
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

    private static func breakElapsedSeconds(state: TimeclockState) -> Int? {
        if case .onBreak(let time) = state {
            return TimeclockTimeMath.timerSeconds(from: time)
        }

        return nil
    }

    private static func isActive(state: TimeclockState) -> Bool {
        switch state {
        case .active:
            return true
        case .loading, .loginRequired, .stale, .clockedOut, .onBreak, .unknown:
            return false
        }
    }
}
