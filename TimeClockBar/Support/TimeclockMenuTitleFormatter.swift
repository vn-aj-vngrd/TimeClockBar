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

enum TimeclockStatusTooltipFormatter {
    static func tooltip(lastRefreshedAt: Date?, now: Date = Date()) -> String {
        guard let lastRefreshedAt else { return "Not updated yet" }

        let seconds = max(0, Int(now.timeIntervalSince(lastRefreshedAt)))
        if seconds < 60 {
            return "Updated just now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "Updated \(minutes) min ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "Updated \(hours) hr ago"
        }

        let days = hours / 24
        return "Updated \(days) day\(days == 1 ? "" : "s") ago"
    }
}
