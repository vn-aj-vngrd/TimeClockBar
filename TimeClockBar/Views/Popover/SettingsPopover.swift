import AppKit
import SwiftUI
import UserNotifications

struct SettingsPopover: View {
    @ObservedObject var controller: TimeclockController
    @ObservedObject private var delivery = TimeclockReminderScheduler.delivery
    @Binding var isRecordingHotkey: Bool
    @State private var isResetAllConfirmationPresented = false

    let quit: () -> Void

    var body: some View {
        Form {
            displaySection
            shiftSection
            notificationPermissionSection
            reminderSoundsSection
            shiftStartNotificationSection
            breakNotificationSection
            shiftEndNotificationSection
            notificationTestSection
            shortcutsSection
            appSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChromeColor.settingsBackground)
        .onAppear {
            controller.refreshNotificationAuthorizationStatus()
        }
        .onDisappear {
            setHotkeyRecording(false)
        }
        .confirmationDialog(
            "Reset all defaults?",
            isPresented: $isResetAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Reset All Defaults", role: .destructive) {
                controller.resetAllDefaults()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores display, shift, notification, shortcut, and app settings.")
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
                .buttonStyle(.settingsControl)
            }
            .lastPreferenceRow()
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
                .lastPreferenceRow()
        }
    }

    private var notificationPermissionSection: some View {
        PreferenceSection("Notifications") {
            PreferenceRow("Permission") {
                HStack(spacing: 8) {
                    Text(notificationPermissionLabel)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(notificationPermissionEnabled ? ChromeColor.secondaryText : ChromeColor.primaryText)

                    if !notificationPermissionEnabled {
                        Button("Open") {
                            openNotificationSettings()
                        }
                        .buttonStyle(.settingsControl)
                    }
                }
            }

            PreferenceRow("Sound") {
                HStack(spacing: 8) {
                    Text(notificationSoundLabel)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(notificationSoundEnabled ? ChromeColor.secondaryText : ChromeColor.primaryText)

                    if !notificationSoundEnabled {
                        Button("Open") {
                            openNotificationSettings()
                        }
                        .buttonStyle(.settingsControl)
                    }
                }
            }
            .lastPreferenceRow()
        }
    }

    private var shiftStartNotificationSection: some View {
        PreferenceSection("Shift Start") {
            if controller.workReminderEnabled {
                PreferenceToggleRow("Before shift", isOn: workReminderEnabledBinding)

                PreferenceRow("Notify before") {
                    leadTimePicker(selection: workReminderLeadBinding)
                }
                .lastPreferenceRow()
            } else {
                PreferenceToggleRow("Before shift", isOn: workReminderEnabledBinding)
                    .lastPreferenceRow()
            }
        }
    }

    private var reminderSoundsSection: some View {
        PreferenceSection("Reminder Sounds") {
            reminderSoundRow("Shift start", kind: .workStart)
            reminderSoundRow("Break", kind: .breakStart)
            reminderSoundRow("Over break", kind: .breakOver)
            reminderSoundRow("Clock out", kind: .clockOut)
            reminderSoundRow("Overtime", kind: .overtime)
                .lastPreferenceRow()
        }
    }

    private var breakNotificationSection: some View {
        PreferenceSection("Break") {
            PreferenceToggleRow("Break reminder", isOn: breakReminderEnabledBinding)

            if controller.breakReminderEnabled {
                TimeRow("Start break at", selection: breakReminderBinding)
            }

            PreferenceToggleRow("Over break reminder", isOn: breakOverReminderEnabledBinding)
                .lastPreferenceRow()
        }
    }

    private var shiftEndNotificationSection: some View {
        PreferenceSection("Shift End") {
            PreferenceToggleRow("Clock out reminder", isOn: clockOutReminderEnabledBinding)

            if controller.clockOutReminderEnabled {
                PreferenceRow("Notify before") {
                    leadTimePicker(selection: clockOutReminderLeadBinding)
                }
            }

            PreferenceToggleRow("Overtime reminder", isOn: overtimeReminderEnabledBinding)
                .lastPreferenceRow()
        }
    }

        private var notificationTestSection: some View {
            PreferenceSection("Notification Tests") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(delivery.status).font(.caption).foregroundStyle(.secondary)
                    if let error = delivery.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                    Text("Send test")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(ChromeColor.primaryText)

                    HStack(spacing: 6) {
                        testNotificationButton("Shift", action: controller.sendTestShiftReminder)
                        testNotificationButton("Break", action: controller.sendTestBreakReminder)
                        testNotificationButton("Over Break", action: controller.sendTestBreakOverReminder)
                    }

                    HStack(spacing: 6) {
                        testNotificationButton("Clock Out", action: controller.sendTestClockOutReminder)
                        testNotificationButton("Overtime", action: controller.sendTestOvertimeReminder)
                    }
                }
                .lastPreferenceRow()
            }
        }

        private func testNotificationButton(_ title: String, action: @escaping () -> Void) -> some View {
            Button(title, action: action)
                .buttonStyle(.settingsControl)
        }

    private var appSection: some View {
        PreferenceSection("App") {
            PreferenceRow("Work timezone") {
                Picker("Work timezone", selection: Binding(get: { controller.workTimeZone }, set: controller.setWorkTimeZone)) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: 240)
            }
            if let error = controller.launchAtLoginError {
                Text("Launch at login: \(error)").foregroundStyle(.red).padding()
            }
            PreferenceRow("Theme") {
                PreferenceMenuPicker(
                    selection: appThemeBinding,
                    options: TimeclockAppTheme.allCases.map { (value: $0, label: $0.label) }
                )
            }

            PreferenceToggleRow("Launch at Login", isOn: launchAtLoginBinding)

            PreferenceRow("Defaults") {
                Button("Reset All") {
                    setHotkeyRecording(false)
                    isResetAllConfirmationPresented = true
                }
                .buttonStyle(.settingsControl)
            }

            PreferenceRow("Quit App") {
                Button("Quit", action: quit)
                    .buttonStyle(.settingsControl)
            }
            .lastPreferenceRow()
        }
    }

    private var shortcutsSection: some View {
        PreferenceSection("Shortcuts") {
            if controller.hotkeyEnabled {
                PreferenceToggleRow("Global shortcut", isOn: hotkeyEnabledBinding)
                hotkeyRow
                ShortcutRow("Settings", shortcut: "⌘,")
                ShortcutRow("Time Clock", shortcut: "⌘1")
                ShortcutRow("Report", shortcut: "⌘2")
                ShortcutRow("Refresh", shortcut: "⌘R")
                ShortcutRow("Open Current Page", shortcut: "⌘O")
                ShortcutRow("Open Time Clock in Browser", shortcut: "⌥⌘1")
                ShortcutRow("Open Report in Browser", shortcut: "⌥⌘2")
                ShortcutRow("Quit App", shortcut: "⌘Q")
                    .lastPreferenceRow()
            } else {
                PreferenceToggleRow("Global shortcut", isOn: hotkeyEnabledBinding)
                    .lastPreferenceRow()
            }
        }
    }

    private var hotkeyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Toggle App")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ChromeColor.primaryText)
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
                    .buttonStyle(.settingsControl)
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

    private var appThemeBinding: Binding<TimeclockAppTheme> {
        Binding(
            get: { controller.appTheme },
            set: { controller.setAppTheme($0) }
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

    private var breakOverReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.breakOverReminderEnabled },
            set: { controller.setBreakOverReminderEnabled($0) }
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

    private var overtimeReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.overtimeReminderEnabled },
            set: { controller.setOvertimeReminderEnabled($0) }
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

    private var notificationSoundEnabled: Bool {
        controller.notificationSoundSetting == .enabled
    }

    private var notificationSoundLabel: String {
        switch controller.notificationSoundSetting {
        case .enabled:
            return "On"
        case .disabled:
            return "Off"
        case .notSupported:
            return "Unavailable"
        @unknown default:
            return "Unknown"
        }
    }

    private func reminderSoundRow(_ title: String, kind: TimeclockReminderKind) -> some View {
        let sound = controller.reminderSound(for: kind)
        let isPreviewing = controller.previewingReminderKind == kind

        return PreferenceRow(title) {
            HStack(spacing: 6) {
                PreferenceMenuPicker(
                    selection: Binding(
                        get: { controller.reminderSound(for: kind) },
                        set: { controller.setReminderSound($0, for: kind) }
                    ),
                    options: TimeclockReminderSound.allCases.map { (value: $0, label: $0.label) }
                )

                Button(isPreviewing ? "Stop" : "Preview") {
                    controller.toggleReminderSoundPreview(for: kind)
                }
                .buttonStyle(.settingsControl)
                .accessibilityLabel(isPreviewing ? "Stop \(sound.label) preview" : "Preview \(sound.label)")
            }
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
        PreferenceMenuPicker(
            selection: selection,
            options: [
                (value: 15, label: "15 min"),
                (value: 10, label: "10 min"),
                (value: 5, label: "5 min")
            ]
        )
    }

    private func setHotkeyRecording(_ isRecording: Bool) {
        isRecordingHotkey = isRecording
        controller.setHotkeyRecording(isRecording)
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: String

    init(_ title: String, shortcut: String) {
        self.title = title
        self.shortcut = shortcut
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ChromeColor.primaryText)

            Spacer(minLength: 12)

            Text(shortcut)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(ChromeColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
