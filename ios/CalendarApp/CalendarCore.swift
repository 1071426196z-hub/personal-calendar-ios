import Foundation
import JavaScriptCore
import SwiftUI

struct CivilDay: Hashable, Comparable, Identifiable {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    static let first = CivilDay(1901, 1, 1)
    static let last = CivilDay(2100, 12, 31)
    static var today: Self { localDay(containing: Date()) }

    static func localCalendar(in timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func localDay(containing instant: Date) -> Self {
        localDay(containing: instant, in: .autoupdatingCurrent)
    }

    static func localDay(containing instant: Date, in timeZone: TimeZone) -> Self {
        let parts = localCalendar(in: timeZone).dateComponents([.year, .month, .day], from: instant)
        return Self(parts.year!, parts.month!, parts.day!)
    }

    static func timeKey(_ instant: Date, in calendar: Calendar) -> String {
        let time = calendar.dateComponents([.hour, .minute], from: instant)
        return String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0)
    }

    let date: Date
    var year: Int { Self.calendar.component(.year, from: date) }
    var month: Int { Self.calendar.component(.month, from: date) }
    var day: Int { Self.calendar.component(.day, from: date) }
    var weekday: Int { (Self.calendar.component(.weekday, from: date) + 5) % 7 }
    var monthStart: Self { Self(year, month, 1) }
    var weekStart: Self { adding(-weekday) }
    var daysInMonth: Int { Self.calendar.range(of: .day, in: .month, for: date)!.count }
    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var id: String { key }
    var label: String { "\(year)年\(month)月\(day)日" }
    var weekdayLabel: String { "星期" + Self.weekdays[weekday] }
    var supported: Bool { (Self.first...Self.last).contains(self) }
    static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    init(_ date: Date) { self.date = Self.calendar.startOfDay(for: date) }
    init(_ year: Int, _ month: Int, _ day: Int) {
        self.init(Self.calendar.date(from: DateComponents(year: year, month: month, day: day))!)
    }
    init?(_ key: String) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(parts[0], parts[1], parts[2])
        guard self.key == key else { return nil }
    }

    func adding(_ days: Int) -> Self {
        Self(Self.calendar.date(byAdding: .day, value: days, to: date)!)
    }

    func instant(at time: String, in timeZone: TimeZone) -> Date? {
        let calendar = Self.localCalendar(in: timeZone)
        let values = time.split(separator: ":").compactMap { Int($0) }
        guard values.count == 2, (0...23).contains(values[0]), (0...59).contains(values[1]) else { return nil }
        let requested = DateComponents(year: year, month: month, day: day, hour: values[0], minute: values[1])
        guard let result = calendar.date(from: requested),
              calendar.date(result, matchesComponents: requested) else { return nil }
        return result
    }
    func movingMonths(_ offset: Int) -> Self {
        let target = Self(Self.calendar.date(byAdding: .month, value: offset, to: monthStart.date)!)
        return Self(target.year, target.month, min(day, target.daysInMonth))
    }
    func distance(to other: Self) -> Int {
        Self.calendar.dateComponents([.day], from: date, to: other.date).day!
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.date < rhs.date }
}

enum EventKind: String, Codable, CaseIterable, Identifiable {
    case event, birthday, anniversary, countdown
    var id: Self { self }
    var label: String {
        switch self {
        case .event: return "日程"
        case .birthday: return "农历生日"
        case .anniversary: return "纪念日"
        case .countdown: return "倒数日"
        }
    }
    var icon: String {
        switch self {
        case .event: return "calendar"
        case .birthday: return "birthday.cake"
        case .anniversary: return "heart"
        case .countdown: return "hourglass"
        }
    }
    var color: Color {
        switch self {
        case .event: return .red
        case .birthday: return .orange
        case .anniversary: return .pink
        case .countdown: return .blue
        }
    }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly
    var id: Self { self }
    var label: String {
        switch self {
        case .none: return "不重复"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
}

struct LunarRule: Codable, Equatable {
    var month: Int
    var day: Int
    var leap: Bool
    static let months = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    static let days = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                       "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                       "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
    var label: String { (leap ? "闰" : "") + Self.months[month - 1] + Self.days[day - 1] }
}

struct CalendarItem: Codable, Identifiable {
    var id = UUID().uuidString
    var kind: EventKind
    var title: String
    var date: String
    var endDate: String? = nil
    var start: String? = nil
    var end: String? = nil
    var repeatRule: RepeatRule? = nil
    var allDay: Bool? = nil
    var annual: Bool? = nil
    var lunar: LunarRule? = nil
    var note: String = ""
    var sample: Bool? = nil
    var linkedSource: String? = nil
    var reminderTime: String? = nil
    var isSystemReminder: Bool? = nil
    var startInstant: Date? = nil
    var endInstant: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, kind, title, date, endDate, start, end, allDay, annual, lunar, note, sample
        case linkedSource, reminderTime, isSystemReminder, startInstant, endInstant
        case repeatRule = "repeat"
    }

    var isTimed: Bool { kind == .event && allDay != true && start != nil && end != nil }
    var icon: String { isSystemReminder == true ? "bell" : kind.icon }
    var displayKind: String { isSystemReminder == true ? "提醒事项" : kind.label }
    var isLinked: Bool { linkedSource != nil }

    func localized(in timeZone: TimeZone) -> Self {
        guard let startInstant, let endInstant, isTimed, repeatRule == RepeatRule.none else { return self }
        let calendar = CivilDay.localCalendar(in: timeZone)
        var item = self
        item.date = CivilDay.localDay(containing: startInstant, in: timeZone).key
        item.endDate = CivilDay.localDay(containing: endInstant, in: timeZone).key
        item.start = CivilDay.timeKey(startInstant, in: calendar)
        item.end = CivilDay.timeKey(endInstant, in: calendar)
        return item
    }
    var timeLabel: String {
        if isSystemReminder == true { return reminderTime ?? "当天到期" }
        guard kind == .event else { return "" }
        let range: String
        if let endDate, endDate != date, let from = CivilDay(date), let to = CivilDay(endDate) {
            range = "\(from.month)月\(from.day)日–\(to.month)月\(to.day)日"
        } else {
            range = ""
        }
        let hours = allDay == true ? "全天" : "\(start ?? "")–\(end ?? "")"
        return [range, hours].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var countdownLabel: String {
        guard let day = CivilDay(date) else { return "" }
        let delta = CivilDay.today.distance(to: day)
        if delta == 0 { return "就是今天" }
        return delta > 0 ? "还有 \(delta) 天" : "已过 \(-delta) 天"
    }
    var caption: String {
        let detail: String
        switch kind {
        case .event: detail = timeLabel
        case .countdown: detail = countdownLabel
        case .birthday, .anniversary: detail = lunar?.label ?? ""
        }
        return [displayKind, detail, linkedSource ?? "", sample == true ? "示例" : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct DayFacts: Decodable {
    let moon: LunarRule
    let lunarText: String
    let term: String?
    let festival: String
    let shift: String
    let shiftText: String
    let shortLabel: String

    func withHolidaySchedule(_ schedule: HolidaySchedule, on day: CivilDay) -> Self {
        let updated = schedule.day(on: day)
        guard updated != nil || schedule.includes(day.year) else { return self }
        let shift = updated.map { $0.isOff ? "休" : "班" } ?? ""
        let shiftText = updated.map { $0.isOff ? $0.name + "放假" : "调休上班" } ?? ""
        return Self(moon: moon, lunarText: lunarText, term: term, festival: festival,
                    shift: shift, shiftText: shiftText, shortLabel: shortLabel)
    }
}

struct AlmanacData: Decodable {
    let pillars: String
    let yi: [String]
    let ji: [String]
    let conflict: String
    let guardian: String
    let happiness: String
    let wealth: String
    let hours: [AlmanacHour]
}

struct AlmanacHour: Decodable, Identifiable {
    let branch: String
    let ganzhi: String
    let start: String
    let end: String
    let luck: String
    let yi: [String]
    let ji: [String]
    var id: String { start }
}

struct TimeSegment: Decodable {
    let from: Int
    let to: Int
}

final class CalendarEngine {
    private let context = JSContext()!
    private var dayCache: [CivilDay: DayFacts] = [:]
    private var almanacCache: [CivilDay: AlmanacData] = [:]

    init() {
        for name in ["lunar-1.7.8", "dates", "NativeBridge"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8) else {
                assertionFailure("Missing calendar resource: \(name)")
                continue
            }
            context.evaluateScript(script, withSourceURL: url)
        }
    }

    private func value<T: Decodable>(_ name: String, _ arguments: [Any]) -> T? {
        guard let encoded = context.objectForKeyedSubscript("NativeCalendar")?
            .invokeMethod(name, withArguments: arguments)?.toString(), encoded != "undefined" else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(encoded.utf8))
    }

    static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func facts(_ day: CivilDay) -> DayFacts? {
        if let facts = dayCache[day] { return facts }
        let facts: DayFacts? = value("dayInfo", [day.key])
        if dayCache.count >= 800 { dayCache.removeAll(keepingCapacity: true) }
        dayCache[day] = facts
        return facts
    }

    func lunarDay(year: Int, rule: LunarRule) -> CivilDay? {
        let key: String? = value("lunarDay", [year, rule.month, rule.day, rule.leap])
        return key.flatMap(CivilDay.init)
    }

    func nextLunar(rule: LunarRule, from: CivilDay) -> CivilDay? {
        let key: String? = value("nextLunarDay", [rule.month, rule.day, rule.leap, from.key])
        return key.flatMap(CivilDay.init)
    }

    func occurrences(_ records: String, on day: CivilDay) -> Set<String> {
        let ids: [String] = value("occurrences", [records, day.key]) ?? []
        return Set(ids)
    }

    func segments(_ item: CalendarItem, on day: CivilDay) -> [TimeSegment] {
        guard let data = Self.encode(item), item.isTimed else { return [] }
        return value("timedSegments", [data, day.key]) ?? []
    }

    func upcoming(_ item: CalendarItem, from day: CivilDay) -> CivilDay? {
        guard let data = Self.encode(item) else { return CivilDay(item.date) }
        let key: String? = value("upcoming", [data, day.key])
        return key.flatMap(CivilDay.init)
    }

    func almanac(_ day: CivilDay, includeHours: Bool = false) -> AlmanacData? {
        if let cached = almanacCache[day], !includeHours || !cached.hours.isEmpty { return cached }
        let result: AlmanacData? = value("almanac", [day.key, includeHours])
        if almanacCache.count >= 60 { almanacCache.removeAll(keepingCapacity: true) }
        almanacCache[day] = result
        return result
    }
}

final class CalendarStore: ObservableObject {
    @Published private(set) var items: [CalendarItem]
    @Published private(set) var linkedItems: [CalendarItem] = []
    @Published private(set) var timeZone = TimeZone.current
    @Published private(set) var holidays = HolidayFeed.saved()
    var allItems: [CalendarItem] { localItems + linkedItems }
    let engine = CalendarEngine()
    private let defaults: UserDefaults
    private let storageKey = "personal-calendar-items-v1"
    private var recordJSON = "[]"
    private var occurrenceCache: [CivilDay: [CalendarItem]] = [:]
    private var localItems: [CalendarItem] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([CalendarItem].self, from: data) {
            items = saved
        } else {
            items = []
            let today = CivilDay.today
            let birthday = today.adding(4)
            items = [
                CalendarItem(id: "demo-meeting", kind: .event, title: "项目周会", date: today.key,
                             endDate: today.key, start: "09:30", end: "10:30", repeatRule: RepeatRule.none,
                             note: "同步本周项目进度", sample: true),
                CalendarItem(id: "demo-dinner", kind: .event, title: "和朋友吃饭", date: today.key,
                             endDate: today.key, start: "18:30", end: "20:00", repeatRule: RepeatRule.none, sample: true),
                CalendarItem(id: "demo-anniversary", kind: .anniversary, title: "搬家纪念日", date: today.adding(1).key,
                             annual: true, sample: true),
                CalendarItem(id: "demo-birthday", kind: .birthday, title: "妈妈的生日", date: birthday.key,
                             lunar: engine.facts(birthday)?.moon, sample: true),
                CalendarItem(id: "demo-countdown", kind: .countdown, title: "周末旅行", date: today.adding(6).key,
                             sample: true)
            ]
        }
        rebuildOccurrences()
    }

    func facts(_ day: CivilDay) -> DayFacts? {
        engine.facts(day)?.withHolidaySchedule(holidays, on: day)
    }

    @discardableResult
    func setTimeZone(_ updated: TimeZone) -> Bool {
        guard updated.identifier != timeZone.identifier else { return false }
        timeZone = updated
        rebuildOccurrences()
        return true
    }

    @discardableResult
    func setHolidays(_ updated: HolidaySchedule) -> Bool {
        guard updated != holidays else { return false }
        holidays = updated
        return true
    }

    func items(on day: CivilDay) -> [CalendarItem] {
        if let list = occurrenceCache[day] { return list }
        let ids = engine.occurrences(recordJSON, on: day)
        let list = allItems.filter { ids.contains($0.id) }.sorted {
            ($0.isTimed ? 1 : 0, $0.start ?? "", $0.title) < ($1.isTimed ? 1 : 0, $1.start ?? "", $1.title)
        }
        if occurrenceCache.count >= 500 { occurrenceCache.removeAll(keepingCapacity: true) }
        occurrenceCache[day] = list
        return list
    }

    func save(_ item: CalendarItem) {
        guard !item.isLinked else { return }
        var updated = items
        if let index = updated.firstIndex(where: { $0.id == item.id }) {
            updated[index] = item
        } else {
            updated.append(item)
        }
        persist(updated)
    }

    func remove(_ id: String) {
        persist(items.filter { $0.id != id })
    }

    func setLinkedItems(_ incoming: [CalendarItem]) {
        linkedItems = incoming
        rebuildOccurrences()
    }

    private func persist(_ updated: [CalendarItem]) {
        guard let encoded = CalendarEngine.encode(updated) else { return }
        defaults.set(Data(encoded.utf8), forKey: storageKey)
        items = updated
        rebuildOccurrences()
    }

    private func rebuildOccurrences() {
        localItems = items.map { $0.localized(in: timeZone) }
        recordJSON = CalendarEngine.encode(allItems) ?? "[]"
        occurrenceCache.removeAll(keepingCapacity: true)
    }
}
