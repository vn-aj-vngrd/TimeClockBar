import Combine
import Foundation

@MainActor
final class WorkdayReminderController: ObservableObject {
    struct Record: Codable, Equatable {
        var seenWorking = false
        var clockedOut = false
        var clockedOutAt: Date?
        var attendance: WorkdayAttendance?
        var hasStartedBreak: Bool?
        var breakStartedAt: Date?
        var breakReturned = false
        var breakSessionNumber: Int?
        var silenced: Set<String> = []
        var scheduledEvents: Set<String> = []
    }
    @Published private(set) var checkpoints: [WorkdayCheckpoint] = []
    @Published private(set) var shift: WorkdaySchedule.Shift?
    @Published private(set) var persistenceError: String?
    @Published private(set) var lastCompletedShift: WorkdayCompletion?
    private var records: [String: Record]
    private let defaults: UserDefaults
    private let key = "workdayCheckpointLedger.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do { records = try JSONDecoder().decode([String: Record].self, from: data) }
            catch { records = [:]; persistenceError = "Reminder history is unreadable. Automatic reminders are paused; the saved history has been preserved." }
        } else { records = [:] }
        updateLastCompletedShift()
    }

    func observe(state: TimeclockState, schedule: WorkdaySchedule, now: Date = Date(),
                 history: [TimeclockHistoryEntry] = [], historyTimeZone: TimeZone? = nil) {
        let nextShift = schedule.currentShift(at: now)
        if shift != nextShift { shift = nextShift }
        guard let shift else { checkpoints = []; return }
        var record = records[shift.id] ?? Record()
        // Count early attendance on this work date without completing a later work date.
        if canObserve(shift, schedule: schedule, now: now) {
            switch state {
            case .active:
                record.seenWorking = true
                record.clockedOut = false
                if record.hasStartedBreak == true || record.breakStartedAt != nil { record.breakReturned = true }
            case .onBreak(let timer):
                record.seenWorking = true
                record.clockedOut = false
                record.hasStartedBreak = true
                if record.breakReturned {
                    record.breakSessionNumber = (record.breakSessionNumber ?? 0) + 1
                    record.breakStartedAt = nil
                }
                record.breakReturned = false
                if let elapsed = TimeclockTimeMath.timerSeconds(from: timer), elapsed <= 24 * 3600 {
                    let startedAt = now.addingTimeInterval(-Double(elapsed))
                    let tolerance: TimeInterval = timer.contains(".") || timer.split(separator: ":").count == 3 ? 2 : 60
                    // Repair a deadline seeded from the zero work counter. Never extend a
                    // break because a stalled/rounded counter suggests a later start.
                    if record.breakStartedAt == nil || record.breakStartedAt!.timeIntervalSince(startedAt) > tolerance {
                        correctBreakStart(startedAt, record: &record, shift: shift, schedule: schedule, now: now)
                    }
                }
            case .clockedOut:
                if record.seenWorking, !record.clockedOut {
                    record.clockedOut = true
                    record.clockedOutAt = now
                }
            case .loading, .stale, .loginRequired, .unknown: break
            }
            if record.seenWorking, let historyTimeZone,
               let actual = TimeclockAttendanceHistory.resolve(history, timeZone: historyTimeZone,
                    shift: shift, schedule: schedule, state: state, now: now) {
                var saved = record.attendance ?? WorkdayAttendance()
                if let start = actual.clockIn { saved.clockIn = start }
                if let start = actual.breakStart {
                    saved.breakStart = start
                    saved.breakEnd = actual.breakEnd
                    record.hasStartedBreak = true
                    if actual.breakEnd != nil { record.breakReturned = true }
                    if record.breakStartedAt == nil { record.breakStartedAt = start }
                    if case .onBreak = state,
                       record.breakStartedAt.map({ abs($0.timeIntervalSince(start)) > 60 }) ?? true {
                        // Explicit recorded history can correct either direction. Keep the
                        // more precise elapsed-counter anchor when within a displayed minute.
                        correctBreakStart(start, record: &record, shift: shift, schedule: schedule, now: now)
                    }
                }
                if state == .clockedOut { saved.clockOut = actual.clockOut ?? saved.clockOut }
                else { saved.clockOut = nil }
                record.attendance = saved
            }
        }
        if records[shift.id] == nil || records[shift.id] != record {
            records[shift.id] = record
            persist()
        }
        let next = makeCheckpoints(shift: shift, record: record, schedule: schedule, workLead: 15, endLead: 15)
        if checkpoints != next { checkpoints = next }
    }

    func plans(schedule: WorkdaySchedule, state: TimeclockState, enabled: Set<TimeclockReminderKind>,
               sounds: [TimeclockReminderKind: TimeclockReminderSound], workLead: Int, endLead: Int,
               now: Date = Date()) -> (plans: [TimeclockReminderPlan], owners: Set<String>) {
        observe(state: state, schedule: schedule, now: now)
        if let shift {
            checkpoints = makeCheckpoints(shift: shift, record: records[shift.id] ?? Record(), schedule: schedule, workLead: workLead, endLead: endLead)
        }
        guard persistenceError == nil else { return ([], []) }
        let verified: Bool
        switch state { case .active, .onBreak, .clockedOut: verified = true; default: verified = false }
        var plans: [TimeclockReminderPlan] = []
        var owners: Set<String> = []
        // Two shifts stay below the platform's finite pending-request budget.
        let shifts = schedule.shifts(around: now).filter { $0.end.addingTimeInterval(4 * 3600) > now }.prefix(2)
        for shift in shifts {
            let record = records[shift.id] ?? Record()
            for checkpoint in makeCheckpoints(shift: shift, record: record, schedule: schedule, workLead: workLead, endLead: endLead) {
                guard enabled.contains(checkpoint.kind), !checkpoint.isComplete, !checkpoint.isSilenced else { continue }
                let isCurrent = shift.id == self.shift?.id && canObserve(shift, schedule: schedule, now: now)
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
                        guard verified else { continue }
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
                            ? "File your daily report on Full Scale, then open Time Clock to clock out. Scheduled end \(deadlineText(checkpoint.due, schedule: schedule))."
                            : "Open Time Clock to check your \(checkpoint.title.lowercased()). Due \(deadlineText(checkpoint.due, schedule: schedule)).",
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
                if plan.ownerIdentifier?.contains("|breakOver-") == true { return 0 }
                if plan.ownerIdentifier?.hasSuffix("|clockOut") == true { return 1 }
                return 2
            }
            let primary = caughtUp.sorted { priority($0) < priority($1) }.first!.identifier
            let skipped = Set(caughtUp.filter { $0.identifier != primary }.map(\.identifier))
            skipped.forEach(markScheduled)
            plans.removeAll { skipped.contains($0.identifier) }
        }
        // One sound per instant. Break return takes priority; other checkpoints stay visible.
        let groups = Dictionary(grouping: plans) { Int(($0.fireDate ?? now).timeIntervalSince1970) }
        plans = groups.values.compactMap { group in
            group.sorted {
                func priority(_ plan: TimeclockReminderPlan) -> Int {
                    if plan.ownerIdentifier?.contains("|breakOver-") == true { return 0 }
                    if plan.ownerIdentifier?.hasSuffix("|clockOut") == true { return 1 }
                    return 2
                }
                let left = priority($0), right = priority($1)
                return left == right ? $0.identifier < $1.identifier : left < right
            }.first
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

    func resume(_ checkpoint: WorkdayCheckpoint) {
        guard let shift, var record = records[shift.id], checkpoint.isSilenced else { return }
        record.silenced.remove(checkpoint.id)
        records[shift.id] = record
        persist()
    }

    func silence(owner: String) {
        guard let shift, checkpoints.contains(where: { $0.id == owner && !$0.isComplete }) else { return }
        var record = records[shift.id] ?? Record()
        record.silenced.insert(owner)
        records[shift.id] = record
        persist()
    }

    private func canObserve(_ shift: WorkdaySchedule.Shift, schedule: WorkdaySchedule, now: Date) -> Bool {
        let earliest = min(schedule.calendar.startOfDay(for: shift.start), shift.start.addingTimeInterval(-3600))
        return now >= earliest && now < shift.end.addingTimeInterval(4 * 3600)
    }

    private func makeCheckpoints(shift: WorkdaySchedule.Shift, record: Record, schedule: WorkdaySchedule,
                                 workLead: Int, endLead: Int) -> [WorkdayCheckpoint] {
        func checkpoint(_ kind: TimeclockReminderKind, _ title: String, _ due: Date, _ lead: Int, _ complete: Bool) -> WorkdayCheckpoint {
            let suffix = kind == .breakOver ? "breakOver-\(record.breakSessionNumber ?? 0)" : kind.rawValue
            let id = "\(shift.id)|\(suffix)"
            let actual: Date?
            switch kind {
            case .workStart: actual = record.attendance?.clockIn
            case .breakStart: actual = record.attendance?.breakStart
            case .breakOver: actual = record.attendance?.breakEnd
            case .clockOut: actual = record.attendance?.clockOut
            case .overtime: actual = nil
            }
            return WorkdayCheckpoint(id: id, kind: kind, title: title, due: due, leadMinutes: lead,
                                     isComplete: complete, isSilenced: record.silenced.contains(id), actualDate: actual)
        }
        var result = [checkpoint(.workStart, "Clock in", shift.start, workLead, record.seenWorking)]
        if let date = shift.preferredBreak ?? record.attendance?.breakStart {
            result.append(checkpoint(.breakStart, "Start break", date, 5,
                                     record.hasStartedBreak == true || record.breakStartedAt != nil || record.clockedOut))
        }
        if let start = record.breakStartedAt, schedule.breakDuration > 0 {
            result.append(checkpoint(.breakOver, "Return from break", start.addingTimeInterval(Double(schedule.breakDuration * 60)),
                                     schedule.breakDuration > 5 ? 5 : 0, record.breakReturned || record.clockedOut))
        }
        result.append(checkpoint(.clockOut, "Clock out", shift.end, endLead, record.clockedOut))
        return result
    }

    private func correctBreakStart(_ start: Date, record: inout Record, shift: WorkdaySchedule.Shift,
                                   schedule: WorkdaySchedule, now: Date) {
        if let previous = makeCheckpoints(shift: shift, record: record, schedule: schedule,
                                          workLead: 15, endLead: 15).first(where: { $0.kind == .breakOver }) {
            // Reschedule future stages without replaying already-due stages.
            for offset in previous.offsets where previous.due.addingTimeInterval(Double(offset * 60)) > now {
                let stage = offset < 0 ? "advance" : "due-\(offset)"
                record.scheduledEvents.remove("\(previous.id)|\(stage)")
            }
        }
        record.breakStartedAt = start
    }

    private func deadlineText(_ date: Date, schedule: WorkdaySchedule) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = schedule.timeZone
        formatter.dateFormat = "EEE HH:mm:ss z"
        return formatter.string(from: date)
    }

    private func persist() {
        updateLastCompletedShift()
        do { defaults.set(try JSONEncoder().encode(records), forKey: key) }
        catch { persistenceError = "Reminder history could not be saved. \(error.localizedDescription)" }
    }

    private func updateLastCompletedShift() {
        let completed = records.compactMap { id, record -> WorkdayCompletion? in
            guard record.seenWorking, record.clockedOut else { return nil }
            let parts = id.components(separatedBy: "|")
            guard parts.count == 2 else { return nil }
            return WorkdayCompletion(id: id, workDate: parts[1], observedAt: record.clockedOutAt,
                                     actualClockOut: record.attendance?.clockOut)
        }.max { $0.workDate < $1.workDate }
        if completed != lastCompletedShift { lastCompletedShift = completed }
    }
}
