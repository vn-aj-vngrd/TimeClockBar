import AppKit
import Carbon
import Combine
import Network
import SwiftUI
import UserNotifications
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private let controller = TimeclockController()
    private let popover = NSPopover()
    private var aboutWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var stateCancellable: AnyCancellable?
    private var hotkeyCancellable: AnyCancellable?
    private var statusTooltipCancellable: AnyCancellable?
    private var fsLogoCancellable: AnyCancellable?
    private var tooltipTimer: Timer?
    private var hotkeyRef: EventHotKeyRef?
    private var hotkeyEventHandler: EventHandlerRef?
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "TimeClockBar.NetworkMonitor")
    private var isNetworkAvailable = true
    private var isAwake = true
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private static let hotkeySignature: OSType = 0x54434248
    private static let hotkeyID: UInt32 = 1
    private static let popoverWidth: CGFloat = 460
    private static let minimumPopoverHeight: CGFloat = 640
    private static let preferredPopoverHeight: CGFloat = 780
    private static let popoverScreenPadding: CGFloat = 72

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = Self.brandAppImage()
        UNUserNotificationCenter.current().delegate = self

        configureStatusItem()
        configurePopover()
        bindStatusTitle()
        bindStatusTooltip()
        bindStatusLogo()
        installHotkeyHandler()
        bindHotkey()
        startSystemMonitoring()

        controller.load()
        updatePolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stopPolling()
        tooltipTimer?.invalidate()
        unregisterHotkey()
        pathMonitor.cancel()

        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }

        if let hotkeyEventHandler {
            RemoveEventHandler(hotkeyEventHandler)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = statusTitle(controller.menuBarTitle)
        item.button?.image = controller.fsLogoEnabled ? Self.brandStatusImage() : nil
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = Self.popoverSize()
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                controller: controller,
                openBrowser: { [weak self] url in self?.openBrowser(url: url) },
                openAbout: { [weak self] in self?.showAboutWindow() },
                quit: { NSApp.terminate(nil) }
            )
        )
    }

    func popoverDidClose(_ notification: Notification) {
        controller.isSettingsPresented = false
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === aboutWindow {
            aboutWindow = nil
        }
    }

    private func bindStatusTitle() {
        stateCancellable = controller.$menuBarTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                self?.statusItem?.button?.title = self?.statusTitle(title) ?? title
            }
    }

    private func bindStatusTooltip() {
        statusTooltipCancellable = controller.$lastRefreshedAt
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusTooltip()
            }

        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateStatusTooltip()
        }
    }

    private func updateStatusTooltip() {
        statusItem?.button?.toolTip = TimeclockStatusTooltipFormatter.tooltip(lastRefreshedAt: controller.lastRefreshedAt)
    }

    private func bindStatusLogo() {
        fsLogoCancellable = controller.$fsLogoEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                self?.statusItem?.button?.image = isEnabled ? Self.brandStatusImage() : nil
                self?.statusItem?.button?.title = self?.statusTitle(self?.controller.menuBarTitle ?? "") ?? ""
            }
    }

    private func statusTitle(_ title: String) -> String {
        controller.fsLogoEnabled ? " \(title)" : title
    }

    private func installHotkeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    appDelegate.togglePopover()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotkeyEventHandler
        )
    }

    private func bindHotkey() {
        hotkeyCancellable = Publishers.CombineLatest4(
            controller.$hotkeyEnabled,
            controller.$hotkeyKeyCode,
            controller.$hotkeyModifierFlags,
            controller.$isRecordingHotkey
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] isEnabled, keyCode, modifiers, isRecording in
            self?.registerHotkey(isEnabled: isEnabled && !isRecording, keyCode: keyCode, modifiers: modifiers)
        }
    }

    private func startSystemMonitoring() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAwake = false
            self?.updatePolling()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAwake = true
            self?.updatePolling()
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }

                self.isNetworkAvailable = path.status == .satisfied
                self.updatePolling()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func updatePolling() {
        guard isAwake && isNetworkAvailable else {
            controller.stopPolling()
            return
        }

        controller.reload()
        controller.startPolling()
    }

    private func registerHotkey(isEnabled: Bool, keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        unregisterHotkey()
        guard isEnabled else { return }

        let hotkeyID = EventHotKeyID(signature: Self.hotkeySignature, id: Self.hotkeyID)
        RegisterEventHotKey(
            keyCode,
            Self.carbonModifiers(from: modifiers),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    private func unregisterHotkey() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
    }

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }

        NSApp.activate(ignoringOtherApps: true)
        popover.contentSize = Self.popoverSize(for: button.window?.screen)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()
        menu.addItem(menuItem("Settings", #selector(openSettingsFromMenu), keyEquivalent: ","))
        menu.addItem(menuItem("About Time Clock Bar", #selector(openAboutFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Time Clock Bar", #selector(openTimeclockInAppFromMenu), keyEquivalent: "1"))
        menu.addItem(menuItem("Open Daily Report", #selector(openDailyReportInAppFromMenu), keyEquivalent: "2"))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Time Clock in Browser", #selector(openTimeclockFromMenu), keyEquivalent: "1", modifiers: [.command, .option]))
        menu.addItem(menuItem("Open Daily Report in Browser", #selector(openDailyReportFromMenu), keyEquivalent: "2", modifiers: [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(menuItem("Refresh", #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", #selector(quitFromMenu), keyEquivalent: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    private func menuItem(
        _ title: String,
        _ action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: controller.hotkeyEnabled ? keyEquivalent : "")
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc private func openSettingsFromMenu() {
        showPopover()

        DispatchQueue.main.async { [weak self] in
            self?.controller.isSettingsPresented = true
        }
    }

    @objc private func refreshFromMenu() {
        controller.reload()
    }

    @objc private func openAboutFromMenu() {
        showAboutWindow()
    }

    @objc private func openTimeclockInAppFromMenu() {
        showPopover(page: .timeclock)
    }

    @objc private func openDailyReportInAppFromMenu() {
        showPopover(page: .dailyReport)
    }

    @objc private func openTimeclockFromMenu() {
        openBrowser(url: controller.url)
    }

    @objc private func openDailyReportFromMenu() {
        openBrowser(url: controller.dailyReportURL)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func openBrowser(url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func showPopover(page: PopoverPage) {
        showPopover()
        controller.requestPopoverPage(page)
    }

    private func showAboutWindow() {
        if let aboutWindow {
            NSApp.activate(ignoringOtherApps: true)
            aboutWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 284, height: 228),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Time Clock Bar"
        window.contentViewController = NSHostingController(rootView: AboutView())
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        aboutWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func brandStatusImage() -> NSImage? {
        guard let image = NSImage(named: "BrandIcon") else { return nil }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    private static func popoverSize(for screen: NSScreen? = NSScreen.main) -> NSSize {
        let availableHeight = max(0, (screen ?? NSScreen.main)?.visibleFrame.height ?? minimumPopoverHeight)
        let responsiveHeight = min(preferredPopoverHeight, max(minimumPopoverHeight, availableHeight - popoverScreenPadding))
        return NSSize(width: popoverWidth, height: responsiveHeight)
    }

    private static func brandAppImage() -> NSImage? {
        guard let image = NSImage(named: "BrandIcon") else { return nil }

        image.size = NSSize(width: 256, height: 256)
        image.isTemplate = false
        return image
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case TimeclockReminderScheduler.openDailyReportActionIdentifier:
            openBrowser(url: controller.dailyReportURL)
        case TimeclockReminderScheduler.openTimeclockActionIdentifier,
            UNNotificationDefaultActionIdentifier:
            showPopover()
        case TimeclockReminderScheduler.snooze5ActionIdentifier:
            snooze(response, minutes: 5)
        case TimeclockReminderScheduler.snooze10ActionIdentifier:
            snooze(response, minutes: 10)
        case TimeclockReminderScheduler.snooze15ActionIdentifier:
            snooze(response, minutes: 15)
        default:
            break
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func snooze(_ response: UNNotificationResponse, minutes: Int) {
        let content = response.notification.request.content
        controller.snoozeNotification(
            title: content.title,
            body: content.body,
            categoryIdentifier: content.categoryIdentifier,
            minutes: minutes
        )
    }

    private static func carbonModifiers(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbonModifiers: UInt32 = 0

        if modifiers.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }

        if modifiers.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }

        if modifiers.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }

        if modifiers.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        return carbonModifiers
    }
}
