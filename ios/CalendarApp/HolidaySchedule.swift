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
    }

    private var cache = HolidayFeed.readCache()
    private var lastAttempt: Date?
    private var inFlight: Task<HolidaySchedule?, Never>?

    private static func readCache() -> Cache {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let result = try? JSONDecoder().decode(Cache.self, from: data) else { return Cache() }
        return result
    }

    static func saved() -> HolidaySchedule { readCache().schedule }

    func refresh() async -> HolidaySchedule {
        if let inFlight {
            // The caller that started the request merges and persists the result.
            guard let update = await inFlight.value else { return cache.schedule }
            var schedule = cache.schedule
            schedule.merge(update)
            return schedule
        }
        let now = Date.now
        if let checked = cache.checkedAt, (0..<86_400).contains(now.timeIntervalSince(checked)) { return cache.schedule }
        if let lastAttempt, (0..<3_600).contains(now.timeIntervalSince(lastAttempt)) { return cache.schedule }
        lastAttempt = now
        let oldest = cache.schedule.generated
        let request = Task { await Self.download(notOlderThan: oldest) }
        inFlight = request
        if let update = await request.value {
            cache.schedule.merge(update)
            cache.checkedAt = .now
            if let data = try? JSONEncoder().encode(cache) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
        inFlight = nil
        return cache.schedule
    }

    private static func download(notOlderThan oldest: String) async -> HolidaySchedule? {
        for url in urls {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 512_000,
                  let schedule = try? HolidaySchedule(feed: data), schedule.generated >= oldest else { continue }
            return schedule
        }
        return nil
    }
}
