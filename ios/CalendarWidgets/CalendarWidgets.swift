import AppIntents
import SwiftUI
import WidgetKit

private extension View {
    func calendarWidgetSurface() -> some View {
        containerBackground(.ultraThinMaterial, for: .widget)
    }
}

private struct CalendarWidgetEntry: TimelineEntry {
    let date: Date
    let day: CivilDay
    let lunar: String
    let label: String

    init(date: Date, engine: CalendarEngine? = nil, holidays: HolidaySchedule = HolidaySchedule()) {
        self.date = date
        day = CivilDay.localDay(containing: date)
        let facts = day.supported ? engine?.facts(day)?.withHolidaySchedule(holidays, on: day) : nil
        lunar = facts?.lunarText ?? ""
        label = facts.map { facts in
            [facts.festival.isEmpty ? (facts.term ?? "") : facts.festival, facts.shiftText]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        } ?? ""
    }
}

private struct CalendarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarWidgetEntry { CalendarWidgetEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (CalendarWidgetEntry) -> Void) {
        completion(CalendarWidgetEntry(date: .now, engine: CalendarEngine(), holidays: HolidayFeed.saved()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarWidgetEntry>) -> Void) {
        Task {
            let holidays = await HolidayFeed.shared.refresh()
            let engine = CalendarEngine()
            let entries = widgetDates().prefix(2).map { CalendarWidgetEntry(date: $0, engine: engine, holidays: holidays) }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

private func widgetDates() -> [Date] {
    let now = Date()
    let calendar = CivilDay.localCalendar()
    let midnight = calendar.startOfDay(for: now)
    return [now] + (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: midnight) }
}

private struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                HStack(spacing: 14) {
                    daySummary
                        .frame(width: 94, alignment: .leading)
                    MonthWidgetGrid(day: entry.day, expanded: false)
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
                    MonthWidgetGrid(day: entry.day, expanded: true)
                }
            default:
                daySummary
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .calendarWidgetSurface()
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
        }
    }
}

private struct MonthWidgetGrid: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let day: CivilDay
    let expanded: Bool

    var body: some View {
        let start = day.monthStart
        let rowCount = (start.weekday + start.daysInMonth + 6) / 7
        Grid(horizontalSpacing: 3, verticalSpacing: expanded ? 4 : 2) {
            GridRow {
                ForEach(CivilDay.weekdays, id: \.self) { weekday in
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
                        let number = row * 7 + column - start.weekday + 1
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

private struct TodayAndMonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PersonalCalendar.TodayAndMonth", provider: CalendarWidgetProvider()) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("日历")
        .description("查看今日农历、节日或整月日期。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(true)
    }
}

struct CountdownWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "设置倒数日"
    static let description = IntentDescription("长按小组件可修改标题和目标日期。")

    @Parameter(title: "标题", default: "倒数日")
    var label: String

    @Parameter(title: "目标日期")
    var target: Date?
}

private struct CountdownWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: CountdownWidgetIntent

    var target: CivilDay? { configuration.target.map(CivilDay.localDay) }
    var days: Int? { target.map { CivilDay.localDay(containing: date).distance(to: $0) } }
}

private struct CountdownWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountdownWidgetEntry {
        var configuration = CountdownWidgetIntent()
        configuration.target = Calendar.current.date(byAdding: .day, value: 7, to: .now)
        return CountdownWidgetEntry(date: .now, configuration: configuration)
    }

    func snapshot(for configuration: CountdownWidgetIntent, in context: Context) async -> CountdownWidgetEntry {
        if context.isPreview, configuration.target == nil { return placeholder(in: context) }
        return CountdownWidgetEntry(date: .now, configuration: configuration)
    }

    func timeline(for configuration: CountdownWidgetIntent, in context: Context) async -> Timeline<CountdownWidgetEntry> {
        Timeline(entries: widgetDates().map { CountdownWidgetEntry(date: $0, configuration: configuration) }, policy: .atEnd)
    }
}

private struct CountdownWidgetView: View {
    let entry: CountdownWidgetEntry

    var body: some View {
        DayCountWidgetFace(
            title: entry.configuration.label,
            icon: "hourglass",
            days: entry.days.map { abs($0) },
            status: entry.days.map { $0 == 0 ? "就是今天" : ($0 > 0 ? "还有" : "已过") } ?? "",
            note: entry.target?.label ?? "",
            target: entry.target
        )
    }
}

private struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PersonalCalendar.Countdown", intent: CountdownWidgetIntent.self,
                               provider: CountdownWidgetProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("倒数日")
        .description("在桌面查看自选日期还有几天。")
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable(true)
    }
}

struct AnniversaryWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "设置纪念日"
    static let description = IntentDescription("设置名称和纪念日期，并查看下次周年。")

    @Parameter(title: "名称", default: "纪念日")
    var label: String

    @Parameter(title: "纪念日期")
    var target: Date?

    @Parameter(title: "显示下次周年", default: true)
    var showNextAnniversary: Bool
}

private struct AnniversaryWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: AnniversaryWidgetIntent

    var target: CivilDay? { configuration.target.map(CivilDay.localDay) }

    var elapsed: Int? {
        target.map { $0.distance(to: CivilDay.localDay(containing: date)) }
    }

    var note: String {
        guard let target else { return "" }
        let today = CivilDay.localDay(containing: date)
        guard configuration.showNextAnniversary, today > target else { return target.label }
        let years = today.year - target.year
        let thisYear = target.movingMonths(years * 12)
        if thisYear == today { return "今天是第 \(years) 个周年" }
        let next = thisYear < today ? target.movingMonths((years + 1) * 12) : thisYear
        return "下次周年还有 \(today.distance(to: next)) 天"
    }
}

private struct AnniversaryWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AnniversaryWidgetEntry {
        var configuration = AnniversaryWidgetIntent()
        configuration.target = Calendar.current.date(byAdding: .day, value: -268, to: .now)
        return AnniversaryWidgetEntry(date: .now, configuration: configuration)
    }

    func snapshot(for configuration: AnniversaryWidgetIntent, in context: Context) async -> AnniversaryWidgetEntry {
        if context.isPreview, configuration.target == nil { return placeholder(in: context) }
        return AnniversaryWidgetEntry(date: .now, configuration: configuration)
    }

    func timeline(for configuration: AnniversaryWidgetIntent, in context: Context) async -> Timeline<AnniversaryWidgetEntry> {
        Timeline(entries: widgetDates().map { AnniversaryWidgetEntry(date: $0, configuration: configuration) }, policy: .atEnd)
    }
}

private struct AnniversaryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PersonalCalendar.Anniversary", intent: AnniversaryWidgetIntent.self,
                               provider: AnniversaryWidgetProvider()) { entry in
            DayCountWidgetFace(
                title: entry.configuration.label,
                icon: "heart",
                days: entry.elapsed.map { abs($0) },
                status: entry.elapsed.map { $0 == 0 ? "就是今天" : ($0 > 0 ? "已经过去" : "距纪念日") } ?? "",
                note: entry.note,
                target: entry.target
            )
        }
        .configurationDisplayName("纪念日")
        .description("查看纪念日已经过去的天数和下次周年。")
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable(true)
    }
}

private struct DayCountWidgetFace: View {
    let title: String
    let icon: String
    let days: Int?
    let status: String
    let note: String
    let target: CivilDay?

    var body: some View {
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
        .calendarWidgetSurface()
        .widgetURL(URL(string: target.map { "personalglasscalendar://day/\($0.key)" } ?? "personalglasscalendar://today"))
    }
}

@main
struct PersonalCalendarWidgets: WidgetBundle {
    var body: some Widget {
        TodayAndMonthWidget()
        CountdownWidget()
        AnniversaryWidget()
    }
}
