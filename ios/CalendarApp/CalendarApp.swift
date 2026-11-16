import SwiftUI

@main
struct PersonalCalendarApp: App {
    @StateObject private var store = CalendarStore()

    var body: some Scene {
        WindowGroup {
            CalendarHome()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "zh-Hans-CN"))
                .preferredColorScheme(.light)
                .tint(CalendarTheme.accent)
        }
    }
}

enum CalendarTheme {
    static let accent = Color(red: 0.88, green: 0.19, blue: 0.22)
    static let ink = Color(red: 0.13, green: 0.16, blue: 0.23)

    static var background: some View {
        ZStack {
            Color(red: 0.96, green: 0.97, blue: 1)
            RadialGradient(colors: [Color(red: 0.73, green: 0.84, blue: 1), .clear],
                           center: .topLeading, startRadius: 20, endRadius: 390)
            RadialGradient(colors: [Color(red: 1, green: 0.78, blue: 0.85), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 277)
            RadialGradient(colors: [Color(red: 0.76, green: 0.95, blue: 0.91), .clear],
                           center: .bottomTrailing, startRadius: 15, endRadius: 325)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func calendarCard(_ radius: CGFloat = 26) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.7)) }
            .shadow(color: Color(red: 0.23, green: 0.31, blue: 0.5).opacity(0.075), radius: 14, x: 0, y: 8)
    }
}

enum CalendarMode: String, CaseIterable, Identifiable {
    case month = "月", week = "周", year = "年"
    var id: Self { self }
}

enum CalendarSheet: Identifiable {
    case date, search, almanac, importSources, editor(CalendarItem?), item(CalendarItem)

    var id: String {
        switch self {
        case .date: return "date"
        case .search: return "search"
        case .almanac: return "almanac"
        case .importSources: return "import-sources"
        case .editor(let item): return "editor-" + (item?.id ?? "new")
        case .item(let item): return "item-" + item.id
        }
    }
}

struct CalendarHome: View {
    @EnvironmentObject private var store: CalendarStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var importer = SystemImport()
    @State private var today = CivilDay.today
    @State private var selection = CivilDay.today
    @State private var mode = CalendarMode.month
    @State private var sheet: CalendarSheet?

    var body: some View {
        ZStack {
            CalendarTheme.background
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                ScrollView {
                    VStack(spacing: 14) {
                        switch mode {
                        case .month: MonthGrid(selection: $selection, today: today)
                        case .week:
                            WeekGrid(selection: $selection, today: today) { sheet = .item($0) }
                        case .year:
                            YearGrid(selection: selection, today: today) { month in
                                selection = bounded(selection.movingMonths(month - selection.month))
                                mode = .month
                            }
                        }
                        if mode != .year {
                            selectedDay
                            agenda
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(CalendarTheme.ink)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                today = .today
                syncSystemItems()
            }
        }
        .task(id: selection.monthStart) {
            await importer.refresh(around: selection, store: store)
        }
        .onReceive(importer.changes) { _ in
            if scenePhase == .active { syncSystemItems() }
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
            case "import":
                sheet = .importSources
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = .today
        }
        .sheet(item: $sheet) { target in
            switch target {
            case .date: DateJumpSheet(selection: $selection)
            case .search: CalendarSearch()
            case .almanac: AlmanacSheet(day: selection)
            case .importSources: ImportSheet(importer: importer, day: selection)
            case .editor(let item): CalendarEditor(day: selection, item: item)
            case .item(let item): CalendarItemDetail(item: item, day: selection)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                Button { sheet = .date } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: mode == .year ? "\(selection.year)年" : "\(selection.year)年\(selection.month)月")
                            .font(.title2.bold())
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .accessibilityLabel("选择日期")
                Spacer(minLength: 0)
                Button { sheet = .almanac } label: {
                    Text("黄历").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10).frame(height: 44)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                iconButton("square.and.arrow.down", "导入与同步") { sheet = .importSources }
                iconButton("magnifyingglass", "搜索") { sheet = .search }
                iconButton("plus", "新建事项", tint: CalendarTheme.accent) { sheet = .editor(nil) }
            }
            HStack(spacing: 8) {
                iconButton("chevron.left", "上一\(mode.rawValue)") { navigate(-1) }
                Picker("日历视图", selection: $mode) {
                    ForEach(CalendarMode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("calendar-mode")
                iconButton("chevron.right", "下一\(mode.rawValue)") { navigate(1) }
                Button { selection = today } label: {
                    Text("今天").font(.subheadline.weight(.semibold))
                        .foregroundStyle(CalendarTheme.accent)
                        .padding(.horizontal, 11).frame(height: 44)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private var selectedDay: some View {
        let facts = store.engine.facts(selection)
        let distance = today.distance(to: selection)
        let message = distance == 0 ? "今天" : (distance > 0 ? "距今天还有 \(distance) 天" : "\(-distance) 天前")
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(selection.month)月\(selection.day)日").font(.title2.bold())
                Text(selection.weekdayLabel).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CalendarTheme.accent)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(CalendarTheme.accent.opacity(0.09), in: Capsule())
            }
            if let facts {
                Text([facts.lunarText, facts.festival, facts.term ?? "", facts.shiftText]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let almanac = store.engine.almanac(selection) {
                Divider()
                Button { sheet = .almanac } label: {
                    HStack(spacing: 8) {
                        Text("宜").foregroundStyle(.green)
                        Text(almanac.yi.prefix(3).joined(separator: "、")).lineLimit(1)
                        Text("忌").foregroundStyle(CalendarTheme.accent)
                        Text(almanac.ji.prefix(3).joined(separator: "、")).lineLimit(1)
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
            }
        }
        .padding(16)
        .calendarCard()
    }

    private var agenda: some View {
        let items = store.items(on: selection)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("当天安排").font(.headline)
                Spacer()
                Button { sheet = .editor(nil) } label: {
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
            }
            ForEach(items) { item in
                Button { sheet = .item(item) } label: {
                    CalendarItemRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .calendarCard()
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

    private func bounded(_ day: CivilDay) -> CivilDay { min(max(day, .first), .last) }

    private func syncSystemItems() {
        Task { await importer.refresh(around: selection, store: store) }
    }

    private func navigate(_ direction: Int) {
        switch mode {
        case .month: selection = bounded(selection.movingMonths(direction))
        case .week: selection = bounded(selection.adding(direction * 7))
        case .year: selection = bounded(selection.movingMonths(direction * 12))
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
