import Foundation

enum TimeclockMenuTitleFormatter {
    static func title(
        state: TimeclockState,
        timers: TimeclockTimers,
        components: Set<TimeclockDisplayComponent>,
        remainingTitle: String,
        showsLabels: Bool
    ) -> String {
        if state == .stale {
            return state.menuBarTitle
        }

        let orderedComponents = TimeclockDisplayComponent.allCases.filter { components.contains($0) }
        let timerComponentCount = orderedComponents.filter { $0 != .status && $0 != .remaining }.count
        let parts = orderedComponents.compactMap { component -> String? in
            switch component {
            case .status:
                return statusLabel(for: state)
            case .remaining:
                guard !remainingTitle.isEmpty else { return nil }
                return showsLabels ? "\(component.label) \(remainingTitle)" : remainingTitle
            case .current, .day, .week:
                let value = timerComponentCount == 1 ? timers.value(for: component) : specificTimerValue(for: component, timers: timers)
                guard !value.isEmpty else { return nil }

                return showsLabels ? "\(component.label) \(value)" : value
            }
        }

        guard !parts.isEmpty else { return state.menuBarTitle }

        return parts.joined(separator: " · ")
    }

    private static func specificTimerValue(for component: TimeclockDisplayComponent, timers: TimeclockTimers) -> String {
        switch component {
        case .status:
            return ""
        case .current:
            return timers.current
        case .day:
            return timers.day
        case .week:
            return timers.week
        case .remaining:
            return ""
        }
    }

    private static func statusLabel(for state: TimeclockState) -> String {
        switch state {
        case .loading:
            return "Loading"
        case .loginRequired:
            return "Login"
        case .stale:
            return "Stale"
        case .clockedOut:
            return "Out"
        case .active:
            return "Active"
        case .onBreak:
            return "Break"
        case .unknown:
            return "Unknown"
        }
    }
}
