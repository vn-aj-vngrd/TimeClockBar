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

    func testDetectsBreakTimerBeforeCurrentMetric() async throws {
        let detection = try await detect(html: """
        <main>
            <button>End Break</button>
            <p data-testid="timer">0:25</p>
            <p>Current 00:00</p>
            <p>Day 05:13</p>
            <p>Week 13:24</p>
        </main>
        """)

        XCTAssertEqual(detection.state, "onBreak")
        XCTAssertEqual(detection.timer, "0:25")
        XCTAssertEqual(detection.currentTimer, "00:00")
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

    func testIncidentalLoginTextDoesNotOverrideActiveControls() async throws {
        let value = try await detect(html: "<main><button>Clock Out</button><p>Current 01:02</p><footer>Last login yesterday</footer></main>")
        XCTAssertEqual(value.state, "active")
    }

    func testHiddenLoginFormDoesNotOverrideAttendance() async throws {
        let value = try await detect(html: "<form hidden><input type='password'><button>Sign in</button></form><main><button>Clock Out</button></main>")
        XCTAssertEqual(value.state, "active")
    }

    func testResumeInUnrelatedTextIsNotABreak() async throws {
        let value = try await detect(html: "<main><button>Clock Out</button><p>Update your resume</p></main>")
        XCTAssertEqual(value.state, "active")
    }

    func testHistoryTimeIsNotAnAttendanceTimer() async throws {
        let value = try await detect(html: "<main><h1>Time Clock</h1><p>Meeting at 09:30</p></main>")
        XCTAssertEqual(value.state, "unknown")
        XCTAssertEqual(value.timer, "")
    }

    func testFloatingClockPanelWithSplitSecondsMatchesVisibleWorkState() async throws {
        // Public clock component structure: flex metrics, a separate seconds span, and stable action IDs.
        let value = try await detect(html: """
        <main>
          <div style="position:absolute;width:340px">
            <div><span>Time Clock</span></div>
            <div style="display:flex;justify-content:space-around">
              <div><span>Current</span><div style="display:flex"><div>02:55.</div><span>45</span></div></div>
              <div><span>Day</span><div>08:05</div></div>
              <div><span>Week</span><div>40:19</div></div>
            </div>
            <div>9:00 PM → Present</div><div>Took a break 8:00 PM → 9:00 PM</div>
            <button id="take-break">Take Break</button><button id="clock-out">Clock Out</button>
          </div>
          <section>Vacation Leave 80h 0m</section>
        </main>
        """)
        XCTAssertEqual(value.state, "active")
        XCTAssertEqual(value.currentTimer, "02:55.45")
        XCTAssertEqual(value.dayTimer, "08:05")
        XCTAssertEqual(value.weekTimer, "40:19")
    }

    func testClockRenderedAfterNavigationRecoversBeforeScheduledReload() async throws {
        let webView = WKWebView()
        let delegate = NavigationWaiter()
        webView.navigationDelegate = delegate
        try await delegate.load(html: "<main id='clock'>Loading clock…</main>", in: webView)
        let initial = try await webView.evaluateJavaScript(TimeclockDOMDetector.detectionScript)
        var value = try XCTUnwrap(TimeclockDOMDetection(initial as? [String: Any]))
        XCTAssertEqual(value.state, "unknown")
        var recovery = TimeclockPageRecovery()
        recovery.schedule(at: Date())
        // The website renders its controls asynchronously after the document finishes loading.
        _ = try await webView.evaluateJavaScript("document.getElementById('clock').innerHTML = '<p>Current 02:55.45</p><button>Take Break</button><button>Clock Out</button>'")
        if recovery.allowsRead(isLoading: webView.isLoading) {
            let rendered = try await webView.evaluateJavaScript(TimeclockDOMDetector.detectionScript)
            value = try XCTUnwrap(TimeclockDOMDetection(rendered as? [String: Any]))
        }
        XCTAssertEqual(value.state, "active")
        XCTAssertEqual(value.currentTimer, "02:55.45")
        var observation = TimeclockObservation()
        XCTAssertTrue(observation.accept(.active(value.currentTimer), timers: TimeclockDOMDetector.timers(from: value), at: Date()))
        recovery.verified()
        XCTAssertNil(recovery.retryAt)
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
