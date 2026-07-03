import WebKit
import XCTest
@testable import Time_Clock_Bar

@MainActor
final class TimeclockDOMDetectorTests: XCTestCase {
    func testDictionaryParsingUsesDefaults() throws {
        XCTAssertNil(TimeclockDOMDetection(nil))

        let empty = try XCTUnwrap(TimeclockDOMDetection([:]))
        XCTAssertEqual(empty.state, "unknown")
        XCTAssertEqual(empty.timer, "")
        XCTAssertEqual(empty.currentTimer, "")
        XCTAssertEqual(empty.dayTimer, "")
        XCTAssertEqual(empty.weekTimer, "")

        let invalid = try XCTUnwrap(TimeclockDOMDetection([
            "state": 1,
            "timer": 2,
            "currentTimer": false,
            "dayTimer": [],
            "weekTimer": [:]
        ]))
        XCTAssertEqual(invalid.state, "unknown")
        XCTAssertEqual(invalid.timer, "")
        XCTAssertEqual(invalid.currentTimer, "")
        XCTAssertEqual(invalid.dayTimer, "")
        XCTAssertEqual(invalid.weekTimer, "")
    }

    func testDictionaryParsingPreservesStrings() throws {
        let detection = try XCTUnwrap(TimeclockDOMDetection([
            "state": "active",
            "timer": "9:00",
            "currentTimer": "0:30",
            "dayTimer": "7:00",
            "weekTimer": "31:00"
        ]))

        XCTAssertEqual(detection.state, "active")
        XCTAssertEqual(detection.timer, "9:00")
        XCTAssertEqual(detection.currentTimer, "0:30")
        XCTAssertEqual(detection.dayTimer, "7:00")
        XCTAssertEqual(detection.weekTimer, "31:00")
    }

    func testDetectsLoginRequired() async throws {
        let detection = try await detect(html: "<main><button>Sign in</button></main>")

        XCTAssertEqual(detection.state, "loginRequired")
    }

    func testDetectsClockedOut() async throws {
        let detection = try await detect(html: "<main><button>Clock In</button></main>")

        XCTAssertEqual(detection.state, "clockedOut")
    }

    func testDetectsActiveWithCurrentTimer() async throws {
        let detection = try await detect(html: "<main><button>Clock Out</button><p>Current 1:02</p></main>")

        XCTAssertEqual(detection.state, "active")
        XCTAssertEqual(detection.currentTimer, "1:02")
        XCTAssertEqual(detection.timer, "1:02")
    }

    func testDetectsBreakWithCurrentTimer() async throws {
        let detection = try await detect(html: "<main><button>End Break</button><p>Current 0:10</p></main>")

        XCTAssertEqual(detection.state, "onBreak")
        XCTAssertEqual(detection.currentTimer, "0:10")
    }

    func testDetectsMetricTimers() async throws {
        let detection = try await detect(html: "<main><p>Current 1:02</p><p>Day 7:30</p><p>Week 32:15</p><button>Clock Out</button></main>")

        XCTAssertEqual(detection.currentTimer, "1:02")
        XCTAssertEqual(detection.dayTimer, "7:30")
        XCTAssertEqual(detection.weekTimer, "32:15")
    }

    func testDetectsSidebarTimerAsActive() async throws {
        let detection = try await detect(html: """
        <aside>
            <h2>Time Clock</h2>
            <div><span>2:14</span></div>
        </aside>
        """)

        XCTAssertEqual(detection.state, "active")
        XCTAssertEqual(detection.timer, "2:14")
    }

    private func detect(html: String) async throws -> TimeclockDOMDetection {
        let webView = WKWebView()
        let delegate = NavigationWaiter()
        webView.navigationDelegate = delegate
        try await delegate.load(html: html, in: webView)

        let result = try await webView.evaluateJavaScript(TimeclockDOMDetector.detectionScript)
        return try XCTUnwrap(TimeclockDOMDetection(result as? [String: Any]))
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
