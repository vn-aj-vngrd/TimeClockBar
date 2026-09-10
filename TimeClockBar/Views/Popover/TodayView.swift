import SwiftUI

struct TodayView: View {
    @ObservedObject var controller: TimeclockController
    @ObservedObject var workday: WorkdayReminderController
    let openClock: () -> Void
    let openReport: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let dashboard = TodayDashboard.resolve(state: controller.state, schedule: controller.workSchedule,
                                                   checkpoints: workday.checkpoints, now: context.date)
            let shift = controller.workSchedule.currentShift(at: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Today").font(.title2.bold())
                        Spacer()
                        Text(formatted(context.date, template: "EEEEMMMd"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label(dashboard.title, systemImage: symbol(dashboard.phase)).font(.title3.bold())
                        Text(dashboard.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let deadline = dashboard.deadline {
                            if dashboard.phase == .offDay || dashboard.phase == .upcoming && deadline > context.date {
                                Text(formatted(deadline, template: "EEEEjm"))
                                    .font(.headline)
                            } else {
                                Text(countdown(deadline, now: context.date)).font(.title3).monospacedDigit()
                            }
                        }
                        if let title = dashboard.actionTitle {
                            HStack(spacing: 12) {
                                Button(title, action: dashboard.destination == .dailyReport ? openReport : openClock)
                                    .buttonStyle(.borderedProminent)
                                if dashboard.phase == .wrapUp {
                                    Button("Then open Time Clock", action: openClock)
                                }
                            }
                        }
                    }
                    if let shift {
                        Divider()
                        VStack(alignment: .leading, spacing: 14) {
                            Text(dashboard.phase == .offDay ? "Next shift · \(shift.workDate)" : "Your shift")
                                .font(.headline)
                            scheduleRow("Clock in", at: shift.start, kind: .workStart)
                            if let date = shift.preferredBreak { scheduleRow("Break", at: date, kind: .breakStart) }
                            if let checkpoint = workday.checkpoints.first(where: { $0.kind == .breakOver }) {
                                scheduleRow("End break", at: checkpoint.due, kind: .breakOver)
                            }
                            HStack {
                                Image(systemName: "doc.text").foregroundStyle(.secondary).frame(width: 18)
                                Text("File report")
                                Spacer()
                                Text("Before clock-out").font(.caption).foregroundStyle(.secondary)
                            }
                            scheduleRow("Clock out", at: shift.end, kind: .clockOut)
                        }
                    }
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: controller.isPreview ? "eye" : "info.circle")
                        Text(controller.isPreview ? "Local preview · website access paused" : controller.connectionStatus)
                            .fixedSize(horizontal: false, vertical: true)
                    }.font(.caption).foregroundStyle(.secondary)
                    if let observed = controller.lastRefreshedAt {
                        Text("Last observed \(observed, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = workday.persistenceError { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(22)
            }
        }
        .environment(\.timeZone, controller.workSchedule.timeZone)
        .background(ChromeColor.settingsBackground)
        .onAppear { controller.scheduleReminders() }
    }

    private func scheduleRow(_ title: String, at date: Date, kind: TimeclockReminderKind) -> some View {
        let complete = workday.checkpoints.first { $0.kind == kind }?.isComplete == true
        return HStack {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(complete ? .green : .secondary).frame(width: 18)
                .accessibilityLabel(complete ? "Observed complete" : "Scheduled")
            Text(title)
            if let checkpoint = workday.checkpoints.first(where: { $0.kind == kind }), !checkpoint.isComplete {
                if checkpoint.isSilenced {
                    Button("Resume") { controller.resumeCheckpoint(checkpoint) }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityLabel("Resume \(title) reminders")
                } else {
                    Button("Silence") { controller.silenceCheckpoint(checkpoint) }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityLabel("Silence \(title) reminders")
                }
            }
            Spacer()
            Text(formatted(date, template: "Ejm"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func symbol(_ phase: TodayDashboard.Phase) -> String {
        switch phase {
        case .offDay: return "sun.max"
        case .onBreak, .breakTime: return "cup.and.saucer"
        case .wrapUp: return "doc.text"
        case .finished: return "checkmark.circle"
        default: return "clock"
        }
    }

    private func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = controller.workSchedule.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private func countdown(_ date: Date, now: Date) -> String {
        let seconds = Int(abs(date.timeIntervalSince(now)))
        let duration = String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        return date > now ? "In \(duration)" : "Due · \(duration) ago"
    }
}
