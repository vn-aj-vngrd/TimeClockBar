import XCTest
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

    func testClockedOutSkipsClockOutReminderOnly() {
        let plans = defaultPlans(state: .clockedOut)

        XCTAssertEqual(plans.map(\.identifier), ["work-start-reminder-2", "break-reminder-2"])
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
        let plans = defaultPlans(state: .loading)

        XCTAssertEqual(plans[0].categoryIdentifier, TimeclockReminderScheduler.reminderCategoryIdentifier)
        XCTAssertEqual(plans[1].categoryIdentifier, TimeclockReminderScheduler.reminderCategoryIdentifier)
        XCTAssertEqual(plans[2].categoryIdentifier, TimeclockReminderScheduler.reportReminderCategoryIdentifier)
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
