import XCTest
@testable import Time_Clock_Bar

final class TimeclockPageRecoveryTests: XCTestCase {
    func testRenderedClockCanBeReadWhileReloadIsPending() {
        var recovery = TimeclockPageRecovery()
        let loadedAt = Date(timeIntervalSince1970: 1000)
        recovery.navigationStarted()
        // Initial document has loaded, but the site's clock is rendered asynchronously.
        recovery.schedule(at: loadedAt)
        XCTAssertNotNil(recovery.retryAt)
        // A DOM-change callback must be allowed to see the clock before the reload fires.
        XCTAssertTrue(recovery.allowsRead(isLoading: false))
        recovery.verified()
        XCTAssertNil(recovery.retryAt)
    }

    func testFailedOrLoadingNavigationCannotReuseOldPage() {
        var recovery = TimeclockPageRecovery()
        XCTAssertFalse(recovery.allowsRead(isLoading: true))
        recovery.navigationDidFail()
        recovery.schedule(at: Date(timeIntervalSince1970: 1000))
        XCTAssertFalse(recovery.allowsRead(isLoading: false))
        recovery.navigationStarted()
        XCTAssertTrue(recovery.allowsRead(isLoading: false))
    }

    func testRepeatedUnknownReadKeepsDeadlineAndSuccessResetsBackoff() {
        var recovery = TimeclockPageRecovery()
        let now = Date(timeIntervalSince1970: 1000)
        for delay in [2.0, 5, 15, 60, 60] {
            recovery.schedule(at: now)
            XCTAssertEqual(recovery.retryAt, now.addingTimeInterval(delay))
            recovery.schedule(at: now.addingTimeInterval(1))
            XCTAssertEqual(recovery.retryAt, now.addingTimeInterval(delay))
            recovery.navigationStarted()
        }
        recovery.verified()
        recovery.schedule(at: now)
        XCTAssertEqual(recovery.retryAt, now.addingTimeInterval(2))
    }
}
