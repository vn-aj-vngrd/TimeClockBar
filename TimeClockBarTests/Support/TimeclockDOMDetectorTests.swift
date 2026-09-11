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

    func testHiddenReadOpensOnlyClockDetailsAndDoesNotToggleAnOpenPanel() async throws {
        let webView = WKWebView()
        let delegate = NavigationWaiter()
        webView.navigationDelegate = delegate
        try await delegate.load(html: """
        <aside><button onclick="window.opens++;document.getElementById('details').hidden=false"><span>Time Clock</span><span>00:32</span></button></aside>
        <main id="details" hidden><span>Time Clock</span><span>Current</span><span>Day</span><span>Week</span>
          <div>You are on a break 00:32.23</div>
          <div class="group relative flex cursor-default"><div class="truncate">Taking a break</div>
            <span class="flex-1 truncate"><span class="truncate">8:09 PM</span><svg></svg><span class="truncate">Present</span></span>
          </div><button onclick="window.actions++">End Break</button>
        </main><button onclick="window.actions++">Clock In</button><button onclick="window.actions++">Clock Out</button>
        <script>window.opens=0;window.actions=0;</script>
        """, in: webView)
        let visibleRead = try await webView.evaluateJavaScript(TimeclockDOMDetector.readScript(revealClockPanel: false))
        XCTAssertEqual(TimeclockDOMDetection(visibleRead as? [String: Any])?.history.count, 0)
        for _ in 0..<2 {
            let result = try await webView.evaluateJavaScript(TimeclockDOMDetector.readScript(revealClockPanel: true))
            let detection = try XCTUnwrap(TimeclockDOMDetection(result as? [String: Any]))
            XCTAssertEqual(detection.state, "onBreak")
            XCTAssertEqual(detection.history.first?.start, "8:09 PM")
            _ = try await webView.evaluateJavaScript("delete window.__timeclockPanelRequestedAt")
        }
        let opens = try await webView.evaluateJavaScript("window.opens")
        let actions = try await webView.evaluateJavaScript("window.actions")
        XCTAssertEqual(opens as? Int, 1)
        XCTAssertEqual(actions as? Int, 0)
    }

    func testClockPanelOpeningProtectsInputAndDebouncesAsynchronousRendering() async throws {
        let webView = WKWebView()
        let delegate = NavigationWaiter()
        webView.navigationDelegate = delegate
        try await delegate.load(html: """
        <input id="draft"><button onclick="window.opens++"><span>Time Clock</span></button>
        <script>window.opens=0;</script>
        """, in: webView)
        _ = try await webView.evaluateJavaScript("document.getElementById('draft').focus()")
        _ = try await webView.evaluateJavaScript(TimeclockDOMDetector.readScript(revealClockPanel: true))
        var opens = try await webView.evaluateJavaScript("window.opens")
        XCTAssertEqual(opens as? Int, 0)
        _ = try await webView.evaluateJavaScript("document.activeElement.blur();window.__timeclockLastInput=Date.now()")
        _ = try await webView.evaluateJavaScript(TimeclockDOMDetector.readScript(revealClockPanel: true))
        opens = try await webView.evaluateJavaScript("window.opens")
        XCTAssertEqual(opens as? Int, 0)
        _ = try await webView.evaluateJavaScript("delete window.__timeclockLastInput")
        for _ in 0..<2 {
            _ = try await webView.evaluateJavaScript(TimeclockDOMDetector.readScript(revealClockPanel: true))
        }
        opens = try await webView.evaluateJavaScript("window.opens")
        XCTAssertEqual(opens as? Int, 1)
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

    func testFloatingBreakPanelUsesBreakElapsedInsteadOfZeroWorkTimer() async throws {
        // Mirrors the public component and reported screenshot: an unannotated break
        // counter with seconds in a span, followed by the separate Current work metric.
        let detection = try await detect(html: """
        <main><div>
          <span>Time Clock</span>
          <div><div><span>You are on a break</span></div>
            <div><div>00:05.<span>59</span></div></div>
          </div>
          <div style="display:flex">
            <div><span>Current</span><div>00:00.<span>00</span></div></div>
            <div><span>Day</span><div>05:30</div></div>
            <div><span>Week</span><div>46:42</div></div>
          </div>
          <div>Taking a break 8:09 PM → Present</div>
          <button id="end-break">End Break</button><button id="clock-out">Clock Out</button>
        </div></main>
        """)
        XCTAssertEqual(detection.state, "onBreak")
        XCTAssertEqual(detection.timer, "00:05.59")
        XCTAssertEqual(detection.currentTimer, "00:00.00")
        let state = TimeclockDOMDetector.state(from: detection)
        var observation = TimeclockObservation()
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(observation.accept(state, timers: TimeclockDOMDetector.timers(from: detection), at: now))
        let displayed = observation.displayTimers(at: now.addingTimeInterval(9))
        XCTAssertEqual(TimeclockMenuTitleFormatter.title(state: .onBreak(displayed.fallback), timers: displayed,
            components: [.status, .current], remainingTitle: "", showsLabels: false), "Break · 00:06:08")
        XCTAssertEqual(displayed.day, "05:30")
        XCTAssertEqual(displayed.week, "46:42")
    }

    func testMissingLabeledBreakTimerNeverUsesWorkCounterOrHistory() async throws {
        let detection = try await detect(html: """
        <main><span>You are on a break</span><div>--:--</div>
          <div class="timer">Current 00:00.00</div><p>Day 05:30</p>
          <p>Taking a break 8:09 PM → Present</p><button>End Break</button>
        </main>
        """)
        XCTAssertEqual(detection.timer, "")
        let state = TimeclockDOMDetector.state(from: detection)
        XCTAssertEqual(state, .onBreak(""))
        for component: TimeclockDisplayComponent in [.current, .day, .week] {
            XCTAssertEqual(TimeclockMenuTitleFormatter.title(state: state,
                timers: TimeclockDOMDetector.timers(from: detection), components: [.status, component],
                remainingTitle: "", showsLabels: false), "Break")
        }
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

    func testClockHistoryContainsRecordedTimesInsteadOfScheduledTimes() async throws {
        // Public time-log cards use a title div and separate start/end spans; the arrow is SVG.
        let detection = try await detect(html: """
        <main><span>Time Clock</span><div>You are on a break 00:32.23</div><p>Current 00:00.00</p>
          <div class="group relative flex cursor-default">
            <div class="truncate">Taking a break</div>
            <span class="flex-1 truncate"><div><span class="truncate">8:09 PM</span><svg></svg><span class="truncate">Present</span></div></span>
          </div>
          <div class="group relative flex cursor-default">
            <div class="truncate">Client name</div>
            <span class="flex-1 truncate"><div><span class="truncate">2:38 PM</span><svg></svg><span class="truncate">8:09 PM</span></div></span>
          </div>
          <button>End Break</button>
        </main>
        """)
        XCTAssertEqual(detection.history.count, 2)
        XCTAssertEqual(detection.history.first?.start, "8:09 PM")
        XCTAssertEqual(detection.history.last?.start, "2:38 PM")
        let zone = TimeZone(identifier: "Asia/Manila")!
        let now = ISO8601DateFormatter().date(from: "2026-09-11T12:42:00Z")!
        let schedule = WorkdaySchedule(timeZone: zone, weekdays: [2,3,4,5,6], startMinutes: 900,
            endMinutes: 0, breakMinutes: 1200, breakDuration: 60)
        let attendance = TimeclockAttendanceHistory.resolve(detection.history, timeZone: zone,
            shift: try XCTUnwrap(schedule.currentShift(at: now)), schedule: schedule, state: .onBreak("00:32.23"), now: now)
        XCTAssertEqual(attendance?.clockIn, ISO8601DateFormatter().date(from: "2026-09-11T06:38:00Z"))
        XCTAssertEqual(attendance?.breakStart, ISO8601DateFormatter().date(from: "2026-09-11T12:09:00Z"))
        XCTAssertNil(attendance?.clockOut)
    }

    func testIncidentalLoginTextDoesNotOverrideActiveControls() async throws {
        let value = try await detect(html: "<main><button>Clock Out</button><p>Current 01:02</p><footer>Last login yesterday</footer></main>")
        XCTAssertEqual(value.state, "active")
    }

    func testHistoryReadsLocalTimezonePairWithoutDuplicatingParentCards() async throws {
        let detection = try await detect(html: """
        <main><div class="group"><span>Time Clock</span><p>Current 00:05</p>
          <div class="group relative flex cursor-default">
            <div class="truncate">Client</div>
            <span class="flex-1 truncate">
              <div><span class="truncate">Sep 11, 2:38 PM</span><svg></svg><span class="truncate">Present</span><span>GMT+8</span></div>
              <div><span class="truncate">Sep 11, 7:38 AM</span><svg></svg><span class="truncate">Present</span><span>GMT+1</span></div>
            </span>
          </div><button>Clock Out</button>
        </div></main>
        """)
        XCTAssertEqual(detection.history.count, 1)
        XCTAssertEqual(detection.history.first?.start, "Sep 11, 7:38 AM")
        XCTAssertNotNil(detection.historyTimeZone)
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

    func testDisabledClockInWhileSessionLoadsDoesNotConfirmClockedOut() async throws {
        let value = try await detect(html: "<main><p>Current 00:00</p><button id='clock-in' disabled>Clock In</button></main>")
        XCTAssertEqual(value.state, "unknown")
    }

    func testDisabledAttendanceControlsDoNotConfirmWorkingOrBreak() async throws {
        let value = try await detect(html: "<main><button aria-disabled='true'>End Break</button><button disabled>Clock Out</button></main>")
        XCTAssertEqual(value.state, "unknown")
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
