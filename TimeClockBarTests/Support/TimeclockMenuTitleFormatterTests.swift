import XCTest
@testable import Time_Clock_Bar

final class TimeclockMenuTitleFormatterTests: XCTestCase {
    private let timers = TimeclockTimers(current: "0:30", day: "7:15", week: "32:00", fallback: "9:00")

    func testStaleStateAlwaysWins() {
        XCTAssertEqual(
            TimeclockMenuTitleFormatter.title(
                state: .stale,
                timers: timers,
                components: [.status, .day, .remaining],
                remainingTitle: "Today 45m left",
                showsLabels: true
            ),
            "Stale"
        )
    }

    func testEmptyComponentsFallBackToStateTitle() {
        XCTAssertEqual(
            TimeclockMenuTitleFormatter.title(
                state: .active("0:30"),
                timers: .empty,
                components: [],
                remainingTitle: "",
                showsLabels: false
            ),
            "Active 0:30"
        )
    }

    func testSingleTimerComponentUsesFallback() {
        XCTAssertEqual(
            TimeclockMenuTitleFormatter.title(
                state: .active("9:00"),
                timers: TimeclockTimers(current: "", day: "", week: "", fallback: "9:00"),
                components: [.day],
                remainingTitle: "",
                showsLabels: false
            ),
            "9:00"
        )
    }

    func testMultipleTimerComponentsDoNotUseFallbackForMissingSpecificValues() {
        XCTAssertEqual(
            TimeclockMenuTitleFormatter.title(
                state: .active("9:00"),
                timers: TimeclockTimers(current: "0:20", day: "", week: "12:00", fallback: "9:00"),
                components: [.current, .day, .week],
                remainingTitle: "",
                showsLabels: false
            ),
            "0:20 · 12:00"
        )
    }

    func testComponentOrderFollowsDisplayComponentOrder() {
        XCTAssertEqual(
            TimeclockMenuTitleFormatter.title(
                state: .active("0:30"),
                timers: timers,
                components: [.week, .status, .day, .current],
                remainingTitle: "",
                showsLabels: false
            ),
            "Active · 0:30 · 7:15 · 32:00"
        )
    }

    func testLabelsCanBeIncluded() {
        XCTAssertEqual(
            TimeclockMenuTitleFormatter.title(
                state: .onBreak("0:10"),
                timers: timers,
                components: [.status, .current, .day, .week, .remaining],
                remainingTitle: "Today 45m left",
                showsLabels: true
            ),
            "Break · Current 0:30 · Day 7:15 · Week 32:00 · Remaining Today 45m left"
        )
    }

    func testRemainingIsOmittedWhenEmpty() {
        XCTAssertEqual(
            TimeclockMenuTitleFormatter.title(
                state: .active("0:30"),
                timers: timers,
                components: [.remaining],
                remainingTitle: "",
                showsLabels: true
            ),
            "Active 0:30"
        )
    }
}
