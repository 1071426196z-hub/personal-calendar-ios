import Foundation

struct HolidaySchedule: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Sendable {
        let name: String
        let isOff: Bool
    }

    private(set) var years: [Int: [String: Day]] = [:]
    private(set) var generated = ""

    func day(on date: CivilDay) -> Day? {
        years[date.year + 1]?[date.key] ?? years[date.year]?[date.key] ?? years[date.year - 1]?[date.key]
    }

    func includes(_ year: Int) -> Bool { years[year] != nil }

    mutating func merge(_ update: HolidaySchedule) {
        guard update.generated >= generated else { return }
        years.merge(update.years) { _, newer in newer }
        generated = update.generated
    }

    init() {}

    init(feed: Data) throws {
        let payload = try JSONDecoder().decode(HolidayPayload.self, from: feed)
        guard payload.timeZone == "Asia/Shanghai", payload.generated.utf8.count == 16,
              payload.generated.range(of: "^[0-9]{8}T[0-9]{6}Z$", options: .regularExpression) != nil else {
            throw URLError(.cannotDecodeContentData)
        }
        generated = payload.generated
        for (key, holidays) in payload.years {
            guard let year = Int(key), (1901...2100).contains(year),
                  let days = Self.days(in: holidays, for: year) else { continue }
            years[year] = days
        }
        guard !years.isEmpty else { throw URLError(.cannotDecodeContentData) }
    }

    private static func days(in holidays: [HolidayPayload.Holiday], for year: Int) -> [String: Day]? {
        guard holidays.count >= 5 else { return nil }
        var days: [String: Day] = [:]
        for holiday in holidays {
            let name = holiday.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80,
                  let start = CivilDay(holiday.start), start.supported, abs(start.year - year) <= 1,
                  let end = CivilDay(holiday.end), end.supported, abs(end.year - year) <= 1 else { return nil }
            let length = start.distance(to: end) + 1
            guard (1...31).contains(length), holiday.compensatingDays.count <= 15 else { return nil }
            for offset in 0..<length { days[start.adding(offset).key] = Day(name: name, isOff: true) }
            for key in holiday.compensatingDays {
                guard let date = CivilDay(key), date.supported, abs(date.year - year) <= 1 else { return nil }
                days[key] = Day(name: name, isOff: false)
            }
        }
        return days
    }
}

private struct HolidayPayload: Decodable {
    struct Holiday: Decodable {
        let name: String
        let start: String
        let end: String
        let compensatingDays: [String]

        enum CodingKeys: String, CodingKey {
            case name = "Name", start = "StartDate", end = "EndDate", compensatingDays = "CompDays"
        }
    }

    let generated: String
    let timeZone: String
    let years: [String: [Holiday]]

    enum CodingKeys: String, CodingKey {
        case generated = "Generated", timeZone = "Timezone", years = "Years"
    }
}

struct HolidaySyncStatus: Equatable {
    enum Outcome: String, Codable { case updated, current, offline }
    let years: [Int]
    let generated: String
    let checkedAt: Date?
    let attemptedAt: Date?
    let source: String?
    let outcome: Outcome?
    // These years are bundled in dates.js; other years need a validated remote schedule.
    static let bundledYears = [2026, 2027]
    var coveredYears: [Int] { Array(Set(years + Self.bundledYears)).sorted() }
    var message: String {
        switch outcome {
        case .updated: return "已更新节假日安排"
        case .current: return "已检查，当前数据已是最新"
        case .offline: return "暂时无法获取更新，继续使用已保存的安排"
        case nil: return "正在使用内置安排，联网后自动检查更新"
        }
    }
}

actor HolidayFeed {
    static let shared = HolidayFeed()
    private static let storageKey = "china-holiday-schedule-v1"
    private static let urls = [
        URL(string: "https://cdn.jsdelivr.net/gh/lanceliao/china-holiday-calender@master/holidayAPI.json")!,
        URL(string: "https://raw.githubusercontent.com/lanceliao/china-holiday-calender/master/holidayAPI.json")!,
    ]

    private struct Cache: Codable {
        var schedule = HolidaySchedule()
        var checkedAt: Date?
        var attemptedAt: Date?
        var source: String?
        var outcome: HolidaySyncStatus.Outcome?

        var status: HolidaySyncStatus {
            HolidaySyncStatus(years: schedule.years.keys.sorted(), generated: schedule.generated,
                              checkedAt: checkedAt, attemptedAt: attemptedAt, source: source, outcome: outcome)
        }
    }

    private struct Download {
        let schedule: HolidaySchedule
        let source: String
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private let endpoints: [URL]
    private var cache: Cache
    private var lastAttempt: Date?
    private var inFlight: Task<Download?, Never>?
    private var inFlightID: UUID?

    init(defaults: UserDefaults = .standard, session: URLSession = .shared, endpoints: [URL]? = nil) {
        self.defaults = defaults
        self.session = session
        self.endpoints = endpoints ?? Self.urls
        cache = Self.readCache(in: defaults)
        lastAttempt = cache.attemptedAt
    }

    private static func readCache(in defaults: UserDefaults = .standard) -> Cache {
        guard let data = defaults.data(forKey: storageKey),
              let result = try? JSONDecoder().decode(Cache.self, from: data) else { return Cache() }
        return result
    }

    static func saved() -> HolidaySchedule { readCache().schedule }
    static func savedStatus() -> HolidaySyncStatus { readCache().status }
    func status() -> HolidaySyncStatus { cache.status }

    func refresh(force: Bool = false) async -> HolidaySchedule {
        if let inFlight, let id = inFlightID {
            let update = await inFlight.value
            complete(update, id: id)
            return cache.schedule
        }
        let now = Date.now
        if !force {
            if let checked = cache.checkedAt, (0..<86_400).contains(now.timeIntervalSince(checked)) { return cache.schedule }
            if let lastAttempt, (0..<3_600).contains(now.timeIntervalSince(lastAttempt)) { return cache.schedule }
        }
        lastAttempt = now
        cache.attemptedAt = now
        let oldest = cache.schedule.generated
        let session = self.session
        let endpoints = self.endpoints
        let request = Task { await Self.download(notOlderThan: oldest, session: session, endpoints: endpoints) }
        let id = UUID()
        inFlight = request
        inFlightID = id
        let update = await request.value
        complete(update, id: id)
        return cache.schedule
    }

    private func complete(_ update: Download?, id: UUID) {
        // Concurrent callers await the same task. Commit it once so the result stays accurate.
        guard inFlightID == id else { return }
        if let update {
            let previous = cache.schedule
            cache.schedule.merge(update.schedule)
            cache.checkedAt = .now
            cache.source = update.source
            cache.outcome = previous == cache.schedule ? .current : .updated
        } else {
            cache.outcome = .offline
        }
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: Self.storageKey)
        }
        inFlight = nil
        inFlightID = nil
    }

    private static func download(notOlderThan oldest: String, session: URLSession, endpoints: [URL]) async -> Download? {
        for url in endpoints {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 512_000,
                  let schedule = try? HolidaySchedule(feed: data), schedule.generated >= oldest else { continue }
            return Download(schedule: schedule, source: url.absoluteString)
        }
        return nil
    }
}
