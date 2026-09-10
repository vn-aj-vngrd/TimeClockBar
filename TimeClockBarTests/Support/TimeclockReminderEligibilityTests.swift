import XCTest
import UserNotifications
@testable import Time_Clock_Bar

@MainActor
final class TimeclockReminderEligibilityTests: XCTestCase {
    private var schedule: WorkdaySchedule {
        WorkdaySchedule(timeZone: TimeZone(identifier: "Asia/Manila")!, weekdays: [2, 3, 4, 5, 6],
                        startMinutes: 14 * 60 + 50, endMinutes: 23 * 60 + 50,
                        breakMinutes: 19 * 60, breakDuration: 60)
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func preferences() -> UserDefaults {
        UserDefaults(suiteName: "ReminderEligibility.\(UUID().uuidString)")!
    }
    private func runtime(_ engine: WorkdayReminderController, state: TimeclockState, at now: Date)
        -> (plans: [TimeclockReminderPlan], owners: Set<String>) {
        engine.plans(schedule: schedule, state: state, enabled: [.workStart, .breakStart, .breakOver, .clockOut],
                     sounds: [:], workLead: 15, endLead: 15, now: now)
    }
    private func reconcile(_ result: (plans: [TimeclockReminderPlan], owners: Set<String>),
                           engine: WorkdayReminderController, delivery: TimeclockReminderDelivery) async {
        await delivery.reconcile(plans: result.plans, activeOwners: result.owners,
                                 onScheduled: { engine.markScheduled($0) }).value
    }

    func testEarlyClockInCancelsTodaysClockInAlertsAndSnoozeButKeepsTomorrow() async throws {
        let defaults = preferences()
        let engine = WorkdayReminderController(defaults: defaults)
        let center = MemoryNotificationCenter()
        var now = date("2026-09-10T03:00:00Z") // 11:00 Manila, before a 14:50 shift.
        let delivery = TimeclockReminderDelivery(center: center, now: { now })
        let owner = "Asia/Manila|2026-09-10|workStart"
        await reconcile(runtime(engine, state: .clockedOut, at: now), engine: engine, delivery: delivery)
        let queued = try XCTUnwrap(center.pending.values.first { TimeclockReminderDelivery.owner($0) == owner })
        await delivery.snooze(queued, minutes: 5).value
        center.delivered[queued.identifier] = queued

        now = date("2026-09-10T04:00:00Z") // Already working at 12:00, over an hour early.
        await reconcile(runtime(engine, state: .active("00:01"), at: now), engine: engine, delivery: delivery)
        XCTAssertFalse(center.pending.values.contains { TimeclockReminderDelivery.owner($0) == owner })
        XCTAssertFalse(center.delivered.values.contains { TimeclockReminderDelivery.owner($0) == owner })
        XCTAssertTrue(center.pending.keys.contains { $0.contains("2026-09-11|workStart") })

        let restarted = WorkdayReminderController(defaults: defaults)
        let due = date("2026-09-10T06:50:00Z") // 14:50, even if status is temporarily unavailable.
        XCTAssertFalse(runtime(restarted, state: .stale, at: due).owners.contains(owner))
        XCTAssertTrue(restarted.checkpoints.first { $0.kind == .workStart }?.isComplete == true)
    }

    func testAlreadyOnBreakCancelsStartBreakEvenWhenTimerIsUnreadable() async throws {
        let defaults = preferences()
        let engine = WorkdayReminderController(defaults: defaults)
        let center = MemoryNotificationCenter()
        let now = date("2026-09-10T10:00:00Z") // 18:00 Manila, before the preferred break.
        let delivery = TimeclockReminderDelivery(center: center, now: { now })
        let owner = "Asia/Manila|2026-09-10|breakStart"
        await reconcile(runtime(engine, state: .active("03:10"), at: now), engine: engine, delivery: delivery)
        let queued = try XCTUnwrap(center.pending.values.first { TimeclockReminderDelivery.owner($0) == owner })
        await delivery.snooze(queued, minutes: 5).value
        center.delivered[queued.identifier] = queued

        await reconcile(runtime(engine, state: .onBreak("--:--"), at: now), engine: engine, delivery: delivery)
        XCTAssertFalse(center.pending.values.contains { TimeclockReminderDelivery.owner($0) == owner })
        XCTAssertFalse(center.delivered.values.contains { TimeclockReminderDelivery.owner($0) == owner })
        XCTAssertTrue(center.pending.keys.contains { $0.contains("2026-09-10|clockOut") })
        XCTAssertFalse(engine.checkpoints.contains { $0.kind == .breakOver }) // No invented deadline.

        let restarted = WorkdayReminderController(defaults: defaults)
        XCTAssertFalse(runtime(restarted, state: .stale, at: now).owners.contains(owner))
        _ = runtime(restarted, state: .onBreak("00:10:00"), at: now.addingTimeInterval(600))
        XCTAssertEqual(restarted.checkpoints.first { $0.kind == .breakOver }?.due, now.addingTimeInterval(3600))
    }

    func testClockedOutCancelsAllCurrentShiftAlertsIncludingSnoozedClockOut() async throws {
        for snoozed in [false, true] {
            let defaults = preferences()
            let engine = WorkdayReminderController(defaults: defaults)
            let center = MemoryNotificationCenter()
            let now = date("2026-09-10T15:30:00Z") // 23:30 Manila, before scheduled clock-out.
            let delivery = TimeclockReminderDelivery(center: center, now: { now })
            let shiftID = "Asia/Manila|2026-09-10|"
            await reconcile(runtime(engine, state: .onBreak("00:30:00"), at: now), engine: engine, delivery: delivery)
            let queued = try XCTUnwrap(center.pending.values.first { TimeclockReminderDelivery.owner($0) == shiftID + "clockOut" })
            if snoozed { await delivery.snooze(queued, minutes: 5).value }
            center.delivered[queued.identifier] = queued

            await reconcile(runtime(engine, state: .clockedOut, at: now), engine: engine, delivery: delivery)
            XCTAssertFalse(center.pending.values.contains { TimeclockReminderDelivery.owner($0)?.hasPrefix(shiftID) == true })
            XCTAssertFalse(center.delivered.values.contains { TimeclockReminderDelivery.owner($0)?.hasPrefix(shiftID) == true })
            XCTAssertTrue(center.pending.keys.contains { $0.contains("2026-09-11|workStart") })
            // An old banner's action must not revive a completed reminder.
            await delivery.snooze(queued, minutes: 5).value
            XCTAssertFalse(center.pending.values.contains { TimeclockReminderDelivery.owner($0)?.hasPrefix(shiftID) == true })

            let restarted = WorkdayReminderController(defaults: defaults)
            let afterEnd = date("2026-09-10T16:00:00Z")
            XCTAssertFalse(runtime(restarted, state: .stale, at: afterEnd).owners.contains { $0.hasPrefix(shiftID) })
            XCTAssertTrue(restarted.checkpoints.first { $0.kind == .clockOut }?.isComplete == true)
        }
    }

    func testReturningFromBreakCancelsReturnAlertsAndSnoozeButKeepsClockOut() async throws {
        let engine = WorkdayReminderController(defaults: preferences())
        let center = MemoryNotificationCenter()
        let now = date("2026-09-10T11:30:00Z")
        let delivery = TimeclockReminderDelivery(center: center, now: { now })
        let owner = "Asia/Manila|2026-09-10|breakOver-0"
        await reconcile(runtime(engine, state: .onBreak("00:30:00"), at: now), engine: engine, delivery: delivery)
        let queued = try XCTUnwrap(center.pending.values.first { TimeclockReminderDelivery.owner($0) == owner })
        await delivery.snooze(queued, minutes: 5).value
        center.delivered[queued.identifier] = queued

        await reconcile(runtime(engine, state: .active("04:10"), at: now), engine: engine, delivery: delivery)
        XCTAssertFalse(center.pending.values.contains { TimeclockReminderDelivery.owner($0) == owner })
        XCTAssertFalse(center.delivered.values.contains { TimeclockReminderDelivery.owner($0) == owner })
        XCTAssertFalse(center.pending.keys.contains { $0.contains("2026-09-10|breakStart") })
        XCTAssertTrue(center.pending.keys.contains { $0.contains("2026-09-10|clockOut") })
    }

    func testClockInBefore1450SuppressesAdvanceDueAndFollowUpsForWorkingAndBreakStates() {
        for state in [TimeclockState.active("00:01"), .onBreak("00:01:00")] {
            let engine = WorkdayReminderController(defaults: preferences())
            for time in ["2026-09-10T06:30:00Z", "2026-09-10T06:35:00Z", "2026-09-10T06:50:00Z", "2026-09-10T07:05:00Z"] {
                let result = runtime(engine, state: state, at: date(time))
                XCTAssertFalse(result.owners.contains("Asia/Manila|2026-09-10|workStart"))
                XCTAssertFalse(result.plans.contains { $0.identifier.contains("2026-09-10|workStart") })
            }
        }
    }

    func testUnverifiedStateDoesNotInventCompletionAndLateClockInStillAppliesWhenClockedOut() {
        let engine = WorkdayReminderController(defaults: preferences())
        let now = date("2026-09-10T06:55:00Z")
        for state in [TimeclockState.loading, .stale, .loginRequired, .unknown(nil)] {
            let result = runtime(engine, state: state, at: now)
            XCTAssertFalse(engine.checkpoints.first { $0.kind == .workStart }!.isComplete)
            XCTAssertFalse(result.plans.contains { $0.fireDate == now.addingTimeInterval(1) })
        }
        let verified = runtime(engine, state: .clockedOut, at: now)
        XCTAssertTrue(verified.plans.contains { $0.ownerIdentifier == "Asia/Manila|2026-09-10|workStart" && $0.fireDate == now.addingTimeInterval(1) })
        XCTAssertFalse(verified.owners.contains { $0.hasSuffix("|clockOut") || $0.contains("|break") })
    }

    func testOffDayWorkDoesNotCompleteNextScheduledShift() {
        let engine = WorkdayReminderController(defaults: preferences())
        let result = runtime(engine, state: .active("01:00"), at: date("2026-09-13T06:00:00Z")) // Sunday.
        XCTAssertTrue(result.owners.contains("Asia/Manila|2026-09-14|workStart"))
        XCTAssertFalse(engine.checkpoints.first { $0.kind == .workStart }!.isComplete)
    }

    func testEarlyClockInBeforeMidnightBelongsToUpcomingMidnightShift() {
        let engine = WorkdayReminderController(defaults: preferences())
        var midnight = schedule
        midnight.startMinutes = 30
        midnight.endMinutes = 9 * 60 + 30
        let result = engine.plans(schedule: midnight, state: .active("00:01"), enabled: [.workStart, .clockOut],
                                  sounds: [:], workLead: 15, endLead: 15, now: date("2026-09-13T15:45:00Z"))
        XCTAssertFalse(result.owners.contains("Asia/Manila|2026-09-14|workStart"))
        XCTAssertTrue(result.owners.contains("Asia/Manila|2026-09-15|workStart"))
        XCTAssertTrue(engine.checkpoints.first { $0.kind == .workStart }!.isComplete)
    }

    func testUnreadableSecondBreakNeverReusesFirstBreakDeadline() throws {
        let engine = WorkdayReminderController(defaults: preferences())
        let now = date("2026-09-10T10:00:00Z")
        _ = runtime(engine, state: .onBreak("00:10:00"), at: now)
        let first = try XCTUnwrap(engine.checkpoints.first { $0.kind == .breakOver })
        _ = runtime(engine, state: .active("03:00"), at: now.addingTimeInterval(1800))
        _ = runtime(engine, state: .onBreak("--:--"), at: now.addingTimeInterval(3600))
        XCTAssertFalse(engine.checkpoints.contains { $0.kind == .breakOver })
        _ = runtime(engine, state: .onBreak("00:05:00"), at: now.addingTimeInterval(3900))
        let second = try XCTUnwrap(engine.checkpoints.first { $0.kind == .breakOver })
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.due, now.addingTimeInterval(7200))
        XCTAssertFalse(second.isComplete)
        _ = runtime(engine, state: .onBreak("--:--"), at: now.addingTimeInterval(4000))
        XCTAssertEqual(engine.checkpoints.first { $0.kind == .breakOver }, second)
    }

    func testExistingLedgerWithoutBreakObservationFlagStillRestoresCompletion() {
        let defaults = preferences()
        let legacy = """
        {"Asia/Manila|2026-09-10":{"seenWorking":true,"clockedOut":false,
        "breakStartedAt":810813600,"breakReturned":true,"silenced":[],"scheduledEvents":[]}}
        """
        defaults.set(Data(legacy.utf8), forKey: "workdayCheckpointLedger.v1")
        let engine = WorkdayReminderController(defaults: defaults)
        let result = runtime(engine, state: .stale, at: date("2026-09-10T12:00:00Z"))
        XCTAssertNil(engine.persistenceError)
        XCTAssertFalse(result.owners.contains { $0.hasSuffix("|workStart") && $0.contains("2026-09-10") })
        XCTAssertTrue(engine.checkpoints.first { $0.kind == .breakStart }!.isComplete)
        XCTAssertTrue(engine.checkpoints.first { $0.kind == .breakOver }!.isComplete)
    }
}
