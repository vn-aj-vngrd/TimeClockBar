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

    func testWakeWaitsForFreshObservationBeforeCatchUp() {
        let engine = WorkdayReminderController(defaults: defaults())
        let now = date("2026-09-04T14:20:00Z")
        XCTAssertFalse(plans(engine, .stale, now).contains { $0.fireDate == now.addingTimeInterval(1) })
        XCTAssertEqual(plans(engine, .clockedOut, now).filter { $0.fireDate == now.addingTimeInterval(1) }.count, 1)
    }

    func testOverdueBreakTakesPriorityOverSimultaneousClockOut() {
        let engine = WorkdayReminderController(defaults: defaults())
        let now = date("2026-09-04T23:20:00Z")
        let result = plans(engine, .onBreak("01:20:00"), now).filter { $0.fireDate == now.addingTimeInterval(1) }
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.ownerIdentifier?.contains("|breakOver-") == true)
    }

    func testSaturdayDashboardHasNoClockInPrompt() {
        let value = TodayDashboard.resolve(state: .clockedOut, schedule: schedule, checkpoints: [], now: date("2026-09-05T06:00:00Z"))
        XCTAssertEqual(value.phase, .offDay)
        XCTAssertNil(value.actionTitle)
        XCTAssertNil(value.destination)
    }

    func testClockOutAfterMidnightShowsNextAfternoonShift() {
        let afternoon = WorkdaySchedule(timeZone: schedule.timeZone, weekdays: [2,3,4,5,6],
            startMinutes: 15 * 60, endMinutes: 0, breakMinutes: 20 * 60, breakDuration: 60)
        let engine = WorkdayReminderController(defaults: defaults())
        engine.observe(state: .active("08:59"), schedule: afternoon, now: date("2026-09-07T15:59:00Z"))
        let now = date("2026-09-07T16:01:00Z") // Tuesday 00:01 Manila
        engine.observe(state: .clockedOut, schedule: afternoon, now: now)
        let value = TodayDashboard.resolve(state: .clockedOut, schedule: afternoon,
            checkpoints: engine.checkpoints, now: now)
        XCTAssertEqual(value.phase, .upcoming)
        XCTAssertEqual(value.deadline, date("2026-09-08T07:00:00Z"))
        XCTAssertEqual(value.title, "Your next shift")
        XCTAssertEqual(value.shift?.workDate, "2026-09-08")
        XCTAssertTrue(value.checkpoints.isEmpty)
        XCTAssertEqual(value.previousShift?.workDate, "2026-09-07")
        XCTAssertFalse(value.isReportComplete)
    }

    func testCompletedShiftSummarySurvivesRestartAfterRecoveryWindow() {
        let preferences = defaults()
        let afternoon = WorkdaySchedule(timeZone: schedule.timeZone, weekdays: [2,3,4,5,6],
            startMinutes: 15 * 60, endMinutes: 0, breakMinutes: 20 * 60, breakDuration: 60)
        let engine = WorkdayReminderController(defaults: preferences)
        engine.observe(state: .active("08:59"), schedule: afternoon, now: date("2026-09-07T15:59:00Z"))
        let clockOut = date("2026-09-07T16:01:00Z")
        engine.observe(state: .clockedOut, schedule: afternoon, now: clockOut)
        engine.observe(state: .clockedOut, schedule: afternoon, now: clockOut.addingTimeInterval(60))
        let restarted = WorkdayReminderController(defaults: preferences)
        let morning = date("2026-09-08T00:00:00Z") // 08:00 Tuesday, old recovery window has ended
        restarted.observe(state: .stale, schedule: afternoon, now: morning)
        let value = TodayDashboard.resolve(state: .stale, schedule: afternoon,
            checkpoints: restarted.checkpoints, now: morning, lastCompletedShift: restarted.lastCompletedShift)
        XCTAssertEqual(value.shift?.workDate, "2026-09-08")
        XCTAssertEqual(value.previousShift?.workDate, "2026-09-07")
        XCTAssertEqual(value.previousShift?.observedAt, clockOut)
        XCTAssertFalse(value.checkpoints.contains { $0.isComplete })
        XCTAssertFalse(value.isReportComplete)
    }

    func testMidnightDoesNotResetAnUnfinishedShiftOrBreak() {
        let afternoon = WorkdaySchedule(timeZone: schedule.timeZone, weekdays: [2,3,4,5,6],
            startMinutes: 15 * 60, endMinutes: 0, breakMinutes: 20 * 60, breakDuration: 60)
        let preferences = defaults()
        let engine = WorkdayReminderController(defaults: preferences)
        engine.observe(state: .active("08:59"), schedule: afternoon, now: date("2026-09-07T15:59:00Z"))
        let now = date("2026-09-07T16:01:00Z")
        for state: TimeclockState in [.active("09:01"), .onBreak("00:05:00"), .stale, .unknown(nil), .loginRequired] {
            let restarted = WorkdayReminderController(defaults: preferences)
            restarted.observe(state: state, schedule: afternoon, now: now)
            let value = TodayDashboard.resolve(state: state, schedule: afternoon,
                checkpoints: restarted.checkpoints, now: now, lastCompletedShift: restarted.lastCompletedShift)
            XCTAssertEqual(value.shift?.workDate, "2026-09-07")
            XCTAssertTrue(value.checkpoints.first { $0.kind == .workStart }?.isComplete == true)
            XCTAssertFalse(value.isReportComplete)
            XCTAssertNil(value.previousShift)
            if case .onBreak = state { XCTAssertEqual(value.phase, .onBreak) }
        }
    }

    func testEarlyClockInForNextShiftStartsItsOwnChecklist() {
        let afternoon = WorkdaySchedule(timeZone: schedule.timeZone, weekdays: [2,3,4,5,6],
            startMinutes: 15 * 60, endMinutes: 0, breakMinutes: 20 * 60, breakDuration: 60)
        let engine = WorkdayReminderController(defaults: defaults())
        engine.observe(state: .active("08:59"), schedule: afternoon, now: date("2026-09-07T15:59:00Z"))
        engine.observe(state: .clockedOut, schedule: afternoon, now: date("2026-09-07T16:01:00Z"))
        let early = date("2026-09-08T06:00:00Z") // Tuesday 14:00, an hour before the next shift
        let plans = engine.plans(schedule: afternoon, state: .active("00:01"), enabled: [.workStart, .clockOut],
            sounds: [:], workLead: 15, endLead: 15, now: early).plans
        let value = TodayDashboard.resolve(state: .active("00:01"), schedule: afternoon,
            checkpoints: engine.checkpoints, now: early, lastCompletedShift: engine.lastCompletedShift)
        XCTAssertEqual(value.phase, .working)
        XCTAssertEqual(value.shift?.workDate, "2026-09-08")
        XCTAssertTrue(value.checkpoints.first { $0.kind == .workStart }?.isComplete == true)
        XCTAssertFalse(value.checkpoints.first { $0.kind == .clockOut }?.isComplete == true)
        XCTAssertFalse(value.isReportComplete)
        XCTAssertNil(value.previousShift)
        XCTAssertFalse(plans.contains { $0.ownerIdentifier == "Asia/Manila|2026-09-08|workStart" })
        XCTAssertTrue(plans.contains { $0.ownerIdentifier == "Asia/Manila|2026-09-08|clockOut" })
    }

    func testFridayClockOutAfterMidnightShowsMondayWithoutClockInPrompt() {
        let afternoon = WorkdaySchedule(timeZone: schedule.timeZone, weekdays: [2,3,4,5,6],
            startMinutes: 15 * 60, endMinutes: 0, breakMinutes: 20 * 60, breakDuration: 60)
        let engine = WorkdayReminderController(defaults: defaults())
        engine.observe(state: .active("08:59"), schedule: afternoon, now: date("2026-09-11T15:59:00Z"))
        let now = date("2026-09-11T16:01:00Z")
        engine.observe(state: .clockedOut, schedule: afternoon, now: now)
        let value = TodayDashboard.resolve(state: .clockedOut, schedule: afternoon,
            checkpoints: engine.checkpoints, now: now, lastCompletedShift: engine.lastCompletedShift)
        XCTAssertEqual(value.phase, .offDay)
        XCTAssertEqual(value.shift?.workDate, "2026-09-14")
        XCTAssertEqual(value.previousShift?.workDate, "2026-09-11")
        XCTAssertEqual(value.deadline, date("2026-09-14T07:00:00Z"))
        XCTAssertNil(value.actionTitle)
        XCTAssertTrue(value.checkpoints.isEmpty)
    }

    func testLegacyCompletedShiftHasNoInventedConfirmationTime() {
        let preferences = defaults()
        let legacy = #"{"Asia/Manila|2026-09-07":{"seenWorking":true,"clockedOut":true,"breakReturned":true,"silenced":[],"scheduledEvents":[]}}"#
        preferences.set(Data(legacy.utf8), forKey: "workdayCheckpointLedger.v1")
        let engine = WorkdayReminderController(defaults: preferences)
        XCTAssertEqual(engine.lastCompletedShift?.workDate, "2026-09-07")
        XCTAssertNil(engine.lastCompletedShift?.observedAt)
        XCTAssertNil(engine.persistenceError)
    }

    func testWrapUpOpensReportBeforeTimeClock() {
        let value = TodayDashboard.resolve(state: .active("08:00"), schedule: schedule, checkpoints: [], now: date("2026-09-04T22:40:00Z"))
        XCTAssertEqual(value.phase, .wrapUp)
        XCTAssertEqual(value.destination, .dailyReport)
        XCTAssertEqual(value.actionTitle, "Open Report")
    }

    func testReportCompletesOnlyAfterObservedWorkThenClockOut() {
        let engine = WorkdayReminderController(defaults: defaults())
        let now = date("2026-09-04T15:00:00Z")
        for state: TimeclockState in [.clockedOut, .active("01:00"), .onBreak("00:10:00"), .stale, .unknown(nil), .loginRequired] {
            engine.observe(state: state, schedule: schedule, now: now)
            XCTAssertFalse(TodayDashboard.resolve(state: state, schedule: schedule,
                checkpoints: engine.checkpoints, now: now).isReportComplete)
        }
        engine.observe(state: .clockedOut, schedule: schedule, now: now)
        let completed = TodayDashboard.resolve(state: .clockedOut, schedule: schedule,
            checkpoints: engine.checkpoints, now: now)
        XCTAssertEqual(completed.previousShift?.workDate, "2026-09-04")
        XCTAssertFalse(completed.isReportComplete) // The next shift's report is still pending.
    }

    func testReportCompletionSurvivesRefreshAndRestartButNotNextShift() {
        let preferences = defaults()
        let engine = WorkdayReminderController(defaults: preferences)
        let now = date("2026-09-04T22:50:00Z") // Saturday morning, still Friday's shift
        engine.observe(state: .active("08:00"), schedule: schedule, now: now)
        engine.observe(state: .clockedOut, schedule: schedule, now: now)
        let restarted = WorkdayReminderController(defaults: preferences)
        restarted.observe(state: .stale, schedule: schedule, now: now.addingTimeInterval(900))
        let completed = TodayDashboard.resolve(state: .stale, schedule: schedule,
            checkpoints: restarted.checkpoints, now: now.addingTimeInterval(900))
        XCTAssertEqual(completed.previousShift?.workDate, "2026-09-04")
        XCTAssertFalse(completed.isReportComplete)
        let nextShift = date("2026-09-07T13:00:00Z")
        // A view tick can select the next shift before the next observation updates the ledger.
        XCTAssertFalse(TodayDashboard.resolve(state: .clockedOut, schedule: schedule,
            checkpoints: restarted.checkpoints, now: nextShift).isReportComplete)
        restarted.observe(state: .clockedOut, schedule: schedule, now: nextShift)
        XCTAssertFalse(TodayDashboard.resolve(state: .clockedOut, schedule: schedule,
            checkpoints: restarted.checkpoints, now: nextShift).isReportComplete)
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
