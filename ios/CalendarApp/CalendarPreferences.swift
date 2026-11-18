import Foundation
import SwiftUI

enum CalendarPreferences {
    static let appearanceKey = "calendar-appearance"
    static let weekStartKey = "calendar-week-start"
    static let showAlmanacKey = "calendar-show-almanac"
}

enum CalendarAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum CalendarWeekStart: Int, CaseIterable, Identifiable, Codable {
    case monday = 0, sunday = 6
    var id: Int { rawValue }
    var label: String { self == .monday ? "周一" : "周日" }
    var weekdays: [String] { (0..<7).map { CivilDay.weekdays[($0 + rawValue) % 7] } }
    func offset(of day: CivilDay) -> Int { (day.weekday - rawValue + 7) % 7 }
    func start(of day: CivilDay) -> CivilDay { day.adding(-offset(of: day)) }
    var calendar: Calendar {
        var result = CivilDay.calendar
        result.firstWeekday = self == .monday ? 2 : 1
        return result
    }
}
