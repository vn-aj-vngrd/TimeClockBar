import XCTest
@testable import Time_Clock_Bar

final class TimeclockTimersTests: XCTestCase {
    func testEmptyTimersReturnEmptyValues() {
        XCTAssertEqual(TimeclockTimers.empty.value(for: .current), "")
        XCTAssertEqual(TimeclockTimers.empty.value(for: .day), "")
        XCTAssertEqual(TimeclockTimers.empty.value(for: .week), "")
        XCTAssertEqual(TimeclockTimers.empty.value(for: .status), "")
        XCTAssertEqual(TimeclockTimers.empty.value(for: .remaining), "")
    }

    func testTimerValuesUseDirectValuesBeforeFallback() {
        let timers = TimeclockTimers(current: "0:45", day: "6:15", week: "31:00", fallback: "9:99")

        XCTAssertEqual(timers.value(for: .current), "0:45")
        XCTAssertEqual(timers.value(for: .day), "6:15")
        XCTAssertEqual(timers.value(for: .week), "31:00")
    }

    func testTimerValuesFallBackWhenSpecificValueIsEmpty() {
        let timers = TimeclockTimers(current: "", day: "", week: "", fallback: "2:30")

        XCTAssertEqual(timers.value(for: .current), "2:30")
        XCTAssertEqual(timers.value(for: .day), "2:30")
        XCTAssertEqual(timers.value(for: .week), "2:30")
    }
}
