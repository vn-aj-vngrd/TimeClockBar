import AppKit
import AVFoundation
import Combine
import Foundation
import OSLog
import ServiceManagement
import UserNotifications
import WebKit

final class TimeclockController: NSObject, ObservableObject, WKNavigationDelegate, AVAudioPlayerDelegate {
    let url = URL(string: "https://timeclock.fullscale.rocks/overview")!
    let dailyReportURL = URL(string: "https://fullscale.rocks/daily-report")!
    private static let isTestProcess = ProcessInfo.processInfo.environment["TIMECLOCKBAR_PREVIEW"] == "1" || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    let isPreview = ProcessInfo.processInfo.arguments.contains("--preview-today") || isTestProcess

    var canSendTestNotifications: Bool {
        guard !Self.isTestProcess else { return false }
        #if DEBUG
        return true // Explicit test buttons are safe; automatic reminders stay paused in preview.
        #else
        return !isPreview
        #endif
    }
    let workday = TimeclockReminderScheduler.workday
    @Published private(set) var workTimeZone = UserDefaults.standard.string(forKey: "workTimeZone") ?? TimeZone.current.identifier
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var longOverdueSounds = UserDefaults.standard.bool(forKey: "longOverdueSounds")
    private var lastReminderReconciledAt = Date.distantPast
    let webView: WKWebView
    let dailyReportWebView: WKWebView

    @Published private(set) var state: TimeclockState = .loading
    @Published private(set) var isRefreshing = false
    /// Presentation only. Reminder decisions always use `state`, never cached display evidence.
    var displayState: TimeclockState {
        observation.displayState(current: state, refreshing: isRefreshing, at: Date())
    }
    let menuBarTitles = PassthroughSubject<String, Never>()
    private(set) var menuBarTitle: String = TimeclockState.loading.menuBarTitle {
        didSet { menuBarTitles.send(menuBarTitle) }
    }
    @Published private(set) var todayProgressTitle: String = ""
    @Published private(set) var displayComponents: Set<TimeclockDisplayComponent>
    @Published private(set) var displayLabelsEnabled: Bool
    @Published private(set) var fsLogoEnabled: Bool
    @Published private(set) var appTheme: TimeclockAppTheme
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var workStartMinutes: Int
    @Published private(set) var workEndMinutes: Int
    @Published private(set) var breakDurationMinutes: Int
    @Published private(set) var workReminderEnabled: Bool
    @Published private(set) var workReminderLeadMinutes: Int
    @Published private(set) var breakReminderEnabled: Bool
    @Published private(set) var breakReminderMinutes: Int
    @Published private(set) var breakOverReminderEnabled: Bool
    @Published private(set) var clockOutReminderEnabled: Bool
    @Published private(set) var clockOutReminderLeadMinutes: Int
    @Published private(set) var overtimeReminderEnabled: Bool
    @Published private(set) var reminderSounds: [TimeclockReminderKind: TimeclockReminderSound]
    @Published private(set) var previewingReminderKind: TimeclockReminderKind?
    @Published private(set) var workingWeekdays: Set<Int>
    @Published private(set) var hotkeyEnabled: Bool
    @Published private(set) var hotkeyKeyCode: UInt32
    @Published private(set) var hotkeyModifierFlags: NSEvent.ModifierFlags
    @Published private(set) var isRecordingHotkey = false
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationSoundSetting: UNNotificationSetting = .notSupported
    @Published private(set) var isPolling = false
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var statusIndicator: TimeclockStatusIndicator = .none
    @Published var isSettingsPresented = false
    @Published private(set) var requestedPopoverPage: PopoverPage?

    private var pollTimer: Timer?
    private var monitoringActivity: NSObjectProtocol?
    private var observation = TimeclockObservation()
    private var lastReadAttempt = Date.distantPast
    private var lastPageLoad = Date.distantPast
    private var navigationStartedAt: Date?
    private var pageRecovery = TimeclockPageRecovery()
    private let monitoringLogger = Logger(subsystem: "com.vanajvanguardia.TimeClockBar", category: "ClockMonitoring")
    private var bridge: TimeclockScriptBridge?
    @Published private(set) var connectionStatus = "Checking Time Clock…"
    private var overtimeRequestInFlight = false
    private var nextOvertimeAttempt = Date.distantPast
    private var lastDetection: TimeclockDOMDetection?
    private var timers = TimeclockTimers.empty
    private var hasSentLoginNotification = false
    private var nextLoginAttempt = Date.distantPast
    private var overtimeMinutes = 0
    private var reminderSoundPreviewPlayer: AVAudioPlayer?

    private static let displayComponentsDefaultsKey = "timeclockDisplayComponents"
    private static let displayLabelsEnabledDefaultsKey = "displayLabelsEnabled"
    private static let fsLogoEnabledDefaultsKey = "fsLogoEnabled"
    private static let appThemeDefaultsKey = "appTheme"
    private static let legacyDisplayMetricDefaultsKey = "timeclockDisplayMetric"
    private static let workStartMinutesDefaultsKey = "workStartMinutes"
    private static let workEndMinutesDefaultsKey = "workEndMinutes"
    private static let breakDurationMinutesDefaultsKey = "breakDurationMinutes"
    private static let workReminderEnabledDefaultsKey = "workReminderEnabled"
    private static let workReminderLeadMinutesDefaultsKey = "workReminderLeadMinutes"
    private static let breakReminderEnabledDefaultsKey = "breakReminderEnabled"
    private static let breakReminderMinutesDefaultsKey = "breakReminderMinutes"
    private static let breakOverReminderEnabledDefaultsKey = "breakOverReminderEnabled"
    private static let clockOutReminderEnabledDefaultsKey = "clockOutReminderEnabled"
    private static let clockOutReminderLeadMinutesDefaultsKey = "clockOutReminderLeadMinutes"
    private static let overtimeReminderEnabledDefaultsKey = "overtimeReminderEnabled"
    private static let reminderSoundDefaultsKeyPrefix = "reminderSound."
    private static let workingWeekdaysDefaultsKey = "workingWeekdays"
    private static let hotkeyEnabledDefaultsKey = "hotkeyEnabled"
    private static let hotkeyKeyCodeDefaultsKey = "hotkeyKeyCode"
    private static let hotkeyModifiersDefaultsKey = "hotkeyModifiers"
    private static let weekdays = Array(1...7)
    private static let defaultDisplayComponents: Set<TimeclockDisplayComponent> = [.status, .day]
    private static let defaultWorkingWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    private static let defaultHotkeyKeyCode: UInt32 = 17
    private static let defaultHotkeyModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    private static let hotkeyModifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    private static let pollingInterval: TimeInterval = 1
    private static let pageReadInterval: TimeInterval = 10

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
        appTheme = TimeclockAppTheme.saved(rawValue: UserDefaults.standard.string(forKey: Self.appThemeDefaultsKey))
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        workStartMinutes = Self.savedMinutes(Self.workStartMinutesDefaultsKey, defaultValue: 15 * 60)
        workEndMinutes = Self.savedMinutes(Self.workEndMinutesDefaultsKey, defaultValue: 0)
        breakDurationMinutes = Self.savedDurationMinutes(Self.breakDurationMinutesDefaultsKey, defaultValue: 60)
        workReminderEnabled = Self.savedBool(Self.workReminderEnabledDefaultsKey, defaultValue: true)
        workReminderLeadMinutes = Self.savedMinutes(Self.workReminderLeadMinutesDefaultsKey, defaultValue: 15)
        breakReminderEnabled = Self.savedBool(Self.breakReminderEnabledDefaultsKey, defaultValue: true)
        breakReminderMinutes = Self.savedMinutes(Self.breakReminderMinutesDefaultsKey, defaultValue: 20 * 60)
        breakOverReminderEnabled = Self.savedBool(Self.breakOverReminderEnabledDefaultsKey, defaultValue: true)
        clockOutReminderEnabled = Self.savedBool(Self.clockOutReminderEnabledDefaultsKey, defaultValue: true)
        clockOutReminderLeadMinutes = Self.savedMinutes(Self.clockOutReminderLeadMinutesDefaultsKey, defaultValue: 15)
        overtimeReminderEnabled = Self.savedBool(Self.overtimeReminderEnabledDefaultsKey, defaultValue: false)
        reminderSounds = Self.savedReminderSounds()
        previewingReminderKind = nil
        workingWeekdays = Self.savedWorkingWeekdays()
        hotkeyEnabled = Self.savedBool(Self.hotkeyEnabledDefaultsKey, defaultValue: true)
        hotkeyKeyCode = UInt32(UserDefaults.standard.object(forKey: Self.hotkeyKeyCodeDefaultsKey) as? Int ?? Int(Self.defaultHotkeyKeyCode))
        hotkeyModifierFlags = Self.savedHotkeyModifiers()

        super.init()
        if !isPreview { UserDefaults.standard.set(workTimeZone, forKey: "workTimeZone") }

        webView.navigationDelegate = self
        let bridge = TimeclockScriptBridge(controller: self)
        self.bridge = bridge
        webView.configuration.userContentController.add(bridge, name: "timeclockChanged")
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: TimeclockDOMDetector.observationScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    func makeWebView(url: URL? = nil) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        webView.load(URLRequest(url: url ?? self.url))
        return webView
    }

    func load() {
        guard !isPreview else { return }
        guard webView.url == nil else { return }

        state = .loading
        webView.load(URLRequest(url: url))
    }

    func reload() {
        guard !isPreview else { return }
        beginPageRefresh()
        pageRecovery.navigationStarted()

        // Always a GET to the overview; never replay the page's last attendance POST.
        observation.resetMotion()
        webView.load(URLRequest(url: url))
    }

    func loadDailyReport() {
        guard !isPreview else { return }
        guard dailyReportWebView.url == nil else { return }

        dailyReportWebView.load(URLRequest(url: dailyReportURL))
    }

    func reloadDailyReport() {
        guard !isPreview else { return }
        if dailyReportWebView.url == nil {
            loadDailyReport()
        } else {
            dailyReportWebView.reload()
        }
    }

    func requestPopoverPage(_ page: PopoverPage?) {
        requestedPopoverPage = page
    }

    func startNotifications() {
        guard !isPreview else { return }
        TimeclockReminderScheduler.registerNotificationCategories()
        TimeclockReminderScheduler.removeLegacyReportReminders()
        refreshNotificationAuthorizationStatus()
        TimeclockReminderScheduler.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshNotificationAuthorizationStatus()
                self?.scheduleReminders()
            }
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        launchAtLoginError = nil
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }

        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setAppTheme(_ theme: TimeclockAppTheme) {
        appTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.appThemeDefaultsKey)
    }

    func setWorkStartMinutes(_ minutes: Int) {
        workStartMinutes = TimeclockTimeMath.normalizedMinutes(minutes)
        UserDefaults.standard.set(workStartMinutes, forKey: Self.workStartMinutesDefaultsKey)
        updateTodayProgressTitle()
        updateStatusIndicator()
        updateMenuBarTitle()
        scheduleReminders()
    }

    func setWorkEndMinutes(_ minutes: Int) {
        workEndMinutes = TimeclockTimeMath.normalizedMinutes(minutes)
        UserDefaults.standard.set(workEndMinutes, forKey: Self.workEndMinutesDefaultsKey)
        updateTodayProgressTitle()
        updateStatusIndicator()
        updateMenuBarTitle()
        scheduleReminders()
    }

    func setBreakDurationMinutes(_ minutes: Int) {
        breakDurationMinutes = TimeclockTimeMath.normalizedDurationMinutes(minutes)
        UserDefaults.standard.set(breakDurationMinutes, forKey: Self.breakDurationMinutesDefaultsKey)
        updateTodayProgressTitle()
        updateStatusIndicator()
        updateMenuBarTitle()
        scheduleReminders()
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

    func setBreakOverReminderEnabled(_ isEnabled: Bool) {
        breakOverReminderEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.breakOverReminderEnabledDefaultsKey)
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

    func setOvertimeReminderEnabled(_ isEnabled: Bool) {
        overtimeReminderEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.overtimeReminderEnabledDefaultsKey)
        scheduleReminders()
        handleOvertimeNotification(for: state)
    }

    func reminderSound(for kind: TimeclockReminderKind) -> TimeclockReminderSound {
        reminderSounds[kind] ?? .defaultSound(for: kind)
    }

    func setReminderSound(_ sound: TimeclockReminderSound, for kind: TimeclockReminderKind) {
        guard reminderSound(for: kind) != sound else { return }

        reminderSounds[kind] = sound
        UserDefaults.standard.set(sound.rawValue, forKey: Self.reminderSoundDefaultsKey(for: kind))
        scheduleReminders()
    }

    func toggleReminderSoundPreview(for kind: TimeclockReminderKind) {
        if previewingReminderKind == kind {
            stopReminderSound()
        } else {
            playReminderSoundPreview(reminderSound(for: kind), for: kind)
        }
    }

    func stopReminderSound() {
        reminderSoundPreviewPlayer?.stop()
        reminderSoundPreviewPlayer = nil
        previewingReminderKind = nil
    }

    func snoozeNotification(_ request: UNNotificationRequest, minutes: Int) {
        TimeclockReminderScheduler.snooze(request, minutes: minutes)
    }

    func sendTestShiftReminder() {
        guard canSendTestNotifications else { return }
        TimeclockReminderScheduler.sendNotification(
            identifier: "test-shift-reminder-\(UUID().uuidString)",
            title: "Test: Shift starts soon",
            body: "Sound check only. No attendance or report action is needed.",
            categoryIdentifier: TimeclockReminderScheduler.reminderCategoryIdentifier,
            delaySeconds: 5,
            reminderSound: reminderSound(for: .workStart)
        )
    }

    func sendTestBreakReminder() {
        guard canSendTestNotifications else { return }
        TimeclockReminderScheduler.sendNotification(
            identifier: "test-break-reminder-\(UUID().uuidString)",
            title: "Test: Break reminder",
            body: "Sound check only. No attendance or report action is needed.",
            categoryIdentifier: TimeclockReminderScheduler.reminderCategoryIdentifier,
            delaySeconds: 5,
            reminderSound: reminderSound(for: .breakStart)
        )
    }

    func sendTestBreakOverReminder() {
        guard canSendTestNotifications else { return }
        TimeclockReminderScheduler.sendNotification(
            identifier: "test-break-over-reminder-\(UUID().uuidString)",
            title: "Test: Over break",
            body: "Sound check only. No attendance or report action is needed.",
            categoryIdentifier: TimeclockReminderScheduler.reminderCategoryIdentifier,
            delaySeconds: 5,
            reminderSound: reminderSound(for: .breakOver),
            soundSeconds: longOverdueSounds ? 20 : 10
        )
    }

    func sendTestClockOutReminder() {
        guard canSendTestNotifications else { return }
        TimeclockReminderScheduler.sendNotification(
            identifier: "test-clock-out-reminder-\(UUID().uuidString)",
            title: "Test: Clock out reminder",
            body: "Sound check only. No attendance or report action is needed.",
            categoryIdentifier: TimeclockReminderScheduler.reminderCategoryIdentifier,
            delaySeconds: 5,
            reminderSound: reminderSound(for: .clockOut),
            soundSeconds: longOverdueSounds ? 20 : 10
        )
    }

    func sendTestOvertimeReminder() {
        guard canSendTestNotifications else { return }
        TimeclockReminderScheduler.sendNotification(
            identifier: "test-overtime-reminder-\(UUID().uuidString)",
            title: "Test: Overtime",
            body: "Sound check only. No attendance or report action is needed.",
            categoryIdentifier: TimeclockReminderScheduler.reminderCategoryIdentifier,
            delaySeconds: 5,
            reminderSound: reminderSound(for: .overtime)
        )
    }

    func playReminderSound(_ sound: TimeclockReminderSound) {
        playReminderSound(sound, previewing: nil)
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
        updateStatusIndicator()
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
            next = Self.defaultDisplayComponents
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
        displayComponents = Self.defaultDisplayComponents
        displayLabelsEnabled = false
        fsLogoEnabled = true
        UserDefaults.standard.set(Self.storedDisplayComponents(displayComponents), forKey: Self.displayComponentsDefaultsKey)
        UserDefaults.standard.set(displayLabelsEnabled, forKey: Self.displayLabelsEnabledDefaultsKey)
        UserDefaults.standard.set(fsLogoEnabled, forKey: Self.fsLogoEnabledDefaultsKey)
        updateMenuBarTitle()
    }

    func resetAllDefaults() {
        setLaunchAtLoginEnabled(false)

        displayComponents = Self.defaultDisplayComponents
        displayLabelsEnabled = false
        fsLogoEnabled = true
        workStartMinutes = 15 * 60
        workEndMinutes = 0
        breakDurationMinutes = 60
        workReminderEnabled = true
        workReminderLeadMinutes = 15
        breakReminderEnabled = true
        breakReminderMinutes = 20 * 60
        breakOverReminderEnabled = true
        clockOutReminderEnabled = true
        clockOutReminderLeadMinutes = 15
        overtimeReminderEnabled = false
        setLongOverdueSounds(false)
        reminderSounds = Self.defaultReminderSounds
        stopReminderSound()
        workingWeekdays = Self.defaultWorkingWeekdays
        appTheme = .system
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
        UserDefaults.standard.set(breakOverReminderEnabled, forKey: Self.breakOverReminderEnabledDefaultsKey)
        UserDefaults.standard.set(clockOutReminderEnabled, forKey: Self.clockOutReminderEnabledDefaultsKey)
        UserDefaults.standard.set(clockOutReminderLeadMinutes, forKey: Self.clockOutReminderLeadMinutesDefaultsKey)
        UserDefaults.standard.set(overtimeReminderEnabled, forKey: Self.overtimeReminderEnabledDefaultsKey)
        for (kind, sound) in reminderSounds {
            UserDefaults.standard.set(sound.rawValue, forKey: Self.reminderSoundDefaultsKey(for: kind))
        }
        UserDefaults.standard.set(Self.storedWorkingWeekdays(workingWeekdays), forKey: Self.workingWeekdaysDefaultsKey)
        UserDefaults.standard.set(appTheme.rawValue, forKey: Self.appThemeDefaultsKey)
        UserDefaults.standard.set(hotkeyEnabled, forKey: Self.hotkeyEnabledDefaultsKey)
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: Self.hotkeyKeyCodeDefaultsKey)
        UserDefaults.standard.set(Int(hotkeyModifierFlags.rawValue), forKey: Self.hotkeyModifiersDefaultsKey)

        updateTodayProgressTitle()
        updateStatusIndicator()
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
                self?.notificationSoundSetting = settings.soundSetting
            }
        }
    }

    func startPolling() {
        guard !isPreview else { return }
        guard pollTimer == nil else { return }
        isPolling = true
        readTimeclockState()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollingInterval, repeats: true) { [weak self] _ in
            self?.pollTick()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        observation.invalidate()
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
        endMonitoringActivity()
        pageRecovery.cancel()
        setUnavailable("Paused · waiting for connection or wake")
    }

    private func pollTick() {
        let now = Date()
        if isRefreshing, observation.displayState(current: state, refreshing: true, at: now) == .stale {
            setUnavailable("Status needs verification")
        }
        if observation.isTimedOut(at: now) {
            observation.invalidate()
            queueRecovery("Time Clock stopped responding")
        }
        if let started = navigationStartedAt, now.timeIntervalSince(started) >= 30 {
            navigationStartedAt = nil
            webView.stopLoading()
            queueRecovery("Time Clock took too long to load")
        }
        if let retry = pageRecovery.retryAt, now >= retry, !webView.isLoading {
            pageRecovery.cancel()
            reload()
            return
        }
        if now.timeIntervalSince(lastReadAttempt) >= Self.pageReadInterval { readTimeclockState() }
        if now.timeIntervalSince(lastReminderReconciledAt) >= 30 {
            scheduleReminders()
            handleOvertimeNotification(for: state)
        }
        // Refresh remote data only while the clock page is not being used.
        if now.timeIntervalSince(lastPageLoad) >= 60, pageRecovery.retryAt == nil,
           webView.window?.isVisible != true, state != .loginRequired, !webView.isLoading,
           observation.token == nil {
            refreshRemoteWhenIdle(at: now)
            return
        }
        if let observed = observation.observedAt, now.timeIntervalSince(observed) > 30,
           Self.isWorking(state) || state == .clockedOut {
            setUnavailable("Status needs verification")
        }
        updateMenuBarTitle()
    }

    private func refreshRemoteWhenIdle(at now: Date) {
        guard let token = observation.begin(at: now) else { return }
        lastPageLoad = now
        // A hidden page can still contain unfinished input. Never discard it automatically.
        let script = "!window.__timeclockLastInput && !document.activeElement?.matches('input, textarea, [contenteditable=true]')"
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, self.isPolling, self.observation.finish(token), error == nil,
                  result as? Bool == true, self.webView.window?.isVisible != true else { return }
            self.reload()
        }
    }

    func readTimeclockState() {
        guard !isPreview, isPolling, webView.url != nil,
              pageRecovery.allowsRead(isLoading: webView.isLoading),
              let token = observation.begin(at: Date()) else { return }
        lastReadAttempt = Date()
        let script = TimeclockDOMDetector.readScript(revealClockPanel: webView.window?.isVisible != true)
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, self.isPolling, self.observation.finish(token) else { return }
            guard error == nil else { self.queueRecovery("Could not read Time Clock"); return }
            let detection = TimeclockDOMDetection(result as? [String: Any])
            let nextTimers = TimeclockDOMDetector.timers(from: detection)
            let nextState = TimeclockDOMDetector.state(from: detection)
            let previousState = self.state
            let wasOvertime = self.overtimeMinutes > 0
            var checkpointsChanged = false
            if nextState == .loginRequired {
                self.isRefreshing = false
                self.state = .loginRequired
                self.pageRecovery.verified()
                self.navigationStartedAt = nil
                self.endMonitoringActivity()
                self.connectionStatus = "Sign in on Time Clock to restore status updates."
                self.handleLoginNotification(for: nextState)
            } else if self.observation.accept(nextState, timers: nextTimers, at: Date()) {
                self.isRefreshing = false
                self.lastDetection = detection
                self.lastRefreshedAt = self.observation.observedAt
                self.timers = nextTimers
                self.state = nextState
                let previousCheckpoints = self.workday.checkpoints
                self.workday.observe(state: nextState, schedule: self.workSchedule,
                    now: self.observation.observedAt ?? Date(), history: detection?.history ?? [],
                    historyTimeZone: detection?.historyTimeZone)
                checkpointsChanged = previousCheckpoints != self.workday.checkpoints
                if checkpointsChanged {
                    let recordedCount = self.workday.checkpoints.filter { $0.actualDate != nil }.count
                    if recordedCount > 0 {
                        self.monitoringLogger.info("Recorded attendance dates available: \(recordedCount, privacy: .public)")
                    }
                }
                if Self.isWorking(nextState) && self.monitoringActivity == nil {
                    self.monitoringActivity = ProcessInfo.processInfo.beginActivity(
                        options: .userInitiatedAllowingIdleSystemSleep, reason: "Monitor the current Time Clock work session")
                } else if !Self.isWorking(nextState) { self.endMonitoringActivity() }
                self.connectionStatus = "Status observed from Time Clock · timer estimated between reads"
                self.pageRecovery.verified()
                self.navigationStartedAt = nil
                self.handleLoginNotification(for: nextState)
                self.updateTodayProgressTitle()
            } else {
                self.queueRecovery("Clock status could not be verified", waitForContent: true)
                return
            }
            if self.state == .loginRequired {
                self.todayProgressTitle = ""
                self.overtimeMinutes = 0
            }
            if Self.reminderSchedulingState(previousState) != Self.reminderSchedulingState(self.state) {
                self.monitoringLogger.info("Clock observation recovered: \(Self.reminderSchedulingState(self.state), privacy: .public)")
            }
            self.updateStatusIndicator()
            self.updateMenuBarTitle()
            if Self.reminderSchedulingState(previousState) != Self.reminderSchedulingState(self.state)
                || checkpointsChanged
                || wasOvertime != (self.overtimeMinutes > 0)
                || Date().timeIntervalSince(self.lastReminderReconciledAt) >= 30 {
                self.scheduleReminders()
            }
            self.handleOvertimeNotification(for: self.state)
        }
    }

    private func endMonitoringActivity() {
        if let activity = monitoringActivity { ProcessInfo.processInfo.endActivity(activity) }
        monitoringActivity = nil
    }

    private func setUnavailable(_ message: String) {
        isRefreshing = false
        endMonitoringActivity()
        let changed = state != .stale
        state = .stale
        let previous = observation.lastState.map { " · Last known: \($0.headerTitle)" } ?? ""
        connectionStatus = message + previous
        todayProgressTitle = ""
        overtimeMinutes = 0
        statusIndicator = .none
        updateMenuBarTitle()
        if changed { scheduleReminders() }
    }

    private func queueRecovery(_ message: String, waitForContent: Bool = false) {
        let keepLastConfirmed = waitForContent && isRefreshing && displayState != .stale
        if isPolling, pageRecovery.retryAt == nil, !keepLastConfirmed {
            monitoringLogger.notice("Clock recovery scheduled: \(message, privacy: .public)")
        }
        if !keepLastConfirmed { setUnavailable(message + " · Reconnecting") }
        guard isPolling else { return }
        pageRecovery.schedule(at: Date(), minimumDelay: waitForContent ? 30 : 0)
    }

    private func beginPageRefresh() {
        let previousState = state
        let canPreserve = isRefreshing || Self.isWorking(state) || state == .clockedOut
        let wasRefreshing = isRefreshing
        observation.invalidate()
        state = observation.lastState == nil ? .loading : .stale
        isRefreshing = canPreserve && observation.displayState(current: state, refreshing: true, at: Date()) != state
        if isRefreshing {
            connectionStatus = "Refreshing Time Clock… · Showing last confirmed status"
            if !wasRefreshing {
                monitoringLogger.info("Refresh keeps last confirmed display: \(Self.reminderSchedulingState(self.displayState), privacy: .public)")
            }
        } else {
            connectionStatus = "Checking Time Clock…" + (observation.lastState.map { " · Last known: \($0.headerTitle)" } ?? "")
        }
        statusIndicator = .none
        updateMenuBarTitle()
        if previousState != state { scheduleReminders() }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        beginPageRefresh()
        navigationStartedAt = Date()
        lastPageLoad = Date()
        pageRecovery.navigationStarted()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        observation.invalidate()
        navigationStartedAt = nil
        pageRecovery.navigationDidFail()
        queueRecovery("Time Clock could not load")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pageRecovery.navigationCommitted()
        readTimeclockState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationStartedAt = nil
        pageRecovery.navigationCommitted()
        observation.resetMotion()
        readTimeclockState()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        observation.invalidate()
        navigationStartedAt = nil
        queueRecovery("Time Clock restarted unexpectedly")
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard self?.reminderSoundPreviewPlayer === player else { return }

            self?.reminderSoundPreviewPlayer = nil
            self?.previewingReminderKind = nil
        }
    }

    private func updateMenuBarTitle() {
        let visibleState = displayState
        let displayedTimers = Self.isWorking(visibleState) ? observation.displayTimers(at: Date()) : (visibleState == .clockedOut ? timers : .empty)
        let displayedState: TimeclockState
        if case .onBreak = visibleState { displayedState = .onBreak(displayedTimers.fallback) }
        else { displayedState = visibleState }
        let title = visibleState == .stale ? (isPolling ? (observation.lastState == nil ? "Checking" : "Unavailable") : "Paused") : TimeclockMenuTitleFormatter.title(
            state: displayedState,
            timers: displayedTimers,
            components: displayComponents,
            remainingTitle: todayProgressTitle,
            statusOverride: statusIndicator.title,
            showsLabels: displayLabelsEnabled
        )
        if menuBarTitle != title { menuBarTitle = title }
    }

    private func updateTodayProgressTitle() {
        let parsedDayMinutes = TimeclockTimeMath.timerMinutes(from: timers.day.isEmpty ? timers.fallback : timers.day)

        let now = Date()
        guard let shift = workSchedule.currentShift(at: now), now >= shift.start,
              now < shift.end.addingTimeInterval(4 * 3600) else {
            let dayMinutes = parsedDayMinutes ?? 0
            todayProgressTitle = dayMinutes > 0 ? "Today +\(TimeclockTimeMath.durationLabel(minutes: dayMinutes))" : "Off today"
            overtimeMinutes = 0
            return
        }

        guard let dayMinutes = parsedDayMinutes else {
            todayProgressTitle = ""
            overtimeMinutes = 0
            return
        }

        let remainingMinutes = TimeclockTimeMath.remainingWorkMinutes(
            dayMinutes: dayMinutes,
            start: workStartMinutes,
            end: workEndMinutes,
            breakDuration: breakDurationMinutes
        )

        if remainingMinutes > 0 {
            todayProgressTitle = "Today \(TimeclockTimeMath.durationLabel(minutes: remainingMinutes)) left"
            overtimeMinutes = 0
        } else if remainingMinutes < 0 {
            overtimeMinutes = abs(remainingMinutes)
            todayProgressTitle = "Today +\(TimeclockTimeMath.durationLabel(minutes: overtimeMinutes))"
        } else {
            todayProgressTitle = "Today target met"
            overtimeMinutes = 0
        }
    }

    private func updateStatusIndicator() {
        let now = Date()
        statusIndicator = TimeclockStatusIndicator.indicator(
            state: state,
            breakDurationMinutes: breakDurationMinutes,
            overtimeMinutes: overtimeMinutes,
            shiftEnded: workSchedule.currentShift(at: now).map { now >= $0.end } ?? false
        )
    }

    private func handleLoginNotification(for state: TimeclockState) {
        guard state == .loginRequired else {
            if Self.isWorking(state) || state == .clockedOut { hasSentLoginNotification = false }
            return
        }

        guard !hasSentLoginNotification, Date() >= nextLoginAttempt else { return }
        nextLoginAttempt = Date().addingTimeInterval(60)
        hasSentLoginNotification = true
        TimeclockReminderScheduler.sendNotification(
            identifier: TimeclockReminderScheduler.loginRequiredNotificationIdentifier,
            title: "Time Clock Bar login expired",
            body: "Open Time Clock Bar to sign in again.",
            categoryIdentifier: TimeclockReminderScheduler.loginRequiredCategoryIdentifier,
            completion: { [weak self] queued in
                if !queued { self?.hasSentLoginNotification = false }
            }
        )
    }

    private var overtimeSilenceKey: String {
        "overtimeSilenced.v1." + (workSchedule.currentShift(at: Date())?.id ?? WorkdaySchedule.dateString(Date()))
    }

    private func handleOvertimeNotification(for state: TimeclockState) {
        guard !isPreview, !UserDefaults.standard.bool(forKey: overtimeSilenceKey) else { return }
        guard overtimeReminderEnabled, overtimeMinutes > 0, Self.isWorking(state) else {
            return
        }

        let workDate = workSchedule.currentShift(at: Date())?.id ?? WorkdaySchedule.dateString(Date())
        let budgetKey = "overtimeQueued.v2." + workDate
        guard !overtimeRequestInFlight, Date() >= nextOvertimeAttempt,
              !UserDefaults.standard.bool(forKey: budgetKey) else { return }
        if clockOutReminderEnabled, let shift = workSchedule.currentShift(at: Date()),
           Date() >= shift.end.addingTimeInterval(-15 * 60) { return }
        overtimeRequestInFlight = true
        nextOvertimeAttempt = Date().addingTimeInterval(60)
        TimeclockReminderScheduler.sendNotification(
            identifier: TimeclockReminderDelivery.overtimeOwner,
            title: "Hours target reached",
            body: "You are over today's work-hours target by \(TimeclockTimeMath.durationLabel(minutes: overtimeMinutes)). Open Time Clock to review your clock-out status.",
            categoryIdentifier: TimeclockReminderScheduler.reminderCategoryIdentifier,
            reminderSound: reminderSound(for: .overtime),
            completion: { [weak self] queued in
                self?.overtimeRequestInFlight = false
                guard queued else { return }
                UserDefaults.standard.set(true, forKey: budgetKey)
            }
        )
    }

    var workSchedule: WorkdaySchedule {
        WorkdaySchedule(timeZone: TimeZone(identifier: workTimeZone) ?? .current, weekdays: workingWeekdays,
                        startMinutes: workStartMinutes, endMinutes: workEndMinutes,
                        breakMinutes: breakReminderMinutes, breakDuration: breakDurationMinutes)
    }

    func setLongOverdueSounds(_ enabled: Bool) {
        longOverdueSounds = enabled
        UserDefaults.standard.set(enabled, forKey: "longOverdueSounds")
        scheduleReminders()
    }

    func setWorkTimeZone(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil else { return }
        workTimeZone = identifier
        UserDefaults.standard.set(identifier, forKey: "workTimeZone")
        scheduleReminders()
    }

    func silenceReminder(_ request: UNNotificationRequest) {
        guard !isPreview, let owner = TimeclockReminderDelivery.owner(request) else { return }
        if owner == TimeclockReminderDelivery.overtimeOwner {
            UserDefaults.standard.set(true, forKey: overtimeSilenceKey)
        } else { workday.silence(owner: owner) }
        scheduleReminders()
    }

    func resumeCheckpoint(_ checkpoint: WorkdayCheckpoint) {
        workday.resume(checkpoint)
        scheduleReminders()
    }

    func silenceCheckpoint(_ checkpoint: WorkdayCheckpoint) {
        workday.silence(checkpoint)
        scheduleReminders()
    }

    func scheduleReminders() {
        guard !isPreview else { return }
        lastReminderReconciledAt = Date()
        TimeclockReminderScheduler.schedule(
            state: state,
            workingWeekdays: workingWeekdays,
            workReminderEnabled: workReminderEnabled,
            workStartMinutes: workStartMinutes,
            workReminderLeadMinutes: workReminderLeadMinutes,
            breakReminderEnabled: breakReminderEnabled,
            breakReminderMinutes: breakReminderMinutes,
            breakOverReminderEnabled: breakOverReminderEnabled,
            breakDurationMinutes: breakDurationMinutes,
            clockOutReminderEnabled: clockOutReminderEnabled,
            workEndMinutes: workEndMinutes,
            clockOutReminderLeadMinutes: clockOutReminderLeadMinutes,
            workReminderSound: reminderSound(for: .workStart),
            breakReminderSound: reminderSound(for: .breakStart),
            breakOverReminderSound: reminderSound(for: .breakOver),
            clockOutReminderSound: reminderSound(for: .clockOut),
            allowsOvertime: overtimeReminderEnabled && overtimeMinutes > 0 && Self.isWorking(state)
                && !UserDefaults.standard.bool(forKey: overtimeSilenceKey),
            overtimeReminderEnabled: overtimeReminderEnabled
        )
    }

    private static func savedBool(_ key: String, defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    private func playReminderSoundPreview(_ sound: TimeclockReminderSound, for kind: TimeclockReminderKind) {
        playReminderSound(sound, previewing: kind)
    }

    private func playReminderSound(_ sound: TimeclockReminderSound, previewing kind: TimeclockReminderKind?) {
        stopReminderSound()

        let name = longOverdueSounds && (kind == .breakOver || kind == .clockOut) ? "\(sound.rawValue)-20" : sound.rawValue
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return
        }

        player.delegate = self
        player.play()
        reminderSoundPreviewPlayer = player
        previewingReminderKind = kind
    }

    private static let defaultReminderSounds = Dictionary(
        uniqueKeysWithValues: TimeclockReminderKind.allCases.map { ($0, TimeclockReminderSound.defaultSound(for: $0)) }
    )

    private static func savedReminderSounds() -> [TimeclockReminderKind: TimeclockReminderSound] {
        Dictionary(uniqueKeysWithValues: TimeclockReminderKind.allCases.map { kind in
            let saved = UserDefaults.standard.string(forKey: reminderSoundDefaultsKey(for: kind))
            return (kind, TimeclockReminderSound(rawValue: saved ?? "") ?? .defaultSound(for: kind))
        })
    }

    private static func reminderSoundDefaultsKey(for kind: TimeclockReminderKind) -> String {
        "\(reminderSoundDefaultsKeyPrefix)\(kind.rawValue)"
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
            return components.isEmpty ? defaultDisplayComponents : components
        }

        if let legacy = UserDefaults.standard.string(forKey: legacyDisplayMetricDefaultsKey),
           let component = TimeclockDisplayComponent(rawValue: legacy) {
            return [component]
        }

        return defaultDisplayComponents
    }

    private static func storedDisplayComponents(_ components: Set<TimeclockDisplayComponent>) -> [String] {
        TimeclockDisplayComponent.allCases
            .filter { components.contains($0) }
            .map(\.rawValue)
    }

    private static func runningTimerValue(state: TimeclockState, timers: TimeclockTimers) -> String {
        switch state {
        case .active:
            return timers.current.isEmpty ? timers.fallback : timers.current
        case .onBreak(let time):
            return time
        case .loading, .loginRequired, .stale, .clockedOut, .unknown:
            return ""
        }
    }

    private static func isWorking(_ state: TimeclockState) -> Bool {
        switch state {
        case .active, .onBreak:
            return true
        case .loading, .loginRequired, .stale, .clockedOut, .unknown:
            return false
        }
    }

    private static func reminderSchedulingState(_ state: TimeclockState) -> String {
        switch state {
        case .loading:
            return "loading"
        case .loginRequired:
            return "loginRequired"
        case .stale:
            return "stale"
        case .clockedOut:
            return "clockedOut"
        case .active:
            return "active"
        case .onBreak(let timer):
            return TimeclockTimeMath.timerSeconds(from: timer) == nil ? "onBreakUnknownTimer" : "onBreak"
        case .unknown:
            return "unknown"
        }
    }

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }
}

/// WKUserContentController retains its handler; keep the controller reference weak.
private final class TimeclockScriptBridge: NSObject, WKScriptMessageHandler {
    weak var controller: TimeclockController?
    init(controller: TimeclockController) { self.controller = controller }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === controller?.webView else { return }
        controller?.readTimeclockState()
    }
}
