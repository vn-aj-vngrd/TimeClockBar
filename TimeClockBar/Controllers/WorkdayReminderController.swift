import Combine
import Foundation

@MainActor
final class WorkdayReminderController: ObservableObject {
    struct Record: Codable, Equatable {
        var seenWorking = false
        var clockedOut = false
        var breakStartedAt: Date?
        var breakReturned = false
        var breakSessionNumber: Int?
        var silenced: Set<String> = []
        var scheduledEvents: Set<String> = []
    }
    @Published private(set) var checkpoints: [WorkdayCheckpoint] = []
    @Published private(set) var shift: WorkdaySchedule.Shift?
    @Published private(set) var persistenceError: String?
    private var records: [String: Record]
    private let defaults: UserDefaults
    private let key = "workdayCheckpointLedger.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do { records = try JSONDecoder().decode([String: Record].self, from: data) }
            catch { records = [:]; persistenceError = "Reminder history is unreadable. Automatic reminders are paused; the saved history has been preserved." }
        } else { records = [:] }
    }

    func observe(state: TimeclockState, schedule: WorkdaySchedule, now: Date = Date()) {
        shift = schedule.currentShift(at: now)
        guard let shift else { checkpoints = []; return }
        var record = records[shift.id] ?? Record()
        // Only associate observations with the actual shift window; future shifts remain untouched.
        if now >= shift.start.addingTimeInterval(-3600), now < shift.end.addingTimeInterval(4 * 3600) {
            switch state {
            case .active:
                record.seenWorking = true
                record.clockedOut = false
                if record.breakStartedAt != nil { record.breakReturned = true }
            case .onBreak(let timer):
                record.seenWorking = true
                record.clockedOut = false
                if (record.breakReturned || record.breakStartedAt == nil),
                   let elapsed = TimeclockTimeMath.timerSeconds(from: timer), elapsed <= 24 * 3600 {
                    if record.breakReturned { record.breakSessionNumber = (record.breakSessionNumber ?? 0) + 1 }
                    record.breakReturned = false
                    record.breakStartedAt = now.addingTimeInterval(-Double(elapsed))
                }
            case .clockedOut:
                if record.seenWorking { record.clockedOut = true }
            case .loading, .stale, .loginRequired, .unknown: break
            }
        }
        if records[shift.id] == nil || records[shift.id] != record {
            records[shift.id] = record
            persist()
        }
        checkpoints = makeCheckpoints(shift: shift, record: record, schedule: schedule, workLead: 15, endLead: 15)
    }

    func plans(schedule: WorkdaySchedule, state: TimeclockState, enabled: Set<TimeclockReminderKind>,
               sounds: [TimeclockReminderKind: TimeclockReminderSound], workLead: Int, endLead: Int,
               now: Date = Date()) -> (plans: [TimeclockReminderPlan], owners: Set<String>) {
        observe(state: state, schedule: schedule, now: now)
        if let shift {
            checkpoints = makeCheckpoints(shift: shift, record: records[shift.id] ?? Record(), schedule: schedule, workLead: workLead, endLead: endLead)
        }
        guard persistenceError == nil else { return ([], []) }
        var plans: [TimeclockReminderPlan] = []
        var owners: Set<String> = []
        // Two shifts stay below the platform's finite pending-request budget.
        let shifts = schedule.shifts(around: now).filter { $0.end.addingTimeInterval(4 * 3600) > now }.prefix(2)
        for shift in shifts {
            let record = records[shift.id] ?? Record()
            for checkpoint in makeCheckpoints(shift: shift, record: record, schedule: schedule, workLead: workLead, endLead: endLead) {
                guard enabled.contains(checkpoint.kind), !checkpoint.isComplete, !checkpoint.isSilenced else { continue }
                let isCurrent = now >= shift.start.addingTimeInterval(-3600)
                let knownOut = state == .clockedOut && isCurrent
                if knownOut && checkpoint.kind != .workStart { continue }
                // Break and clock-out prompts require an observed work session.
                if checkpoint.kind != .workStart && !record.seenWorking { continue }
                owners.insert(checkpoint.id)
                var caughtUp = false
                for offset in checkpoint.offsets.reversed() {
                    let stage = offset < 0 ? "advance" : "due-\(offset)"
                    let date = checkpoint.due.addingTimeInterval(Double(offset * 60))
                    let id = "\(checkpoint.id)|\(stage)"
                    if date <= now {
                        // On wake, emit only the latest missed stage. Never replay a delivered/queued stage.
                        guard !caughtUp else { continue }
                        caughtUp = true
                        guard !record.scheduledEvents.contains(id), now < shift.end.addingTimeInterval(4 * 3600) else { continue }
                    }
                    plans.append(TimeclockReminderPlan(
                        identifier: id,
                        title: checkpoint.kind == .clockOut && offset < 0 ? "File your report before clock-out"
                            : date > now && offset < 0 ? "\(checkpoint.title) soon" : "Check: \(checkpoint.title.lowercased())",
                        body: checkpoint.kind == .clockOut
                            ? "File your daily report on Full Scale, then open Time Clock to clock out."
                            : "Open Time Clock to check your \(checkpoint.title.lowercased()).",
                        minutes: 0, weekday: 0,
                        categoryIdentifier: checkpoint.kind == .clockOut && offset < 0
                            ? TimeclockReminderScheduler.reportReminderCategoryIdentifier : TimeclockReminderScheduler.reminderCategoryIdentifier,
                        delaySeconds: nil, sound: sounds[checkpoint.kind] ?? .defaultSound(for: checkpoint.kind),
                        fireDate: max(date, now.addingTimeInterval(1)), ownerIdentifier: checkpoint.id
                    ))
                }
            }
        }
        let catchUpTime = now.addingTimeInterval(1)
        let caughtUp = plans.filter { $0.fireDate == catchUpTime }
        if caughtUp.count > 1 {
            func priority(_ plan: TimeclockReminderPlan) -> Int {
                if plan.ownerIdentifier?.hasSuffix("|clockOut") == true { return 0 }
                if plan.ownerIdentifier?.contains("|breakOver-") == true { return 1 }
                return 2
            }
            let primary = caughtUp.sorted { priority($0) < priority($1) }.first!.identifier
            let skipped = Set(caughtUp.filter { $0.identifier != primary }.map(\.identifier))
            skipped.forEach(markScheduled)
            plans.removeAll { skipped.contains($0.identifier) }
        }
        return (plans.sorted { ($0.fireDate ?? now) < ($1.fireDate ?? now) }, owners)
    }

    func markScheduled(_ identifier: String) {
        let pieces = identifier.components(separatedBy: "|")
        guard pieces.count == 4 else { return }
        let shiftID = pieces.prefix(2).joined(separator: "|")
        var record = records[shiftID] ?? Record()
        guard record.scheduledEvents.insert(identifier).inserted else { return }
        records[shiftID] = record
        persist()
    }

    func silence(_ checkpoint: WorkdayCheckpoint) { silence(owner: checkpoint.id) }

    func silence(owner: String) {
        guard let shift, checkpoints.contains(where: { $0.id == owner && !$0.isComplete }) else { return }
        var record = records[shift.id] ?? Record()
        record.silenced.insert(owner)
        records[shift.id] = record
        persist()
    }

    private func makeCheckpoints(shift: WorkdaySchedule.Shift, record: Record, schedule: WorkdaySchedule,
                                 workLead: Int, endLead: Int) -> [WorkdayCheckpoint] {
        func checkpoint(_ kind: TimeclockReminderKind, _ title: String, _ due: Date, _ lead: Int, _ complete: Bool) -> WorkdayCheckpoint {
            let suffix = kind == .breakOver ? "breakOver-\(record.breakSessionNumber ?? 0)" : kind.rawValue
            let id = "\(shift.id)|\(suffix)"
            return WorkdayCheckpoint(id: id, kind: kind, title: title, due: due, leadMinutes: lead,
                                     isComplete: complete, isSilenced: record.silenced.contains(id))
        }
        var result = [checkpoint(.workStart, "Clock in", shift.start, workLead, record.seenWorking)]
        if let date = shift.preferredBreak {
            result.append(checkpoint(.breakStart, "Start break", date, 5, record.breakStartedAt != nil || record.clockedOut))
        }
        if let start = record.breakStartedAt, schedule.breakDuration > 0 {
            result.append(checkpoint(.breakOver, "Return from break", start.addingTimeInterval(Double(schedule.breakDuration * 60)),
                                     schedule.breakDuration > 5 ? 5 : 0, record.breakReturned || record.clockedOut))
        }
        result.append(checkpoint(.clockOut, "Clock out", shift.end, endLead, record.clockedOut))
        return result
    }

    private func persist() {
        do { defaults.set(try JSONEncoder().encode(records), forKey: key) }
        catch { persistenceError = "Reminder history could not be saved. \(error.localizedDescription)" }
    }
}
