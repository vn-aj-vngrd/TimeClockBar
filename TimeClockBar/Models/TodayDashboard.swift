import Foundation

/// Presents shift progress and destinations without performing website actions.
struct TodayDashboard {
    enum Phase { case offDay, upcoming, working, breakTime, onBreak, wrapUp, unavailable }
    let phase: Phase
    let title: String
    let detail: String
    let actionTitle: String?
    let destination: PopoverPage?
    let deadline: Date?
    private(set) var isReportComplete = false
    private(set) var shift: WorkdaySchedule.Shift?
    private(set) var checkpoints: [WorkdayCheckpoint] = []
    private(set) var previousShift: WorkdayCompletion?

    static func resolve(state: TimeclockState, schedule: WorkdaySchedule,
                        checkpoints: [WorkdayCheckpoint], now: Date,
                        lastCompletedShift: WorkdayCompletion? = nil) -> Self {
        let working: Bool
        switch state { case .active, .onBreak: working = true; default: working = false }
        var shift = schedule.currentShift(at: now)
        var completion = lastCompletedShift
        if !working, let current = shift,
           checkpoints.contains(where: { $0.id == "\(current.id)|clockOut" && $0.isComplete }) {
            if completion?.id != current.id {
                completion = WorkdayCompletion(id: current.id, workDate: current.workDate, observedAt: nil)
            }
            // The reminder engine retains its recovery window; Today can already show what's next.
            shift = schedule.shifts(around: now).first { $0.start > now && $0.start > current.start }
        }
        let displayedCheckpoints = checkpoints.filter { checkpoint in
            shift.map { checkpoint.id.hasPrefix("\($0.id)|") } ?? false
        }
        var dashboard = presentation(state: state, schedule: schedule, shift: shift,
                                     checkpoints: displayedCheckpoints, now: now)
        dashboard.shift = shift
        dashboard.checkpoints = displayedCheckpoints
        dashboard.isReportComplete = displayedCheckpoints.contains { $0.kind == .clockOut && $0.isComplete }
        if !working, let completion, completion.id.hasPrefix("\(schedule.timeZone.identifier)|"),
           completion.id != shift?.id,
           shift.map({ completion.workDate < $0.workDate }) ?? true {
            dashboard.previousShift = completion
        }
        return dashboard
    }

    private static func presentation(state: TimeclockState, schedule: WorkdaySchedule,
                                     shift: WorkdaySchedule.Shift?,
                                     checkpoints: [WorkdayCheckpoint], now: Date) -> Self {
        let working: Bool
        switch state { case .active, .onBreak: working = true; default: working = false }
        let isOvernightShift = shift.map { $0.start <= now && now < $0.end } ?? false
        let isWorkday = schedule.weekdays.contains(schedule.calendar.component(.weekday, from: now)) || isOvernightShift
        if !isWorkday && !working {
            return Self(phase: .offDay, title: "No shift today", detail: "Enjoy your day off. Your next shift is shown below.",
                        actionTitle: nil, destination: nil, deadline: shift?.start)
        }
        if case .onBreak(let timer) = state {
            let deadline = checkpoints.first { $0.kind == .breakOver && !$0.isComplete }?.due
                ?? TimeclockTimeMath.timerSeconds(from: timer).map { now.addingTimeInterval(Double(schedule.breakDuration * 60 - $0)) }
            return Self(phase: .onBreak, title: "You're on break", detail: "End your break in Time Clock when you're back.",
                        actionTitle: "Open Time Clock", destination: .timeclock, deadline: deadline)
        }
        guard let shift else {
            return Self(phase: .unavailable, title: "Set your work schedule", detail: "Choose working days and shift times in Settings.",
                        actionTitle: nil, destination: nil, deadline: nil)
        }
        if working {
            if now >= shift.end.addingTimeInterval(-30 * 60) {
                return Self(phase: .wrapUp, title: "Report, then clock out", detail: "File your daily report on Full Scale before clocking out.",
                            actionTitle: "Open Report", destination: .dailyReport, deadline: shift.end)
            }
            if let nextBreak = checkpoints.first(where: { $0.kind == .breakStart && !$0.isComplete }),
               now >= nextBreak.due.addingTimeInterval(-5 * 60) {
                return Self(phase: .breakTime, title: "Time for your break", detail: "Start your break in Time Clock. We'll remind you when it's time to return.",
                            actionTitle: "Open Time Clock", destination: .timeclock, deadline: nextBreak.due)
            }
            let nextBreak = checkpoints.first { $0.kind == .breakStart && !$0.isComplete }?.due
            return Self(phase: .working, title: "You're working", detail: nextBreak == nil ? "Next: file your report before clock-out." : "Next: your scheduled break.",
                        actionTitle: "View Time Clock", destination: .timeclock, deadline: nextBreak ?? shift.end.addingTimeInterval(-30 * 60))
        }
        if now < shift.start {
            return Self(phase: .upcoming, title: "Your next shift", detail: "Clock in using Time Clock when your shift starts.",
                        actionTitle: "Open Time Clock", destination: .timeclock, deadline: shift.start)
        }
        if state == .clockedOut {
            return Self(phase: .upcoming, title: "Time to clock in", detail: "Your shift has started. Open Time Clock to clock in.",
                        actionTitle: "Open Time Clock", destination: .timeclock, deadline: shift.start)
        }
        return Self(phase: .unavailable, title: "Check your clock status", detail: "Open Time Clock to refresh or sign in.",
                    actionTitle: "Open Time Clock", destination: .timeclock, deadline: nil)
    }
}
