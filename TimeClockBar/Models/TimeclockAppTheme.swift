import AppKit

enum TimeclockAppTheme: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    static func saved(rawValue: String?) -> TimeclockAppTheme {
        rawValue.flatMap(TimeclockAppTheme.init(rawValue:)) ?? .system
    }
}
