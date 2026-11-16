import AppIntents
import SwiftUI
import WidgetKit

private enum WidgetStyle {
    static let accent = Color(red: 0.88, green: 0.19, blue: 0.22)
}

private struct WidgetGlass: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            scheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.18) : Color(red: 0.96, green: 0.97, blue: 1)
            RadialGradient(colors: [Color(red: 0.48, green: 0.64, blue: 1).opacity(scheme == .dark ? 0.38 : 0.32), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 150)
            RadialGradient(colors: [Color(red: 1, green: 0.42, blue: 0.59).opacity(scheme == .dark ? 0.25 : 0.24), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 120)
            RadialGradient(colors: [Color(red: 0.40, green: 0.90, blue: 0.81).opacity(scheme == .dark ? 0.19 : 0.29), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 140)
        }
    }
}

private struct CalendarWidgetEntry: TimelineEntry {
    let date: Date
    let day: CivilDay
    let lunar: String
    let label: String

    init(date: Date, engine: CalendarEngine? = nil) {
        self.date = date
        day = CivilDay.localDay(containing: date)
        let facts = day.supported ? engine?.facts(day) : nil
        lunar = facts?.lunarText ?? ""
        label = facts.flatMap { $0.festival.isEmpty ? $0.term : $0.festival } ?? ""
    }
}

private struct CalendarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarWidgetEntry { CalendarWidgetEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (CalendarWidgetEntry) -> Void) {
        completion(CalendarWidgetEntry(date: .now, engine: CalendarEngine()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarWidgetEntry>) -> Void) {
        let engine = CalendarEngine()
        let entries = widgetDates().map { CalendarWidgetEntry(date: $0, engine: engine) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private func widgetDates() -> [Date] {
    let now = Date()
    let calendar = Calendar(identifier: .gregorian)
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
                HStack(spacing: 15) {
                    daySummary
                        .frame(width: 88, alignment: .leading)
                    Divider().opacity(0.48)
                    MonthWidgetGrid(day: entry.day, expanded: false)
                }
            case .systemLarge:
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: "\(entry.day.year)年\(entry.day.month)月")
                            .font(.title2.bold())
                        Spacer()
                        Text(entry.lunar)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    MonthWidgetGrid(day: entry.day, expanded: true)
                    if !entry.label.isEmpty {
                        Text(entry.label).font(.subheadline.weight(.semibold)).foregroundStyle(WidgetStyle.accent)
                            .widgetAccentable()
                    }
                }
            default:
                daySummary
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { WidgetGlass() }
        .widgetURL(URL(string: family == .systemSmall ? "personalglasscalendar://today" : "personalglasscalendar://month"))
    }

    private var daySummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: "\(entry.day.month)月 · \(entry.day.weekdayLabel)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(verbatim: String(entry.day.day))
                .font(.system(size: 55, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.accent)
                .widgetAccentable()
                .accessibilityLabel(entry.day.label)
            if !entry.lunar.isEmpty {
                Text(entry.lunar).font(.caption.weight(.medium)).lineLimit(1)
            }
            if !entry.label.isEmpty {
                Text(entry.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct MonthWidgetGrid: View {
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
            .font(.system(size: expanded ? 16 : 10, weight: selected ? .bold : .medium).monospacedDigit())
            .foregroundStyle(selected ? WidgetStyle.accent : Color.primary)
            .frame(width: size, height: size)
            .background(selected ? WidgetStyle.accent.opacity(0.18) : .clear, in: Circle())
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
        VStack(alignment: .leading, spacing: 5) {
            Label(entry.configuration.label, systemImage: "hourglass")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 2)
            if let target = entry.target, let days = entry.days {
                Text(days == 0 ? "就是今天" : (days > 0 ? "还有" : "已过"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if days != 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: String(abs(days)))
                            .font(.system(size: 39, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .widgetAccentable()
                        Text("天").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(WidgetStyle.accent)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                }
                Text(target.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("长按小组件设置日期")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { WidgetGlass() }
        .widgetURL(URL(string: entry.target.map { "personalglasscalendar://day/\($0.key)" } ?? "personalglasscalendar://today"))
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
    }
}

@main
struct PersonalCalendarWidgets: WidgetBundle {
    var body: some Widget {
        TodayAndMonthWidget()
        CountdownWidget()
    }
}
