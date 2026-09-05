import XCTest
import UserNotifications
@testable import Time_Clock_Bar

final class TimeclockReminderSchedulerTests: XCTestCase {
    func testEmptyWorkingWeekdaysReturnNoPlans() {
        XCTAssertTrue(defaultPlans(workingWeekdays: []).isEmpty)
    }

    func testAllReminderTogglesOffReturnNoPlans() {
        XCTAssertTrue(defaultPlans(
            workReminderEnabled: false,
            breakReminderEnabled: false,
            breakOverReminderEnabled: false,
            clockOutReminderEnabled: false
        ).isEmpty)
    }

    func testClockedOutOnlySchedulesClockInReminder() {
        let plans = defaultPlans(state: .clockedOut)

        XCTAssertEqual(plans.map(\.identifier), ["work-start-reminder-2"])
    }

    func testUnavailableClockStatesDoNotScheduleBreakOrClockOutAssertions() {
        for state in [TimeclockState.loading, .loginRequired, .stale, .unknown(nil)] {
            let plans = defaultPlans(state: state)
            XCTAssertFalse(plans.contains { $0.identifier.hasPrefix("break-") }, "\(state)")
            XCTAssertFalse(plans.contains { $0.identifier.hasPrefix("clock-out-") }, "\(state)")
        }
    }

    func testOvernightBreakUsesFollowingWeekday() throws {
        let plan = try XCTUnwrap(defaultPlans(
            state: .active("1:00"),
            workingWeekdays: [7],
            workStartMinutes: 22 * 60,
            breakReminderMinutes: 2 * 60,
            workEndMinutes: 6 * 60
        ).first { $0.identifier.hasPrefix("break-reminder-") })

        XCTAssertEqual(plan.weekday, 1)
        XCTAssertEqual(plan.minutes, 2 * 60)
    }

    func testBreakOutsideShiftDoesNotSchedule() {
        for breakTime in [8 * 60, 17 * 60, 20 * 60] {
            XCTAssertFalse(defaultPlans(state: .active("1:00"), breakReminderMinutes: breakTime)
                .contains { $0.identifier.hasPrefix("break-reminder-") })
        }
    }

    func testBreakReturnPreservesElapsedSeconds() throws {
        for timer in ["0:59:50", "0:59.50"] {
            let plan = try XCTUnwrap(defaultPlans(state: .onBreak(timer), workingWeekdays: []).first)
            XCTAssertEqual(plan.delaySeconds, 10)
        }
    }

    func testUnknownBreakTimerDoesNotInventAFullBreakRemaining() {
        for timer in ["", "unavailable", "0:xx:30", "0:60:00", "0:05:99"] {
            XCTAssertTrue(defaultPlans(state: .onBreak(timer), workingWeekdays: []).isEmpty)
        }
    }

    func testZeroDurationDoesNotScheduleBreakReminders() {
        for state in [TimeclockState.active("1:00"), .onBreak("0:10")] {
            XCTAssertFalse(defaultPlans(state: state, breakDurationMinutes: 0)
                .contains { $0.identifier.hasPrefix("break-") })
        }
    }

    func testActiveSkipsShiftReminderOnly() {
        let plans = defaultPlans(state: .active("1:00"))

        XCTAssertEqual(plans.map(\.identifier), ["break-reminder-2", "clock-out-reminder-2"])
    }

    func testOnBreakSchedulesBreakOverReminder() throws {
        let plans = defaultPlans(state: .onBreak("0:10"))
        let plan = try XCTUnwrap(plans.first)

        XCTAssertEqual(plans.map(\.identifier), ["break-over-reminder", "clock-out-reminder-2"])
        XCTAssertEqual(plan.title, "Over break")
        XCTAssertEqual(plan.body, "Time to end your break.")
        XCTAssertEqual(plan.categoryIdentifier, TimeclockReminderScheduler.reminderCategoryIdentifier)
        XCTAssertEqual(plan.minutes, 60)
        XCTAssertEqual(plan.delaySeconds, TimeInterval(50 * 60))
    }

    func testOnBreakSchedulesBreakOverReminderWithoutWorkingWeekdays() throws {
        let plan = try XCTUnwrap(defaultPlans(
            state: .onBreak("0:10"),
            workingWeekdays: []
        ).first)

        XCTAssertEqual(plan.identifier, "break-over-reminder")
        XCTAssertEqual(plan.delaySeconds, TimeInterval(50 * 60))
    }

    func testOnBreakSchedulesBreakOverReminderImmediatelyWhenAlreadyOverBreak() throws {
        let plan = try XCTUnwrap(defaultPlans(
            state: .onBreak("1:05"),
            workingWeekdays: []
        ).first)

        XCTAssertEqual(plan.identifier, "break-over-reminder")
        XCTAssertEqual(plan.delaySeconds, TimeInterval(1))
    }

    func testOnBreakSkipsBreakOverReminderWhenDisabled() {
        let plans = defaultPlans(
            state: .onBreak("0:10"),
            breakOverReminderEnabled: false
        )

        XCTAssertEqual(plans.map(\.identifier), ["clock-out-reminder-2"])
    }

    func testWorkReminderAtMidnightKeepsWeekday() throws {
        let plan = try XCTUnwrap(defaultPlans(
            workStartMinutes: 15,
            workReminderLeadMinutes: 15,
            breakReminderEnabled: false,
            clockOutReminderEnabled: false
        ).first)

        XCTAssertEqual(plan.minutes, 0)
        XCTAssertEqual(plan.weekday, 2)
    }

    func testWorkReminderBeforeMidnightMovesToPreviousWeekday() throws {
        let plan = try XCTUnwrap(defaultPlans(
            workStartMinutes: 5,
            workReminderLeadMinutes: 15,
            breakReminderEnabled: false,
            clockOutReminderEnabled: false
        ).first)

        XCTAssertEqual(TimeclockTimeMath.normalizedMinutes(plan.minutes), 1430)
        XCTAssertEqual(plan.weekday, 1)
    }

    func testOvernightShiftClockOutMovesToNextWeekday() throws {
        let plan = try XCTUnwrap(defaultPlans(
            state: .active("1:00"),
            workReminderEnabled: false,
            workStartMinutes: 22 * 60,
            breakReminderEnabled: false,
            workEndMinutes: 6 * 60,
            clockOutReminderLeadMinutes: 15
        ).first)

        XCTAssertEqual(plan.identifier, "clock-out-reminder-2")
        XCTAssertEqual(plan.weekday, 3)
        XCTAssertEqual(TimeclockTimeMath.normalizedMinutes(plan.minutes), 5 * 60 + 45)
    }

    func testReminderCategoriesMatchReminderType() {
        for state in [TimeclockState.clockedOut, .active("1:00"), .onBreak("0:10")] {
            let plans = defaultPlans(state: state)
            XCTAssertFalse(plans.isEmpty)
            XCTAssertTrue(plans.allSatisfy { $0.categoryIdentifier == TimeclockReminderScheduler.reminderCategoryIdentifier })
        }
    }

    func testReminderPlansUseConfiguredSounds() {
        let plans = TimeclockReminderScheduler.plans(
            state: .active("1:00"),
            workingWeekdays: [2],
            workReminderEnabled: true,
            workStartMinutes: 9 * 60,
            workReminderLeadMinutes: 15,
            breakReminderEnabled: true,
            breakReminderMinutes: 12 * 60,
            breakOverReminderEnabled: false,
            breakDurationMinutes: 60,
            clockOutReminderEnabled: true,
            workEndMinutes: 17 * 60,
            clockOutReminderLeadMinutes: 15,
            workReminderSound: .siren,
            breakReminderSound: .signal,
            breakOverReminderSound: .urgent,
            clockOutReminderSound: .beacon
        )

        XCTAssertEqual(plans.map(\.sound), [.signal, .beacon])
    }

    func testApplyingReminderSoundAddsNotificationSoundMetadata() {
        let content = UNMutableNotificationContent()

        TimeclockReminderScheduler.apply(.siren, to: content)

        XCTAssertNotNil(content.sound)
        XCTAssertEqual(
            TimeclockReminderScheduler.reminderSound(from: content),
            .siren
        )
    }

    func testInvalidReminderSoundMetadataIsIgnored() {
        let content = UNMutableNotificationContent()
        content.userInfo[TimeclockReminderScheduler.reminderSoundUserInfoKey] = "missing"

        XCTAssertNil(TimeclockReminderScheduler.reminderSound(from: content))
    }

    func testReminderCategoriesProvideStopAndDismissActions() throws {
        let categories = TimeclockReminderScheduler.notificationCategories()

        for identifier in [
            TimeclockReminderScheduler.reminderCategoryIdentifier,
            TimeclockReminderScheduler.reportReminderCategoryIdentifier
        ] {
            let category = try XCTUnwrap(categories.first { $0.identifier == identifier })

            XCTAssertTrue(category.actions.contains { $0.identifier == TimeclockReminderScheduler.stopAlarmActionIdentifier })
            XCTAssertEqual(category.actions[1].identifier, TimeclockReminderScheduler.snooze5ActionIdentifier)
            XCTAssertEqual(category.actions.first?.identifier, identifier == TimeclockReminderScheduler.reminderCategoryIdentifier
                ? TimeclockReminderScheduler.openTimeclockActionIdentifier
                : TimeclockReminderScheduler.openDailyReportActionIdentifier)
            XCTAssertTrue(category.options.contains(.customDismissAction))
        }
    }

    func testNotificationActionsRouteToTheirOwnPage() {
        let report = TimeclockReminderScheduler.reportReminderCategoryIdentifier
        let clock = TimeclockReminderScheduler.reminderCategoryIdentifier
        XCTAssertEqual(TimeclockReminderScheduler.popoverPage(for: "open-timeclock", category: report), .timeclock)
        XCTAssertEqual(TimeclockReminderScheduler.popoverPage(for: "open-daily-report", category: clock), .dailyReport)
        XCTAssertEqual(TimeclockReminderScheduler.popoverPage(for: UNNotificationDefaultActionIdentifier, category: clock), .timeclock)
        XCTAssertEqual(TimeclockReminderScheduler.popoverPage(for: UNNotificationDefaultActionIdentifier, category: report), .dailyReport)
        XCTAssertNil(TimeclockReminderScheduler.popoverPage(for: "stop-alarm", category: clock))
        XCTAssertNil(TimeclockReminderScheduler.popoverPage(for: "snooze-5", category: clock))
    }

    func testBreakDeadlineDoesNotMoveWhileWaitingForAuthorization() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let plan = try XCTUnwrap(defaultPlans(state: .onBreak("0:59:50"), workingWeekdays: []).first)
        let request = TimeclockReminderScheduler.request(for: plan, plannedAt: start, now: start.addingTimeInterval(7))
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 3)
    }

    private func defaultPlans(
        state: TimeclockState = .clockedOut,
        workingWeekdays: Set<Int> = [2],
        workReminderEnabled: Bool = true,
        workStartMinutes: Int = 9 * 60,
        workReminderLeadMinutes: Int = 15,
        breakReminderEnabled: Bool = true,
        breakReminderMinutes: Int = 12 * 60,
        breakOverReminderEnabled: Bool = true,
        breakDurationMinutes: Int = 60,
        clockOutReminderEnabled: Bool = true,
        workEndMinutes: Int = 17 * 60,
        clockOutReminderLeadMinutes: Int = 15
    ) -> [TimeclockReminderPlan] {
        TimeclockReminderScheduler.plans(
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
    }
}
