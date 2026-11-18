import SwiftUI

struct CalendarPager: View {
    @EnvironmentObject private var store: CalendarStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let mode: CalendarMode
    @Binding var selection: CivilDay
    let today: CivilDay
    let weekStart: CalendarWeekStart
    @Binding var previewMonthPage: Int?
    let showMonth: (CivilDay) -> Void
    let newItem: (CivilDay) -> Void
    let editItem: (CalendarItem, CalendarEditorAction) -> Void
    let openItem: (CalendarItem) -> Void

    @State private var position: ScrollPosition
    @State private var displayedPage: Int
    @State private var followsSwipe = false
    @State private var heights: [Int: CGFloat] = [:]

    init(mode: CalendarMode, selection: Binding<CivilDay>, today: CivilDay, weekStart: CalendarWeekStart, previewMonthPage: Binding<Int?>,
         showMonth: @escaping (CivilDay) -> Void, newItem: @escaping (CivilDay) -> Void,
         editItem: @escaping (CalendarItem, CalendarEditorAction) -> Void, openItem: @escaping (CalendarItem) -> Void) {
        self.mode = mode
        self._selection = selection
        self.today = today
        self.weekStart = weekStart
        self._previewMonthPage = previewMonthPage
        self.showMonth = showMonth
        self.newItem = newItem
        self.editItem = editItem
        self.openItem = openItem
        let initial = mode.page(containing: selection.wrappedValue, weekStart: weekStart)
        var startingPosition = ScrollPosition(idType: Int.self)
        startingPosition.scrollTo(id: initial, anchor: .center)
        _position = State(initialValue: startingPosition)
        _displayedPage = State(initialValue: initial)
    }

    var body: some View {
        let height = heights[displayedPage] ?? mode.estimatedHeight
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(0..<mode.pageCount(weekStart: weekStart), id: \.self) { page in
                    content(on: page)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .containerRelativeFrame(.horizontal)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                            guard measured > 0, abs(page - displayedPage) <= 2,
                                  abs((heights[page] ?? 0) - measured) > 0.5 else { return }
                            heights = heights.filter { abs($0.key - displayedPage) <= 2 }
                            heights[page] = measured
                        }
                        .accessibilityHidden(page != displayedPage)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: height)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition($position, anchor: .center)
        .onScrollGeometryChange(for: Int?.self) { geometry in
            mode == .month ? centeredPage(in: geometry) : nil
        } action: { _, page in
            if followsSwipe { previewMonthPage = page }
        }
        .onScrollPhaseChange { previous, phase, context in
            if mode == .month, phase == .interacting {
                followsSwipe = true
                previewMonthPage = centeredPage(in: context.geometry)
            }
            guard phase == .idle else { return }
            let wasSwiping = followsSwipe || position.isPositionedByUser || previous == .interacting || previous == .decelerating
            followsSwipe = false
            defer { if mode == .month { previewMonthPage = nil } }
            guard wasSwiping, let reachedPage = centeredPage(in: context.geometry) else { return }
            displayedPage = reachedPage
            if reachedPage != mode.page(containing: selection, weekStart: weekStart) {
                selection = mode.day(on: reachedPage, matching: selection, weekStart: weekStart)
            }
        }
        .onChange(of: mode.page(containing: selection, weekStart: weekStart)) { _, target in
            guard target != displayedPage else { return }
            followsSwipe = false
            if mode == .month { previewMonthPage = nil }
            let animate = !reduceMotion && abs(target - displayedPage) == 1
            displayedPage = target
            withAnimation(animate ? .smooth(duration: 0.28) : nil) {
                position.scrollTo(id: target, anchor: .center)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: height)
        .accessibilityIdentifier("calendar-pager")
        .task(id: "\(mode.rawValue)-\(selection.monthStart.key)-\(weekStart.rawValue)-\(store.presentationRevision)") {
            guard mode == .month else { return }
            // Yield the first frame, then prepare adjacent months before the next drag begins.
            for offset in [1, -1] {
                await Task.yield()
                guard !Task.isCancelled else { return }
                let next = selection.monthStart.movingMonths(offset)
                if next.supported { _ = store.monthCells(containing: next, weekStart: weekStart) }
            }
        }
    }

    private func centeredPage(in geometry: ScrollGeometry) -> Int? {
        let width = geometry.containerSize.width
        guard width > 0 else { return nil }
        let page = Int(floor(geometry.visibleRect.midX / width))
        return (0..<mode.pageCount(weekStart: weekStart)).contains(page) ? page : nil
    }

    @ViewBuilder private func content(on page: Int) -> some View {
        let day = mode.day(on: page, matching: selection, weekStart: weekStart)
        switch mode {
        case .month:
            MonthGrid(selection: day, today: today, weekStart: weekStart, select: select, newItem: newItem)
        case .week:
            WeekGrid(selection: day, today: today, weekStart: weekStart, select: select, newItem: newItem, open: openItem, edit: editItem)
        case .year:
            YearGrid(selection: day, today: today, weekStart: weekStart) { month in
                showMonth(day.movingMonths(month - day.month))
            }
        }
    }

    private func select(_ day: CivilDay) { selection = day }
}

private struct CalendarDateButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: configuration.isPressed)
    }
}

private struct CalendarDayCell: View, Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let day: CivilDay
    let selected: Bool
    let isToday: Bool
    let muted: Bool
    let facts: DayFacts?
    let kinds: [EventKind]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.day == rhs.day && lhs.selected == rhs.selected && lhs.isToday == rhs.isToday &&
        lhs.muted == rhs.muted && lhs.facts == rhs.facts && lhs.kinds == rhs.kinds
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day.day)")
                .font(.system(size: 19, weight: selected || isToday ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(selected ? (isToday ? Color.white : CalendarTheme.onInk) : isToday ? CalendarTheme.accent : CalendarTheme.ink.opacity(muted ? 0.34 : 1))
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(isToday ? CalendarTheme.accent : CalendarTheme.ink)
                        .scaleEffect(selected || reduceMotion ? 1 : 0.62)
                        .opacity(selected ? 1 : 0)
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.23, extraBounce: 0.04), value: selected)
                .overlay(alignment: .topTrailing) {
                    if let shift = facts?.shift, !shift.isEmpty {
                        Text(shift)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(shift == "休" ? Color.green : CalendarTheme.accent)
                            .padding(2)
                            .background(CalendarTheme.badge, in: Circle())
                            .offset(x: 5, y: -1)
                    }
                }
            Text(facts?.shortLabel ?? "")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(facts?.festival.isEmpty == false ? CalendarTheme.accent.opacity(muted ? 0.45 : 1) :
                                     CalendarTheme.ink.opacity(muted ? 0.31 : 0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 2) {
                ForEach(kinds) { kind in
                    Circle().fill(kind.color.opacity(muted ? 0.42 : 0.9)).frame(width: 4, height: 4)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 55)
        .contentShape(Rectangle())
        .accessibilityLabel([day.label, facts?.lunarText ?? "", facts?.festival ?? ""]
            .filter { !$0.isEmpty }.joined(separator: "，"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MonthGrid: View {
    @EnvironmentObject private var store: CalendarStore
    let selection: CivilDay
    let today: CivilDay
    let weekStart: CalendarWeekStart
    let select: (CivilDay) -> Void
    let newItem: (CivilDay) -> Void
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 1), count: 7)

    var body: some View {
        let cells = store.monthCells(containing: selection, weekStart: weekStart)
        VStack(spacing: 8) {
            HStack(spacing: 1) {
                ForEach(Array(weekStart.weekdays.enumerated()), id: \.element) { index, name in
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle((index + weekStart.rawValue) % 7 >= 5 ? CalendarTheme.accent : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(cells) { cell in
                    let day = cell.day
                    Button { select(day) } label: {
                        CalendarDayCell(day: day, selected: day == selection, isToday: day == today,
                                        muted: day.month != selection.month, facts: cell.facts,
                                        kinds: cell.kinds)
                            .equatable()
                    }
                    .disabled(!day.supported)
                    .buttonStyle(CalendarDateButtonStyle())
                    .contextMenu {
                        if day.supported {
                            Button { newItem(day) } label: { Label("新建事项", systemImage: "plus") }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .calendarCard()
    }
}

struct YearGrid: View {
    @EnvironmentObject private var store: CalendarStore
    let selection: CivilDay
    let today: CivilDay
    let weekStart: CalendarWeekStart
    let choose: (Int) -> Void
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 7), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
            ForEach(store.yearMonths(selection.year, weekStart: weekStart)) { geometry in
                let month = geometry.first.month
                Button { choose(month) } label: {
                    miniMonth(geometry)
                }
                .buttonStyle(CalendarDateButtonStyle())
                .accessibilityLabel(Text(verbatim: "\(selection.year)年\(month)月"))
                .accessibilityIdentifier("calendar-year-month-\(selection.year)-\(month)")
                .accessibilityAddTraits(month == selection.month ? .isSelected : [])
            }
        }
        .padding(8)
        .calendarCard()
    }

    private func miniMonth(_ geometry: CalendarMonthGeometry) -> some View {
        let month = geometry.first.month
        return VStack(alignment: .leading, spacing: 7) {
            Text("\(month)月")
                .font(.subheadline.bold())
                .foregroundStyle(month == selection.month ? CalendarTheme.accent : CalendarTheme.ink)
            miniMonthDays(geometry)
        }
        .padding(6)
        .background(month == selection.month ? CalendarTheme.accent.opacity(0.08) : CalendarTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: 13))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private func miniMonthDays(_ geometry: CalendarMonthGeometry) -> some View {
        let first = geometry.first
        let month = first.month
        let weekdayOffset = geometry.offset
        let count = geometry.count
        let selectedDay = selection.month == month ? selection.day : nil
        let currentDay = today.year == first.year && today.month == month ? today.day : nil
        let rowHeight: CGFloat = 15
        return Canvas { context, size in
            let columnWidth = size.width / 7
            for (column, weekday) in weekStart.weekdays.enumerated() {
                let center = CGPoint(x: (CGFloat(column) + 0.5) * columnWidth, y: 6)
                context.draw(Text(weekday).font(.system(size: 6, weight: .semibold)).foregroundStyle(.secondary), at: center)
            }
            for day in 1...count {
                let index = weekdayOffset + day - 1
                let center = CGPoint(x: (CGFloat(index % 7) + 0.5) * columnWidth,
                                     y: 6 + CGFloat(index / 7 + 1) * rowHeight)
                let highlighted = day == currentDay || day == selectedDay
                if highlighted {
                    let circle = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: circle), with: .color(day == currentDay ? CalendarTheme.accent : CalendarTheme.ink))
                }
                let label = Text("\(day)")
                    .font(.system(size: 8, weight: highlighted ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(highlighted ? (day == currentDay ? Color.white : CalendarTheme.onInk) : CalendarTheme.ink)
                context.draw(label, at: center)
            }
        }
        .frame(height: 6 * rowHeight + 12)
        .accessibilityHidden(true)
    }
}

struct WeekGrid: View {
    @EnvironmentObject private var store: CalendarStore
    let selection: CivilDay
    let today: CivilDay
    let weekStart: CalendarWeekStart
    let select: (CivilDay) -> Void
    let newItem: (CivilDay) -> Void
    let open: (CalendarItem) -> Void
    let edit: (CalendarItem, CalendarEditorAction) -> Void
    private let hourHeight: CGFloat = 50
    private let gutter: CGFloat = 30

    private struct Entry: Identifiable {
        let item: CalendarItem
        let from: Int
        let to: Int
        var lane: Int = 0
        var width: Int = 1
        var id: String { "\(item.id)-\(from)-\(to)-\(lane)" }
    }

    var body: some View {
        let start = weekStart.start(of: selection)
        let days = (0..<7).map { start.adding($0) }
        let columns = days.map(entries)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter, height: 1)
                ForEach(days) { day in
                    VStack(spacing: 0) {
                        Text(CivilDay.weekdays[day.weekday]).font(.caption2).foregroundStyle(.secondary)
                        Button { select(day) } label: {
                            CalendarDayCell(day: day, selected: selection == day, isToday: today == day,
                                            muted: false, facts: store.facts(day), kinds: [])
                                .equatable()
                        }
                        .buttonStyle(CalendarDateButtonStyle())
                        .disabled(!day.supported)
                        .contextMenu {
                            if day.supported {
                                Button { newItem(day) } label: { Label("新建事项", systemImage: "plus") }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 9)
            allDayRow(days)
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    timeline(days: days, columns: columns)
                }
                .frame(height: 305)
                .accessibilityIdentifier("calendar-week-timeline-\(start.key)")
                .defaultScrollAnchor(.top)
                .onAppear {
                    proxy.scrollTo(Self.initialHour(columns), anchor: .top)
                }
                .onChange(of: start) { _, _ in
                    proxy.scrollTo(Self.initialHour(columns), anchor: .top)
                }
            }
        }
        .padding(.horizontal, 6)
        .calendarCard()
    }

    private static func initialHour(_ columns: [[Entry]]) -> Int {
        let earliest = columns.flatMap { $0 }.map(\.from).min() ?? 480
        return min(8, earliest / 60)
    }

    private func allDayRow(_ days: [CivilDay]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("全天").font(.system(size: 8)).foregroundStyle(.secondary)
                .frame(width: gutter, alignment: .leading)
                .padding(.top, 4)
            ForEach(days) { day in
                VStack(spacing: 3) {
                    ForEach(store.items(on: day).filter { !$0.isTimed }) { item in
                        Button { open(item) } label: {
                            eventTile(item)
                        }
                        .buttonStyle(.plain)
                        .calendarItemMenu(item) { edit(item, $0) }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .top)
                .padding(.horizontal, 1)
            }
        }
        .padding(.vertical, 4)
    }

    private func timeline(days: [CivilDay], columns: [[Entry]]) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: gutter, alignment: .leading)
                    Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .background {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter)
                ForEach(days) { day in
                    Rectangle()
                        .fill(day == selection ? CalendarTheme.accent.opacity(0.06) : .clear)
                        .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.13)).frame(width: 1) }
                }
            }
            .accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter)
                ForEach(Array(columns.enumerated()), id: \.offset) { _, entries in
                    GeometryReader { geometry in
                        ForEach(entries) { entry in
                            let width = geometry.size.width / CGFloat(entry.width)
                            Button { open(entry.item) } label: { eventTile(entry.item) }
                                .buttonStyle(.plain)
                                .frame(width: max(1, width - 2),
                                       height: max(16, y(entry.to - entry.from) - 2), alignment: .topLeading)
                                .background(entry.item.kind.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
                                .offset(x: width * CGFloat(entry.lane) + 1, y: y(entry.from))
                                .calendarItemMenu(entry.item) { edit(entry.item, $0) }
                        }
                    }
                }
            }
        }
    }

    private func y(_ minutes: Int) -> CGFloat { CGFloat(minutes) / 60 * hourHeight }

    private func eventTile(_ item: CalendarItem) -> some View {
        Text(item.title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(item.kind.color)
            .lineLimit(2)
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(item.kind.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
    }

    private func entries(_ day: CivilDay) -> [Entry] {
        var result = store.items(on: day).flatMap { item in
            store.engine.segments(item, on: day).map { Entry(item: item, from: $0.from, to: $0.to) }
        }
        result.sort { ($0.from, -$0.to) < ($1.from, -$1.to) }
        var groupStart = 0
        var groupEnd = 0
        var laneEnds: [Int] = []
        for index in result.indices {
            let current = result[index]
            if current.from >= groupEnd {
                for index in groupStart..<index { result[index].width = laneEnds.count }
                groupStart = index
                laneEnds.removeAll(keepingCapacity: true)
            }
            groupEnd = max(groupEnd, current.to)
            let lane = laneEnds.firstIndex { $0 <= current.from } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(current.to) } else { laneEnds[lane] = current.to }
            result[index].lane = lane
        }
        for index in groupStart..<result.count { result[index].width = laneEnds.count }
        return result
    }
}
