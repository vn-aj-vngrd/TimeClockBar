import Foundation

/// Chooses a useful destination without performing or claiming a website action.
struct TodayDashboard {
    enum Phase { case offDay, upcoming, working, breakTime, onBreak, wrapUp, finished, unavailable }
    let phase: Phase
    let title: String
    let detail: String
    let actionTitle: String?
    let destination: PopoverPage?
    let deadline: Date?

    static func resolve(state: TimeclockState, schedule: WorkdaySchedule,
                        checkpoints: [WorkdayCheckpoint], now: Date) -> Self {
        let shift = schedule.currentShift(at: now)
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
        if !working && checkpoints.contains(where: { $0.kind == .clockOut && $0.isComplete }) {
            return Self(phase: .finished, title: "You're clocked out", detail: "Your shift is finished. Reports stay on Full Scale.",
                        actionTitle: nil, destination: nil, deadline: nil)
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
