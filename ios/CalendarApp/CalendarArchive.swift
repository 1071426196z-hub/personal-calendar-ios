import Foundation

enum CalendarTransferError: LocalizedError {
    case invalidBackup, invalidCalendar, fileTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidBackup: "这份文件不是可恢复的日历备份。"
        case .invalidCalendar: "这份文件不是有效的 .ics 日历。"
        case .fileTooLarge: "文件超过 16 MB，无法导入。"
        }
    }
}

struct CalendarArchive: Codable {
    let version: Int
    let items: [CalendarItem]

    init(items: [CalendarItem]) {
        version = 1
        self.items = items.filter { !$0.isLinked && $0.sample != true }
    }

    static func read(_ data: Data) throws -> [CalendarItem] {
        guard let backup = try? JSONDecoder().decode(Self.self, from: data), backup.version == 1,
              Set(backup.items.map(\.id)).count == backup.items.count,
              backup.items.allSatisfy(Self.isValid) else { throw CalendarTransferError.invalidBackup }
        return backup.items
    }

    private static func isValid(_ item: CalendarItem) -> Bool {
        guard !item.isLinked, !item.id.isEmpty, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let day = CivilDay(item.date), day.supported else { return false }
        if let lunar = item.lunar, !(1...12).contains(lunar.month) || !(1...30).contains(lunar.day) { return false }
        if item.kind == .event {
            guard let endKey = item.endDate, let end = CivilDay(endKey), end.supported && end >= day else { return false }
            if item.allDay != true {
                guard let startTime = item.start, let endTime = item.end,
                      startTime.range(of: "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil,
                      endTime.range(of: "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil else { return false }
            }
        }
        if let start = item.startInstant, let end = item.endInstant, end <= start { return false }
        return (item.startInstant == nil) == (item.endInstant == nil)
    }
}
