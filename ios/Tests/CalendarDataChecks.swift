import Foundation

@main
enum CalendarDataChecks {
    static func main() throws {
        checkTimeZones()
        try checkHolidayFeed()
        print("Calendar time-zone and holiday data checks passed")
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
        let invalid = fixture(generated: "20261107T090000Z", winterBreak: "2027-02-30")
        precondition((try? HolidaySchedule(feed: invalid)) == nil)
    }
}
