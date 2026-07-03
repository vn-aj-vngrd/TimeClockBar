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
                        IconButton("Settings", systemImage: "gearshape") {
                            showSettings()
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
            switch page {
            case .timeclock:
                controller.loadDailyReport()
                page = .dailyReport
            case .dailyReport:
                page = .timeclock
            case .settings:
                closeSettings()
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
        .help(page == .timeclock ? "Open daily report" : "Back to TimeClock Bar")
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
}

#Preview {
    PopoverView(
        controller: TimeclockController(),
        openBrowser: { _ in },
        quit: {}
    )
}
