import Combine
import SwiftUI
import UIKit
import WidgetKit

@main
struct PersonalCalendarApp: App {
    @UIApplicationDelegateAdaptor(CalendarNotificationDelegate.self) private var notifications
    @StateObject private var store = CalendarStore()
    @AppStorage(CalendarPreferences.appearanceKey) private var appearance = CalendarAppearance.system

    init() {
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--verify-calendar-paging") || arguments.contains("--verify-settings-screen") || arguments.contains("--verify-widget-screen") {
            UserDefaults.standard.set(CalendarWeekStart.monday.rawValue, forKey: CalendarPreferences.weekStartKey)
            UserDefaults.standard.set(true, forKey: CalendarPreferences.showAlmanacKey)
            UserDefaults.standard.set(arguments.contains("--verify-dark-mode") ? "dark" : "light", forKey: CalendarPreferences.appearanceKey)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            CalendarHome()
                .environmentObject(store)
                .environmentObject(notifications)
                .environment(\.locale, Locale(identifier: "zh-Hans-CN"))
                .preferredColorScheme(appearance.colorScheme)
                .tint(CalendarTheme.accent)
        }
    }
}

enum CalendarTheme {
    static let accent = adaptive(UIColor(red: 0.88, green: 0.19, blue: 0.22, alpha: 1),
                                 UIColor(red: 1, green: 0.40, blue: 0.43, alpha: 1))
    static let ink = Color.primary
    static let onInk = Color(uiColor: .systemBackground)
    static let subtleFill = Color(uiColor: .tertiarySystemFill)
    static let badge = Color(uiColor: .secondarySystemBackground)

    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static var background: some View { CalendarGlassBackground() }
}

private struct CalendarGlassBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            scheme == .dark ? Color(red: 0.035, green: 0.045, blue: 0.075) : Color(red: 0.96, green: 0.97, blue: 1)
            RadialGradient(colors: [Color(red: 0.45, green: 0.65, blue: 1).opacity(scheme == .dark ? 0.22 : 0.52), .clear],
                           center: .topLeading, startRadius: 20, endRadius: 390)
            RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.72).opacity(scheme == .dark ? 0.15 : 0.48), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 277)
            RadialGradient(colors: [Color(red: 0.40, green: 0.85, blue: 0.73).opacity(scheme == .dark ? 0.12 : 0.40), .clear],
                           center: .bottomTrailing, startRadius: 15, endRadius: 325)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func calendarCard(_ radius: CGFloat = 26) -> some View {
        modifier(CalendarGlassCard(radius: radius))
    }
}

private struct CalendarGlassCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: radius).fill(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    RoundedRectangle(cornerRadius: radius).fill(.regularMaterial)
                }
            }
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(scheme == .dark ? 0.13 : 0.7)) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.16 : 0.05), radius: 14, x: 0, y: 8)
    }
}

enum CalendarMode: String, CaseIterable, Identifiable {
    case month = "月", week = "周", year = "年"
    var id: Self { self }

    func pageCount(weekStart: CalendarWeekStart = .monday) -> Int { page(containing: .last, weekStart: weekStart) + 1 }

    var estimatedHeight: CGFloat {
        switch self {
        case .month: 413
        case .week: 428
        case .year: 588
        }
    }

    func page(containing day: CivilDay, weekStart: CalendarWeekStart = .monday) -> Int {
        switch self {
        case .month: (day.year - CivilDay.first.year) * 12 + day.month - 1
        case .week: weekStart.start(of: .first).distance(to: weekStart.start(of: day)) / 7
        case .year: day.year - CivilDay.first.year
        }
    }

    func day(on page: Int, matching selection: CivilDay, weekStart: CalendarWeekStart = .monday) -> CivilDay {
        let offset = page - self.page(containing: selection, weekStart: weekStart)
        let target: CivilDay
        switch self {
        case .month: target = selection.movingMonths(offset)
        case .week: target = selection.adding(7 * offset)
        case .year: target = selection.movingMonths(12 * offset)
        }
        return min(max(target, .first), .last)
    }
}

enum CalendarSheet: Identifiable {
    case date, search, almanac, importSources, upcoming, settings, widgetPreview
    case editor(CivilDay, CalendarItem?, CalendarEditorAction), item(CalendarItem)

    var id: String {
        switch self {
        case .date: return "date"
        case .search: return "search"
        case .almanac: return "almanac"
        case .importSources: return "import-sources"
        case .upcoming: return "upcoming"
        case .settings: return "settings"
        case .widgetPreview: return "widget-preview"
        case .editor(let day, let item, let action): return "editor-\(action.rawValue)-" + (item?.id ?? day.key)
        case .item(let item): return "item-" + item.id
        }
    }
}

struct CalendarHome: View {
    @EnvironmentObject private var store: CalendarStore
    @EnvironmentObject private var notifications: CalendarNotificationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var importer = SystemImport()
    @StateObject private var holidaySync = HolidaySyncModel()
    @AppStorage(CalendarPreferences.weekStartKey) private var weekStart = CalendarWeekStart.monday
    @AppStorage(CalendarPreferences.showAlmanacKey) private var showAlmanac = true
    @State private var today = CivilDay.today
    @State private var selection = CalendarHome.initialSelection
    @State private var mode = CalendarMode.month
    @State private var previewMonthPage: Int?
    @State private var sheet: CalendarSheet?

    private static var initialSelection: CivilDay {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--verify-calendar-paging") {
            return CivilDay(2026, 11, 17)
        }
        #endif
        return .today
    }

    private var periodPage: Int {
        if mode == .month, let previewMonthPage { return previewMonthPage }
        return mode.page(containing: selection, weekStart: weekStart)
    }

    private var periodTitle: String {
        let day = mode == .month && previewMonthPage != nil ? mode.day(on: periodPage, matching: selection) : selection
        return mode == .year ? "\(day.year)年" : "\(day.year)年\(day.month)月"
    }

    var body: some View {
        ZStack {
            CalendarTheme.background
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                ScrollView {
                    VStack(spacing: 8) {
                        CalendarPager(mode: mode, selection: $selection, today: today, weekStart: weekStart,
                                      previewMonthPage: $previewMonthPage, showMonth: showMonth,
                                      newItem: { sheet = .editor($0, nil, .edit) },
                                      editItem: { sheet = .editor(selection, $0, $1) }, openItem: { sheet = .item($0) })
                        .id("\(mode.rawValue)-\(weekStart.rawValue)")
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))

                        if mode != .year {
                            VStack(spacing: 14) {
                                selectedDay
                                agenda
                            }
                            .padding(.horizontal, 16)
                            .transition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: mode)
                    .frame(maxWidth: 720)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(CalendarTheme.ink)
        }
        .onChange(of: mode) { _, _ in previewMonthPage = nil }
        .onChange(of: weekStart) { _, _ in previewMonthPage = nil }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                updateClock()
                syncSystemItems()
                refreshAlerts()
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await holidaySync.refresh(store: store)
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(3_600))
            }
        }
        .task(id: selection.monthStart) {
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--verify-import-screen") {
                sheet = .importSources
            } else if ProcessInfo.processInfo.arguments.contains("--verify-settings-screen") {
                sheet = .settings
            } else if ProcessInfo.processInfo.arguments.contains("--verify-widget-screen") {
                sheet = .widgetPreview
            }
            #endif
            await importer.refresh(around: selection, store: store)
        }
        .onReceive(importer.changes) { _ in
            if scenePhase == .active { syncSystemItems() }
        }
        .onChange(of: store.items) { _, _ in refreshAlerts() }
        .onReceive(notifications.$route) { route in
            guard let route else { return }
            showItem(id: route.itemID, on: route.day)
            notifications.clearRoute()
        }
        .onOpenURL { url in
            guard url.scheme == "personalglasscalendar" else { return }
            switch url.host {
            case "today", "month":
                today = .today
                selection = today
                mode = .month
            case "day":
                if let day = CivilDay(url.lastPathComponent), day.supported {
                    selection = day
                    mode = .month
                }
            case "item":
                if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value {
                    showItem(id: id)
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))
            .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged))) { _ in
            if updateClock(), scenePhase == .active { syncSystemItems() }
            if scenePhase == .active { refreshAlerts() }
        }
        .sheet(item: $sheet) { target in
            switch target {
            case .date: DateJumpSheet(selection: $selection)
            case .search: CalendarSearch()
            case .almanac: AlmanacSheet(day: selection)
            case .importSources: ImportSheet(importer: importer, day: selection)
            case .upcoming: UpcomingCalendarSheet()
            case .settings: CalendarSettingsSheet(holidaySync: holidaySync)
            case .widgetPreview:
                NavigationStack {
                    CalendarWidgetPreviewScreen()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
                }
            case .editor(let day, let item, let action): CalendarEditor(day: day, item: item, action: action)
            case .item(let item): CalendarItemDetail(item: item, day: selection)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                Button { sheet = .date } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: periodTitle)
                            .font(.title2.bold())
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(periodPage)))
                            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: periodPage)
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .accessibilityLabel("选择日期")
                .accessibilityValue(Text(verbatim: periodTitle))
                .accessibilityIdentifier("calendar-period")
                Spacer(minLength: 0)
                Button { sheet = .almanac } label: {
                    Text("黄历").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10).frame(height: 44)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                iconButton("square.and.arrow.down", "导入与同步") { sheet = .importSources }
                iconButton("magnifyingglass", "搜索") { sheet = .search }
                iconButton("plus", "新建事项", tint: CalendarTheme.accent) { sheet = .editor(selection, nil, .edit) }
            }
            HStack(spacing: 8) {
                iconButton("chevron.left", "上一\(mode.rawValue)") { navigate(-1) }
                    .disabled(mode.page(containing: selection, weekStart: weekStart) == 0)
                Picker("日历视图", selection: $mode) {
                    ForEach(CalendarMode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("calendar-mode")
                iconButton("chevron.right", "下一\(mode.rawValue)") { navigate(1) }
                    .disabled(mode.page(containing: selection, weekStart: weekStart) == mode.pageCount(weekStart: weekStart) - 1)
                Button { selection = today } label: {
                    Text("今天").font(.subheadline.weight(.semibold))
                        .foregroundStyle(CalendarTheme.accent)
                        .padding(.horizontal, 11).frame(height: 44)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                iconButton("gearshape", "设置") { sheet = .settings }
                    .accessibilityIdentifier("calendar-settings")
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private var selectedDay: some View {
        let facts = store.facts(selection)
        let distance = today.distance(to: selection)
        let message = distance == 0 ? "今天" : (distance > 0 ? "距今天还有 \(distance) 天" : "\(-distance) 天前")
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(selection.month)月\(selection.day)日")
                    .font(.title2.bold())
                    .contentTransition(reduceMotion ? .identity : .numericText(value: selection.date.timeIntervalSinceReferenceDate))
                    .accessibilityIdentifier("calendar-selected-date")
                Text(selection.weekdayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .identity : .opacity)
                Spacer()
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CalendarTheme.accent)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(CalendarTheme.accent.opacity(0.09), in: Capsule())
                    .contentTransition(reduceMotion ? .identity : .opacity)
            }
            if let facts {
                Text([facts.lunarText, facts.festival, facts.term ?? "", facts.shiftText]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .identity : .opacity)
            }
            if showAlmanac, let almanac = store.engine.almanac(selection) {
                Divider()
                Button { sheet = .almanac } label: {
                    HStack(spacing: 8) {
                        Text("宜").foregroundStyle(.green)
                        Text(almanac.yi.prefix(3).joined(separator: "、")).lineLimit(1)
                            .contentTransition(reduceMotion ? .identity : .opacity)
                        Text("忌").foregroundStyle(CalendarTheme.accent)
                        Text(almanac.ji.prefix(3).joined(separator: "、")).lineLimit(1)
                            .contentTransition(reduceMotion ? .identity : .opacity)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CalendarTheme.ink)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看当天黄历")
                .accessibilityIdentifier("calendar-almanac-summary")
            }
        }
        .padding(16)
        .calendarCard()
        .animation(reduceMotion ? nil : .smooth(duration: 0.23), value: selection)
    }

    private var agenda: some View {
        let items = store.items(on: selection)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("当天安排").font(.headline)
                Spacer()
                Button("接下来") { sheet = .upcoming }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("upcoming-agenda")
                Button { sheet = .editor(selection, nil, .edit) } label: {
                    Label("新建", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(CalendarTheme.accent)
            }
            if items.isEmpty {
                Text("当天没有安排").font(.subheadline).foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            ForEach(items) { item in
                Button { sheet = .item(item) } label: {
                    CalendarItemRow(item: item)
                }
                .buttonStyle(.plain)
                .calendarItemMenu(item) { sheet = .editor(selection, item, $0) }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .calendarCard()
        .animation(reduceMotion ? nil : .smooth(duration: 0.23), value: selection)
    }

    private func iconButton(_ icon: String, _ label: String, tint: Color = CalendarTheme.ink,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel(label)
    }

    private func syncSystemItems() {
        Task { await importer.refresh(around: selection, store: store) }
    }

    private func refreshAlerts() {
        CalendarNotifications.shared.refresh(store)
        Task { await CalendarLiveActivities.reconcile(store) }
    }

    private func showItem(id: String, on day: CivilDay? = nil) {
        guard let item = store.allItems.first(where: { $0.id == id }) else { return }
        let date = day ?? store.engine.nextOccurrence(of: item, onOrAfter: today) ?? CivilDay(item.date)
        if let date, date.supported { selection = date }
        mode = .month
        sheet = .item(item)
    }

    @discardableResult
    private func updateClock() -> Bool {
        let zone = TimeZone(identifier: TimeZone.autoupdatingCurrent.identifier) ?? .current
        let newToday = CivilDay.localDay(containing: .now, in: zone)
        if selection == today { selection = newToday }
        today = newToday
        let changed = store.setTimeZone(zone)
        if changed { WidgetCenter.shared.reloadAllTimelines() }
        return changed
    }

    private func navigate(_ direction: Int) {
        let page = mode.page(containing: selection, weekStart: weekStart) + direction
        guard (0..<mode.pageCount(weekStart: weekStart)).contains(page) else { return }
        selection = mode.day(on: page, matching: selection, weekStart: weekStart)
    }

    private func showMonth(_ day: CivilDay) {
        selection = day
        mode = .month
    }
}

enum CalendarEditorAction: String {
    case edit = "编辑事项", copy = "复制事项", reschedule = "改期"
}

extension View {
    @ViewBuilder
    func calendarItemMenu(_ item: CalendarItem, perform: @escaping (CalendarEditorAction) -> Void) -> some View {
        if item.isLinked {
            self
        } else {
            self.contextMenu {
                Button { perform(.copy) } label: { Label("复制事项", systemImage: "plus.square.on.square") }
                Button { perform(.reschedule) } label: { Label("改期", systemImage: "calendar") }
            }
        }
    }
}

struct CalendarItemRow: View {
    let item: CalendarItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(item.kind.color)
                .frame(width: 34, height: 34)
                .background(item.kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(CalendarTheme.ink)
                Text(item.caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
