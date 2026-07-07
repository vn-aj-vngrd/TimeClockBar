import XCTest
@testable import Time_Clock_Bar

final class TimeclockAppThemeTests: XCTestCase {
    func testSavedThemeFallsBackToSystem() {
        XCTAssertEqual(TimeclockAppTheme.saved(rawValue: nil), .system)
        XCTAssertEqual(TimeclockAppTheme.saved(rawValue: "unknown"), .system)
    }

    func testSavedThemeUsesKnownRawValue() {
        XCTAssertEqual(TimeclockAppTheme.saved(rawValue: "light"), .light)
        XCTAssertEqual(TimeclockAppTheme.saved(rawValue: "dark"), .dark)
    }
}
