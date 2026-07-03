import SwiftUI

enum ChromeColor {
    static let controlGroup = Color.white.opacity(0.055)
    static let controlHover = Color.white.opacity(0.085)
    static let border = Color.white.opacity(0.09)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.58)
    static let reportBottom = Color(red: 0.0, green: 0.34, blue: 0.88)
    static let sectionBackground = Color.white.opacity(0.045)
    static let sectionRing = Color.white.opacity(0.075)
}

enum PopoverPage: Equatable {
    case timeclock
    case dailyReport
    case settings
}
