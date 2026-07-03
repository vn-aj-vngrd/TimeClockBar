import AppKit
import Carbon
import Combine
import SwiftUI
import UserNotifications
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private let controller = TimeclockController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var stateCancellable: AnyCancellable?
    private var hotkeyCancellable: AnyCancellable?
    private var hotkeyRef: EventHotKeyRef?
    private var hotkeyEventHandler: EventHandlerRef?

    private static let hotkeySignature: OSType = 0x54434248
    private static let hotkeyID: UInt32 = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        configureStatusItem()
        configurePopover()
        bindStatusTitle()
        installHotkeyHandler()
        bindHotkey()

        controller.load()
        controller.startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stopPolling()
        unregisterHotkey()

        if let hotkeyEventHandler {
            RemoveEventHandler(hotkeyEventHandler)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = controller.menuBarTitle
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
                self?.statusItem?.button?.title = title
            }
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
        menu.addItem(menuItem("Open Timeclock in Browser", #selector(openTimeclockFromMenu)))
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case TimeclockController.openDailyReportNotificationActionIdentifier:
            openBrowser(url: controller.dailyReportURL)
        case TimeclockController.openTimeclockNotificationActionIdentifier,
            UNNotificationDefaultActionIdentifier:
            showPopover()
        default:
            break
        }

        completionHandler()
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
