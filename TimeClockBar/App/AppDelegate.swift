import AppKit
import Carbon
import Combine
import Network
import SwiftUI
import UserNotifications
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private let controller = TimeclockController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var stateCancellable: AnyCancellable?
    private var hotkeyCancellable: AnyCancellable?
    private var hotkeyLabelCancellable: AnyCancellable?
    private var fsLogoCancellable: AnyCancellable?
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
        popover.contentSize = NSSize(width: 460, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                controller: controller,
                openBrowser: { [weak self] url in self?.openBrowser(url: url) },
                quit: { NSApp.terminate(nil) }
            )
        )
    }

    private func bindStatusTitle() {
        stateCancellable = controller.$menuBarTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                self?.statusItem?.button?.title = self?.statusTitle(title) ?? title
            }
    }

    private func bindStatusTooltip() {
        hotkeyLabelCancellable = Publishers.CombineLatest(
            controller.$hotkeyEnabled,
            controller.$hotkeyKeyCode.combineLatest(controller.$hotkeyModifierFlags)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] isEnabled, hotkey in
            let label = HotkeyFormatting.label(keyCode: hotkey.0, modifiers: hotkey.1)
            let shortcut = isEnabled ? " · \(label) toggles" : ""
            self?.statusItem?.button?.toolTip = "Click to open\(shortcut) · Right-click for menu"
        }
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()
        menu.addItem(menuItem("Settings", #selector(openSettingsFromMenu)))
        menu.addItem(menuItem("Refresh", #selector(refreshFromMenu)))
        menu.addItem(menuItem("Open TimeClock Bar in Browser", #selector(openTimeclockFromMenu)))
        menu.addItem(menuItem("Open Daily Report in Browser", #selector(openDailyReportFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", #selector(quitFromMenu)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
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

    private static func brandStatusImage() -> NSImage? {
        guard let image = NSImage(named: "BrandIcon") else { return nil }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
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
