import AppKit
import SwiftUI

enum ChromeColor {
    static let settingsBackground = Color(nsColor: .windowBackgroundColor)
    static let controlGroup = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let primaryText = Color(nsColor: .textColor)
    static let secondaryText = adaptiveColor(
        light: NSColor(calibratedRed: 0.510, green: 0.510, blue: 0.510, alpha: 1),
        dark: NSColor(calibratedWhite: 1, alpha: 0.58)
    )
    static let accentText = Color.white
    static let selectHover = adaptiveColor(
        light: NSColor(calibratedWhite: 0.92, alpha: 1),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let selectChevronBackground = adaptiveColor(
        light: NSColor(calibratedWhite: 0.88, alpha: 1),
        dark: NSColor(calibratedWhite: 1, alpha: 0.12)
    )
    static let settingsButtonBackground = adaptiveColor(
        light: NSColor(calibratedRed: 0.925, green: 0.925, blue: 0.925, alpha: 1),
        dark: NSColor(calibratedWhite: 1, alpha: 0.12)
    )
    static let settingsButtonPressedBackground = adaptiveColor(
        light: NSColor(calibratedWhite: 0.88, alpha: 1),
        dark: NSColor(calibratedWhite: 1, alpha: 0.18)
    )
    static let headerBackground = Color(nsColor: .windowBackgroundColor)
    static let headerControlBackground = adaptiveColor(
        light: NSColor(calibratedWhite: 1, alpha: 1),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let headerControlStroke = adaptiveColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.06),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let headerControlShadow = adaptiveColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.12),
        dark: NSColor(calibratedWhite: 0, alpha: 0.28)
    )
    static let headerAction = adaptiveColor(
        light: NSColor(calibratedWhite: 0.28, alpha: 1),
        dark: NSColor(calibratedWhite: 0.96, alpha: 1)
    )
    static let headerActionHover = adaptiveColor(
        light: NSColor(calibratedWhite: 0.90, alpha: 1),
        dark: NSColor(calibratedWhite: 1, alpha: 0.12)
    )
    static let statusWarningBackground = adaptiveColor(
        light: NSColor.systemOrange.withAlphaComponent(0.16),
        dark: NSColor.systemOrange.withAlphaComponent(0.22)
    )
    static let statusWarningText = Color(nsColor: .systemOrange)
    static let statusWarningStroke = adaptiveColor(
        light: NSColor.systemOrange.withAlphaComponent(0.28),
        dark: NSColor.systemOrange.withAlphaComponent(0.36)
    )
    static let statusDangerBackground = adaptiveColor(
        light: NSColor.systemRed.withAlphaComponent(0.14),
        dark: NSColor.systemRed.withAlphaComponent(0.22)
    )
    static let statusDangerText = Color(nsColor: .systemRed)
    static let statusDangerStroke = adaptiveColor(
        light: NSColor.systemRed.withAlphaComponent(0.26),
        dark: NSColor.systemRed.withAlphaComponent(0.38)
    )
    static let reportBottom = Color(nsColor: .controlAccentColor)

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum PopoverPage: Equatable {
    case timeclock
    case dailyReport
    case settings
}
