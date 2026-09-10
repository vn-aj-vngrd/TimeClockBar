import AppKit
import SwiftUI
import WebKit

struct PopoverView: View {
    @ObservedObject var controller: TimeclockController
    @State private var isRecordingHotkey = false
    @State private var page: PopoverPage = .today
    @State private var pageBeforeSettings: PopoverPage = .timeclock
    @State private var isClosingSettings = false

    let openBrowser: (URL) -> Void
    let openAbout: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if page != .settings { pageNavigation }
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
                    .padding(3)
                    .headerCircleContainer()
                } else {
                    HStack(spacing: 2) {
                        IconButton("Settings", systemImage: "gearshape", shortcut: shortcutLabel("⌘,")) {
                            showSettings()
                        }

                        IconButton("Refresh", systemImage: "arrow.clockwise", shortcut: shortcutLabel("⌘R")) {
                            refresh()
                        }.disabled(controller.isPreview)

                        IconButton("Open Browser", systemImage: "arrow.up.right.square", shortcut: shortcutLabel("⌘O")) {
                            if !controller.isPreview { openBrowser(currentURL) }
                        }.disabled(controller.isPreview)
                    }
                    .padding(3)
                    .headerCapsuleContainer()
                }

                Spacer()
                if page != .settings { Text("Time Clock Bar").font(.system(size: 13, weight: .semibold)) }
                #if DEBUG
                Text("DEV")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .foregroundStyle(ChromeColor.statusWarningText)
                    .background(ChromeColor.statusWarningBackground, in: Capsule())
                    .accessibilityLabel("Development build")
                    .help("Development build · not the installed release")
                #endif
                if page == .settings {
                    IconButton("About", systemImage: "info.circle") {
                        openAbout()
                    }
                    .padding(3)
                    .headerCircleContainer()
                } else {
                    HStack(spacing: 8) {
                        statusChip
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background {
            ZStack(alignment: .bottom) {
                ChromeColor.headerBackground

                Rectangle()
                    .fill(ChromeColor.border)
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if let title = statusChipTitle {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusChipForeground)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(statusChipBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(statusChipStroke, lineWidth: 0.5)
                )
                .shadow(color: ChromeColor.headerControlShadow, radius: 8, x: 0, y: 2)
                .help(statusChipHelp)
        }
    }

    private var statusChipTitle: String? {
        if controller.isPreview { return nil }
        if !controller.isPolling {
            return "Offline"
        }

        if controller.isRefreshing { return "Refreshing" }
        if controller.state == .stale {
            return "Unavailable"
        }

        return controller.statusIndicator.title
    }

    private var statusChipHelp: String {
        if controller.isPreview { return "Local preview with website access paused" }
        if !controller.isPolling {
            return "Polling paused"
        }

        if controller.isRefreshing { return "Refreshing the website · Showing your last confirmed status" }
        if controller.state == .stale {
            return "The latest clock status could not be verified"
        }

        return controller.statusIndicator.help
    }

    private var statusChipBackground: Color {
        switch controller.statusIndicator {
        case .overBreak where controller.isPolling && controller.state != .stale:
            return ChromeColor.statusDangerBackground
        case .overtime where controller.isPolling && controller.state != .stale,
             .pastShiftEnd where controller.isPolling && controller.state != .stale:
            return ChromeColor.statusWarningBackground
        case .none, .overtime, .overBreak, .pastShiftEnd:
            return ChromeColor.headerControlBackground
        }
    }

    private var statusChipForeground: Color {
        switch controller.statusIndicator {
        case .overBreak where controller.isPolling && controller.state != .stale:
            return ChromeColor.statusDangerText
        case .overtime where controller.isPolling && controller.state != .stale,
             .pastShiftEnd where controller.isPolling && controller.state != .stale:
            return ChromeColor.statusWarningText
        case .none, .overtime, .overBreak, .pastShiftEnd:
            return ChromeColor.primaryText
        }
    }

    private var statusChipStroke: Color {
        switch controller.statusIndicator {
        case .overBreak where controller.isPolling && controller.state != .stale:
            return ChromeColor.statusDangerStroke
        case .overtime where controller.isPolling && controller.state != .stale,
             .pastShiftEnd where controller.isPolling && controller.state != .stale:
            return ChromeColor.statusWarningStroke
        case .none, .overtime, .overBreak, .pastShiftEnd:
            return ChromeColor.headerControlStroke
        }
    }

    private var pageNavigation: some View {
        Picker("Page", selection: Binding(get: { page }, set: { show(page: $0) })) {
            Text("Today").tag(PopoverPage.today)
            Text("Time Clock").tag(PopoverPage.timeclock)
            Text("Report").tag(PopoverPage.dailyReport)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(ChromeColor.headerBackground)
        .help("Today ⌘0 · Time Clock ⌘1 · Report ⌘2")
    }

    private var content: some View {
        Group {
            if page == .settings {
                SettingsPopover(
                    controller: controller,
                    isRecordingHotkey: $isRecordingHotkey,
                    quit: quit
                )
            } else if page == .today {
                TodayView(controller: controller, workday: controller.workday,
                          openClock: showTimeclock, openReport: showDailyReport)
            } else if controller.isPreview {
                ContentUnavailableView(page == .timeclock ? "Time Clock" : "Report", systemImage: page == .timeclock ? "clock" : "doc.text",
                                       description: Text("Website access is paused for this local preview."))
            } else {
                WebView(webView: currentWebView)
                    .id(page)
            }
        }
        .id(page)
        .transition(contentTransition)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .identity : isClosingSettings
            ? .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
            : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    }

    private var currentWebView: WKWebView {
        switch page {
        case .timeclock:
            return controller.webView
        case .dailyReport:
            return controller.dailyReportWebView
        case .settings, .today:
            return controller.webView
        }
    }

    private var currentURL: URL {
        switch page {
        case .timeclock:
            return controller.url
        case .dailyReport:
            return controller.dailyReportURL
        case .settings, .today:
            return controller.url
        }
    }

    private func refresh() {
        switch page {
        case .timeclock, .today:
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
        guard page != .settings else { return }

        pageBeforeSettings = page
        isClosingSettings = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            page = .settings
            controller.isSettingsPresented = true
        }
    }

    private func closeSettings() {
        isClosingSettings = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            page = pageBeforeSettings == .settings ? .timeclock : pageBeforeSettings
            controller.isSettingsPresented = false
        }
    }

    private func show(page: PopoverPage) {
        switch page {
        case .today:
            self.page = .today
            controller.isSettingsPresented = false
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
            guard !controller.isPreview else { return true }
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
        case "0":
            show(page: .today)
        case ",":
            showSettings()
        case "1":
            showTimeclock()
        case "2":
            showDailyReport()
        case "r":
            refresh()
        case "o":
            if !controller.isPreview { openBrowser(currentURL) }
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

private extension View {
    func headerCapsuleContainer(isHovered: Bool = false) -> some View {
        background(isHovered ? ChromeColor.headerActionHover : ChromeColor.headerControlBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(ChromeColor.headerControlStroke, lineWidth: 0.5)
            )
            .shadow(color: ChromeColor.headerControlShadow, radius: 8, x: 0, y: 2)
    }

    func headerCircleContainer() -> some View {
        background(ChromeColor.headerControlBackground)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(ChromeColor.headerControlStroke, lineWidth: 0.5)
            )
            .shadow(color: ChromeColor.headerControlShadow, radius: 8, x: 0, y: 2)
    }
}

#Preview {
    PopoverView(
        controller: TimeclockController(),
        openBrowser: { _ in },
        openAbout: {},
        quit: {}
    )
}
