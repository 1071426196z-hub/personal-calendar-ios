import AppIntents
import ActivityKit
import SwiftUI
import WidgetKit

private extension View {
    func calendarWidgetSurface() -> some View {
        containerBackground(.ultraThinMaterial, for: .widget)
    }
}

enum WidgetWeekStart: String, AppEnum {
    case monday, sunday
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "每周起始")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.monday: "周一", .sunday: "周日"]
    var value: CalendarWeekStart { self == .monday ? .monday : .sunday }
}

struct TodayWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "设置日历"
    @Parameter(title: "每周起始", default: .monday) var weekStart: WidgetWeekStart
    @Parameter(title: "显示宜忌摘要", default: false) var showAlmanac: Bool
}

private struct TodayWidgetEntry: TimelineEntry {
    let snapshot: CalendarWidgetEntry
    let configuration: TodayWidgetIntent
    var date: Date { snapshot.date }
}

private struct CalendarWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(snapshot: CalendarWidgetEntry(date: .now), configuration: TodayWidgetIntent())
    }
    func snapshot(for configuration: TodayWidgetIntent, in context: Context) async -> TodayWidgetEntry {
        TodayWidgetEntry(snapshot: CalendarWidgetEntry(date: .now, engine: CalendarEngine(),
            holidays: HolidayFeed.saved(), showAlmanac: configuration.showAlmanac), configuration: configuration)
    }
    func timeline(for configuration: TodayWidgetIntent, in context: Context) async -> Timeline<TodayWidgetEntry> {
        let holidays = await HolidayFeed.shared.refresh()
        let engine = CalendarEngine()
        let entries = widgetDates().map {
            TodayWidgetEntry(snapshot: CalendarWidgetEntry(date: $0, engine: engine, holidays: holidays,
                showAlmanac: configuration.showAlmanac), configuration: configuration)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry
    var body: some View {
        CalendarWidgetFace(entry: entry.snapshot, family: family, weekStart: entry.configuration.weekStart.value)
            .calendarWidgetSurface()
    }
}

private func widgetDates() -> [Date] {
    let now = Date()
    let calendar = CivilDay.localCalendar()
    let midnight = calendar.startOfDay(for: now)
    return [now] + (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: midnight) }
}

private struct TodayAndMonthWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PersonalCalendar.TodayAndMonth", intent: TodayWidgetIntent.self,
                               provider: CalendarWidgetProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("日历")
        .description("查看今日农历、节日或整月日期。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryRectangular, .accessoryCircular])
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
    @Environment(\.widgetFamily) private var family
    let entry: CountdownWidgetEntry

    var body: some View {
        DayCountWidgetFace(
            title: entry.configuration.label,
            icon: "hourglass",
            days: entry.days.map { abs($0) },
            status: entry.days.map { $0 == 0 ? "就是今天" : ($0 > 0 ? "还有" : "已过") } ?? "",
            note: entry.target?.label ?? "",
            target: entry.target, family: family
        )
        .calendarWidgetSurface()
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
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryRectangular, .accessoryCircular])
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

private struct AnniversaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AnniversaryWidgetEntry
    var body: some View {
        DayCountWidgetFace(title: entry.configuration.label, icon: "heart", days: entry.elapsed.map { abs($0) },
            status: entry.elapsed.map { $0 == 0 ? "就是今天" : ($0 > 0 ? "已经过去" : "距纪念日") } ?? "",
            note: entry.note, target: entry.target, family: family)
            .calendarWidgetSurface()
    }
}

private struct AnniversaryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PersonalCalendar.Anniversary", intent: AnniversaryWidgetIntent.self,
                               provider: AnniversaryWidgetProvider()) { entry in
            AnniversaryWidgetView(entry: entry)
        }
        .configurationDisplayName("纪念日")
        .description("查看纪念日已经过去的天数和下次周年。")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryRectangular, .accessoryCircular])
        .containerBackgroundRemovable(true)
    }
}

@main
struct PersonalCalendarWidgets: WidgetBundle {
    var body: some Widget {
        TodayAndMonthWidget()
        CountdownWidget()
        AnniversaryWidget()
        CalendarLiveWidget()
    }
}

private struct CalendarLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CalendarLiveAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock").font(.title3).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title).font(.headline).lineLimit(2).privacySensitive()
                    Text(context.state.target, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                timer(context).font(.title3.weight(.semibold))
            }
            .padding(16)
            .widgetURL(context.attributes.link)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "calendar.badge.clock").foregroundStyle(.red) }
                DynamicIslandExpandedRegion(.trailing) { timer(context) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.title).lineLimit(1).privacySensitive()
                        Spacer(minLength: 6)
                        Text(context.state.target, style: .time).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            } compactLeading: {
                Image(systemName: "calendar").foregroundStyle(.red)
            } compactTrailing: {
                timer(context).font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: "calendar").foregroundStyle(.red)
            }
            .widgetURL(context.attributes.link)
        }
    }

    @ViewBuilder private func timer(_ context: ActivityViewContext<CalendarLiveAttributes>) -> some View {
        if context.isStale {
            Text("已到时间")
        } else {
            Text(timerInterval: context.state.begins...context.state.target, countsDown: true, showsHours: false)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}
