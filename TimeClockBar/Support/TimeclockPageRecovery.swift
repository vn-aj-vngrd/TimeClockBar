import Foundation

/// Reload backoff and navigation failure state for the monitored clock page.
struct TimeclockPageRecovery {
    private(set) var retryAt: Date?
    private var attempt = 0
    private var navigationFailed = false
    private var documentCommitted = false

    func allowsRead(isLoading: Bool) -> Bool {
        // A reload is only a fallback. The site's clock may render after didFinish.
        (!isLoading || documentCommitted) && !navigationFailed
    }

    mutating func schedule(at now: Date, minimumDelay: TimeInterval = 0) {
        guard retryAt == nil else { return }
        let delays: [TimeInterval] = [2, 5, 15, 60]
        retryAt = now.addingTimeInterval(max(minimumDelay, delays[min(attempt, delays.count - 1)]))
        attempt += 1
    }

    mutating func cancel() { retryAt = nil }

    mutating func navigationStarted() {
        navigationFailed = false
        documentCommitted = false
        cancel()
    }

    mutating func navigationCommitted() {
        documentCommitted = true
        navigationFailed = false
    }

    mutating func navigationDidFail() { navigationFailed = true }

    mutating func verified() {
        navigationFailed = false
        cancel()
        attempt = 0
    }
}
