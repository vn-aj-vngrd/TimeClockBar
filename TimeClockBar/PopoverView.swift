import AppKit
import SwiftUI
import UserNotifications
import WebKit

struct PopoverView: View {
    @ObservedObject var controller: TimeclockController
    @State private var isReportHovered = false
    @State private var isRecordingHotkey = false
    @State private var page: PopoverPage = .timeclock

    let openBrowser: (URL) -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            WebView(webView: currentWebView)
                .id(page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 460, height: 640)
        .background(Color.clear)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                IconButton(settingsTooltip, systemImage: "gearshape") {
                    controller.isSettingsPresented.toggle()
                }
                .popover(isPresented: $controller.isSettingsPresented, arrowEdge: .top) {
                    settingsPopover
                }

                IconButton("Refresh", systemImage: "arrow.clockwise") {
                    refresh()
                }

                IconButton("Open Browser", systemImage: "arrow.up.right.square") {
                    openBrowser(currentURL)
                }
            }
            .padding(3)
            .background(ChromeColor.controlGroup)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(ChromeColor.border, lineWidth: 1)
            )

            Spacer()

            pageToggleButton
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(ChromeColor.border)
                .frame(height: 1)
        }
    }

    private var pageToggleButton: some View {
        Button {
            switch page {
            case .timeclock:
                controller.loadDailyReport()
                page = .dailyReport
            case .dailyReport:
                page = .timeclock
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: page == .timeclock ? "doc.text.fill" : "clock.fill")
                    .font(.system(size: 12, weight: .bold))

                Text(page == .timeclock ? "Report" : "Clock")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(ChromeColor.primaryText)
            .frame(height: 30)
            .padding(.horizontal, 12)
            .background(isReportHovered ? ChromeColor.controlHover : ChromeColor.controlGroup)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(ChromeColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(page == .timeclock ? "Open daily report" : "Back to timeclock")
        .onHover { isReportHovered = $0 }
    }

    private var currentWebView: WKWebView {
        switch page {
        case .timeclock:
            return controller.webView
        case .dailyReport:
            return controller.dailyReportWebView
        }
    }

    private var settingsTooltip: String {
        controller.hotkeyEnabled ? "Settings · \(controller.hotkeyLabel) toggles app" : "Settings"
    }

    private var currentURL: URL {
        switch page {
        case .timeclock:
            return controller.url
        case .dailyReport:
            return controller.dailyReportURL
        }
    }

    private func refresh() {
        switch page {
        case .timeclock:
            controller.reload()
        case .dailyReport:
            controller.reloadDailyReport()
        }
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
        minutesBinding(
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

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 14, weight: .semibold))

            PreferenceSection("Display") {
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

            PreferenceSection("Shift") {
                WorkingDaysRow(selectedWeekdays: controller.workingWeekdays) { weekday, isEnabled in
                    controller.setWorkingWeekday(weekday, isEnabled: isEnabled)
                }
                TimeRow("Start", selection: workStartBinding)
                TimeRow("End", selection: workEndBinding)
                DurationRow("Break", selection: breakDurationBinding)
            }

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

                PreferenceRow("Test") {
                    Button("Send") {
                        controller.sendTestNotification()
                    }
                    .controlSize(.small)
                }
            }

            PreferenceSection("App") {
                PreferenceToggleRow("Launch at Login", isOn: launchAtLoginBinding)
                PreferenceToggleRow("Global shortcut", isOn: hotkeyEnabledBinding)

                if controller.hotkeyEnabled {
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

                PreferenceRow("Quit App") {
                    Button("Quit", action: quit)
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear {
            controller.refreshNotificationAuthorizationStatus()
        }
        .onDisappear {
            setHotkeyRecording(false)
        }
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

private struct WorkingDaysRow: View {
    let selectedWeekdays: Set<Int>
    let onChange: (Int, Bool) -> Void

    private let weekdays = [
        (weekday: 2, label: "Mon"),
        (weekday: 3, label: "Tue"),
        (weekday: 4, label: "Wed"),
        (weekday: 5, label: "Thu"),
        (weekday: 6, label: "Fri"),
        (weekday: 7, label: "Sat"),
        (weekday: 1, label: "Sun")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Working days")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.secondaryText)

            HStack(spacing: 4) {
                ForEach(weekdays, id: \.weekday) { day in
                    let isSelected = selectedWeekdays.contains(day.weekday)

                    Button {
                        onChange(day.weekday, !isSelected)
                    } label: {
                        Text(day.label)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? ChromeColor.primaryText : ChromeColor.secondaryText)
                    .background(isSelected ? ChromeColor.reportBottom : ChromeColor.controlGroup)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(ChromeColor.sectionRing, lineWidth: 1)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct HotkeyRecorderButton: View {
    let label: String
    @Binding var isRecording: Bool
    let onRecord: (UInt32, NSEvent.ModifierFlags) -> Void
    @State private var recordingLabel = "Listening..."

    private let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    var body: some View {
        HStack(spacing: 6) {
            Text(isRecording ? recordingLabel : label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isRecording ? ChromeColor.primaryText : ChromeColor.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 96, alignment: .trailing)

            if isRecording {
                Button("Clear") {
                    stopRecording()
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Button("Change") {
                    startRecording()
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background {
            HotkeyCaptureView(
                isActive: isRecording,
                onKeyDown: handleKeyDown,
                onModifierChange: updateRecordingLabel
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        recordingLabel = "Listening..."
        isRecording = true
    }

    private func stopRecording() {
        recordingLabel = "Listening..."
        isRecording = false
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        let modifiers = event.modifierFlags.intersection(allowedModifiers)
        recordingLabel = TimeclockController.hotkeyLabel(keyCode: UInt32(event.keyCode), modifiers: modifiers)

        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        onRecord(UInt32(event.keyCode), modifiers)
        stopRecording()
    }

    private func updateRecordingLabel(modifiers: NSEvent.ModifierFlags) {
        let modifierLabel = TimeclockController.hotkeyModifierLabel(modifiers.intersection(allowedModifiers))
        recordingLabel = modifierLabel.isEmpty ? "Listening..." : "\(modifierLabel)..."
    }
}

private struct HotkeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onKeyDown: (NSEvent) -> Void
    let onModifierChange: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKeyDown = onKeyDown
        view.onModifierChange = onModifierChange
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onKeyDown = onKeyDown
        view.onModifierChange = onModifierChange

        guard isActive else { return }

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }

    final class CaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?
        var onModifierChange: ((NSEvent.ModifierFlags) -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }

        override func flagsChanged(with event: NSEvent) {
            onModifierChange?(event.modifierFlags)
        }
    }
}

private struct PreferenceSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ChromeColor.secondaryText)

            VStack(alignment: .leading, spacing: 9) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(ChromeColor.sectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ChromeColor.sectionRing, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PreferenceRow<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.secondaryText)

            Spacer(minLength: 12)

            accessory
        }
        .frame(minHeight: 32)
    }
}

private struct PreferenceToggleRow: View {
    let title: String
    let isOn: Binding<Bool>

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self.isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.primaryText)

            Spacer(minLength: 12)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }
}

private struct TimeRow: View {
    let title: String
    let selection: Binding<Int>

    init(_ title: String, selection: Binding<Int>) {
        self.title = title
        self.selection = selection
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.secondaryText)

            Spacer(minLength: 12)

            Picker(title, selection: selection) {
                ForEach(Array(stride(from: 0, to: 1440, by: 15)), id: \.self) { minutes in
                    Text(Self.timeLabel(minutes: minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }

    private static func timeLabel(minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(displayHour):\(String(format: "%02d", minute)) \(suffix)"
    }
}

private struct DurationRow: View {
    let title: String
    let selection: Binding<Int>

    init(_ title: String, selection: Binding<Int>) {
        self.title = title
        self.selection = selection
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.secondaryText)

            Spacer(minLength: 12)

            Picker(title, selection: selection) {
                ForEach(Array(stride(from: 0, through: 240, by: 15)), id: \.self) { minutes in
                    Text(Self.durationLabel(minutes: minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }

    private static func durationLabel(minutes: Int) -> String {
        if minutes == 0 {
            return "None"
        }

        let hours = minutes / 60
        let minutes = minutes % 60

        if hours == 0 {
            return "\(minutes) min"
        }

        if minutes == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        return "\(hours)h \(minutes)m"
    }
}

private struct IconButton: View {
    let title: String
    let systemImage: String
    let showsBackground: Bool
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, systemImage: String, showsBackground: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.showsBackground = showsBackground
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? ChromeColor.primaryText : ChromeColor.secondaryText)
        .background(isHovered ? ChromeColor.controlHover : showsBackground ? ChromeColor.controlGroup : .clear)
        .clipShape(Circle())
        .help(title)
        .onHover { isHovered = $0 }
    }
}

private enum ChromeColor {
    static let controlGroup = Color.white.opacity(0.055)
    static let controlHover = Color.white.opacity(0.085)
    static let border = Color.white.opacity(0.09)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.58)
    static let reportBottom = Color(red: 0.0, green: 0.34, blue: 0.88)
    static let sectionBackground = Color.white.opacity(0.045)
    static let sectionRing = Color.white.opacity(0.075)
}

private enum PopoverPage {
    case timeclock
    case dailyReport
}

#Preview {
    PopoverView(
        controller: TimeclockController(),
        openBrowser: { _ in },
        quit: {}
    )
}
