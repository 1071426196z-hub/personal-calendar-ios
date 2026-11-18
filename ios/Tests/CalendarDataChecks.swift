import Foundation

@main
enum CalendarDataChecks {
    static func main() async throws {
        checkTimeZones()
        checkWeekStartsAndCacheInvalidation()
        try checkHolidayFeed()
        try await checkHolidayRefreshAndOfflineFallback()
        try checkBackupAndCalendarFiles()
        checkReminders()
        print("Calendar time-zone, grid cache, holiday, reminder and file checks passed")
    }

    private static func checkHolidayRefreshAndOfflineFallback() async throws {
        let suite = "calendar-feed-check-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HolidayFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let endpoint = URL(string: "https://calendar-fixture.invalid/holidays.json")!
        let feed = HolidayFeed(defaults: defaults, session: session, endpoints: [endpoint])
        HolidayFixtureProtocol.reset()
        async let first = feed.refresh(force: true)
        async let second = feed.refresh(force: true)
        let results = await (first, second)
        precondition(results.0 == results.1 && results.0.includes(2027))
        let downloaded = await feed.status()
        precondition(downloaded.outcome == .updated && downloaded.checkedAt != nil)
        precondition(HolidayFixtureProtocol.requestCount == 1)
        _ = await feed.refresh()
        precondition(HolidayFixtureProtocol.requestCount == 1, "Automatic refresh must respect the daily interval")
        _ = await feed.refresh(force: true)
        let unchanged = await feed.status()
        precondition(unchanged.outcome == .current && HolidayFixtureProtocol.requestCount == 2)

        HolidayFixtureProtocol.setOffline()
        let fallback = await feed.refresh(force: true)
        let failed = await feed.status()
        precondition(fallback == results.0 && failed.outcome == .offline)
        precondition(failed.checkedAt == unchanged.checkedAt, "Failure must not pretend a successful check")
        let reopened = HolidayFeed(defaults: defaults, session: session, endpoints: [endpoint])
        let restored = await reopened.status()
        precondition(restored.years == downloaded.years && restored.outcome == .offline)
    }

    private static func checkWeekStartsAndCacheInvalidation() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scripts = ["prototype/vendor/lunar-1.7.8.js", "prototype/dates.js", "ios/CalendarApp/NativeBridge.js"].map {
            root.appendingPathComponent($0)
        }
        let suite = "calendar-cache-check-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("[]".utf8), forKey: "personal-calendar-items-v1")
        let store = CalendarStore(defaults: defaults, engine: CalendarEngine(scriptURLs: scripts))
        let month = CivilDay(2026, 11, 17)
        let monday = store.monthCells(containing: month, weekStart: .monday)
        let sunday = store.monthCells(containing: month, weekStart: .sunday)
        precondition(monday.count == 42 && sunday.count == 42)
        precondition(monday.first?.day == CivilDay(2026, 10, 26))
        precondition(sunday.first?.day == CivilDay(2026, 11, 1))
        precondition(CalendarWeekStart.sunday.start(of: CivilDay(2027, 1, 1)) == CivilDay(2026, 12, 27))
        precondition(CalendarWeekStart.monday.start(of: CivilDay(2027, 1, 1)) == CivilDay(2026, 12, 28))

        // Warm a month, then edit its data: cached event dots must not survive changes.
        let revision = store.presentationRevision
        let item = CalendarItem(id: "cache-fixture", kind: .countdown, title: "Cache check", date: month.key)
        store.save(item)
        precondition(store.presentationRevision > revision)
        precondition(store.monthCells(containing: month, weekStart: .monday).first { $0.day == month }!.kinds.contains(.countdown))
        store.remove(item.id)
        precondition(!store.monthCells(containing: month, weekStart: .monday).first { $0.day == month }!.kinds.contains(.countdown))

        // Imported records and timezone conversion also affect date-cell presentation.
        let linked = CalendarItem(id: "linked-cache", kind: .event, title: "Imported", date: month.key,
                                  endDate: month.key, allDay: true, linkedSource: "Test")
        store.setLinkedItems([linked])
        precondition(store.monthCells(containing: month, weekStart: .sunday).first { $0.day == month }!.kinds.contains(.event))
        store.setLinkedItems([])
        precondition(!store.items(on: month).contains { $0.id == linked.id })

        // Exercise eviction, and switch the year layout without stale weekday offsets.
        for offset in 0..<24 { _ = store.monthCells(containing: month.movingMonths(offset), weekStart: .monday) }
        precondition(store.monthCells(containing: month, weekStart: .sunday).first?.day == CivilDay(2026, 11, 1))
        let leapFebruary = store.yearMonths(2028, weekStart: .monday)[1]
        precondition(leapFebruary.count == 29)
        let january = store.yearMonths(2027, weekStart: .sunday)[0]
        precondition(january.offset == 5 && january.count == 31)
    }

    private static func checkReminders() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let calendar = CivilDay.localCalendar(in: zone)
        let target = CivilDay(2027, 3, 14)
        let item = CalendarItem(kind: .anniversary, title: "Anniversary", date: target.key, annual: true, reminder: .oneDay)
        let reminder = item.reminderFireDate(on: target, in: calendar)!
        precondition(CivilDay.localDay(containing: reminder, in: zone) == target.adding(-1))
        precondition(CivilDay.timeKey(reminder, in: calendar) == "09:00")
        let event = CalendarItem(kind: .event, title: "Meeting", date: target.key, start: "09:30", end: "10:00",
                                 reminder: .tenMinutes)
        precondition(CivilDay.timeKey(event.reminderFireDate(on: target, in: calendar)!, in: calendar) == "09:20")
    }

    private static func checkBackupAndCalendarFiles() throws {
        let special = CalendarItem(id: "test-birthday", kind: .birthday, title: "Birthday", date: "2027-02-06",
                                   lunar: LunarRule(month: 1, day: 1, leap: false), note: "Note", reminder: .morning)
        let data = try JSONEncoder().encode(CalendarArchive(items: [special]))
        let restored = try CalendarArchive.read(data)
        precondition(restored == [special])

        let ics = Data("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:single-test
        DTSTART:20270101T233000Z
        DTEND:20270102T003000Z
        SUMMARY:跨日\\,日程
         标题
        DESCRIPTION:说明\\n备注
        END:VEVENT
        BEGIN:VEVENT
        UID:all-day-test
        DTSTART;VALUE=DATE:20270102
        DTEND;VALUE=DATE:20270105
        SUMMARY:全天日程
        END:VEVENT
        BEGIN:VEVENT
        UID:unsupported-test
        DTSTART;VALUE=DATE:20270101
        RRULE:FREQ=WEEKLY;COUNT=3
        END:VEVENT
        END:VCALENDAR
        """.utf8)
        let imported = try CalendarICS.read(ics, displayTimeZone: TimeZone(identifier: "Asia/Shanghai")!)
        precondition(imported.skipped == 1 && imported.items.count == 2)
        let timed = imported.items[0]
        precondition(timed.date == "2027-01-02" && timed.start == "07:30" && timed.title == "跨日,日程标题")
        precondition(timed.note == "说明\n备注" && timed.startInstant != nil && timed.calendarImportID == "single-test")
        let allDay = imported.items[1]
        precondition(allDay.allDay == true && allDay.endDate == "2027-01-04")
    }

    private static func checkTimeZones() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let start = CivilDay(2027, 1, 2).instant(at: "08:00", in: shanghai)!
        let end = CivilDay(2027, 1, 2).instant(at: "09:00", in: shanghai)!
        let item = CalendarItem(kind: .event, title: "Meeting", date: "2027-01-02", endDate: "2027-01-02",
                                start: "08:00", end: "09:00", repeatRule: RepeatRule.none,
                                startInstant: start, endInstant: end)
        let converted = item.localized(in: losAngeles)
        precondition(converted.date == "2027-01-01" && converted.endDate == "2027-01-01")
        precondition(converted.start == "16:00" && converted.end == "17:00")
        precondition(converted.localized(in: shanghai).start == "08:00")

        let gap = CivilDay(2027, 3, 14)
        precondition(gap.instant(at: "02:30", in: losAngeles) == nil)
        precondition(gap.instant(at: "03:30", in: losAngeles) != nil)

        let legacy = CalendarItem(kind: .event, title: "Legacy", date: "2027-01-02", start: "08:00", end: "09:00")
        precondition(legacy.localized(in: losAngeles).date == "2027-01-02")
        var repeating = item
        repeating.repeatRule = .weekly
        precondition(repeating.localized(in: losAngeles).start == "08:00")
    }

    private static func checkHolidayFeed() throws {
        func fixture(generated: String, winterBreak: String, invalidYear: Bool = false) -> Data {
            let partial = invalidYear ? ", \"2028\": []" : ""
            return Data("""
            {"Generated":"\(generated)","Timezone":"Asia/Shanghai","Years":{"2027":[
              {"Name":"元旦","StartDate":"\(winterBreak)","EndDate":"2027-01-02","CompDays":[]},
              {"Name":"春节","StartDate":"2027-02-05","EndDate":"2027-02-13","CompDays":["2027-01-31","2027-02-14"]},
              {"Name":"清明节","StartDate":"2027-04-03","EndDate":"2027-04-05","CompDays":[]},
              {"Name":"劳动节","StartDate":"2027-05-01","EndDate":"2027-05-05","CompDays":["2027-05-08"]},
              {"Name":"国庆节","StartDate":"2027-10-01","EndDate":"2027-10-07","CompDays":["2027-10-09"]}
            ]\(partial)}}
            """.utf8)
        }

        let original = try HolidaySchedule(feed: fixture(generated: "20261101T090000Z", winterBreak: "2027-01-01"))
        let update = try HolidaySchedule(feed: fixture(generated: "20261107T090000Z", winterBreak: "2026-12-31", invalidYear: true))
        var cached = original
        cached.merge(update)
        cached.merge(original)
        precondition(cached.day(on: CivilDay(2026, 12, 31))?.isOff == true)
        precondition(cached.day(on: CivilDay(2027, 1, 31))?.isOff == false)
        precondition(cached.day(on: CivilDay(2027, 2, 11))?.name == "春节")
        precondition(!cached.includes(2028))
        let status = HolidaySyncStatus(years: [2027, 2029], generated: cached.generated,
                                       checkedAt: .now, attemptedAt: .now, source: nil, outcome: .offline)
        precondition(status.coveredYears == [2026, 2027, 2029])
        precondition(!status.coveredYears.contains(2028))
        precondition(status.message.contains("已保存"))
        let invalid = fixture(generated: "20261107T090000Z", winterBreak: "2027-02-30")
        precondition((try? HolidaySchedule(feed: invalid)) == nil)
    }
}

private final class HolidayFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    private static var offline = false
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); defer { lock.unlock() }; count = 0; offline = false }
    static func setOffline() { lock.lock(); defer { lock.unlock() }; offline = true }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "calendar-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        let offline = Self.offline
        Self.lock.unlock()
        if offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let data = Data("""
        {"Generated":"20261118T090000Z","Timezone":"Asia/Shanghai","Years":{"2027":[
        {"Name":"元旦","StartDate":"2027-01-01","EndDate":"2027-01-03","CompDays":[]},
        {"Name":"春节","StartDate":"2027-02-05","EndDate":"2027-02-13","CompDays":[]},
        {"Name":"清明节","StartDate":"2027-04-03","EndDate":"2027-04-05","CompDays":[]},
        {"Name":"劳动节","StartDate":"2027-05-01","EndDate":"2027-05-05","CompDays":[]},
        {"Name":"国庆节","StartDate":"2027-10-01","EndDate":"2027-10-07","CompDays":[]}]}}
        """.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
