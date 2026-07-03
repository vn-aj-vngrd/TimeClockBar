import AppKit
import SwiftUI
import UserNotifications

struct SettingsPopover: View {
    @ObservedObject var controller: TimeclockController
    @Binding var isRecordingHotkey: Bool

    let quit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                displaySection
                shiftSection
                notificationsSection
                appSection
            }
            .padding(16)
        }
        .onAppear {
            controller.refreshNotificationAuthorizationStatus()
        }
        .onDisappear {
            setHotkeyRecording(false)
        }
    }

    private var displaySection: some View {
        PreferenceSection("Display") {
            PreferenceToggleRow("Show FS logo", isOn: fsLogoBinding)
            PreferenceToggleRow("Show labels", isOn: displayLabelsBinding)

            ForEach(TimeclockDisplayComponent.allCases) { component in
                PreferenceToggleRow(component.label, isOn: displayComponentBinding(component))
            }

            PreferenceRow("Defaults") {
                Button("Reset") {
                    controller.resetDisplayDefaults()
                }
                .controlSize(.small)
            }
        }
    }

    private var shiftSection: some View {
        PreferenceSection("Shift") {
            WorkingDaysRow(selectedWeekdays: controller.workingWeekdays) { weekday, isEnabled in
                controller.setWorkingWeekday(weekday, isEnabled: isEnabled)
            }
            TimeRow("Start", selection: workStartBinding)
            TimeRow("End", selection: workEndBinding)
            DurationRow("Break", selection: breakDurationBinding)
        }
    }

    private var notificationsSection: some View {
        PreferenceSection("Notifications") {
            PreferenceRow("Permission") {
                HStack(spacing: 8) {
                    Text(notificationPermissionLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(notificationPermissionEnabled ? ChromeColor.secondaryText : ChromeColor.primaryText)

                    if !notificationPermissionEnabled {
                        Button("Open") {
                            openNotificationSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }

            PreferenceToggleRow("Before shift", isOn: workReminderEnabledBinding)

            if controller.workReminderEnabled {
                PreferenceRow("Before shift time") {
                    leadTimePicker(selection: workReminderLeadBinding)
                }
            }

            PreferenceToggleRow("Break reminder", isOn: breakReminderEnabledBinding)

            if controller.breakReminderEnabled {
                TimeRow("At", selection: breakReminderBinding)
            }

            PreferenceToggleRow("Clock out reminder", isOn: clockOutReminderEnabledBinding)

            if controller.clockOutReminderEnabled {
                PreferenceRow("Before clock out") {
                    leadTimePicker(selection: clockOutReminderLeadBinding)
                }
            }

            #if DEBUG
                PreferenceRow("Test") {
                    HStack(spacing: 6) {
                        Button("Shift") {
                            controller.sendTestShiftReminder()
                        }
                        Button("Break") {
                            controller.sendTestBreakReminder()
                        }
                        Button("Clock Out") {
                            controller.sendTestClockOutReminder()
                        }
                    }
                    .controlSize(.small)
                }
            #endif
        }
    }

    private var appSection: some View {
        PreferenceSection("App") {
            PreferenceToggleRow("Launch at Login", isOn: launchAtLoginBinding)
            PreferenceToggleRow("Global shortcut", isOn: hotkeyEnabledBinding)

            if controller.hotkeyEnabled {
                hotkeyRow
            }

            PreferenceRow("Defaults") {
                Button("Reset All") {
                    setHotkeyRecording(false)
                    controller.resetAllDefaults()
                }
                .controlSize(.small)
            }

            PreferenceRow("Quit App") {
                Button("Quit", action: quit)
                    .controlSize(.small)
            }
        }
    }

    private var hotkeyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Toggle App")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ChromeColor.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 12)

                HotkeyRecorderButton(
                    label: controller.hotkeyLabel,
                    isRecording: hotkeyRecordingBinding
                ) { keyCode, modifiers in
                    controller.setHotkey(keyCode: keyCode, modifiers: modifiers)
                }

                if !controller.isDefaultHotkey {
                    Button("Reset") {
                        setHotkeyRecording(false)
                        controller.resetHotkeyDefaults()
                    }
                    .controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity)

            if isRecordingHotkey {
                Text("Press a modifier + key. Esc or Clear cancels.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ChromeColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { controller.launchAtLoginEnabled },
            set: { controller.setLaunchAtLoginEnabled($0) }
        )
    }

    private var workStartBinding: Binding<Int> {
        minutesBinding(
            get: { controller.workStartMinutes },
            set: { controller.setWorkStartMinutes($0) }
        )
    }

    private var workEndBinding: Binding<Int> {
        minutesBinding(
            get: { controller.workEndMinutes },
            set: { controller.setWorkEndMinutes($0) }
        )
    }

    private var breakDurationBinding: Binding<Int> {
        minutesBinding(
            get: { controller.breakDurationMinutes },
            set: { controller.setBreakDurationMinutes($0) }
        )
    }

    private var workReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.workReminderEnabled },
            set: { controller.setWorkReminderEnabled($0) }
        )
    }

    private var workReminderLeadBinding: Binding<Int> {
        Binding(
            get: { controller.workReminderLeadMinutes },
            set: { controller.setWorkReminderLeadMinutes($0) }
        )
    }

    private var breakReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.breakReminderEnabled },
            set: { controller.setBreakReminderEnabled($0) }
        )
    }

    private var breakReminderBinding: Binding<Int> {
        minutesBinding(
            get: { controller.breakReminderMinutes },
            set: { controller.setBreakReminderMinutes($0) }
        )
    }

    private var clockOutReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.clockOutReminderEnabled },
            set: { controller.setClockOutReminderEnabled($0) }
        )
    }

    private var clockOutReminderLeadBinding: Binding<Int> {
        Binding(
            get: { controller.clockOutReminderLeadMinutes },
            set: { controller.setClockOutReminderLeadMinutes($0) }
        )
    }

    private var displayLabelsBinding: Binding<Bool> {
        Binding(
            get: { controller.displayLabelsEnabled },
            set: { controller.setDisplayLabelsEnabled($0) }
        )
    }

    private var fsLogoBinding: Binding<Bool> {
        Binding(
            get: { controller.fsLogoEnabled },
            set: { controller.setFSLogoEnabled($0) }
        )
    }

    private var hotkeyEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.hotkeyEnabled },
            set: {
                if !$0 {
                    setHotkeyRecording(false)
                }

                controller.setHotkeyEnabled($0)
            }
        )
    }

    private var hotkeyRecordingBinding: Binding<Bool> {
        Binding(
            get: { isRecordingHotkey },
            set: { setHotkeyRecording($0) }
        )
    }

    private var notificationPermissionEnabled: Bool {
        switch controller.notificationAuthorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private var notificationPermissionLabel: String {
        switch controller.notificationAuthorizationStatus {
        case .authorized:
            return "Allowed"
        case .provisional:
            return "Allowed quietly"
        case .denied:
            return "Disabled"
        case .notDetermined:
            return "Not set"
        @unknown default:
            return "Unknown"
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func displayComponentBinding(_ component: TimeclockDisplayComponent) -> Binding<Bool> {
        Binding(
            get: { controller.displayComponents.contains(component) },
            set: { controller.setDisplayComponent(component, isEnabled: $0) }
        )
    }

    private func minutesBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(
            get: { get() },
            set: { set($0) }
        )
    }

    private func leadTimePicker(selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            Text("15 min").tag(15)
            Text("10 min").tag(10)
            Text("5 min").tag(5)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 178)
    }

    private func setHotkeyRecording(_ isRecording: Bool) {
        isRecordingHotkey = isRecording
        controller.setHotkeyRecording(isRecording)
    }
}
