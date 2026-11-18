import SwiftUI
import WidgetKit

struct CalendarWidgetEntry: TimelineEntry {
    let date: Date
    let day: CivilDay
    let lunar: String
    let label: String
    let almanac: String

    init(date: Date, engine: CalendarEngine? = nil, holidays: HolidaySchedule = HolidaySchedule(), showAlmanac: Bool = false) {
        self.date = date
        day = CivilDay.localDay(containing: date)
        let facts = day.supported ? engine?.facts(day)?.withHolidaySchedule(holidays, on: day) : nil
        lunar = facts?.lunarText ?? ""
        label = facts.map { facts in
            [facts.festival.isEmpty ? (facts.term ?? "") : facts.festival, facts.shiftText]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        } ?? ""
        let detail = showAlmanac && day.supported ? engine?.almanac(day) : nil
        almanac = detail.map { "宜 " + $0.yi.prefix(2).joined(separator: "、") + " · 忌 " + $0.ji.prefix(2).joined(separator: "、") } ?? ""
    }
}

struct CalendarWidgetFace: View {
    let entry: CalendarWidgetEntry
    let family: WidgetFamily
    var weekStart: CalendarWeekStart = .monday

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                HStack(spacing: 14) {
                    daySummary
                        .frame(width: 94, alignment: .leading)
                    MonthWidgetGrid(day: entry.day, expanded: false, weekStart: weekStart)
                }
            case .systemLarge:
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(entry.day.year)年\(entry.day.month)月")
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                        Text([entry.lunar, entry.label].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    MonthWidgetGrid(day: entry.day, expanded: true, weekStart: weekStart)
                }
            case .accessoryInline:
                Text([entry.lunar, entry.label].filter { !$0.isEmpty }.joined(separator: " · "))
                    .lineLimit(1)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.day.month)月\(entry.day.day)日 · \(entry.day.weekdayLabel)").font(.headline)
                    Text(entry.lunar).font(.caption)
                    Text(entry.almanac.isEmpty ? entry.label : entry.almanac).font(.caption2)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text("\(entry.day.month)月").font(.caption2)
                    Text(verbatim: String(entry.day.day)).font(.title2.bold()).monospacedDigit()
                    Text(entry.day.weekdayLabel).font(.system(size: 9))
                }
            default:
                daySummary
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: family == .systemSmall ? "personalglasscalendar://today" : "personalglasscalendar://month"))
    }

    private var daySummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(entry.day.month)月  \(entry.day.weekdayLabel)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(verbatim: String(entry.day.day))
                .font(.system(size: 51, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
                .widgetAccentable()
                .accessibilityLabel(entry.day.label)
            if !entry.lunar.isEmpty {
                Text(entry.lunar).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
            }
            if !entry.label.isEmpty {
                Text(entry.label).font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            if !entry.almanac.isEmpty {
                Text(entry.almanac).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

private struct MonthWidgetGrid: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let day: CivilDay
    let expanded: Bool
    let weekStart: CalendarWeekStart

    var body: some View {
        let start = day.monthStart
        let offset = weekStart.offset(of: start)
        let rowCount = (offset + start.daysInMonth + 6) / 7
        Grid(horizontalSpacing: 3, verticalSpacing: expanded ? 4 : 2) {
            GridRow {
                ForEach(weekStart.weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: expanded ? 13 : 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            ForEach(0..<rowCount, id: \.self) { row in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        let number = row * 7 + column - offset + 1
                        if (1...start.daysInMonth).contains(number) {
                            dateCell(number)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: expanded ? 25 : 15)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    private func dateCell(_ number: Int) -> some View {
        let selected = number == day.day
        let size: CGFloat = expanded ? 25 : 15
        return Text(verbatim: String(number))
            .font(.system(size: expanded ? 16 : 10, weight: selected ? .bold : .regular).monospacedDigit())
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .overlay {
                if selected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(renderingMode == .accented ? 0.85 : 0.65),
                                      lineWidth: expanded ? 1.1 : 0.8)
                        .accessibilityHidden(true)
                }
            }
            .widgetAccentable(selected)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(CivilDay(day.year, day.month, number).label)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DayCountWidgetFace: View {
    let title: String
    let icon: String
    let days: Int?
    let status: String
    let note: String
    let target: CivilDay?
    var family: WidgetFamily = .systemSmall

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("\(title) · \(countText)", systemImage: icon).lineLimit(1).privacySensitive()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: icon).font(.headline)
                    Text(countText).font(.subheadline.weight(.semibold)).monospacedDigit()
                    if !note.isEmpty { Text(note).font(.caption2) }
                }
                .lineLimit(1).minimumScaleFactor(0.7).privacySensitive()
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: icon).font(.caption2)
                    Text(days.map { String($0) } ?? "—").font(.title3.bold()).monospacedDigit()
                    Text(days == nil ? "待设置" : "天").font(.system(size: 9))
                }
                .lineLimit(1).minimumScaleFactor(0.6).privacySensitive()
                .accessibilityLabel("\(title)，\(countText)")
            default:
                homeContent
            }
        }
        .widgetURL(URL(string: target.map { "personalglasscalendar://day/\($0.key)" } ?? "personalglasscalendar://today"))
    }

    private var countText: String {
        guard let days else { return "长按编辑，设置日期" }
        return days == 0 ? "就是今天" : "\(status) \(days) 天"
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 3)
            if let days {
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if days > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: String(days))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .widgetAccentable()
                        Text("天").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .accessibilityElement(children: .combine)
                }
                Text(note).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Text("长按编辑，设置日期")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: target.map { "personalglasscalendar://day/\($0.key)" } ?? "personalglasscalendar://today"))
    }
}

