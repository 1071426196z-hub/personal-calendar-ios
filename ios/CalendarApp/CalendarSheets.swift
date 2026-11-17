import SwiftUI

struct DateJumpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: CivilDay
    @State private var draft = Date()

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("日期", selection: $draft, in: CivilDay.first.date...CivilDay.last.date,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
                    .padding()
                Spacer(minLength: 0)
            }
            .background { CalendarTheme.background }
            .environment(\.timeZone, CivilDay.calendar.timeZone)
            .environment(\.calendar, CivilDay.calendar)
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        selection = CivilDay(draft)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { draft = selection.date }
        .presentationDetents([.medium, .large])
    }
}

struct CalendarEditor: View {
    @EnvironmentObject private var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    private let original: CalendarItem?
    private let selection: CivilDay
    @State private var kind: EventKind
    @State private var title: String
    @State private var date: Date
    @State private var endDate: Date
    @State private var start: Date
    @State private var end: Date
    @State private var repeatRule: RepeatRule
    @State private var allDay: Bool
    @State private var annual: Bool
    @State private var useLunar: Bool
    @State private var lunar: LunarRule
    @State private var year: Int
    @State private var note: String
    @State private var error: String?

    init(day: CivilDay, item: CalendarItem?) {
        original = item
        selection = day
        let from = item.flatMap { CivilDay($0.date) } ?? day
        _kind = State(initialValue: item?.kind ?? .event)
        _title = State(initialValue: item?.title ?? "")
        _date = State(initialValue: from.date)
        _endDate = State(initialValue: item?.endDate.flatMap(CivilDay.init)?.date ?? from.date)
        _start = State(initialValue: Self.timeDate(item?.start ?? "09:00"))
        _end = State(initialValue: Self.timeDate(item?.end ?? "10:00"))
        _repeatRule = State(initialValue: item?.repeatRule ?? .none)
        _allDay = State(initialValue: item?.allDay ?? false)
        _annual = State(initialValue: item?.annual ?? true)
        _useLunar = State(initialValue: item?.lunar != nil)
        _lunar = State(initialValue: item?.lunar ?? LunarRule(month: 1, day: 1, leap: false))
        _year = State(initialValue: from.year)
        _note = State(initialValue: item?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("事项类型", selection: $kind) {
                        ForEach(EventKind.allCases) { item in Text(item.label).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editor-kind")
                    TextField("标题", text: $title)
                        .accessibilityIdentifier("editor-title")
                }
                Section {
                    switch kind {
                    case .event: eventFields
                    case .birthday: lunarFields(showYear: false)
                    case .anniversary:
                        Picker("历法", selection: $useLunar) {
                            Text("公历").tag(false)
                            Text("农历").tag(true)
                        }
                        if useLunar { lunarFields(showYear: true) }
                        else { datePicker("日期", value: $date) }
                        Toggle("每年重复", isOn: $annual)
                    case .countdown: datePicker("目标日期", value: $date)
                    }
                }
                Section("备注") {
                    TextField("添加备注", text: $note, axis: .vertical).lineLimit(3...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background { CalendarTheme.background }
            .environment(\.timeZone, CivilDay.calendar.timeZone)
            .environment(\.calendar, CivilDay.calendar)
            .navigationTitle(original == nil ? "新建事项" : "编辑事项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .accessibilityIdentifier("editor-save")
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if let facts = store.facts(original.flatMap { CivilDay($0.date) } ?? selection) {
                if original?.lunar == nil { lunar = facts.moon }
                let monthStartsInPreviousYear = CivilDay(date).month <= 2 && facts.moon.month >= 11
                year = CivilDay(date).year - (monthStartsInPreviousYear ? 1 : 0)
            }
        }
        .alert("请检查日期和时间", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("确定", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var eventFields: some View {
        Group {
            Toggle("全天", isOn: $allDay)
            datePicker("开始日期", value: $date)
                .onChange(of: date) { _, updated in
                    if endDate < updated { endDate = updated }
                }
            if !allDay { DatePicker("开始时间", selection: $start, displayedComponents: .hourAndMinute) }
            datePicker("结束日期", value: $endDate, lowerBound: CivilDay(date))
            if !allDay { DatePicker("结束时间", selection: $end, displayedComponents: .hourAndMinute) }
            Picker("重复", selection: $repeatRule) {
                ForEach(RepeatRule.allCases) { rule in Text(rule.label).tag(rule) }
            }
        }
    }

    private func lunarFields(showYear: Bool) -> some View {
        Group {
            if showYear {
                Picker("农历年份", selection: $year) {
                    ForEach(CivilDay.first.year...CivilDay.last.year, id: \.self) { year in
                        Text(verbatim: "\(year)年").tag(year)
                    }
                }
            }
            Picker("农历月份", selection: $lunar.month) {
                ForEach(1...12, id: \.self) { month in
                    Text(LunarRule.months[month - 1]).tag(month)
                }
            }
            Picker("农历日期", selection: $lunar.day) {
                ForEach(1...30, id: \.self) { day in Text(LunarRule.days[day - 1]).tag(day) }
            }
            Toggle("闰月", isOn: $lunar.leap)
            if let next = lunarPreview(showYear: showYear) {
                LabeledContent(showYear ? "对应公历" : "最近一次", value: next.label)
            }
        }
    }

    private func lunarPreview(showYear: Bool) -> CivilDay? {
        showYear ? store.engine.lunarDay(year: year, rule: lunar)
            : store.engine.nextLunar(rule: lunar, from: selection)
    }

    private func datePicker(_ label: String, value: Binding<Date>, lowerBound: CivilDay = CivilDay.first) -> some View {
        DatePicker(label, selection: value, in: lowerBound.date...CivilDay.last.date, displayedComponents: .date)
    }

    private static func timeDate(_ key: String) -> Date {
        let parts = key.split(separator: ":").compactMap { Int($0) }
        return CivilDay(2001, 1, 1).date.addingTimeInterval(
            Double((parts.first ?? 9) * 60 + (parts.last ?? 0)) * 60
        )
    }

    private static func timeKey(_ value: Date) -> String {
        CivilDay.timeKey(value, in: CivilDay.calendar)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let from = CivilDay(date)
        var item = CalendarItem(id: original?.id ?? UUID().uuidString, kind: kind, title: cleanTitle,
                                date: from.key, note: note, sample: original?.sample)
        switch kind {
        case .event:
            let to = CivilDay(endDate)
            let startTime = Self.timeKey(start)
            let endTime = Self.timeKey(end)
            guard to >= from, allDay || to > from || endTime > startTime else {
                error = "结束时间要晚于开始时间。"
                return
            }
            item.endDate = to.key
            item.allDay = allDay
            item.start = allDay ? nil : startTime
            item.end = allDay ? nil : endTime
            item.repeatRule = repeatRule
            if !allDay, repeatRule == .none {
                let sameStart = original?.date == from.key && original?.start == startTime
                let sameEnd = original?.endDate == to.key && original?.end == endTime
                guard let first = (sameStart ? original?.startInstant : nil) ?? from.instant(at: startTime, in: store.timeZone),
                      let last = (sameEnd ? original?.endInstant : nil) ?? to.instant(at: endTime, in: store.timeZone),
                      last > first else {
                    error = "请选一个在当前时区有效的开始和结束时间。"
                    return
                }
                item.startInstant = first
                item.endInstant = last
            }
        case .birthday:
            let existing = kind == original?.kind && lunar == original?.lunar ? original.flatMap { CivilDay($0.date) } : nil
            guard let next = existing ?? lunarPreview(showYear: false), next.supported else {
                error = "找不到支持范围内的农历生日日期。"
                return
            }
            item.date = next.key
            item.lunar = lunar
        case .anniversary:
            item.annual = annual
            if useLunar {
                guard let next = lunarPreview(showYear: true), next.supported else {
                    error = "请选一个支持范围内的农历日期。"
                    return
                }
                item.date = next.key
                item.lunar = lunar
            }
        case .countdown: break
        }
        store.save(item)
        dismiss()
    }
}

struct CalendarItemDetail: View {
    @EnvironmentObject private var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    let item: CalendarItem
    let day: CivilDay

    var body: some View {
        let current = store.allItems.first { $0.id == item.id } ?? item
        NavigationStack {
            Form {
                Section {
                    LabeledContent("类型", value: current.displayKind)
                    if let source = current.linkedSource { LabeledContent("同步来源", value: source) }
                    if let date = CivilDay(current.date) { LabeledContent("日期", value: date.label) }
                    if current.kind == .event {
                        LabeledContent("时间", value: current.timeLabel)
                        if !current.isLinked { LabeledContent("重复", value: (current.repeatRule ?? .none).label) }
                    }
                    if let lunar = current.lunar { LabeledContent("农历", value: lunar.label) }
                    if current.kind == .birthday || (current.kind == .anniversary && current.annual == true) {
                        if let next = store.engine.upcoming(current, from: .today) {
                            LabeledContent("下一次", value: next.label)
                        }
                    }
                    if current.kind == .countdown { LabeledContent("倒数", value: current.countdownLabel) }
                    if current.sample == true { LabeledContent("来源", value: "示例事项") }
                }
                if !current.note.isEmpty { Section("备注") { Text(current.note) } }
                if !current.isLinked {
                    Section { Button("删除事项", role: .destructive) { deleting = true } }
                }
            }
            .scrollContentBackground(.hidden)
            .background { CalendarTheme.background }
            .navigationTitle(current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                if !current.isLinked {
                    ToolbarItem(placement: .confirmationAction) { Button("编辑") { editing = true } }
                }
            }
            .sheet(isPresented: $editing) { CalendarEditor(day: day, item: current) }
            .confirmationDialog("删除这条事项？", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    store.remove(current.id)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

struct CalendarSearch: View {
    @EnvironmentObject private var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var detail: CalendarItem?

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = store.allItems.filter {
            term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) || $0.note.localizedCaseInsensitiveContains(term)
        }.sorted { $0.date < $1.date }
        NavigationStack {
            List {
                if matching.isEmpty {
                    ContentUnavailableView.search(text: term)
                }
                ForEach(matching) { item in
                    Button { detail = item } label: { CalendarItemRow(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索标题或备注")
            .navigationTitle("搜索事项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $detail) { item in
                CalendarItemDetail(item: item, day: CivilDay(item.date) ?? .today)
            }
        }
    }
}

struct AlmanacSheet: View {
    @EnvironmentObject private var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var day: CivilDay
    @State private var selectedHour: String?

    init(day: CivilDay) {
        _day = State(initialValue: day)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        navigationButton(-1, icon: "chevron.left", label: "前一天")
                        Spacer()
                        VStack(spacing: 4) {
                            Text("\(day.month)月\(day.day)日").font(.title2.bold())
                            Text(store.engine.facts(day)?.lunarText ?? day.weekdayLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        navigationButton(1, icon: "chevron.right", label: "后一天")
                    }
                    .padding(16)
                    .calendarCard()
                    if let data = store.engine.almanac(day, includeHours: true) {
                        dailyCard(data)
                        hourlyCard(data.hours)
                    }
                }
                .padding(16)
            }
            .background { CalendarTheme.background }
            .navigationTitle("黄历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func navigationButton(_ delta: Int, icon: String, label: String) -> some View {
        let target = day.adding(delta)
        return Button {
            day = target
            selectedHour = nil
        } label: {
            Image(systemName: icon).font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel(label)
        .disabled(!target.supported)
        .buttonStyle(.plain)
    }

    private func dailyCard(_ data: AlmanacData) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(data.pillars).font(.headline)
            activity("宜", data.yi, color: .green)
            activity("忌", data.ji, color: CalendarTheme.accent)
            Divider()
            LabeledContent("冲煞", value: data.conflict)
            LabeledContent("值神", value: data.guardian)
            LabeledContent("喜神", value: data.happiness)
            LabeledContent("财神", value: data.wealth)
        }
        .font(.subheadline)
        .padding(16)
        .calendarCard()
    }

    private func hourlyCard(_ hours: [AlmanacHour]) -> some View {
        let displayed = hours.first { $0.id == selectedHour } ?? hours.first
        return VStack(alignment: .leading, spacing: 12) {
            Text("时辰").font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(hours) { hour in
                        Button { selectedHour = hour.id } label: {
                            VStack(spacing: 4) {
                                Text(hour.branch).font(.subheadline.bold())
                                Text(hour.luck).font(.caption2)
                            }
                            .foregroundStyle(hour.id == displayed?.id ? Color.white : CalendarTheme.ink)
                            .frame(minWidth: 40, minHeight: 47)
                            .background(hour.id == displayed?.id ? CalendarTheme.ink : .white.opacity(0.58),
                                        in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(hour.branch)时 \(hour.start) \(hour.luck)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            if let hour = displayed {
                Text("\(hour.ganzhi) · \(hour.start)–\(hour.end) · \(hour.luck)")
                    .font(.subheadline.weight(.semibold))
                activity("宜", hour.yi, color: .green)
                activity("忌", hour.ji, color: CalendarTheme.accent)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .calendarCard()
    }

    private func activity(_ title: String, _ activities: [String], color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).fontWeight(.bold).foregroundStyle(color)
            Text(activities.joined(separator: "、")).foregroundStyle(.secondary)
        }
    }
}
