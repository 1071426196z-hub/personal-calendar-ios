import Combine
import SwiftUI
import WidgetKit

@MainActor
final class HolidaySyncModel: ObservableObject {
    @Published private(set) var status = HolidayFeed.savedStatus()
    @Published private(set) var isUpdating = false

    func refresh(store: CalendarStore, force: Bool = false) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        let schedule = await HolidayFeed.shared.refresh(force: force)
        if store.setHolidays(schedule) {
            WidgetCenter.shared.reloadTimelines(ofKind: "PersonalCalendar.TodayAndMonth")
        }
        status = await HolidayFeed.shared.status()
    }
}

struct CalendarSettingsSheet: View {
    @EnvironmentObject private var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var holidaySync: HolidaySyncModel
    @AppStorage(CalendarPreferences.appearanceKey) private var appearance = CalendarAppearance.system
    @AppStorage(CalendarPreferences.weekStartKey) private var weekStart = CalendarWeekStart.monday
    @AppStorage(CalendarPreferences.showAlmanacKey) private var showAlmanac = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("外观与日历", systemImage: "circle.lefthalf.filled").font(.headline)
                        Picker("外观", selection: $appearance) {
                            ForEach(CalendarAppearance.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("calendar-appearance")
                        HStack {
                            Text("每周起始")
                            Spacer()
                            Picker("每周起始", selection: $weekStart) {
                                ForEach(CalendarWeekStart.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 148)
                            .accessibilityIdentifier("calendar-week-start")
                        }
                        Divider()
                        Toggle("首页显示黄历摘要", isOn: $showAlmanac)
                            .accessibilityIdentifier("calendar-show-almanac")
                        Text("关闭摘要后，仍可从首页顶部打开完整黄历。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(18).calendarCard()

                    VStack(alignment: .leading, spacing: 14) {
                        Label("小组件", systemImage: "square.grid.2x2").font(.headline)
                        NavigationLink {
                            CalendarWidgetPreviewScreen()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("预览桌面与锁屏小组件").font(.subheadline.weight(.semibold))
                                    Text("日历 · 倒数日 · 纪念日").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("calendar-widget-preview")
                        Text("桌面：长按空白处 → 编辑 → 添加小组件。\n锁屏：长按锁屏 → 自定 → 点时间下方的组件区域。")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18).calendarCard()

                    holidaySection
                }
                .padding(16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background { CalendarTheme.background }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        // A sheet is its own presentation. Apply the override here as well as at the app root.
        .preferredColorScheme(appearance.colorScheme)
    }

    private var holidaySection: some View {
        let status = holidaySync.status
        return VStack(alignment: .leading, spacing: 13) {
            Label("节假日数据", systemImage: "calendar.badge.checkmark").font(.headline)
            Text(status.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(status.outcome == .offline ? Color.secondary : CalendarTheme.ink)
                .accessibilityIdentifier("holiday-update-status")
            detail("内置年份", HolidaySyncStatus.bundledYears.map { String($0) }.joined(separator: "、"))
            if !status.years.isEmpty {
                detail("已下载年份", status.years.map { String($0) }.joined(separator: "、"))
            }
            if let date = status.checkedAt { detail("最近成功检查", date.formatted(date: .abbreviated, time: .shortened)) }
            if let date = status.attemptedAt, status.outcome == .offline {
                detail("最近尝试", date.formatted(date: .abbreviated, time: .shortened))
            }
            if let stamp = dataDate(status.generated) { detail("数据版本", stamp) }
            Link("查看节假日数据来源", destination: URL(string: "https://github.com/lanceliao/china-holiday-calender")!)
                .font(.caption)
            Button {
                Task { await holidaySync.refresh(store: store, force: true) }
            } label: {
                HStack(spacing: 8) {
                    if holidaySync.isUpdating { ProgressView().controlSize(.small) }
                    Text(holidaySync.isUpdating ? "正在检查…" : "立即检查更新")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(holidaySync.isUpdating)
            .accessibilityIdentifier("holiday-check-now")
            let nextYear = CivilDay.today.year + 1
            if !status.coveredYears.contains(nextYear) {
                Text("\(nextYear) 年调休安排尚未获取，将在数据发布后自动更新。节日名称照常显示，不推测休班日期。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("联网时每天自动检查。网络不可用时保留现有安排；圣诞节、万圣节等节日名称与法定休班标记分别显示。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).calendarCard()
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func dataDate(_ value: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.date(from: value)?.formatted(date: .abbreviated, time: .shortened)
    }
}

struct CalendarWidgetPreviewScreen: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case calendar = "日历", countdown = "倒数日", anniversary = "纪念日"
        var id: String { rawValue }
    }
    @EnvironmentObject private var store: CalendarStore
    @AppStorage(CalendarPreferences.weekStartKey) private var weekStart = CalendarWeekStart.monday
    @AppStorage(CalendarPreferences.showAlmanacKey) private var showAlmanac = true
    @State private var kind = Kind.calendar
    @State private var family = WidgetFamily.systemSmall
    @State private var milestoneTitle = "旅行出发"
    @State private var milestoneDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var snapshot = CalendarWidgetEntry(date: .now)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("组件内容", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("widget-preview-kind")
                if kind == .calendar {
                    Picker("组件尺寸", selection: $family) {
                        Text("小").tag(WidgetFamily.systemSmall)
                        Text("中").tag(WidgetFamily.systemMedium)
                        Text("大").tag(WidgetFamily.systemLarge)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("widget-preview-size")
                } else {
                    VStack(spacing: 12) {
                        TextField("名称", text: $milestoneTitle)
                            .accessibilityIdentifier("widget-preview-title")
                        DatePicker("目标日期", selection: $milestoneDate, displayedComponents: .date)
                    }
                    .padding(16).calendarCard()
                }
                Text("桌面效果").font(.headline)
                face(kind == .calendar ? family : .systemSmall)
                    .padding(16)
                    .frame(width: homeSize.width, height: homeSize.height)
                    .calendarCard(28)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("widget-preview-home")

                Text("锁屏效果").font(.headline)
                face(.accessoryInline)
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 32)
                    .calendarCard(16)
                HStack(spacing: 20) {
                    face(.accessoryRectangular).frame(width: 160, height: 72)
                        .padding(10).calendarCard(18)
                    face(.accessoryCircular).frame(width: 64, height: 64)
                        .padding(12).calendarCard(44)
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("widget-preview-lock")
                VStack(alignment: .leading, spacing: 8) {
                    Text("背景会随壁纸和系统外观变化，锁屏组件由系统统一显示。")
                    Text("预览中的名称和日期仅用于试样式。添加后，长按小组件即可单独设置日期、周起始与宜忌摘要。")
                    Text("日程倒计时可在事项详情中开启，会显示在锁屏实时活动和灵动岛。")
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background { CalendarTheme.background }
        .navigationTitle("小组件预览")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(showAlmanac)-\(store.presentationRevision)") {
            snapshot = CalendarWidgetEntry(date: .now, engine: store.engine, holidays: store.holidays, showAlmanac: showAlmanac)
        }
        .onChange(of: kind) { _, value in
            if value != .calendar {
                milestoneTitle = value == .anniversary ? "相识纪念日" : "旅行出发"
                milestoneDate = Calendar.current.date(byAdding: .day, value: value == .anniversary ? -268 : 30, to: .now) ?? .now
            }
        }
    }

    private var homeSize: CGSize {
        guard kind == .calendar else { return CGSize(width: 164, height: 164) }
        switch family {
        case .systemMedium: return CGSize(width: 328, height: 164)
        case .systemLarge: return CGSize(width: 328, height: 344)
        default: return CGSize(width: 164, height: 164)
        }
    }

    @ViewBuilder private func face(_ family: WidgetFamily) -> some View {
        if kind == .calendar {
            CalendarWidgetFace(entry: snapshot, family: family, weekStart: weekStart)
        } else {
            let target = CivilDay.localDay(containing: milestoneDate)
            let today = CivilDay.today
            let distance = today.distance(to: target)
            let anniversary = kind == .anniversary
            let status = distance == 0 ? "就是今天" : (anniversary ? (distance < 0 ? "已经过去" : "距纪念日") : (distance > 0 ? "还有" : "已过"))
            DayCountWidgetFace(title: milestoneTitle, icon: anniversary ? "heart" : "hourglass",
                               days: abs(distance), status: status,
                               note: anniversary ? anniversaryNote(target: target, today: today) : target.label,
                               target: target, family: family)
        }
    }

    private func anniversaryNote(target: CivilDay, today: CivilDay) -> String {
        guard today > target else { return target.label }
        let years = today.year - target.year
        let thisYear = target.movingMonths(years * 12)
        if thisYear == today { return "今天是第 \(years) 个周年" }
        let next = thisYear < today ? target.movingMonths((years + 1) * 12) : thisYear
        return "下次周年还有 \(today.distance(to: next)) 天"
    }
}
