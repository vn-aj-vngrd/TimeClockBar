import Foundation

/// Reload backoff and navigation failure state for the monitored clock page.
struct TimeclockPageRecovery {
    private(set) var retryAt: Date?
    private var attempt = 0
    private var navigationFailed = false

    func allowsRead(isLoading: Bool) -> Bool {
        // A reload is only a fallback. The site's clock may render after didFinish.
        !isLoading && !navigationFailed
    }

    mutating func schedule(at now: Date) {
        guard retryAt == nil else { return }
        let delays: [TimeInterval] = [2, 5, 15, 60]
        retryAt = now.addingTimeInterval(delays[min(attempt, delays.count - 1)])
        attempt += 1
    }

    mutating func cancel() { retryAt = nil }

    mutating func navigationStarted() {
        navigationFailed = false
        cancel()
    }

    mutating func navigationDidFail() { navigationFailed = true }

    mutating func verified() {
        navigationStarted()
        attempt = 0
    }
}
