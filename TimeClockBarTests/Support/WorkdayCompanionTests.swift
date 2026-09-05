import XCTest
import UserNotifications
@testable import Time_Clock_Bar

@MainActor
final class WorkdayCompanionTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var schedule: WorkdaySchedule {
        WorkdaySchedule(timeZone: TimeZone(identifier: "Asia/Manila")!, weekdays: [2,3,4,5,6],
                        startMinutes: 22 * 60, endMinutes: 7 * 60, breakMinutes: 2 * 60, breakDuration: 60)
    }
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "WorkdayCompanionTests.\(UUID().uuidString)")!
    }
    private func plans(_ engine: WorkdayReminderController, _ state: TimeclockState, _ now: Date) -> [TimeclockReminderPlan] {
        engine.plans(schedule: schedule, state: state, enabled: [.workStart, .breakStart, .breakOver, .clockOut],
                     sounds: [:], workLead: 15, endLead: 15, now: now).plans
    }

    func testFridayOvernightShiftKeepsFridayIdentityOnSaturday() throws {
        let now = date("2026-09-04T19:00:00Z") // Saturday 03:00 Manila
        let shift = try XCTUnwrap(schedule.currentShift(at: now))
        XCTAssertEqual(shift.workDate, "2026-09-04")
        XCTAssertEqual(shift.end, date("2026-09-04T23:00:00Z"))
        XCTAssertEqual(shift.preferredBreak, date("2026-09-04T18:00:00Z"))
    }

    func testDSTUsesCalendarWallTimeRatherThanFixed24Hours() throws {
        let value = WorkdaySchedule(timeZone: TimeZone(identifier: "America/New_York")!, weekdays: Set(1...7),
                                   startMinutes: 22 * 60, endMinutes: 7 * 60, breakMinutes: 2 * 60 + 30, breakDuration: 30)
        let shift = try XCTUnwrap(value.currentShift(at: date("2026-03-08T06:00:00Z")))
        XCTAssertEqual(shift.start, date("2026-03-08T03:00:00Z"))
        XCTAssertEqual(shift.end, date("2026-03-08T11:00:00Z"))
        XCTAssertEqual(shift.preferredBreak, date("2026-03-08T07:00:00Z"))
    }

    func testBreakCompletionSurvivesRelaunchAndUnknownObservation() {
        let preferences = defaults()
        let now = date("2026-09-04T18:30:00Z")
        let engine = WorkdayReminderController(defaults: preferences)
        _ = plans(engine, .onBreak("00:30:00"), now)
        _ = plans(engine, .active("03:00"), now.addingTimeInterval(1800))
        let restarted = WorkdayReminderController(defaults: preferences)
        _ = plans(restarted, .stale, now.addingTimeInterval(1900))
        XCTAssertTrue(restarted.checkpoints.first { $0.kind == .breakStart }!.isComplete)
        XCTAssertTrue(restarted.checkpoints.first { $0.kind == .breakOver }!.isComplete)
        XCTAssertFalse(restarted.checkpoints.first { $0.kind == .clockOut }!.isComplete)
    }

    func testClockedOutDoesNotCreateBreakOrClockOutPlans() {
        let engine = WorkdayReminderController(defaults: defaults())
        let result = plans(engine, .clockedOut, date("2026-09-04T15:00:00Z"))
        XCTAssertFalse(result.contains { $0.ownerIdentifier!.contains("clockOut") || $0.ownerIdentifier!.contains("break") })
    }

    func testCatchUpCoalescesMissedStagesAndDoesNotRepeatAfterRestart() {
        let preferences = defaults()
        let engine = WorkdayReminderController(defaults: preferences)
        let now = date("2026-09-04T14:20:00Z")
        let first = plans(engine, .clockedOut, now).filter { $0.identifier.contains("2026-09-04") }
        XCTAssertEqual(first.count, 1)
        first.forEach { engine.markScheduled($0.identifier) }
        let restarted = WorkdayReminderController(defaults: preferences)
        XCTAssertTrue(plans(restarted, .clockedOut, now.addingTimeInterval(60)).filter { $0.identifier.contains("2026-09-04") }.isEmpty)
        XCTAssertFalse(restarted.checkpoints.first!.isComplete)
    }

    func testSilencePersistsWithoutCompletingCheckpoint() throws {
        let preferences = defaults()
        let engine = WorkdayReminderController(defaults: preferences)
        let now = date("2026-09-04T14:00:00Z")
        _ = plans(engine, .clockedOut, now)
        engine.silence(try XCTUnwrap(engine.checkpoints.first))
        let restarted = WorkdayReminderController(defaults: preferences)
        _ = plans(restarted, .clockedOut, now)
        XCTAssertTrue(restarted.checkpoints.first!.isSilenced)
        XCTAssertFalse(restarted.checkpoints.first!.isComplete)
    }

    func testDatedRequestsNeverRepeatAndKeepCheckpointOwner() throws {
        let engine = WorkdayReminderController(defaults: defaults())
        let now = date("2026-09-04T13:00:00Z")
        let plan = try XCTUnwrap(plans(engine, .clockedOut, now).first)
        let request = TimeclockReminderScheduler.request(for: plan, plannedAt: now, now: now)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertNotNil(trigger.dateComponents.year)
        XCTAssertEqual(TimeclockReminderDelivery.owner(request), plan.ownerIdentifier)
    }








    func testMissedBreakAndClockOutCoalesceToClockOutOnWake() {
        let engine = WorkdayReminderController(defaults: defaults())
        _ = plans(engine, .active("01:00"), date("2026-09-04T15:00:00Z"))
        let now = date("2026-09-04T23:20:00Z")
        let catchUp = plans(engine, .active("09:20"), now).filter { $0.fireDate == now.addingTimeInterval(1) }
        XCTAssertEqual(catchUp.count, 1)
        XCTAssertTrue(catchUp.first?.ownerIdentifier?.hasSuffix("|clockOut") == true)
    }


    func testSecondBreakGetsItsOwnDeadlineAndSilenceIdentity() throws {
        let engine = WorkdayReminderController(defaults: defaults())
        let now = date("2026-09-04T18:00:00Z")
        _ = plans(engine, .onBreak("00:00:00"), now)
        let first = try XCTUnwrap(engine.checkpoints.first { $0.kind == .breakOver })
        engine.silence(first)
        _ = plans(engine, .active("05:00"), now.addingTimeInterval(3600))
        _ = plans(engine, .onBreak("00:02:30"), now.addingTimeInterval(7200))
        let second = try XCTUnwrap(engine.checkpoints.first { $0.kind == .breakOver })
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(second.isSilenced)
        XCTAssertFalse(second.isComplete)
        XCTAssertEqual(second.due, now.addingTimeInterval(7200 - 150 + 3600))
    }

    func testSaturdayDashboardHasNoClockInPrompt() {
        let value = TodayDashboard.resolve(state: .clockedOut, schedule: schedule, checkpoints: [], now: date("2026-09-05T06:00:00Z"))
        XCTAssertEqual(value.phase, .offDay)
        XCTAssertNil(value.actionTitle)
        XCTAssertNil(value.destination)
    }

    func testWrapUpOpensReportBeforeTimeClock() {
        let value = TodayDashboard.resolve(state: .active("08:00"), schedule: schedule, checkpoints: [], now: date("2026-09-04T22:40:00Z"))
        XCTAssertEqual(value.phase, .wrapUp)
        XCTAssertEqual(value.destination, .dailyReport)
        XCTAssertEqual(value.actionTitle, "Open Report")
    }

    func testBreakReturnTakesPriorityOverWrapUp() {
        let value = TodayDashboard.resolve(state: .onBreak("00:55:30"), schedule: schedule, checkpoints: [], now: date("2026-09-04T22:40:00Z"))
        XCTAssertEqual(value.phase, .onBreak)
        XCTAssertEqual(value.destination, .timeclock)
        XCTAssertEqual(value.deadline, date("2026-09-04T22:44:30Z"))
    }

    func testAdvanceClockOutReminderOpensReportAndDueReminderOpensClock() throws {
        let engine = WorkdayReminderController(defaults: defaults())
        let result = plans(engine, .active("07:00"), date("2026-09-04T21:00:00Z"))
        let advance = try XCTUnwrap(result.first { $0.identifier.hasSuffix("clockOut|advance") })
        XCTAssertEqual(advance.categoryIdentifier, TimeclockReminderScheduler.reportReminderCategoryIdentifier)
        XCTAssertEqual(TimeclockReminderScheduler.popoverPage(for: UNNotificationDefaultActionIdentifier, category: advance.categoryIdentifier), .dailyReport)
        let due = try XCTUnwrap(result.first { $0.identifier.hasSuffix("clockOut|due-0") })
        XCTAssertEqual(due.categoryIdentifier, TimeclockReminderScheduler.reminderCategoryIdentifier)
        XCTAssertTrue(due.body.contains("report"))
    }

    func testTestHostNeverLoadsWebsites() {
        let controller = TimeclockController()
        XCTAssertTrue(controller.isPreview)
        XCTAssertFalse(controller.canSendTestNotifications)
        controller.load()
        controller.loadDailyReport()
        controller.reload()
        controller.startPolling()
        XCTAssertNil(controller.webView.url)
        XCTAssertNil(controller.dailyReportWebView.url)
        XCTAssertFalse(controller.isPolling)
    }

}
