import XCTest
@testable import Time_Clock_Bar

final class TimeclockObservationTests: XCTestCase {
    func testOverlapTimeoutAndLateResultAfterRecovery() throws {
        var observation = TimeclockObservation()
        let now = Date(timeIntervalSince1970: 1000)
        let old = try XCTUnwrap(observation.begin(at: now))
        XCTAssertNil(observation.begin(at: now.addingTimeInterval(1)))
        XCTAssertTrue(observation.isTimedOut(at: now.addingTimeInterval(10)))
        observation.invalidate()
        let new = try XCTUnwrap(observation.begin(at: now.addingTimeInterval(11)))
        XCTAssertFalse(observation.finish(old))
        XCTAssertEqual(observation.token, new)
        XCTAssertTrue(observation.finish(new))
    }

    func testUnverifiedReadPreservesLastKnownStateAndFreshness() {
        var observation = TimeclockObservation()
        let now = Date(timeIntervalSince1970: 1000)
        let timers = TimeclockTimers(current: "01:00:00", day: "02:00:00", week: "04:00:00", fallback: "01:00:00")
        XCTAssertTrue(observation.accept(.active("01:00:00"), timers: timers, at: now))
        XCTAssertFalse(observation.accept(.unknown(nil), timers: .empty, at: now.addingTimeInterval(10)))
        XCTAssertEqual(observation.lastState, .active("01:00:00"))
        XCTAssertEqual(observation.observedAt, now)
        XCTAssertEqual(observation.displayTimers(at: now.addingTimeInterval(5)).day, "02:00:05")
        XCTAssertEqual(observation.observedAt, now)
    }

    func testFrozenTimerCannotRemainFreshForever() {
        var observation = TimeclockObservation()
        let now = Date(timeIntervalSince1970: 1000)
        let timers = TimeclockTimers(current: "01:00", day: "01:00", week: "01:00", fallback: "01:00")
        XCTAssertTrue(observation.accept(.active("01:00"), timers: timers, at: now))
        XCTAssertFalse(observation.accept(.active("01:00"), timers: timers, at: now.addingTimeInterval(121)))
        XCTAssertEqual(observation.observedAt, now)
    }

    func testBreakDisplayTicksWithoutAddingWorkHours() {
        var observation = TimeclockObservation()
        let now = Date(timeIntervalSince1970: 1000)
        let timers = TimeclockTimers(current: "00:00:00", day: "03:00:00", week: "10:00:00", fallback: "00:59:58")
        XCTAssertTrue(observation.accept(.onBreak("00:59:58"), timers: timers, at: now))
        let displayed = observation.displayTimers(at: now.addingTimeInterval(5))
        XCTAssertEqual(displayed.fallback, "01:00:03")
        XCTAssertEqual(displayed.day, "03:00:00")
        XCTAssertEqual(observation.observedAt, now)
    }

    func testMinuteOnlyReadDoesNotResetTheEstimatedSeconds() {
        var observation = TimeclockObservation()
        let now = Date(timeIntervalSince1970: 1000)
        let timers = TimeclockTimers(current: "01:00", day: "03:00", week: "10:00", fallback: "01:00")
        XCTAssertTrue(observation.accept(.active("01:00"), timers: timers, at: now))
        XCTAssertTrue(observation.accept(.active("01:00"), timers: timers, at: now.addingTimeInterval(10)))
        XCTAssertEqual(observation.displayTimers(at: now.addingTimeInterval(11)).current, "01:00:11")
        XCTAssertEqual(observation.observedAt, now.addingTimeInterval(10))
    }

    func testShiftEndIndicatorAndDisabledBreakDuration() {
        XCTAssertEqual(TimeclockStatusIndicator.indicator(state: .active("07:00"), breakDurationMinutes: 60,
                                                          overtimeMinutes: 0, shiftEnded: true), .pastShiftEnd)
        XCTAssertEqual(TimeclockStatusIndicator.indicator(state: .onBreak("00:01"), breakDurationMinutes: 0,
                                                          overtimeMinutes: 0), .none)
    }
}
