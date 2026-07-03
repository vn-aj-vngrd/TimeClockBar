import XCTest
@testable import Time_Clock_Bar

final class TimeclockStateTests: XCTestCase {
    func testMenuBarAndHeaderTitles() {
        XCTAssertEqual(TimeclockState.loading.menuBarTitle, "Loading")
        XCTAssertEqual(TimeclockState.loading.headerTitle, "Loading Time Clock Bar")

        XCTAssertEqual(TimeclockState.loginRequired.menuBarTitle, "Login")
        XCTAssertEqual(TimeclockState.loginRequired.headerTitle, "Login required")

        XCTAssertEqual(TimeclockState.stale.menuBarTitle, "Stale")
        XCTAssertEqual(TimeclockState.stale.headerTitle, "Status stale")

        XCTAssertEqual(TimeclockState.clockedOut.menuBarTitle, "Out")
        XCTAssertEqual(TimeclockState.clockedOut.headerTitle, "Not active")

        XCTAssertEqual(TimeclockState.active("").menuBarTitle, "Active")
        XCTAssertEqual(TimeclockState.active("").headerTitle, "Active")
        XCTAssertEqual(TimeclockState.active("1:23").menuBarTitle, "Active 1:23")
        XCTAssertEqual(TimeclockState.active("1:23").headerTitle, "Active · 1:23")

        XCTAssertEqual(TimeclockState.onBreak("").menuBarTitle, "Break")
        XCTAssertEqual(TimeclockState.onBreak("").headerTitle, "On break")
        XCTAssertEqual(TimeclockState.onBreak("0:15").menuBarTitle, "Break 0:15")
        XCTAssertEqual(TimeclockState.onBreak("0:15").headerTitle, "On break · 0:15")

        XCTAssertEqual(TimeclockState.unknown(nil).menuBarTitle, "Unknown")
        XCTAssertEqual(TimeclockState.unknown(nil).headerTitle, "Unknown status")
    }
}
