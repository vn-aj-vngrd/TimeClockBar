import XCTest
@testable import Time_Clock_Bar

final class TimeclockTimeMathTests: XCTestCase {
    func testNormalizesMinutesIntoSingleDay() {
        XCTAssertEqual(TimeclockTimeMath.normalizedMinutes(-1), 1439)
        XCTAssertEqual(TimeclockTimeMath.normalizedMinutes(1440), 0)
        XCTAssertEqual(TimeclockTimeMath.normalizedMinutes(1500), 60)
    }

    func testClampsDurationMinutes() {
        XCTAssertEqual(TimeclockTimeMath.normalizedDurationMinutes(-1), 0)
        XCTAssertEqual(TimeclockTimeMath.normalizedDurationMinutes(60), 60)
        XCTAssertEqual(TimeclockTimeMath.normalizedDurationMinutes(1500), 1440)
    }

    func testParsesTimerMinutes() {
        XCTAssertEqual(TimeclockTimeMath.timerMinutes(from: "1:05"), 65)
        XCTAssertEqual(TimeclockTimeMath.timerMinutes(from: "1:05.30"), 65)
        XCTAssertNil(TimeclockTimeMath.timerMinutes(from: "bad"))
    }

    func testShiftDurationHandlesSameDayOvernightAndFullDay() {
        XCTAssertEqual(TimeclockTimeMath.shiftDurationMinutes(start: 9 * 60, end: 17 * 60), 480)
        XCTAssertEqual(TimeclockTimeMath.shiftDurationMinutes(start: 22 * 60, end: 6 * 60), 480)
        XCTAssertEqual(TimeclockTimeMath.shiftDurationMinutes(start: 0, end: 0), 1440)
    }

    func testRemainingWorkMinutesCanGoNegativeForOvertime() {
        XCTAssertEqual(TimeclockTimeMath.remainingWorkMinutes(dayMinutes: 6 * 60, start: 9 * 60, end: 17 * 60, breakDuration: 60), 60)
        XCTAssertEqual(TimeclockTimeMath.remainingWorkMinutes(dayMinutes: 7 * 60, start: 9 * 60, end: 17 * 60, breakDuration: 60), 0)
        XCTAssertEqual(TimeclockTimeMath.remainingWorkMinutes(dayMinutes: 8 * 60, start: 9 * 60, end: 17 * 60, breakDuration: 60), -60)
    }

    func testDurationLabels() {
        XCTAssertEqual(TimeclockTimeMath.durationLabel(minutes: 45), "45m")
        XCTAssertEqual(TimeclockTimeMath.durationLabel(minutes: 60), "1h")
        XCTAssertEqual(TimeclockTimeMath.durationLabel(minutes: 75), "1h 15m")
    }

    func testDayOffsetsAndWeekdayShifts() {
        XCTAssertEqual(TimeclockTimeMath.dayOffset(forMinutes: -15), -1)
        XCTAssertEqual(TimeclockTimeMath.dayOffset(forMinutes: 15), 0)
        XCTAssertEqual(TimeclockTimeMath.dayOffset(forMinutes: 1500), 1)
        XCTAssertEqual(TimeclockTimeMath.shiftedWeekday(1, byDays: -1), 7)
        XCTAssertEqual(TimeclockTimeMath.shiftedWeekday(7, byDays: 1), 1)
    }
}
