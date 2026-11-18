import XCTest

final class CalendarPagingTests: XCTestCase {
    func testSettingsAndSharedWidgetPreviews() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--verify-calendar-paging"]
        app.launch()
        let settings = app.buttons["calendar-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))
        app.segmentedControls["calendar-appearance"].buttons["深色"].tap()
        attach(app, name: "1.6-Dark-Settings")
        app.segmentedControls["calendar-week-start"].buttons["周日"].tap()
        app.switches["calendar-show-almanac"].tap()
        app.navigationBars["设置"].buttons["完成"].tap()
        XCTAssertFalse(app.buttons["calendar-almanac-summary"].exists)
        app.segmentedControls["calendar-mode"].buttons["周"].tap()
        XCTAssertTrue(app.scrollViews["calendar-week-timeline-2026-11-15"].waitForExistence(timeout: 8))
        app.scrollViews["calendar-pager"].swipeLeft()
        waitFor(app.staticTexts["calendar-selected-date"], key: "label", toEqual: "11月24日")
        XCTAssertTrue(app.scrollViews["calendar-week-timeline-2026-11-22"].exists)
        attach(app, name: "1.6-Sunday-Week")

        settings.tap()
        let preview = app.buttons["calendar-widget-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        preview.tap()
        XCTAssertTrue(app.navigationBars["小组件预览"].waitForExistence(timeout: 8))
        let sizes = app.segmentedControls["widget-preview-size"]
        sizes.buttons["中"].tap()
        attach(app, name: "1.6-Medium-Widget-Preview")
        sizes.buttons["大"].tap()
        attach(app, name: "1.6-Large-Widget-Preview")
        app.segmentedControls["widget-preview-kind"].buttons["纪念日"].tap()
        XCTAssertTrue(app.textFields["widget-preview-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["widget-preview-title"].value as? String, "相识纪念日")
        attach(app, name: "1.6-Anniversary-Lock-Widgets")
        app.segmentedControls["widget-preview-kind"].buttons["倒数日"].tap()
        XCTAssertEqual(app.textFields["widget-preview-title"].value as? String, "旅行出发")
    }

    func testCancelledSwipeAndFastReversePaging() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--verify-calendar-paging"]
        app.launch()
        let pager = app.scrollViews["calendar-pager"]
        let period = app.buttons["calendar-period"]
        XCTAssertTrue(pager.waitForExistence(timeout: 30))
        let start = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.45))
        let end = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.45))
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        waitFor(period, key: "value", toEqual: "2026年11月")
        pager.swipeLeft(velocity: .fast)
        waitFor(period, key: "value", toEqual: "2026年12月")
        pager.swipeRight(velocity: .fast)
        waitFor(period, key: "value", toEqual: "2026年11月")
        pager.swipeRight(velocity: .fast)
        waitFor(period, key: "value", toEqual: "2026年10月")
        pager.swipeLeft(velocity: .fast)
        waitFor(period, key: "value", toEqual: "2026年11月")
    }

    func testMonthScrollPerformance() {
        let app = XCUIApplication()
        app.launchArguments = ["--verify-calendar-paging"]
        app.launch()
        let pager = app.scrollViews["calendar-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 30))
        // Warm both neighboring pages before measuring steady-state interaction.
        pager.swipeLeft()
        pager.swipeRight()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app),
                          XCTMemoryMetric(application: app)], options: options) {
            pager.swipeLeft(velocity: .fast)
            pager.swipeRight(velocity: .fast)
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCalendarPagingAndWeeklyTimeline() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--verify-calendar-paging"]
        app.launch()

        let pager = app.scrollViews["calendar-pager"]
        let period = app.buttons["calendar-period"]
        let selectedDate = app.staticTexts["calendar-selected-date"]
        let modes = app.segmentedControls["calendar-mode"]

        XCTAssertTrue(period.waitForExistence(timeout: 30))
        waitFor(period, key: "value", toEqual: "2026年11月")
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeRight()
        waitFor(period, key: "value", toEqual: "2026年10月")
        waitFor(selectedDate, key: "label", toEqual: "10月17日")
        app.buttons["下一月"].tap()
        waitFor(period, key: "value", toEqual: "2026年11月")

        modes.buttons["周"].tap()
        XCTAssertTrue(app.scrollViews["calendar-week-timeline-2026-11-16"].waitForExistence(timeout: 5))
        pager.swipeLeft()
        waitFor(selectedDate, key: "label", toEqual: "11月24日")
        let timeline = app.scrollViews["calendar-week-timeline-2026-11-23"]
        let firstHour = timeline.staticTexts["08:00"]
        XCTAssertTrue(firstHour.isHittable)
        timeline.swipeUp()
        XCTAssertFalse(firstHour.isHittable)
        waitFor(selectedDate, key: "label", toEqual: "11月24日")

        modes.buttons["年"].tap()
        waitFor(period, key: "value", toEqual: "2026年")
        pager.swipeLeft()
        waitFor(period, key: "value", toEqual: "2027年")
        app.buttons["calendar-year-month-2027-3"].tap()
        waitFor(period, key: "value", toEqual: "2027年3月")

        app.buttons["upcoming-agenda"].tap()
        XCTAssertTrue(app.navigationBars["接下来"].waitForExistence(timeout: 8))
        app.navigationBars["接下来"].buttons["完成"].tap()
        app.buttons["导入与同步"].tap()
        XCTAssertTrue(app.buttons["calendar-backup"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["xiaomi-calendar-source"].exists)
    }

    private func waitFor(_ element: XCUIElement, key: String, toEqual value: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(20)
        var actual: String?
        repeat {
            actual = key == "value" ? element.value as? String : element.label
            if actual == value { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        XCTAssertEqual(actual, value, file: file, line: line)
    }
}
