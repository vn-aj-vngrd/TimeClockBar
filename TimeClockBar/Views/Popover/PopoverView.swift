import AppKit
import SwiftUI
import WebKit

struct PopoverView: View {
    @ObservedObject var controller: TimeclockController
    @State private var isReportHovered = false
    @State private var isRecordingHotkey = false
    @State private var page: PopoverPage = .timeclock
    @State private var pageBeforeSettings: PopoverPage = .timeclock

    let openBrowser: (URL) -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            content
        }
        .frame(width: 460, height: 640)
        .background(Color.clear)
        .onChange(of: controller.isSettingsPresented) { _, isPresented in
            if isPresented {
                showSettings()
            } else if page == .settings {
                closeSettings()
            }
        }
        .onChange(of: controller.requestedPopoverPage) { _, requestedPage in
            guard let requestedPage else { return }

            show(page: requestedPage)
            controller.requestPopoverPage(nil)
        }
        .background {
            PopoverShortcutCaptureView(isEnabled: controller.hotkeyEnabled && !isRecordingHotkey) { event in
                handleShortcut(event)
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
    }

    private var header: some View {
        ZStack {
            if page == .settings {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ChromeColor.primaryText)
            }

            HStack(spacing: 10) {
                if page == .settings {
                    IconButton("Back", systemImage: "chevron.left") {
                        closeSettings()
                    }
                } else {
                    HStack(spacing: 2) {
                        IconButton("Settings", systemImage: "gearshape", shortcut: shortcutLabel("⌘,")) {
                            showSettings()
                        }

                        IconButton("Refresh", systemImage: "arrow.clockwise", shortcut: shortcutLabel("⌘R")) {
                            refresh()
                        }

                        IconButton("Open Browser", systemImage: "arrow.up.right.square", shortcut: shortcutLabel("⌘O")) {
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
                }

                Spacer()

                if page != .settings {
                    pageToggleButton
                }
            }
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
            togglePage()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: page == .timeclock ? "doc.text.fill" : "clock.fill")
                    .font(.system(size: 12, weight: .bold))

                Text(page == .timeclock ? "Report" : "Time Clock")
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
        .help(page == .timeclock ? shortcutHelp("Report", "⌘2") : shortcutHelp("Time Clock", "⌘1"))
        .onHover { isReportHovered = $0 }
    }

    private var content: some View {
        Group {
            if page == .settings {
                SettingsPopover(
                    controller: controller,
                    isRecordingHotkey: $isRecordingHotkey,
                    quit: quit
                )
            } else {
                WebView(webView: currentWebView)
                    .id(page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentWebView: WKWebView {
        switch page {
        case .timeclock:
            return controller.webView
        case .dailyReport:
            return controller.dailyReportWebView
        case .settings:
            return controller.webView
        }
    }

    private var currentURL: URL {
        switch page {
        case .timeclock:
            return controller.url
        case .dailyReport:
            return controller.dailyReportURL
        case .settings:
            return controller.url
        }
    }

    private func refresh() {
        switch page {
        case .timeclock:
            controller.reload()
        case .dailyReport:
            controller.reloadDailyReport()
        case .settings:
            break
        }
    }

    private func shortcutLabel(_ label: String) -> String? {
        controller.hotkeyEnabled ? label : nil
    }

    private func shortcutHelp(_ title: String, _ label: String) -> String {
        shortcutLabel(label).map { "\(title) \($0)" } ?? title
    }

    private func showSettings() {
        if page != .settings {
            pageBeforeSettings = page
        }

        page = .settings
        controller.isSettingsPresented = true
    }

    private func closeSettings() {
        page = pageBeforeSettings == .settings ? .timeclock : pageBeforeSettings
        controller.isSettingsPresented = false
    }

    private func togglePage() {
        switch page {
        case .timeclock:
            showDailyReport()
        case .dailyReport:
            showTimeclock()
        case .settings:
            closeSettings()
        }
    }

    private func show(page: PopoverPage) {
        switch page {
        case .timeclock:
            showTimeclock()
        case .dailyReport:
            showDailyReport()
        case .settings:
            showSettings()
        }
    }

    private func showTimeclock() {
        page = .timeclock
        controller.isSettingsPresented = false
    }

    private func showDailyReport() {
        controller.loadDailyReport()
        page = .dailyReport
        controller.isSettingsPresented = false
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == [.command, .option] {
            switch key {
            case "1":
                openBrowser(controller.url)
            case "2":
                openBrowser(controller.dailyReportURL)
            default:
                return false
            }

            return true
        }

        guard modifiers == .command else { return false }

        switch key {
        case ",":
            showSettings()
        case "1":
            showTimeclock()
        case "2":
            showDailyReport()
        case "r":
            refresh()
        case "o":
            openBrowser(currentURL)
        case "q":
            quit()
        default:
            return false
        }

        return true
    }
}

private struct PopoverShortcutCaptureView: NSViewRepresentable {
    let isEnabled: Bool
    let onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled = true
        var onKeyDown: (NSEvent) -> Bool = { _ in false }
        private var monitor: Any?

        func installMonitor() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled, self.onKeyDown(event) else {
                    return event
                }

                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}

#Preview {
    PopoverView(
        controller: TimeclockController(),
        openBrowser: { _ in },
        quit: {}
    )
}
