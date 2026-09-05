import UserNotifications
import XCTest
@testable import Time_Clock_Bar

@MainActor
final class TimeclockReminderDeliveryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testClockOutCancelsPendingAndDeliveredSnooze() async throws {
        let center = MemoryNotificationCenter()
        let delivery = TimeclockReminderDelivery(center: center)
        let plan = makePlan("clock-out-reminder-2")
        await delivery.reconcile(plans: actualPlans(state: .active("7:00"))).value
        let notification = try XCTUnwrap(center.pending[plan.identifier])
        await delivery.snooze(notification, minutes: 5).value
        let snoozeID = TimeclockReminderDelivery.snoozePrefix + plan.identifier
        let snooze = try XCTUnwrap(center.pending[snoozeID])
        center.delivered[snoozeID] = snooze
        center.delivered[plan.identifier] = notification

        await delivery.reconcile(plans: actualPlans(state: .clockedOut)).value

        XCTAssertEqual(Set(center.pending.keys), ["work-start-reminder-2"])
        XCTAssertTrue(center.delivered.isEmpty)
    }

    func testCompletedReminderCannotBeSnoozedFromAnOldNotification() async throws {
        let center = MemoryNotificationCenter()
        let delivery = TimeclockReminderDelivery(center: center)
        let plan = makePlan("clock-out-reminder-2")
        await delivery.reconcile(plans: [plan]).value
        let notification = try XCTUnwrap(center.pending[plan.identifier])
        await delivery.reconcile(plans: []).value

        await delivery.snooze(notification, minutes: 5).value

        XCTAssertTrue(center.pending.isEmpty)
    }

    func testRepeatedSnoozeReplacesItsOwnRequestAndRefreshesRelativeCopy() async throws {
        let center = MemoryNotificationCenter()
        let delivery = TimeclockReminderDelivery(center: center)
        let plan = makePlan("clock-out-reminder-2")
        await delivery.reconcile(plans: [plan]).value
        let notification = try XCTUnwrap(center.pending[plan.identifier])
        await delivery.snooze(notification, minutes: 5).value
        let identifier = TimeclockReminderDelivery.snoozePrefix + plan.identifier
        let firstSnooze = try XCTUnwrap(center.pending[identifier])
        await delivery.snooze(firstSnooze, minutes: 10).value

        XCTAssertEqual(center.pending.keys.filter { $0.hasPrefix(TimeclockReminderDelivery.snoozePrefix) }.count, 1)
        let content = try XCTUnwrap(center.pending[identifier]?.content)
        XCTAssertFalse(content.body.contains("in 15 minutes"))
        XCTAssertFalse(content.title.contains("soon"))
        XCTAssertEqual(TimeclockReminderScheduler.reminderSound(from: content), .beacon)
        XCTAssertEqual(content.categoryIdentifier, TimeclockReminderScheduler.reminderCategoryIdentifier)
    }

    func testActiveSnoozeSurvivesReconciliationAndAppRestart() async throws {
        let center = MemoryNotificationCenter()
        let firstDelivery = TimeclockReminderDelivery(center: center)
        let plan = makePlan("break-over-reminder", delay: 10)
        await firstDelivery.reconcile(plans: [plan]).value
        let notification = try XCTUnwrap(center.pending[plan.identifier])
        await firstDelivery.snooze(notification, minutes: 5).value
        let identifier = TimeclockReminderDelivery.snoozePrefix + plan.identifier
        let snooze = try XCTUnwrap(center.pending[identifier])

        let restartedDelivery = TimeclockReminderDelivery(center: center)
        await restartedDelivery.reconcile(
            plans: actualPlans(state: .loading),
            unverifiedSnoozeOwners: TimeclockReminderScheduler.unverifiedSnoozeOwners(
                state: .loading, weekdays: [2], enabledKinds: Set(TimeclockReminderKind.allCases)
            )
        ).value
        XCTAssertNotNil(center.pending[identifier])
        await restartedDelivery.reconcile(plans: [plan]).value

        XCTAssertEqual(Set(center.pending.keys), [identifier])
        XCTAssertTrue(center.pending[identifier] === snooze)
    }

    func testWeeklyScheduleSurvivesSnoozeToCoverFutureDays() async throws {
        let center = MemoryNotificationCenter()
        let delivery = TimeclockReminderDelivery(center: center)
        let plan = makePlan("clock-out-reminder-2")
        await delivery.reconcile(plans: [plan]).value
        await delivery.snooze(try XCTUnwrap(center.pending[plan.identifier]), minutes: 5).value
        await delivery.reconcile(plans: [plan]).value

        XCTAssertEqual(center.pending.count, 2)
        XCTAssertNotNil(center.pending[plan.identifier])
    }

    func testDisabledReminderCancelsSnoozeEvenWhenClockIsUnverified() async throws {
        let center = MemoryNotificationCenter()
        let delivery = TimeclockReminderDelivery(center: center)
        let plan = makePlan("break-over-reminder", delay: 10)
        await delivery.reconcile(plans: [plan]).value
        await delivery.snooze(try XCTUnwrap(center.pending[plan.identifier]), minutes: 5).value

        await delivery.reconcile(
            plans: [],
            unverifiedSnoozeOwners: TimeclockReminderScheduler.unverifiedSnoozeOwners(
                state: .stale, weekdays: [2], enabledKinds: []
            )
        ).value

        XCTAssertTrue(center.pending.isEmpty)
    }

    func testLegacyUnownedSnoozesAreRemovedWithoutRemovingUnrelatedNotifications() async {
        let center = MemoryNotificationCenter()
        for identifier in ["snooze-legacy-uuid", "daily-unrelated", "break-reminder", "break-reminder-3"] {
            let request = makeRequest(identifier)
            center.pending[identifier] = request
            center.delivered[identifier] = request
        }
        let delivery = TimeclockReminderDelivery(center: center)
        await delivery.reconcile(plans: []).value

        XCTAssertEqual(Set(center.pending.keys), ["daily-unrelated"])
        XCTAssertEqual(Set(center.delivered.keys), ["daily-unrelated"])
    }

    func testOlderAuthorizationCannotRestoreObsoleteRequests() async {
        let center = MemoryNotificationCenter()
        let gate = OperationGate()
        center.beforeAuthorization = { await gate.wait() }
        let delivery = TimeclockReminderDelivery(center: center)
        let old = delivery.reconcile(plans: [makePlan("break-reminder-2")])
        await fulfillment(of: [gate.entered], timeout: 2)
        let latest = delivery.reconcile(plans: [])
        gate.release()
        await old.value
        await latest.value

        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.addCount, 0)
    }

    func testInFlightAddIsRemovedBeforeLatestPlanIsApplied() async {
        let center = MemoryNotificationCenter()
        let gate = OperationGate()
        center.beforeAdd = { await gate.wait() }
        let delivery = TimeclockReminderDelivery(center: center)
        let old = delivery.reconcile(plans: [makePlan("break-reminder-2")])
        await fulfillment(of: [gate.entered], timeout: 2)
        center.beforeAdd = nil
        let latest = delivery.reconcile(plans: [makePlan("work-start-reminder-2")])
        gate.release()
        await old.value
        await latest.value

        XCTAssertEqual(Set(center.pending.keys), ["work-start-reminder-2"])
    }

    func testSnoozeCannotReappearWhenStateChangesDuringAdd() async throws {
        let center = MemoryNotificationCenter()
        let delivery = TimeclockReminderDelivery(center: center)
        let plan = makePlan("clock-out-reminder-2")
        await delivery.reconcile(plans: [plan]).value
        let notification = try XCTUnwrap(center.pending[plan.identifier])
        let gate = OperationGate()
        center.beforeAdd = { await gate.wait() }
        let snooze = delivery.snooze(notification, minutes: 5)
        await fulfillment(of: [gate.entered], timeout: 2)
        center.beforeAdd = nil
        let latest = delivery.reconcile(plans: [])
        gate.release()
        await snooze.value
        await latest.value

        XCTAssertTrue(center.pending.isEmpty)
    }

    func testAuthorizationDelayDoesNotExtendBreakDeadline() async throws {
        let center = MemoryNotificationCenter()
        var currentTime = start
        let delivery = TimeclockReminderDelivery(center: center, now: { currentTime })
        center.beforeAuthorization = { currentTime = currentTime.addingTimeInterval(7) }
        await delivery.reconcile(plans: [makePlan("break-over-reminder", delay: 10)]).value

        let trigger = try XCTUnwrap(center.pending["break-over-reminder"]?.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 3)
    }

    func testDeniedAuthorizationStillCancelsObsoleteRequests() async {
        let center = MemoryNotificationCenter()
        center.authorized = false
        center.pending["break-reminder-2"] = makeRequest("break-reminder-2")
        let delivery = TimeclockReminderDelivery(center: center)
        await delivery.reconcile(plans: [makePlan("work-start-reminder-2")]).value

        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.addCount, 0)
    }

    func testAddFailureDoesNotBlockTheNextReconciliation() async {
        let center = MemoryNotificationCenter()
        center.shouldFailAdd = true
        let delivery = TimeclockReminderDelivery(center: center)
        await delivery.reconcile(plans: [makePlan("break-reminder-2")]).value
        center.shouldFailAdd = false
        await delivery.reconcile(plans: [makePlan("work-start-reminder-2")]).value

        XCTAssertEqual(Set(center.pending.keys), ["work-start-reminder-2"])
    }

    func testDisablingOvertimeCancelsItsOwnedSnooze() async throws {
        let center = MemoryNotificationCenter()
        let delivery = TimeclockReminderDelivery(center: center)
        await delivery.reconcile(plans: [], allowsOvertime: true).value
        let notification = makeRequest("overtime-reminder")
        await delivery.send(notification).value
        await delivery.snooze(notification, minutes: 5).value
        XCTAssertEqual(center.pending.count, 2)

        await delivery.reconcile(plans: [], allowsOvertime: false).value

        XCTAssertTrue(center.pending.isEmpty)
    }

    func testUnrelatedImmediateNotificationsDoNotRequireAnActiveSchedule() async {
        let center = MemoryNotificationCenter()
        let delivery = TimeclockReminderDelivery(center: center)
        await delivery.send(makeRequest("login-required")).value
        XCTAssertNotNil(center.pending["login-required"])
    }

    func testExplicitTestNotificationCanSnoozeWithoutAnActiveShift() async throws {
        let center = MemoryNotificationCenter()
        let delivery = TimeclockReminderDelivery(center: center)
        let request = makeRequest("test-break-reminder-example")
        await delivery.send(request).value
        await delivery.snooze(request, minutes: 5).value
        await delivery.reconcile(plans: []).value

        let snooze = try XCTUnwrap(center.pending[TimeclockReminderDelivery.snoozePrefix + request.identifier])
        XCTAssertTrue(snooze.content.title.contains("test"))
        XCTAssertTrue(snooze.content.body.contains("test reminder"))
    }

    private func makePlan(_ identifier: String, delay: TimeInterval? = nil) -> TimeclockReminderPlan {
        TimeclockReminderPlan(
            identifier: identifier, title: "Shift ends soon", body: "Your shift ends in 15 minutes.",
            minutes: 12 * 60, weekday: 2,
            categoryIdentifier: TimeclockReminderScheduler.reminderCategoryIdentifier,
            delaySeconds: delay, sound: .beacon
        )
    }

    private func makeRequest(_ identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: identifier, content: UNMutableNotificationContent(), trigger: nil)
    }

    private func actualPlans(state: TimeclockState) -> [TimeclockReminderPlan] {
        TimeclockReminderScheduler.plans(
            state: state, workingWeekdays: [2], workReminderEnabled: true,
            workStartMinutes: 9 * 60, workReminderLeadMinutes: 15,
            breakReminderEnabled: true, breakReminderMinutes: 12 * 60,
            breakOverReminderEnabled: true, breakDurationMinutes: 60,
            clockOutReminderEnabled: true, workEndMinutes: 17 * 60, clockOutReminderLeadMinutes: 15
        )
    }
}

@MainActor
private final class MemoryNotificationCenter: TimeclockNotificationCenter {
    var pending: [String: UNNotificationRequest] = [:]
    var delivered: [String: UNNotificationRequest] = [:]
    var authorized = true
    var shouldFailAdd = false
    var addCount = 0
    var beforeAuthorization: (() async -> Void)?
    var beforeAdd: (() async -> Void)?

    func authorize() async throws -> Bool {
        await beforeAuthorization?()
        return authorized
    }

    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
    func deliveredRequests() async -> [UNNotificationRequest] { Array(delivered.values) }

    func add(_ request: UNNotificationRequest) async throws {
        await beforeAdd?()
        if shouldFailAdd { throw CocoaError(.fileWriteUnknown) }
        pending[request.identifier] = request
        addCount += 1
    }

    func removePending(_ identifiers: [String]) {
        for identifier in identifiers { pending.removeValue(forKey: identifier) }
    }

    func removeDelivered(_ identifiers: [String]) {
        for identifier in identifiers { delivered.removeValue(forKey: identifier) }
    }
}

@MainActor
private final class OperationGate {
    let entered = XCTestExpectation(description: "Operation reached its asynchronous boundary")
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}
