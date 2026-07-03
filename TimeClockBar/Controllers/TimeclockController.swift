import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications
import WebKit

final class TimeclockController: NSObject, ObservableObject, WKNavigationDelegate {
    let url = URL(string: "https://timeclock.fullscale.rocks/overview")!
    let dailyReportURL = URL(string: "https://fullscale.rocks/daily-report")!
    let webView: WKWebView
    let dailyReportWebView: WKWebView

    @Published private(set) var state: TimeclockState = .loading
    @Published private(set) var menuBarTitle: String = TimeclockState.loading.menuBarTitle
    @Published private(set) var todayProgressTitle: String = ""
    @Published private(set) var displayComponents: Set<TimeclockDisplayComponent>
    @Published private(set) var displayLabelsEnabled: Bool
    @Published private(set) var fsLogoEnabled: Bool
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var workStartMinutes: Int
    @Published private(set) var workEndMinutes: Int
    @Published private(set) var breakDurationMinutes: Int
    @Published private(set) var workReminderEnabled: Bool
    @Published private(set) var workReminderLeadMinutes: Int
    @Published private(set) var breakReminderEnabled: Bool
    @Published private(set) var breakReminderMinutes: Int
    @Published private(set) var clockOutReminderEnabled: Bool
    @Published private(set) var clockOutReminderLeadMinutes: Int
    @Published private(set) var workingWeekdays: Set<Int>
    @Published private(set) var hotkeyEnabled: Bool
    @Published private(set) var hotkeyKeyCode: UInt32
    @Published private(set) var hotkeyModifierFlags: NSEvent.ModifierFlags
    @Published private(set) var isRecordingHotkey = false
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isSettingsPresented = false
    @Published private(set) var requestedPopoverPage: PopoverPage?

    private var pollTimer: Timer?
    private var lastDetection: TimeclockDOMDetection?
    private var timers = TimeclockTimers.empty
    private var lastRunningTimerValue = ""
    private var lastRunningTimerChangedAt = Date()
    private var hasSentLoginNotification = false

    private static let displayComponentsDefaultsKey = "timeclockDisplayComponents"
    private static let displayLabelsEnabledDefaultsKey = "displayLabelsEnabled"
    private static let fsLogoEnabledDefaultsKey = "fsLogoEnabled"
    private static let legacyDisplayMetricDefaultsKey = "timeclockDisplayMetric"
    private static let workStartMinutesDefaultsKey = "workStartMinutes"
    private static let workEndMinutesDefaultsKey = "workEndMinutes"
    private static let breakDurationMinutesDefaultsKey = "breakDurationMinutes"
    private static let workReminderEnabledDefaultsKey = "workReminderEnabled"
    private static let workReminderLeadMinutesDefaultsKey = "workReminderLeadMinutes"
    private static let breakReminderEnabledDefaultsKey = "breakReminderEnabled"
    private static let breakReminderMinutesDefaultsKey = "breakReminderMinutes"
    private static let clockOutReminderEnabledDefaultsKey = "clockOutReminderEnabled"
    private static let clockOutReminderLeadMinutesDefaultsKey = "clockOutReminderLeadMinutes"
    private static let workingWeekdaysDefaultsKey = "workingWeekdays"
    private static let hotkeyEnabledDefaultsKey = "hotkeyEnabled"
    private static let hotkeyKeyCodeDefaultsKey = "hotkeyKeyCode"
    private static let hotkeyModifiersDefaultsKey = "hotkeyModifiers"
    private static let weekdays = Array(1...7)
    private static let defaultWorkingWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    private static let defaultHotkeyKeyCode: UInt32 = 17
    private static let defaultHotkeyModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    private static let hotkeyModifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    private static let staleTimerSeconds: TimeInterval = 120

    var hotkeyLabel: String {
        HotkeyFormatting.label(keyCode: hotkeyKeyCode, modifiers: hotkeyModifierFlags)
    }

    var isDefaultHotkey: Bool {
        hotkeyKeyCode == Self.defaultHotkeyKeyCode && hotkeyModifierFlags == Self.defaultHotkeyModifiers
    }

    override init() {
        webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        dailyReportWebView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())

        displayComponents = Self.savedDisplayComponents()
        displayLabelsEnabled = Self.savedBool(Self.displayLabelsEnabledDefaultsKey, defaultValue: false)
        fsLogoEnabled = Self.savedBool(Self.fsLogoEnabledDefaultsKey, defaultValue: true)
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        workStartMinutes = Self.savedMinutes(Self.workStartMinutesDefaultsKey, defaultValue: 15 * 60)
        workEndMinutes = Self.savedMinutes(Self.workEndMinutesDefaultsKey, defaultValue: 0)
        breakDurationMinutes = Self.savedDurationMinutes(Self.breakDurationMinutesDefaultsKey, defaultValue: 60)
        workReminderEnabled = Self.savedBool(Self.workReminderEnabledDefaultsKey, defaultValue: true)
        workReminderLeadMinutes = Self.savedMinutes(Self.workReminderLeadMinutesDefaultsKey, defaultValue: 15)
        breakReminderEnabled = Self.savedBool(Self.breakReminderEnabledDefaultsKey, defaultValue: false)
        breakReminderMinutes = Self.savedMinutes(Self.breakReminderMinutesDefaultsKey, defaultValue: 19 * 60)
        clockOutReminderEnabled = Self.savedBool(Self.clockOutReminderEnabledDefaultsKey, defaultValue: true)
        clockOutReminderLeadMinutes = Self.savedMinutes(Self.clockOutReminderLeadMinutesDefaultsKey, defaultValue: 15)
        workingWeekdays = Self.savedWorkingWeekdays()
        hotkeyEnabled = Self.savedBool(Self.hotkeyEnabledDefaultsKey, defaultValue: true)
        hotkeyKeyCode = UInt32(UserDefaults.standard.object(forKey: Self.hotkeyKeyCodeDefaultsKey) as? Int ?? Int(Self.defaultHotkeyKeyCode))
        hotkeyModifierFlags = Self.savedHotkeyModifiers()

        super.init()

        webView.navigationDelegate = self
        TimeclockReminderScheduler.registerNotificationCategories()
        TimeclockReminderScheduler.removeLegacyReportReminders()
        refreshNotificationAuthorizationStatus()
        scheduleReminders()
    }

    func makeWebView(url: URL? = nil) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        webView.load(URLRequest(url: url ?? self.url))
        return webView
    }

    func load() {
        guard webView.url == nil else { return }

        state = .loading
        webView.load(URLRequest(url: url))
    }

    func reload() {
        state = .loading

        if webView.url == nil {
            load()
        } else {
            webView.reload()
        }
    }

    func loadDailyReport() {
        guard dailyReportWebView.url == nil else { return }

        dailyReportWebView.load(URLRequest(url: dailyReportURL))
    }

    func reloadDailyReport() {
        if dailyReportWebView.url == nil {
            loadDailyReport()
        } else {
            dailyReportWebView.reload()
        }
    }

    func requestPopoverPage(_ page: PopoverPage?) {
        requestedPopoverPage = page
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // ponytail: expose only the final system state; add user-facing errors if registration fails in real use.
        }

        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setWorkStartMinutes(_ minutes: Int) {
        workStartMinutes = TimeclockTimeMath.normalizedMinutes(minutes)
        UserDefaults.standard.set(workStartMinutes, forKey: Self.workStartMinutesDefaultsKey)
        updateTodayProgressTitle()
        updateMenuBarTitle()
        scheduleReminders()
    }

    func setWorkEndMinutes(_ minutes: Int) {
        workEndMinutes = TimeclockTimeMath.normalizedMinutes(minutes)
        UserDefaults.standard.set(workEndMinutes, forKey: Self.workEndMinutesDefaultsKey)
        updateTodayProgressTitle()
        updateMenuBarTitle()
        scheduleReminders()
    }

    func setBreakDurationMinutes(_ minutes: Int) {
        breakDurationMinutes = TimeclockTimeMath.normalizedDurationMinutes(minutes)
        UserDefaults.standard.set(breakDurationMinutes, forKey: Self.breakDurationMinutesDefaultsKey)
        updateTodayProgressTitle()
        updateMenuBarTitle()
    }

    func setWorkReminderEnabled(_ isEnabled: Bool) {
        workReminderEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.workReminderEnabledDefaultsKey)
        scheduleReminders()
    }

    func setWorkReminderLeadMinutes(_ minutes: Int) {
        workReminderLeadMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: Self.workReminderLeadMinutesDefaultsKey)
        scheduleReminders()
    }

    func setBreakReminderEnabled(_ isEnabled: Bool) {
        breakReminderEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.breakReminderEnabledDefaultsKey)
        scheduleReminders()
    }

    func setBreakReminderMinutes(_ minutes: Int) {
        breakReminderMinutes = TimeclockTimeMath.normalizedMinutes(minutes)
        UserDefaults.standard.set(breakReminderMinutes, forKey: Self.breakReminderMinutesDefaultsKey)
        scheduleReminders()
    }

    func setClockOutReminderEnabled(_ isEnabled: Bool) {
        clockOutReminderEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.clockOutReminderEnabledDefaultsKey)
        scheduleReminders()
    }

    func setClockOutReminderLeadMinutes(_ minutes: Int) {
        clockOutReminderLeadMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: Self.clockOutReminderLeadMinutesDefaultsKey)
        scheduleReminders()
    }

    func snoozeNotification(title: String, body: String, categoryIdentifier: String, minutes: Int) {
        TimeclockReminderScheduler.sendNotification(
            identifier: "snooze-\(UUID().uuidString)",
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            delaySeconds: TimeInterval(minutes * 60)
        )
    }

    func sendTestShiftReminder() {
        TimeclockReminderScheduler.sendNotification(
            identifier: "test-shift-reminder-\(UUID().uuidString)",
            title: "Shift starts soon",
            body: "Your work shift starts in \(workReminderLeadMinutes) minutes.",
            categoryIdentifier: TimeclockReminderScheduler.reminderCategoryIdentifier
        )
    }

    func sendTestBreakReminder() {
        TimeclockReminderScheduler.sendNotification(
            identifier: "test-break-reminder-\(UUID().uuidString)",
            title: "Break reminder",
            body: "Time for your preferred break.",
            categoryIdentifier: TimeclockReminderScheduler.reminderCategoryIdentifier
        )
    }

    func sendTestClockOutReminder() {
        TimeclockReminderScheduler.sendNotification(
            identifier: "test-clock-out-reminder-\(UUID().uuidString)",
            title: "Clock out reminder",
            body: "Your shift ends in \(clockOutReminderLeadMinutes) minutes. Submit your report before clocking out.",
            categoryIdentifier: TimeclockReminderScheduler.reportReminderCategoryIdentifier
        )
    }

    func setWorkingWeekday(_ weekday: Int, isEnabled: Bool) {
        var next = workingWeekdays

        if isEnabled {
            next.insert(weekday)
        } else {
            next.remove(weekday)
        }

        guard next != workingWeekdays else { return }

        workingWeekdays = next
        UserDefaults.standard.set(Self.storedWorkingWeekdays(next), forKey: Self.workingWeekdaysDefaultsKey)
        updateTodayProgressTitle()
        updateMenuBarTitle()
        scheduleReminders()
    }

    func setDisplayComponent(_ component: TimeclockDisplayComponent, isEnabled: Bool) {
        var next = displayComponents

        if isEnabled {
            next.insert(component)
        } else {
            next.remove(component)
        }

        if next.isEmpty {
            next.insert(.day)
        }

        guard next != displayComponents else { return }

        displayComponents = next
        UserDefaults.standard.set(Self.storedDisplayComponents(next), forKey: Self.displayComponentsDefaultsKey)
        updateMenuBarTitle()
    }

    func setDisplayLabelsEnabled(_ isEnabled: Bool) {
        guard displayLabelsEnabled != isEnabled else { return }

        displayLabelsEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.displayLabelsEnabledDefaultsKey)
        updateMenuBarTitle()
    }

    func setFSLogoEnabled(_ isEnabled: Bool) {
        guard fsLogoEnabled != isEnabled else { return }

        fsLogoEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.fsLogoEnabledDefaultsKey)
    }

    func resetDisplayDefaults() {
        displayComponents = [.day]
        displayLabelsEnabled = false
        fsLogoEnabled = true
        UserDefaults.standard.set(Self.storedDisplayComponents(displayComponents), forKey: Self.displayComponentsDefaultsKey)
        UserDefaults.standard.set(displayLabelsEnabled, forKey: Self.displayLabelsEnabledDefaultsKey)
        UserDefaults.standard.set(fsLogoEnabled, forKey: Self.fsLogoEnabledDefaultsKey)
        updateMenuBarTitle()
    }

    func resetAllDefaults() {
        setLaunchAtLoginEnabled(false)

        displayComponents = [.day]
        displayLabelsEnabled = false
        fsLogoEnabled = true
        workStartMinutes = 15 * 60
        workEndMinutes = 0
        breakDurationMinutes = 60
        workReminderEnabled = true
        workReminderLeadMinutes = 15
        breakReminderEnabled = false
        breakReminderMinutes = 19 * 60
        clockOutReminderEnabled = true
        clockOutReminderLeadMinutes = 15
        workingWeekdays = Self.defaultWorkingWeekdays
        isRecordingHotkey = false
        hotkeyEnabled = true
        hotkeyKeyCode = Self.defaultHotkeyKeyCode
        hotkeyModifierFlags = Self.defaultHotkeyModifiers

        UserDefaults.standard.set(Self.storedDisplayComponents(displayComponents), forKey: Self.displayComponentsDefaultsKey)
        UserDefaults.standard.set(displayLabelsEnabled, forKey: Self.displayLabelsEnabledDefaultsKey)
        UserDefaults.standard.set(fsLogoEnabled, forKey: Self.fsLogoEnabledDefaultsKey)
        UserDefaults.standard.set(workStartMinutes, forKey: Self.workStartMinutesDefaultsKey)
        UserDefaults.standard.set(workEndMinutes, forKey: Self.workEndMinutesDefaultsKey)
        UserDefaults.standard.set(breakDurationMinutes, forKey: Self.breakDurationMinutesDefaultsKey)
        UserDefaults.standard.set(workReminderEnabled, forKey: Self.workReminderEnabledDefaultsKey)
        UserDefaults.standard.set(workReminderLeadMinutes, forKey: Self.workReminderLeadMinutesDefaultsKey)
        UserDefaults.standard.set(breakReminderEnabled, forKey: Self.breakReminderEnabledDefaultsKey)
        UserDefaults.standard.set(breakReminderMinutes, forKey: Self.breakReminderMinutesDefaultsKey)
        UserDefaults.standard.set(clockOutReminderEnabled, forKey: Self.clockOutReminderEnabledDefaultsKey)
        UserDefaults.standard.set(clockOutReminderLeadMinutes, forKey: Self.clockOutReminderLeadMinutesDefaultsKey)
        UserDefaults.standard.set(Self.storedWorkingWeekdays(workingWeekdays), forKey: Self.workingWeekdaysDefaultsKey)
        UserDefaults.standard.set(hotkeyEnabled, forKey: Self.hotkeyEnabledDefaultsKey)
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: Self.hotkeyKeyCodeDefaultsKey)
        UserDefaults.standard.set(Int(hotkeyModifierFlags.rawValue), forKey: Self.hotkeyModifiersDefaultsKey)

        updateTodayProgressTitle()
        updateMenuBarTitle()
        scheduleReminders()
    }

    func setHotkeyEnabled(_ isEnabled: Bool) {
        if !isEnabled {
            isRecordingHotkey = false
        }

        hotkeyEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.hotkeyEnabledDefaultsKey)
    }

    func setHotkeyRecording(_ isRecording: Bool) {
        isRecordingHotkey = isRecording
    }

    func setHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        let allowedModifiers = modifiers.intersection(Self.hotkeyModifierMask)
        guard !allowedModifiers.isEmpty else { return }

        isRecordingHotkey = false
        hotkeyKeyCode = keyCode
        hotkeyModifierFlags = allowedModifiers
        UserDefaults.standard.set(Int(keyCode), forKey: Self.hotkeyKeyCodeDefaultsKey)
        UserDefaults.standard.set(Int(allowedModifiers.rawValue), forKey: Self.hotkeyModifiersDefaultsKey)
    }

    func resetHotkeyDefaults() {
        isRecordingHotkey = false
        hotkeyEnabled = true
        hotkeyKeyCode = Self.defaultHotkeyKeyCode
        hotkeyModifierFlags = Self.defaultHotkeyModifiers
        UserDefaults.standard.set(hotkeyEnabled, forKey: Self.hotkeyEnabledDefaultsKey)
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: Self.hotkeyKeyCodeDefaultsKey)
        UserDefaults.standard.set(Int(hotkeyModifierFlags.rawValue), forKey: Self.hotkeyModifiersDefaultsKey)
    }

    func refreshNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationAuthorizationStatus = settings.authorizationStatus
            }
        }
    }

    func startPolling() {
        stopPolling()

        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.readTimeclockState()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func readTimeclockState() {
        webView.evaluateJavaScript(TimeclockDOMDetector.detectionScript) { [weak self] result, error in
            guard let self else { return }

            if error != nil {
                self.state = .stale
                self.timers = .empty
                self.todayProgressTitle = ""
                self.updateMenuBarTitle()
                return
            }

            let detection = TimeclockDOMDetection(result as? [String: Any])
            self.lastDetection = detection
            let nextTimers = TimeclockDOMDetector.timers(from: detection)
            let nextState = self.parseState(from: detection)
            let previousState = self.state
            self.timers = nextTimers
            self.updateTodayProgressTitle()
            self.handleLoginNotification(for: nextState)
            let resolvedState = self.stateWithStaleCheck(nextState, timers: nextTimers)
            if resolvedState == .stale {
                self.todayProgressTitle = ""
            }
            self.state = resolvedState
            self.updateMenuBarTitle()
            if previousState != resolvedState {
                self.scheduleReminders()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        readTimeclockState()
    }

    private func parseState(from detection: TimeclockDOMDetection?) -> TimeclockState {
        guard let detection else {
            return .unknown(nil)
        }

        let timer = firstNonEmpty(detection.currentTimer, detection.dayTimer, detection.weekTimer, detection.timer)

        switch detection.state {
        case "loginRequired":
            return .loginRequired
        case "clockedOut":
            return .clockedOut
        case "active":
            return .active(timer)
        case "onBreak":
            return .onBreak(timer)
        default:
            return .unknown(timer.isEmpty ? nil : timer)
        }
    }

    private func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.isEmpty } ?? ""
    }

    private func updateMenuBarTitle() {
        menuBarTitle = TimeclockMenuTitleFormatter.title(
            state: state,
            timers: timers,
            components: displayComponents,
            remainingTitle: todayProgressTitle,
            showsLabels: displayLabelsEnabled
        )
    }

    private func updateTodayProgressTitle() {
        let parsedDayMinutes = TimeclockTimeMath.timerMinutes(from: timers.day.isEmpty ? timers.fallback : timers.day)

        guard workingWeekdays.contains(Calendar.current.component(.weekday, from: Date())) else {
            let dayMinutes = parsedDayMinutes ?? 0
            todayProgressTitle = dayMinutes > 0 ? "Today +\(TimeclockTimeMath.durationLabel(minutes: dayMinutes))" : "Off today"
            return
        }

        guard let dayMinutes = parsedDayMinutes else {
            todayProgressTitle = ""
            return
        }

        let targetMinutes = max(0, TimeclockTimeMath.shiftDurationMinutes(start: workStartMinutes, end: workEndMinutes) - breakDurationMinutes)
        let remainingMinutes = targetMinutes - dayMinutes

        if remainingMinutes > 0 {
            todayProgressTitle = "Today \(TimeclockTimeMath.durationLabel(minutes: remainingMinutes)) left"
        } else if remainingMinutes < 0 {
            todayProgressTitle = "Today +\(TimeclockTimeMath.durationLabel(minutes: abs(remainingMinutes)))"
        } else {
            todayProgressTitle = "Today target met"
        }
    }

    private func stateWithStaleCheck(_ state: TimeclockState, timers: TimeclockTimers) -> TimeclockState {
        let timerValue = Self.runningTimerValue(state: state, timers: timers)
        let now = Date()

        if timerValue.isEmpty {
            lastRunningTimerValue = ""
            lastRunningTimerChangedAt = now
            return state
        }

        if timerValue != lastRunningTimerValue {
            lastRunningTimerValue = timerValue
            lastRunningTimerChangedAt = now
            return state
        }

        return now.timeIntervalSince(lastRunningTimerChangedAt) > Self.staleTimerSeconds ? .stale : state
    }

    private func handleLoginNotification(for state: TimeclockState) {
        guard state == .loginRequired else {
            hasSentLoginNotification = false
            return
        }

        guard !hasSentLoginNotification else { return }

        hasSentLoginNotification = true
        TimeclockReminderScheduler.sendNotification(
            identifier: TimeclockReminderScheduler.loginRequiredNotificationIdentifier,
            title: "Time Clock Bar login expired",
            body: "Open Time Clock Bar to sign in again.",
            categoryIdentifier: TimeclockReminderScheduler.loginRequiredCategoryIdentifier
        )
    }

    private func scheduleReminders() {
        TimeclockReminderScheduler.schedule(
            state: state,
            workingWeekdays: workingWeekdays,
            workReminderEnabled: workReminderEnabled,
            workStartMinutes: workStartMinutes,
            workReminderLeadMinutes: workReminderLeadMinutes,
            breakReminderEnabled: breakReminderEnabled,
            breakReminderMinutes: breakReminderMinutes,
            clockOutReminderEnabled: clockOutReminderEnabled,
            workEndMinutes: workEndMinutes,
            clockOutReminderLeadMinutes: clockOutReminderLeadMinutes
        )
    }

    private static func savedBool(_ key: String, defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func savedMinutes(_ key: String, defaultValue: Int) -> Int {
        TimeclockTimeMath.normalizedMinutes(UserDefaults.standard.object(forKey: key) as? Int ?? defaultValue)
    }

    private static func savedDurationMinutes(_ key: String, defaultValue: Int) -> Int {
        TimeclockTimeMath.normalizedDurationMinutes(UserDefaults.standard.object(forKey: key) as? Int ?? defaultValue)
    }

    private static func savedWorkingWeekdays() -> Set<Int> {
        guard let values = UserDefaults.standard.array(forKey: workingWeekdaysDefaultsKey) as? [Int] else {
            return defaultWorkingWeekdays
        }

        return Set(values.filter { weekdays.contains($0) })
    }

    private static func storedWorkingWeekdays(_ weekdays: Set<Int>) -> [Int] {
        Self.weekdays.filter { weekdays.contains($0) }
    }

    private static func savedHotkeyModifiers() -> NSEvent.ModifierFlags {
        let rawValue = UserDefaults.standard.object(forKey: hotkeyModifiersDefaultsKey) as? Int ?? Int(defaultHotkeyModifiers.rawValue)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(rawValue)).intersection(hotkeyModifierMask)
        return modifiers.isEmpty ? defaultHotkeyModifiers : modifiers
    }

    private static func savedDisplayComponents() -> Set<TimeclockDisplayComponent> {
        if let values = UserDefaults.standard.array(forKey: displayComponentsDefaultsKey) as? [String] {
            let components = Set(values.compactMap(TimeclockDisplayComponent.init(rawValue:)))
            return components.isEmpty ? [.day] : components
        }

        if let legacy = UserDefaults.standard.string(forKey: legacyDisplayMetricDefaultsKey),
           let component = TimeclockDisplayComponent(rawValue: legacy) {
            return [component]
        }

        return [.day]
    }

    private static func storedDisplayComponents(_ components: Set<TimeclockDisplayComponent>) -> [String] {
        TimeclockDisplayComponent.allCases
            .filter { components.contains($0) }
            .map(\.rawValue)
    }

    private static func runningTimerValue(state: TimeclockState, timers: TimeclockTimers) -> String {
        switch state {
        case .active, .onBreak:
            return timers.current.isEmpty ? timers.fallback : timers.current
        case .loading, .loginRequired, .stale, .clockedOut, .unknown:
            return ""
        }
    }

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }
}
