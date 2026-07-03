import Combine
import AppKit
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

    private var pollTimer: Timer?
    private var lastDetection: TimeclockDetection?
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
    private static let workReminderIdentifier = "work-start-reminder"
    private static let breakReminderIdentifier = "break-reminder"
    private static let clockOutReminderIdentifier = "clock-out-reminder"
    private static let loginRequiredNotificationIdentifier = "login-required"
    static let openTimeclockNotificationActionIdentifier = "open-timeclock"
    static let openDailyReportNotificationActionIdentifier = "open-daily-report"
    static let snooze5NotificationActionIdentifier = "snooze-5"
    static let snooze10NotificationActionIdentifier = "snooze-10"
    static let snooze15NotificationActionIdentifier = "snooze-15"
    static let loginRequiredCategoryIdentifier = "login-required-actions"
    static let reminderCategoryIdentifier = "timeclock-reminder-actions"
    static let reportReminderCategoryIdentifier = "timeclock-report-reminder-actions"
    private static let weekdays = Array(1...7)
    private static let defaultWorkingWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    private static let defaultHotkeyKeyCode: UInt32 = 17
    private static let defaultHotkeyModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    private static let hotkeyModifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    private static let staleTimerSeconds: TimeInterval = 120

    var hotkeyLabel: String {
        Self.hotkeyLabel(keyCode: hotkeyKeyCode, modifiers: hotkeyModifierFlags)
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
        Self.registerNotificationCategories()
        Self.removeLegacyReportReminders()
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
        workStartMinutes = Self.normalizedMinutes(minutes)
        UserDefaults.standard.set(workStartMinutes, forKey: Self.workStartMinutesDefaultsKey)
        updateTodayProgressTitle()
        updateMenuBarTitle()
        scheduleReminders()
    }

    func setWorkEndMinutes(_ minutes: Int) {
        workEndMinutes = Self.normalizedMinutes(minutes)
        UserDefaults.standard.set(workEndMinutes, forKey: Self.workEndMinutesDefaultsKey)
        updateTodayProgressTitle()
        updateMenuBarTitle()
        scheduleReminders()
    }

    func setBreakDurationMinutes(_ minutes: Int) {
        breakDurationMinutes = Self.normalizedDurationMinutes(minutes)
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
        breakReminderMinutes = Self.normalizedMinutes(minutes)
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
        Self.sendNotification(
            identifier: "snooze-\(UUID().uuidString)",
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            delaySeconds: TimeInterval(minutes * 60)
        )
    }

    func sendTestShiftReminder() {
        Self.sendNotification(
            identifier: "test-shift-reminder-\(UUID().uuidString)",
            title: "Shift starts soon",
            body: "Your work shift starts in \(workReminderLeadMinutes) minutes.",
            categoryIdentifier: Self.reminderCategoryIdentifier
        )
    }

    func sendTestBreakReminder() {
        Self.sendNotification(
            identifier: "test-break-reminder-\(UUID().uuidString)",
            title: "Break reminder",
            body: "Time for your preferred break.",
            categoryIdentifier: Self.reminderCategoryIdentifier
        )
    }

    func sendTestClockOutReminder() {
        Self.sendNotification(
            identifier: "test-clock-out-reminder-\(UUID().uuidString)",
            title: "Clock out reminder",
            body: "Your shift ends in \(clockOutReminderLeadMinutes) minutes. Submit your report before clocking out.",
            categoryIdentifier: Self.reportReminderCategoryIdentifier
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
        webView.evaluateJavaScript(Self.stateDetectionScript) { [weak self] result, error in
            guard let self else { return }

            if error != nil {
                self.state = .stale
                self.timers = .empty
                self.todayProgressTitle = ""
                self.updateMenuBarTitle()
                return
            }

            let detection = TimeclockDetection(result as? [String: Any])
            self.lastDetection = detection
            let nextTimers = Self.timers(from: detection)
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

    private func parseState(from detection: TimeclockDetection?) -> TimeclockState {
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
        menuBarTitle = Self.menuBarTitle(
            state: state,
            timers: timers,
            components: displayComponents,
            remainingTitle: todayProgressTitle,
            showsLabels: displayLabelsEnabled
        )
    }

    private func updateTodayProgressTitle() {
        let parsedDayMinutes = Self.timerMinutes(from: timers.day.isEmpty ? timers.fallback : timers.day)

        guard workingWeekdays.contains(Calendar.current.component(.weekday, from: Date())) else {
            let dayMinutes = parsedDayMinutes ?? 0
            todayProgressTitle = dayMinutes > 0 ? "Today +\(Self.durationLabel(minutes: dayMinutes))" : "Off today"
            return
        }

        guard let dayMinutes = parsedDayMinutes else {
            todayProgressTitle = ""
            return
        }

        let targetMinutes = max(0, Self.shiftDurationMinutes(start: workStartMinutes, end: workEndMinutes) - breakDurationMinutes)
        let remainingMinutes = targetMinutes - dayMinutes

        if remainingMinutes > 0 {
            todayProgressTitle = "Today \(Self.durationLabel(minutes: remainingMinutes)) left"
        } else if remainingMinutes < 0 {
            todayProgressTitle = "Today +\(Self.durationLabel(minutes: abs(remainingMinutes)))"
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
        Self.sendNotification(
            identifier: Self.loginRequiredNotificationIdentifier,
            title: "TimeClock Bar login expired",
            body: "Open TimeClock Bar to sign in again.",
            categoryIdentifier: Self.loginRequiredCategoryIdentifier
        )
    }

    private func scheduleReminders() {
        let currentState = state
        let identifiers =
            [
            Self.workReminderIdentifier,
            Self.breakReminderIdentifier,
            Self.clockOutReminderIdentifier
            ] +
            Self.notificationIdentifiers(prefix: Self.workReminderIdentifier) +
            Self.notificationIdentifiers(prefix: Self.breakReminderIdentifier) +
            Self.notificationIdentifiers(prefix: Self.clockOutReminderIdentifier)

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)

        guard !workingWeekdays.isEmpty,
              workReminderEnabled || breakReminderEnabled || clockOutReminderEnabled else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] isAllowed, _ in
            guard isAllowed, let self else { return }

            for weekday in self.workingWeekdays {
                if self.workReminderEnabled && !Self.isWorking(state: currentState) {
                    let reminderMinutes = self.workStartMinutes - self.workReminderLeadMinutes

                    Self.scheduleWeeklyNotification(
                        identifier: Self.notificationIdentifier(prefix: Self.workReminderIdentifier, weekday: weekday),
                        title: "Shift starts soon",
                        body: "Your work shift starts in \(self.workReminderLeadMinutes) minutes.",
                        minutes: reminderMinutes,
                        weekday: Self.shiftedWeekday(weekday, byDays: Self.dayOffset(forMinutes: reminderMinutes)),
                        categoryIdentifier: Self.reminderCategoryIdentifier
                    )
                }

                if self.breakReminderEnabled && !Self.isOnBreak(state: currentState) {
                    Self.scheduleWeeklyNotification(
                        identifier: Self.notificationIdentifier(prefix: Self.breakReminderIdentifier, weekday: weekday),
                        title: "Break reminder",
                        body: "Time for your preferred break.",
                        minutes: self.breakReminderMinutes,
                        weekday: weekday,
                        categoryIdentifier: Self.reminderCategoryIdentifier
                    )
                }

                if self.clockOutReminderEnabled && !Self.isClockedOut(state: currentState) {
                    let reminderMinutes = self.workEndMinutes - self.clockOutReminderLeadMinutes
                    let endWeekday = Self.shiftedWeekday(
                        weekday,
                        byDays: (self.workEndMinutes <= self.workStartMinutes ? 1 : 0) + Self.dayOffset(forMinutes: reminderMinutes)
                    )

                    Self.scheduleWeeklyNotification(
                        identifier: Self.notificationIdentifier(prefix: Self.clockOutReminderIdentifier, weekday: weekday),
                        title: "Clock out reminder",
                        body: "Your shift ends in \(self.clockOutReminderLeadMinutes) minutes. Submit your report before clocking out.",
                        minutes: reminderMinutes,
                        weekday: endWeekday,
                        categoryIdentifier: Self.reportReminderCategoryIdentifier
                    )
                }
            }
        }
    }

    private static func scheduleWeeklyNotification(identifier: String, title: String, body: String, minutes: Int, weekday: Int, categoryIdentifier: String) {
        let normalized = normalizedMinutes(minutes)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: normalized / 60, minute: normalized % 60, weekday: weekday),
            repeats: true
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func notificationIdentifiers(prefix: String) -> [String] {
        weekdays.map { notificationIdentifier(prefix: prefix, weekday: $0) }
    }

    private static func notificationIdentifier(prefix: String, weekday: Int) -> String {
        "\(prefix)-\(weekday)"
    }

    private static func removeLegacyReportReminders() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("daily-report-") }

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private static func savedBool(_ key: String, defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func savedMinutes(_ key: String, defaultValue: Int) -> Int {
        normalizedMinutes(UserDefaults.standard.object(forKey: key) as? Int ?? defaultValue)
    }

    private static func savedDurationMinutes(_ key: String, defaultValue: Int) -> Int {
        normalizedDurationMinutes(UserDefaults.standard.object(forKey: key) as? Int ?? defaultValue)
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

    static func hotkeyLabel(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        "\(modifierLabel(modifiers))\(keyLabel(keyCode))"
    }

    static func hotkeyModifierLabel(_ modifiers: NSEvent.ModifierFlags) -> String {
        modifierLabel(modifiers)
    }

    private static func modifierLabel(_ modifiers: NSEvent.ModifierFlags) -> String {
        [
            modifiers.contains(.control) ? "⌃" : "",
            modifiers.contains(.option) ? "⌥" : "",
            modifiers.contains(.shift) ? "⇧" : "",
            modifiers.contains(.command) ? "⌘" : ""
        ].joined()
    }

    private static func keyLabel(_ keyCode: UInt32) -> String {
        let labels: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            49: "Space", 51: "Delete", 53: "Esc", 76: "Enter", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]

        return labels[keyCode] ?? "Key \(keyCode)"
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

    private static func timers(from detection: TimeclockDetection?) -> TimeclockTimers {
        guard let detection else { return .empty }

        return TimeclockTimers(
            current: detection.currentTimer,
            day: detection.dayTimer,
            week: detection.weekTimer,
            fallback: detection.timer
        )
    }

    private static func menuBarTitle(
        state: TimeclockState,
        timers: TimeclockTimers,
        components: Set<TimeclockDisplayComponent>,
        remainingTitle: String,
        showsLabels: Bool
    ) -> String {
        if state == .stale {
            return state.menuBarTitle
        }

        let orderedComponents = TimeclockDisplayComponent.allCases.filter { components.contains($0) }
        let timerComponentCount = orderedComponents.filter { $0 != .status && $0 != .remaining }.count
        let parts = orderedComponents.compactMap { component -> String? in
            switch component {
            case .status:
                return statusLabel(for: state)
            case .remaining:
                guard !remainingTitle.isEmpty else { return nil }
                return showsLabels ? "\(component.label) \(remainingTitle)" : remainingTitle
            case .current, .day, .week:
                let value = timerComponentCount == 1 ? timers.value(for: component) : specificTimerValue(for: component, timers: timers)
                guard !value.isEmpty else { return nil }

                return showsLabels ? "\(component.label) \(value)" : value
            }
        }

        guard !parts.isEmpty else { return state.menuBarTitle }

        return parts.joined(separator: " · ")
    }

    private static func specificTimerValue(for component: TimeclockDisplayComponent, timers: TimeclockTimers) -> String {
        switch component {
        case .status:
            return ""
        case .current:
            return timers.current
        case .day:
            return timers.day
        case .week:
            return timers.week
        case .remaining:
            return ""
        }
    }

    private static func statusLabel(for state: TimeclockState) -> String {
        switch state {
        case .loading:
            return "Loading"
        case .loginRequired:
            return "Login"
        case .stale:
            return "Stale"
        case .clockedOut:
            return "Out"
        case .active:
            return "Active"
        case .onBreak:
            return "Break"
        case .unknown:
            return "Unknown"
        }
    }

    private static func normalizedMinutes(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }

    private static func normalizedDurationMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), 24 * 60)
    }

    private static func runningTimerValue(state: TimeclockState, timers: TimeclockTimers) -> String {
        switch state {
        case .active, .onBreak:
            return timers.current.isEmpty ? timers.fallback : timers.current
        case .loading, .loginRequired, .stale, .clockedOut, .unknown:
            return ""
        }
    }

    private static func isWorking(state: TimeclockState) -> Bool {
        switch state {
        case .active, .onBreak:
            return true
        case .loading, .loginRequired, .stale, .clockedOut, .unknown:
            return false
        }
    }

    private static func isOnBreak(state: TimeclockState) -> Bool {
        switch state {
        case .onBreak:
            return true
        case .loading, .loginRequired, .stale, .clockedOut, .active, .unknown:
            return false
        }
    }

    private static func isClockedOut(state: TimeclockState) -> Bool {
        switch state {
        case .clockedOut:
            return true
        case .loading, .loginRequired, .stale, .active, .onBreak, .unknown:
            return false
        }
    }

    private static func timerMinutes(from value: String) -> Int? {
        let parts = value.replacingOccurrences(of: ".", with: ":").split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private static func shiftDurationMinutes(start: Int, end: Int) -> Int {
        let duration = normalizedMinutes(end - start)
        return duration == 0 ? 24 * 60 : duration
    }

    private static func durationLabel(minutes: Int) -> String {
        let hours = minutes / 60
        let minutes = minutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }

    private static func dayOffset(forMinutes minutes: Int) -> Int {
        if minutes < 0 {
            return -1
        }

        if minutes >= 1440 {
            return 1
        }

        return 0
    }

    private static func shiftedWeekday(_ weekday: Int, byDays offset: Int) -> Int {
        ((weekday - 1 + offset + 7) % 7) + 1
    }

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }

    static func registerNotificationCategories() {
        let openTimeclock = UNNotificationAction(
            identifier: openTimeclockNotificationActionIdentifier,
            title: "Open TimeClock Bar",
            options: [.foreground]
        )
        let openReport = UNNotificationAction(
            identifier: openDailyReportNotificationActionIdentifier,
            title: "Open Report",
            options: [.foreground]
        )
        let snooze5 = UNNotificationAction(identifier: snooze5NotificationActionIdentifier, title: "Snooze 5 min", options: [])
        let snooze10 = UNNotificationAction(identifier: snooze10NotificationActionIdentifier, title: "Snooze 10 min", options: [])
        let snooze15 = UNNotificationAction(identifier: snooze15NotificationActionIdentifier, title: "Snooze 15 min", options: [])

        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: loginRequiredCategoryIdentifier,
                actions: [openTimeclock],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: reminderCategoryIdentifier,
                actions: [openTimeclock, snooze5, snooze10, snooze15],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: reportReminderCategoryIdentifier,
                actions: [openReport, openTimeclock, snooze5, snooze10, snooze15],
                intentIdentifiers: []
            )
        ])
    }

    private static func sendNotification(identifier: String, title: String, body: String, categoryIdentifier: String, delaySeconds: TimeInterval? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { isAllowed, _ in
            guard isAllowed else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier

            let trigger = delaySeconds.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private struct TimeclockDetection {
        let state: String
        let timer: String
        let currentTimer: String
        let dayTimer: String
        let weekTimer: String

        init?(_ dictionary: [String: Any]?) {
            guard let dictionary else { return nil }

            state = dictionary["state"] as? String ?? "unknown"
            timer = dictionary["timer"] as? String ?? ""
            currentTimer = dictionary["currentTimer"] as? String ?? ""
            dayTimer = dictionary["dayTimer"] as? String ?? ""
            weekTimer = dictionary["weekTimer"] as? String ?? ""
        }
    }

    // DOM detection is intentionally text-based so selectors can be tuned after inspecting the live page.
    private static let stateDetectionScript = """
    (() => {
      const normalize = (value) =>
        (value || "").replace(/\\s+/g, " ").trim();

      const bodyText = normalize(document.body?.innerText || "");
      const lower = bodyText.toLowerCase();

      const timePattern = /\\b\\d{1,2}:\\d{2}(?:(?::|\\.)\\d{1,2})?\\b/;
      const cleanTimer = (value) => {
        const match = normalize(value).match(timePattern);
        return match ? match[0] : "";
      };
      const metricTime = (label) => {
        const match = bodyText.match(new RegExp("\\\\b" + label + "\\\\s+(\\\\d{1,2}:\\\\d{2}(?:(?::|\\\\.)\\\\d{1,2})?)", "i"));
        return match ? match[1] : "";
      };

      const timerSelectors = [
        '[data-testid="timer"]',
        '[data-testid*="timer"]',
        '[data-testid*="elapsed"]',
        '[data-testid*="duration"]',
        '[class*="timer"]',
        '[class*="duration"]',
        '[class*="elapsed"]',
        '[id*="timer"]'
      ];

      const findSidebarTimer = () => {
        const elements = Array.from(document.querySelectorAll("body *"));

        for (const element of elements) {
          const text = normalize(element.innerText || element.textContent || "");
          const timer = cleanTimer(text);

          if (!timer || text !== timer) {
            continue;
          }

          let parent = element.parentElement;

          for (let depth = 0; parent && depth < 5; depth += 1) {
            const parentText = normalize(parent.innerText || parent.textContent || "").toLowerCase();

            if (parentText.includes("time clock")) {
              return timer;
            }

            parent = parent.parentElement;
          }
        }

        return "";
      };

      const currentTimer = metricTime("Current");
      const dayTimer = metricTime("Day");
      const weekTimer = metricTime("Week");
      let timer = currentTimer || dayTimer || weekTimer;

      for (const selector of timerSelectors) {
        if (timer) {
          break;
        }

        const el = document.querySelector(selector);
        const text = cleanTimer(el?.innerText || el?.textContent || "");
        if (text) {
          timer = text;
          break;
        }
      }

      if (!timer) {
        timer = findSidebarTimer();
      }

      if (!timer) {
        const match = bodyText.match(timePattern);
        timer = match ? match[0] : "";
      }

      const hasLogin =
        lower.includes("login") ||
        lower.includes("log in") ||
        lower.includes("sign in");

      const hasClockIn = lower.includes("clock in");
      const hasClockOut = lower.includes("clock out");

      const hasStartBreak =
        lower.includes("start break") ||
        lower.includes("take break");

      const hasEndBreak =
        lower.includes("end break") ||
        lower.includes("resume") ||
        lower.includes("back from break");

      const hasOnBreak =
        lower.includes("on break") ||
        lower.includes("currently on break");

      const hasSidebarTimer =
        Boolean(timer) &&
        lower.includes("time clock") &&
        !hasClockIn;

      let state = "unknown";

      if (hasLogin) {
        state = "loginRequired";
      } else if (hasEndBreak || hasOnBreak) {
        state = "onBreak";
      } else if (hasClockOut || hasStartBreak) {
        state = "active";
      } else if (hasSidebarTimer) {
        state = "active";
      } else if (hasClockIn) {
        state = "clockedOut";
      }

      return {
        state,
        timer,
        currentTimer,
        dayTimer,
        weekTimer,
        bodyPreview: bodyText.slice(0, 300)
      };
    })();
    """
}
