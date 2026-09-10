import Foundation
import Combine
import OSLog
import UserNotifications

@MainActor
protocol TimeclockNotificationCenter: AnyObject {
    func authorize() async throws -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    func deliveredRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
}

@MainActor
final class SystemTimeclockNotificationCenter: TimeclockNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func authorize() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func deliveredRequests() async -> [UNNotificationRequest] {
        await center.deliveredNotifications().map(\.request)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePending(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// Serializes OS requests so an older asynchronous add cannot undo a newer cancellation.
@MainActor
final class TimeclockReminderDelivery: ObservableObject {
    @Published private(set) var status = "Checking notification delivery…"
    @Published private(set) var lastError: String?
    @Published private(set) var testStatus: String?
    @Published private(set) var lastReconciledAt: Date?
    @Published private(set) var nextReminderAt: Date?
    static let ownerKey = "timeclockReminderOwner"
    static let snoozePrefix = "timeclock-snooze."
    static let overtimeOwner = "overtime-reminder"

    private let center: TimeclockNotificationCenter
    private let now: () -> Date
    private var revision = 0
    private var eligibleOwners: Set<String> = []
    private var eligibleSnoozeOwners: Set<String> = []
    private var pendingOperation: Task<Void, Never>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.vanajvanguardia.TimeClockBar",
        category: "ReminderDelivery"
    )

    init(center: TimeclockNotificationCenter, now: @escaping () -> Date = Date.init) {
        self.center = center
        self.now = now
    }

    @discardableResult
    func reconcile(
        plans: [TimeclockReminderPlan],
        allowsOvertime: Bool = false,
        unverifiedSnoozeOwners: Set<String>? = nil,
        activeOwners: Set<String>? = nil,
        onScheduled: @escaping (String) -> Void = { _ in }
    ) -> Task<Void, Never> {
        revision += 1
        let expectedRevision = revision
        eligibleOwners = activeOwners ?? Set(plans.map { $0.ownerIdentifier ?? $0.identifier })
        if allowsOvertime { eligibleOwners.insert(Self.overtimeOwner) }
        eligibleSnoozeOwners = unverifiedSnoozeOwners ?? eligibleOwners
        if allowsOvertime { eligibleSnoozeOwners.insert(Self.overtimeOwner) }
        let plannedAt = now()

        return enqueue { [self] in
            guard revision == expectedRevision else { return }
            let pending = await center.pendingRequests()
            let delivered = await center.deliveredRequests()
            guard revision == expectedRevision else { return }

            let desiredIDs = Set(plans.map(\.identifier))
            // Rebuild base schedules, but preserve still-applicable snoozes and their deadlines.
            let removedPending = pending.filter {
                guard Self.isOwned($0) else { return false }
                if Self.isSnooze($0) { return !isEligibleSnooze($0) }
                if Self.owner($0) == Self.overtimeOwner { return !isEligible($0) }
                if $0.identifier.contains("|") { return !isEligible($0) || !desiredIDs.contains($0.identifier) }
                return true
            }.map(\.identifier)
            center.removePending(removedPending)
            center.removeDelivered(delivered.filter {
                Self.isOwned($0) && !(Self.isSnooze($0) ? isEligibleSnooze($0) : isEligible($0))
            }.map(\.identifier))

            lastError = nil
            lastReconciledAt = now()
            if plans.isEmpty {
                nextReminderAt = pending.filter { !removedPending.contains($0.identifier) && Self.isOwned($0) }
                    .compactMap { Self.nextDate($0.trigger) }.min()
                status = "No automatic reminders currently apply."
                return
            }
            guard await isAuthorized(), revision == expectedRevision else { return }
            let snoozedOwners = Set(pending.filter { Self.isSnooze($0) && isEligibleSnooze($0) }.compactMap(Self.owner))
            for plan in plans {
                guard revision == expectedRevision else { return }
                // A snooze replaces a one-shot return reminder; weekly plans still cover future days.
                if (plan.delaySeconds != nil || plan.fireDate != nil) && snoozedOwners.contains(plan.ownerIdentifier ?? plan.identifier) { continue }
                let request = TimeclockReminderScheduler.request(for: plan, plannedAt: plannedAt, now: now())
                if let existing = pending.first(where: { $0.identifier == request.identifier }),
                   existing.content.title == request.content.title,
                   existing.content.categoryIdentifier == request.content.categoryIdentifier,
                   existing.content.interruptionLevel == request.content.interruptionLevel,
                   existing.content.userInfo["soundSeconds"] as? Int == request.content.userInfo["soundSeconds"] as? Int,
                   existing.content.body == request.content.body,
                   existing.content.userInfo[TimeclockReminderScheduler.reminderSoundUserInfoKey] as? String == request.content.userInfo[TimeclockReminderScheduler.reminderSoundUserInfoKey] as? String,
                   let oldTrigger = existing.trigger as? UNCalendarNotificationTrigger,
                   let newTrigger = request.trigger as? UNCalendarNotificationTrigger,
                   !oldTrigger.repeats, oldTrigger.dateComponents == newTrigger.dateComponents {
                    onScheduled(plan.identifier)
                    continue
                }
                if await add(request, expectedRevision: expectedRevision) { onScheduled(plan.identifier) }
            }
            guard revision == expectedRevision else { return }
            let scheduled = await center.pendingRequests().filter { Self.isOwned($0) }
            guard revision == expectedRevision else { return }
            nextReminderAt = scheduled.compactMap { Self.nextDate($0.trigger) }.min()
            lastReconciledAt = now()
            status = "\(scheduled.count) reminders queued with macOS. Focus and notification settings control presentation."
        }
    }

    @discardableResult
    func snooze(_ request: UNNotificationRequest, minutes: Int) -> Task<Void, Never> {
        let expectedRevision = revision
        let snoozedUntil = now().addingTimeInterval(TimeInterval(minutes) * 60)
        return enqueue { [self] in
            let source = Self.owner(request) ?? (Self.isTestOwner(request.identifier) ? request.identifier : nil)
            guard (1...15).contains(minutes), let owner = source,
                  revision == expectedRevision, canSnooze(owner),
                  await isAuthorized(), revision == expectedRevision else { return }

            let content = UNMutableNotificationContent()
            content.title = Self.isTestOwner(owner) ? "Time Clock test reminder" : "Time Clock reminder"
            content.body = request.content.categoryIdentifier == TimeclockReminderScheduler.reportReminderCategoryIdentifier
                ? "File your report on Full Scale before clocking out." : Self.snoozeBody(owner: owner)
            content.categoryIdentifier = request.content.categoryIdentifier
            content.userInfo[Self.ownerKey] = owner
            content.sound = request.content.sound
            content.interruptionLevel = request.content.interruptionLevel
            if let sound = TimeclockReminderScheduler.reminderSound(from: request.content) {
                TimeclockReminderScheduler.apply(sound, to: content, seconds: request.content.userInfo["soundSeconds"] as? Int ?? 10)
            }

            let identifier = Self.snoozePrefix + owner
            center.removePending([identifier])
            center.removeDelivered([request.identifier, identifier])
            if owner.contains("|") {
                let owned = await center.pendingRequests().filter { Self.owner($0) == owner }.map(\.identifier)
                guard revision == expectedRevision else { return }
                center.removePending(owned)
            } else if owner == "break-over-reminder" { center.removePending([owner]) }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, snoozedUntil.timeIntervalSince(now())), repeats: false)
            await add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger), expectedRevision: expectedRevision)
        }
    }

    @discardableResult
    func send(_ request: UNNotificationRequest, completion: @escaping (Bool) -> Void = { _ in }) -> Task<Void, Never> {
        let expectedRevision = revision
        return enqueue { [self] in
            var queued = false
            defer { completion(queued) }
            let owner = Self.owner(request)
            guard owner == nil || (revision == expectedRevision && isEligible(request)) else { return }
            guard await isAuthorized() else {
                if Self.isTestOwner(request.identifier) { testStatus = "Test blocked: notification authorization is unavailable. Check Permission above." }
                return
            }
            if owner != nil {
                guard revision == expectedRevision else { return }
                queued = await add(request, expectedRevision: expectedRevision)
            } else {
                do {
                    try await center.add(request)
                    queued = true
                    lastError = nil
                    if Self.isTestOwner(request.identifier) {
                        testStatus = "Test queued for 5 seconds from now. Listen for the sound; switch apps to test background delivery."
                    }
                    let soundName = TimeclockReminderScheduler.reminderSound(from: request.content)?.fileName ?? "system default"
                    logger.notice("Queued notification \(request.identifier, privacy: .public); sound: \(soundName, privacy: .public)")
                } catch {
                    lastError = error.localizedDescription
                    if Self.isTestOwner(request.identifier) { testStatus = "Test could not be queued." }
                    logger.error("Notification could not be scheduled: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func recordPresentationRequest(_ request: UNNotificationRequest) {
        logger.notice("macOS received \(request.identifier, privacy: .public); banner and sound requested.")
        if Self.isTestOwner(request.identifier) {
            testStatus = "Test reached macOS; banner and sound requested. Confirm that you heard it; delivery alone cannot verify your speakers."
        }
    }

    private static func nextDate(_ trigger: UNNotificationTrigger?) -> Date? {
        if let calendar = trigger as? UNCalendarNotificationTrigger { return calendar.nextTriggerDate() }
        if let interval = trigger as? UNTimeIntervalNotificationTrigger { return interval.nextTriggerDate() }
        return nil
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = pendingOperation
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        pendingOperation = task
        return task
    }

    private func isAuthorized() async -> Bool {
        do {
            let allowed = try await center.authorize()
            if !allowed { status = "Notifications are not allowed. Enable them in System Settings." }
            return allowed
        }
        catch {
            lastError = error.localizedDescription
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    private func add(_ request: UNNotificationRequest, expectedRevision: Int) async -> Bool {
        do {
            try await center.add(request)
            if revision != expectedRevision {
                center.removePending([request.identifier])
                center.removeDelivered([request.identifier])
                return false
            }
            return true
        } catch {
            lastError = error.localizedDescription
            logger.error("Reminder \(request.identifier, privacy: .public) could not be scheduled: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func isEligible(_ request: UNNotificationRequest) -> Bool {
        Self.owner(request).map { eligibleOwners.contains($0) } ?? false
    }

    private func isEligibleSnooze(_ request: UNNotificationRequest) -> Bool {
        Self.owner(request).map(canSnooze) ?? false
    }

    private func canSnooze(_ owner: String) -> Bool {
        eligibleSnoozeOwners.contains(owner) || Self.isTestOwner(owner)
    }

    static func owner(_ request: UNNotificationRequest) -> String? {
        if let owner = request.content.userInfo[ownerKey] as? String { return owner }
        if request.identifier == overtimeOwner || request.identifier.hasPrefix("overtime-reminder-") { return overtimeOwner }
        if isBaseIdentifier(request.identifier) { return request.identifier }
        return nil
    }

    private static func isSnooze(_ request: UNNotificationRequest) -> Bool {
        request.identifier.hasPrefix(snoozePrefix)
    }

    private static func isOwned(_ request: UNNotificationRequest) -> Bool {
        owner(request) != nil || isSnooze(request) || request.identifier.hasPrefix("snooze-")
    }

    private static func isBaseIdentifier(_ identifier: String) -> Bool {
        ["work-start-reminder", "break-reminder", "break-over-reminder", "clock-out-reminder"].contains { prefix in
            identifier == prefix || (1...7).contains { identifier == "\(prefix)-\($0)" }
        }
    }

    private static func snoozeBody(owner: String) -> String {
        if owner.contains("|") { return "Open Time Clock to check your attendance. This reminder does not confirm an action was completed." }
        if isTestOwner(owner) { return "This is a snoozed test reminder. Open Time Clock to check your notification actions." }
        if owner.hasPrefix("work-start-reminder") { return "Open Time Clock to check your clock-in." }
        if owner.hasPrefix("break-over-reminder") { return "Open Time Clock to check whether it is time to return from break." }
        if owner.hasPrefix("break-reminder") { return "Open Time Clock to check your planned break." }
        if owner == overtimeOwner { return "Open Time Clock to review your hours and clock-out status." }
        return "Open Time Clock to check your clock-out."
    }

    private static func isTestOwner(_ identifier: String) -> Bool {
        ["test-shift-reminder-", "test-break-reminder-", "test-break-over-reminder-", "test-clock-out-reminder-", "test-overtime-reminder-"]
            .contains { identifier.hasPrefix($0) }
    }
}
