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

        waitFor(period, key: "value", toEqual: "2026年11月")
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()
        waitFor(period, key: "value", toEqual: "2026年12月")
        pager.swipeRight()
        waitFor(period, key: "value", toEqual: "2026年11月")
        app.buttons["下一月"].tap()
        waitFor(period, key: "value", toEqual: "2026年12月")
        app.buttons["上一月"].tap()
        waitFor(period, key: "value", toEqual: "2026年11月")

        modes.buttons["周"].tap()
        let timeline = app.scrollViews["calendar-week-timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        pager.swipeLeft()
        waitFor(selectedDate, key: "label", toEqual: "11月24日")
        timeline.swipeUp()
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
        let expectsValue = NSPredicate(format: "exists == true AND %K == %@", key, value)
        let expectation = XCTNSPredicateExpectation(predicate: expectsValue, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed,
                       "Expected \(key) to be \(value)", file: file, line: line)
    }
}
