import Foundation

/// Formats page-observation freshness without advancing the last successful read time.
struct TimeclockObservationLabel {
    let title: String
    let help: String

    static func resolve(observedAt: Date?, state: TimeclockState, isRefreshing: Bool,
                        connectionStatus: String, now: Date, timeZone: TimeZone,
                        locale: Locale = .current) -> Self {
        let status: String
        let age = observedAt.map { now.timeIntervalSince($0) }
        if state == .loginRequired {
            status = "Sign in required"
        } else if isRefreshing, let age, (0...30).contains(age) {
            status = "Refreshing"
        } else {
            switch state {
            case .active, .onBreak, .clockedOut:
                status = age.map { (0...30).contains($0) ? "" : "Update delayed" } ?? "Checking Time Clock…"
            case .loading:
                status = observedAt == nil ? "Checking Time Clock…" : "Update delayed"
            case .stale, .unknown:
                status = observedAt == nil ? "Status unavailable" : "Update delayed"
            case .loginRequired:
                status = "Sign in required"
            }
        }
        guard let observedAt else {
            return Self(title: status, help: "No successful observation yet.\n\(connectionStatus)")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let stamp = observedAt.formatted(Date.FormatStyle(
            date: calendar.isDate(observedAt, inSameDayAs: now) ? .omitted : .abbreviated,
            time: .shortened, locale: locale, timeZone: timeZone))
        let exact = observedAt.formatted(Date.FormatStyle(date: .complete, time: .standard,
                                                         locale: locale, timeZone: timeZone))
        let relative = RelativeDateTimeFormatter()
        relative.locale = locale
        let elapsed = now >= observedAt ? relative.localizedString(for: observedAt, relativeTo: now)
            : "Device clock is earlier than the last observation."
        let title = [status, "Observed \(stamp)"].filter { !$0.isEmpty }.joined(separator: " · ")
        return Self(title: title, help: "\(exact) (\(timeZone.identifier))\n\(elapsed)\n\(connectionStatus)\nObserved means the loaded page was read successfully; it does not confirm a fresh server update.")
    }
}
