import XCTest

final class CalendarPagingTests: XCTestCase {
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
        app.buttons["2027年3月"].tap()
        waitFor(period, key: "value", toEqual: "2027年3月")
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
