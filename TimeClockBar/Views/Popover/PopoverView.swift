import SwiftUI
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
                IconButton("Settings", systemImage: "gearshape") {
                    controller.isSettingsPresented.toggle()
                }
                .popover(isPresented: $controller.isSettingsPresented, arrowEdge: .bottom) {
                    SettingsPopover(
                        controller: controller,
                        isRecordingHotkey: $isRecordingHotkey,
                        quit: quit
                    )
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
        .help(page == .timeclock ? "Open daily report" : "Back to TimeClock Bar")
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
}

#Preview {
    PopoverView(
        controller: TimeclockController(),
        openBrowser: { _ in },
        quit: {}
    )
}
