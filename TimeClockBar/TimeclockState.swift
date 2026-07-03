import Foundation

enum TimeclockDisplayComponent: String, CaseIterable, Identifiable {
    case status
    case current
    case day
    case week
    case remaining

    var id: String { rawValue }

    var label: String {
        switch self {
        case .status:
            return "Status"
        case .current:
            return "Current"
        case .day:
            return "Day"
        case .week:
            return "Week"
        case .remaining:
            return "Remaining"
        }
    }
}

struct TimeclockTimers: Equatable {
    let current: String
    let day: String
    let week: String
    let fallback: String

    static let empty = TimeclockTimers(current: "", day: "", week: "", fallback: "")

    func value(for component: TimeclockDisplayComponent) -> String {
        switch component {
        case .status:
            return ""
        case .current:
            return current.isEmpty ? fallback : current
        case .day:
            return day.isEmpty ? fallback : day
        case .week:
            return week.isEmpty ? fallback : week
        case .remaining:
            return ""
        }
    }
}

enum TimeclockState: Equatable {
    case loading
    case loginRequired
    case stale
    case clockedOut
    case active(String)
    case onBreak(String)
    case unknown(String?)

    var menuBarTitle: String {
        switch self {
        case .loading:
            return "Loading"
        case .loginRequired:
            return "Login"
        case .stale:
            return "Stale"
        case .clockedOut:
            return "Out"
        case .active(let time):
            return time.isEmpty ? "Active" : "Active \(time)"
        case .onBreak(let time):
            return time.isEmpty ? "Break" : "Break \(time)"
        case .unknown:
            return "Unknown"
        }
    }

    var headerTitle: String {
        switch self {
        case .loading:
            return "Loading TimeClock Bar"
        case .loginRequired:
            return "Login required"
        case .stale:
            return "Status stale"
        case .clockedOut:
            return "Not active"
        case .active(let time):
            return time.isEmpty ? "Active" : "Active · \(time)"
        case .onBreak(let time):
            return time.isEmpty ? "On break" : "On break · \(time)"
        case .unknown:
            return "Unknown status"
        }
    }
}
