import XCTest
@testable import Time_Clock_Bar

final class TimeclockObservationLabelTests: XCTestCase {
    private let observed = ISO8601DateFormatter().date(from: "2026-09-11T05:48:12Z")!
    private let zone = TimeZone(identifier: "Asia/Manila")!

    private func label(_ state: TimeclockState = .clockedOut, refreshing: Bool = false,
                       elapsed: TimeInterval = 10, observedAt: Date? = nil) -> TimeclockObservationLabel {
        TimeclockObservationLabel.resolve(observedAt: observedAt ?? observed, state: state,
            isRefreshing: refreshing, connectionStatus: "Connection detail", now: observed.addingTimeInterval(elapsed),
            timeZone: zone, locale: Locale(identifier: "en_US"))
    }

    func testVisibleTimestampStaysFixedWhileHoverAgeChanges() {
        let first = label(elapsed: 5)
        let later = label(elapsed: 20)
        XCTAssertEqual(first.title, later.title)
        XCTAssertTrue(first.title.hasPrefix("Observed 1:48"))
        XCTAssertFalse(first.title.contains("ago"))
        XCTAssertTrue(first.help.contains("1:48:12"))
        XCTAssertTrue(first.help.contains("2026"))
        XCTAssertTrue(first.help.contains("Asia/Manila"))
        XCTAssertTrue(first.help.contains("5 seconds ago"))
        XCTAssertTrue(later.help.contains("20 seconds ago"))
        XCTAssertTrue(first.help.contains("Connection detail"))
    }

    func testRefreshFailureAndLoginPreserveTimestampWithoutClaimingFreshness() {
        let healthy = label()
        XCTAssertEqual(label(.stale, refreshing: true).title, "Refreshing · \(healthy.title)")
        for state: TimeclockState in [.stale, .unknown(nil), .loading] {
            XCTAssertEqual(label(state).title, "Update delayed · \(healthy.title)")
        }
        XCTAssertEqual(label(.loginRequired).title, "Sign in required · \(healthy.title)")
        XCTAssertEqual(label(.stale, refreshing: true, elapsed: 31).title, "Update delayed · \(healthy.title)")
        XCTAssertEqual(label(elapsed: -1).title, "Update delayed · \(healthy.title)")
    }

    func testMidnightShowsObservationDateAndSuccessfulReadAdvancesTime() {
        let tomorrow = label(elapsed: 12 * 3600)
        XCTAssertTrue(tomorrow.title.contains("Sep 11, 2026"))
        XCTAssertTrue(tomorrow.title.contains("1:48"))
        let updated = label(elapsed: 60, observedAt: observed.addingTimeInterval(60))
        XCTAssertTrue(updated.title.hasPrefix("Observed 1:49"))
    }

    func testNoObservationDoesNotInventTimestamp() {
        for state: TimeclockState in [.loading, .stale, .loginRequired] {
            let value = TimeclockObservationLabel.resolve(observedAt: nil, state: state, isRefreshing: false,
                connectionStatus: "Connection detail", now: observed, timeZone: zone)
            XCTAssertFalse(value.title.contains("Observed"))
            XCTAssertTrue(value.help.contains("No successful observation yet"))
        }
    }
}
