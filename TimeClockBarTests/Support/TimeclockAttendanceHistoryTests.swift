import XCTest
@testable import Time_Clock_Bar

@MainActor
final class TimeclockAttendanceHistoryTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Manila")!
    private var schedule: WorkdaySchedule {
        WorkdaySchedule(timeZone: zone, weekdays: [2,3,4,5,6], startMinutes: 900,
            endMinutes: 0, breakMinutes: 1200, breakDuration: 60)
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "AttendanceHistory.\(UUID().uuidString)")! }
    private let breaking = [TimeclockHistoryEntry(isBreak: true, start: "8:09 PM", end: "Present"),
                            TimeclockHistoryEntry(isBreak: false, start: "2:38 PM", end: "8:09 PM")]

    func testRecordedTimesReplaceScheduledDisplayAndRepairBreakDeadline() {
        let preferences = defaults()
        let engine = WorkdayReminderController(defaults: preferences)
        engine.observe(state: .onBreak("00:00"), schedule: schedule, now: date("2026-09-11T12:00:00Z"))
        let now = date("2026-09-11T12:41:23Z")
        engine.observe(state: .onBreak("00:32.23"), schedule: schedule, now: now, history: breaking, historyTimeZone: zone)
        let clockIn = engine.checkpoints.first { $0.kind == .workStart }
        XCTAssertEqual(clockIn?.due, date("2026-09-11T07:00:00Z")) // Policy stays 15:00.
        XCTAssertEqual(clockIn?.displayedDate, date("2026-09-11T06:38:00Z"))
        XCTAssertEqual(clockIn?.timingLabel, "Recorded")
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .breakStart }?.displayedDate, date("2026-09-11T12:09:00Z"))
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .breakOver }?.displayedDate, date("2026-09-11T13:09:00Z"))
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .breakOver }?.timingLabel, "Due")
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .clockOut }?.timingLabel, "Scheduled")
        let restarted = WorkdayReminderController(defaults: preferences)
        restarted.observe(state: .stale, schedule: schedule, now: now)
        XCTAssertEqual(restarted.checkpoints.first { $0.kind == .workStart }?.displayedDate, date("2026-09-11T06:38:00Z"))
    }

    func testAfterMidnightClockOutUsesRecordedEndRatherThanObservationTime() {
        let engine = WorkdayReminderController(defaults: defaults())
        engine.observe(state: .onBreak("00:32.23"), schedule: schedule, now: date("2026-09-11T12:41:23Z"),
            history: breaking, historyTimeZone: zone)
        let returned = [TimeclockHistoryEntry(isBreak: false, start: "9:10 PM", end: "Present"),
                        TimeclockHistoryEntry(isBreak: true, start: "8:09 PM", end: "9:10 PM"), breaking[1]]
        engine.observe(state: .active("00:05"), schedule: schedule, now: date("2026-09-11T13:15:00Z"),
            history: returned, historyTimeZone: zone)
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .breakOver }?.displayedDate, date("2026-09-11T13:10:00Z"))
        var completed = returned
        completed[0] = TimeclockHistoryEntry(isBreak: false, start: "Sep 11, 9:10 PM", end: "Sep 12, 12:01 AM")
        let observed = date("2026-09-11T16:10:00Z")
        engine.observe(state: .clockedOut, schedule: schedule, now: observed, history: completed, historyTimeZone: zone)
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .clockOut }?.displayedDate, date("2026-09-11T16:01:00Z"))
        XCTAssertEqual(engine.lastCompletedShift?.actualClockOut, date("2026-09-11T16:01:00Z"))
        XCTAssertEqual(engine.lastCompletedShift?.observedAt, observed)
        XCTAssertEqual(engine.lastCompletedShift?.workDate, "2026-09-11")
    }

    func testUnknownHistoryDoesNotTurnScheduledOrObservedTimesIntoActualTimes() {
        let engine = WorkdayReminderController(defaults: defaults())
        let now = date("2026-09-11T12:41:23Z")
        engine.observe(state: .active("05:00"), schedule: schedule, now: now)
        let clockIn = engine.checkpoints.first { $0.kind == .workStart }
        XCTAssertTrue(clockIn?.isComplete == true)
        XCTAssertNil(clockIn?.displayedDate)
        XCTAssertEqual(clockIn?.timingLabel, "Time unavailable")
        engine.observe(state: .stale, schedule: schedule, now: now, history: breaking, historyTimeZone: zone)
        XCTAssertNil(engine.checkpoints.first { $0.kind == .workStart }?.actualDate)
        // A logged-out page/history cannot establish completion for an unobserved work session.
        let fresh = WorkdayReminderController(defaults: defaults())
        fresh.observe(state: .clockedOut, schedule: schedule, now: now,
            history: [TimeclockHistoryEntry(isBreak: false, start: "2:38 PM", end: "8:09 PM")], historyTimeZone: zone)
        XCTAssertFalse(fresh.checkpoints.contains { $0.isComplete })
    }

    func testOpeningAppAfterBreakRestoresRecordedBreakCompletion() {
        let engine = WorkdayReminderController(defaults: defaults())
        let history = [TimeclockHistoryEntry(isBreak: false, start: "9:10 PM", end: "Present"),
                       TimeclockHistoryEntry(isBreak: true, start: "8:09 PM", end: "9:10 PM"), breaking[1]]
        let now = date("2026-09-11T13:15:00Z")
        engine.observe(state: .active("00:05"), schedule: schedule, now: now, history: history, historyTimeZone: zone)
        XCTAssertTrue(engine.checkpoints.first { $0.kind == .breakStart }?.isComplete == true)
        XCTAssertTrue(engine.checkpoints.first { $0.kind == .breakOver }?.isComplete == true)
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .breakOver }?.displayedDate, date("2026-09-11T13:10:00Z"))
        let plans = engine.plans(schedule: schedule, state: .active("00:05"), enabled: [.breakStart, .breakOver],
            sounds: [:], workLead: 15, endLead: 15, now: now).plans
        XCTAssertFalse(plans.contains { $0.ownerIdentifier?.hasPrefix("Asia/Manila|2026-09-11|break") == true })
    }

    func testHistoryLocalTimezoneAndNewYearOvernightDates() throws {
        let now = date("2027-01-01T00:10:00Z") // 16:10 December 31 in Los Angeles
        let value = WorkdaySchedule(timeZone: TimeZone(identifier: "America/Los_Angeles")!, weekdays: Set(1...7),
            startMinutes: 8 * 60, endMinutes: 17 * 60, breakMinutes: 12 * 60, breakDuration: 60)
        let history = [TimeclockHistoryEntry(isBreak: false, start: "Dec 31, 1:00 PM", end: "4:01 PM"),
                       TimeclockHistoryEntry(isBreak: true, start: "12:00 PM", end: "1:00 PM"),
                       TimeclockHistoryEntry(isBreak: false, start: "8:38 AM", end: "12:00 PM")]
        let actual = TimeclockAttendanceHistory.resolve(history, timeZone: value.timeZone,
            shift: try XCTUnwrap(value.currentShift(at: now)), schedule: value, state: .clockedOut, now: now)
        XCTAssertEqual(actual?.clockIn, date("2026-12-31T16:38:00Z"))
        XCTAssertEqual(actual?.clockOut, date("2027-01-01T00:01:00Z"))
    }

    func testLaterBreakUsesLatestRecordedBreakAndKeepsOriginalClockIn() {
        let engine = WorkdayReminderController(defaults: defaults())
        let now = date("2026-09-11T14:05:00Z")
        let history = [TimeclockHistoryEntry(isBreak: true, start: "10:00 PM", end: "Present"),
                       TimeclockHistoryEntry(isBreak: false, start: "9:10 PM", end: "10:00 PM"),
                       TimeclockHistoryEntry(isBreak: true, start: "8:09 PM", end: "9:10 PM"), breaking[1]]
        engine.observe(state: .onBreak("00:05:00"), schedule: schedule, now: now, history: history, historyTimeZone: zone)
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .workStart }?.displayedDate, date("2026-09-11T06:38:00Z"))
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .breakStart }?.displayedDate, date("2026-09-11T14:00:00Z"))
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .breakOver }?.displayedDate, date("2026-09-11T15:00:00Z"))
    }
}
