import SwiftUI

struct CalendarPager: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let mode: CalendarMode
    @Binding var selection: CivilDay
    let today: CivilDay
    let showMonth: (CivilDay) -> Void
    let openItem: (CalendarItem) -> Void

    @State private var position: ScrollPosition
    @State private var displayedPage: Int
    @State private var heights: [Int: CGFloat] = [:]

    init(mode: CalendarMode, selection: Binding<CivilDay>, today: CivilDay,
         showMonth: @escaping (CivilDay) -> Void, openItem: @escaping (CalendarItem) -> Void) {
        self.mode = mode
        self._selection = selection
        self.today = today
        self.showMonth = showMonth
        self.openItem = openItem
        let initial = mode.page(containing: selection.wrappedValue)
        var startingPosition = ScrollPosition(idType: Int.self)
        startingPosition.scrollTo(id: initial, anchor: .center)
        _position = State(initialValue: startingPosition)
        _displayedPage = State(initialValue: initial)
    }

    var body: some View {
        let height = heights[displayedPage] ?? mode.estimatedHeight
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(0..<mode.pageCount, id: \.self) { page in
                    content(on: page)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .containerRelativeFrame(.horizontal)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                            if measured > 0 { heights[page] = measured }
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
        .onScrollPhaseChange { previous, phase, context in
            guard phase == .idle,
                  position.isPositionedByUser || previous == .interacting || previous == .decelerating else { return }
            let width = context.geometry.containerSize.width
            guard width > 0 else { return }
            let reachedPage = Int(floor(context.geometry.visibleRect.midX / width))
            guard (0..<mode.pageCount).contains(reachedPage) else { return }
            displayedPage = reachedPage
            if reachedPage != mode.page(containing: selection) {
                selection = mode.day(on: reachedPage, matching: selection)
            }
        }
        .onChange(of: mode.page(containing: selection)) { _, target in
            guard target != displayedPage else { return }
            let animate = !reduceMotion && abs(target - displayedPage) == 1
            displayedPage = target
            withAnimation(animate ? .smooth(duration: 0.28) : nil) {
                position.scrollTo(id: target, anchor: .center)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: height)
        .accessibilityIdentifier("calendar-pager")
    }

    @ViewBuilder private func content(on page: Int) -> some View {
        let day = mode.day(on: page, matching: selection)
        switch mode {
        case .month:
            MonthGrid(selection: day, today: today, select: select)
        case .week:
            WeekGrid(selection: day, today: today, select: select, open: openItem)
        case .year:
            YearGrid(selection: day, today: today) { month in
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

private struct CalendarDayCell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let day: CivilDay
    let selected: Bool
    let isToday: Bool
    let muted: Bool
    let facts: DayFacts?
    let kinds: [EventKind]

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day.day)")
                .font(.system(size: 19, weight: selected || isToday ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : isToday ? CalendarTheme.accent : CalendarTheme.ink.opacity(muted ? 0.34 : 1))
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
                            .background(.white, in: Circle())
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
    let select: (CivilDay) -> Void
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 1), count: 7)

    var body: some View {
        let first = selection.monthStart
        VStack(spacing: 8) {
            HStack(spacing: 1) {
                ForEach(Array(CivilDay.weekdays.enumerated()), id: \.element) { index, name in
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(index >= 5 ? CalendarTheme.accent : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<42, id: \.self) { offset in
                    let day = first.adding(offset - first.weekday)
                    let itemKinds = Set(store.items(on: day).map(\.kind))
                    Button { select(day) } label: {
                        CalendarDayCell(day: day, selected: day == selection, isToday: day == today,
                                        muted: day.month != selection.month, facts: store.engine.facts(day),
                                        kinds: EventKind.allCases.filter { itemKinds.contains($0) })
                    }
                    .disabled(!day.supported)
                    .buttonStyle(CalendarDateButtonStyle())
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .calendarCard()
    }
}

struct YearGrid: View {
    let selection: CivilDay
    let today: CivilDay
    let choose: (Int) -> Void
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 7), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
            ForEach(1...12, id: \.self) { month in
                Button { choose(month) } label: {
                    miniMonth(month)
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

    private func miniMonth(_ month: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(month)月")
                .font(.subheadline.bold())
                .foregroundStyle(month == selection.month ? CalendarTheme.accent : CalendarTheme.ink)
            miniMonthDays(for: CivilDay(selection.year, month, 1))
        }
        .padding(6)
        .background(month == selection.month ? CalendarTheme.accent.opacity(0.08) : .white.opacity(0.42),
                    in: RoundedRectangle(cornerRadius: 13))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private func miniMonthDays(for first: CivilDay) -> some View {
        let month = first.month
        let weekdayOffset = first.weekday
        let count = first.daysInMonth
        let selectedDay = selection.month == month ? selection.day : nil
        let currentDay = today.year == first.year && today.month == month ? today.day : nil
        let rowHeight: CGFloat = 15
        return Canvas { context, size in
            let columnWidth = size.width / 7
            for (column, weekday) in CivilDay.weekdays.enumerated() {
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
                    .foregroundStyle(highlighted ? Color.white : CalendarTheme.ink)
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
    let select: (CivilDay) -> Void
    let open: (CalendarItem) -> Void
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
        let start = selection.weekStart
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
                                            muted: false, facts: store.engine.facts(day), kinds: [])
                        }
                        .buttonStyle(CalendarDateButtonStyle())
                        .disabled(!day.supported)
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
