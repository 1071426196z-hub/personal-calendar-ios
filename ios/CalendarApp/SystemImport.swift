import EventKit
import SwiftUI
import UIKit

enum SystemSource: String, CaseIterable, Identifiable {
    case reminders, calendars

    var id: String { rawValue }
    var entityType: EKEntityType { self == .reminders ? .reminder : .event }
    var title: String { self == .reminders ? "系统提醒事项" : "系统日历" }
    var icon: String { self == .reminders ? "bell" : "calendar" }
    var listTitle: String { self == .reminders ? "提醒列表" : "日历" }
}

struct ImportList: Identifiable {
    let id: String
    let title: String
    let account: String
}

@MainActor
final class SystemImport: ObservableObject {
    @Published private(set) var enabled: Set<SystemSource>
    @Published private(set) var excluded: [String: [String]]
    @Published private(set) var lists: [SystemSource: [ImportList]] = [:]
    @Published private(set) var access: [SystemSource: EKAuthorizationStatus] = [:]
    @Published private(set) var undated: [String] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var requesting: SystemSource?
    @Published private(set) var message: String?

    private let eventStore = EKEventStore()
    private let defaults: UserDefaults
    private var generation = 0
    private var visibleDay = CivilDay.today
    private var linkedItemsBySource: [SystemSource: [CalendarItem]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Set((defaults.stringArray(forKey: "system-import-sources") ?? []).compactMap(SystemSource.init))
        excluded = defaults.dictionary(forKey: "system-import-excluded") as? [String: [String]] ?? [:]
        updateAccess()
    }

    var changes: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventStore)
    }

    func allowed(_ source: SystemSource) -> Bool { access[source] == .fullAccess }

    func listEnabled(_ list: ImportList, source: SystemSource) -> Bool {
        !(excluded[source.rawValue] ?? []).contains(list.id)
    }

    func setList(_ list: ImportList, source: SystemSource, enabled: Bool, store: CalendarStore) async {
        var ids = Set(excluded[source.rawValue] ?? [])
        if enabled { ids.remove(list.id) } else { ids.insert(list.id) }
        excluded[source.rawValue] = ids.sorted()
        defaults.set(excluded, forKey: "system-import-excluded")
        await refresh(around: visibleDay, store: store)
    }

    func setEnabled(_ value: Bool, source: SystemSource, store: CalendarStore) async {
        guard requesting == nil else { return }
        message = nil
        if value {
            requesting = source
            defer { requesting = nil }
            do {
                let granted: Bool
                switch source {
                case .reminders: granted = try await eventStore.requestFullAccessToReminders()
                case .calendars: granted = try await eventStore.requestFullAccessToEvents()
                }
                updateAccess()
                guard granted else {
                    message = "请在系统设置里允许读取\(source.title)。"
                    return
                }
                enabled.insert(source)
            } catch {
                updateAccess()
                message = "暂时无法读取\(source.title)。请检查系统权限后重试。"
                return
            }
        } else {
            enabled.remove(source)
        }
        defaults.set(enabled.map(\.rawValue).sorted(), forKey: "system-import-sources")
        await refresh(around: visibleDay, store: store)
    }

    func refresh(around day: CivilDay, store: CalendarStore) async {
        visibleDay = day
        generation += 1
        let revision = generation
        updateAccess()
        let connected = SystemSource.allCases.filter { enabled.contains($0) && allowed($0) }
        for source in SystemSource.allCases where !connected.contains(source) {
            lists[source] = nil
            linkedItemsBySource[source] = nil
        }
        if !connected.contains(.reminders) { undated = [] }
        publishItems(to: store)
        guard !connected.isEmpty else {
            isRefreshing = false
            lastRefresh = nil
            return
        }

        isRefreshing = true
        defer { if generation == revision { isRefreshing = false } }

        var systemLists: [SystemSource: [ImportList]] = [:]
        var events: [CalendarItem] = []
        var reminders: [CalendarItem] = []
        var unscheduled: [String] = []
        let timeZone = store.timeZone
        for source in connected {
            let calendars = eventStore.calendars(for: source.entityType)
            systemLists[source] = calendars.map {
                ImportList(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "")
            }
            let ignored = Set(excluded[source.rawValue] ?? [])
            let active = calendars.filter { !ignored.contains($0.calendarIdentifier) }
            guard !active.isEmpty else { continue }
            switch source {
            case .calendars:
                events = SystemFeed.events(eventStore, calendars: active, around: day, in: timeZone)
                let today = CivilDay.today
                if today.monthStart != day.monthStart {
                    events += SystemFeed.events(eventStore, calendars: active, around: today, in: timeZone)
                }
            case .reminders:
                let loaded = await SystemFeed.reminders(eventStore, calendars: active, in: timeZone)
                reminders = loaded.dated
                unscheduled = loaded.undated
            }
        }
        guard generation == revision, !Task.isCancelled else { return }
        lists = systemLists
        linkedItemsBySource[.calendars] = events
        linkedItemsBySource[.reminders] = reminders
        undated = unscheduled
        publishItems(to: store)
        lastRefresh = .now
    }

    private func publishItems(to store: CalendarStore) {
        var seen: Set<String> = []
        let items = SystemSource.allCases.flatMap { linkedItemsBySource[$0] ?? [] }
            .filter { seen.insert($0.id).inserted }
        store.setLinkedItems(items)
    }

    private func updateAccess() {
        access = Dictionary(uniqueKeysWithValues: SystemSource.allCases.map {
            ($0, EKEventStore.authorizationStatus(for: $0.entityType))
        })
    }
}

enum SystemFeed {
    static func events(_ store: EKEventStore, calendars: [EKCalendar], around date: CivilDay,
                       in timeZone: TimeZone) -> [CalendarItem] {
        let first = date.monthStart.movingMonths(-1)
        let last = date.monthStart.movingMonths(2)
        let calendar = CivilDay.localCalendar(in: timeZone)
        let start = calendar.date(from: DateComponents(year: first.year, month: first.month, day: 1)) ?? first.date
        let end = calendar.date(from: DateComponents(year: last.year, month: last.month, day: 1)) ?? last.date
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            guard let start = event.startDate, let finish = event.endDate else { return nil }
            let allDay = event.isAllDay
            let effectiveEnd = allDay && finish > start ? finish.addingTimeInterval(-1) : max(start, finish)
            let dateZone = allDay ? event.timeZone ?? timeZone : timeZone
            let from = CivilDay.localDay(containing: start, in: dateZone)
            let to = CivilDay.localDay(containing: effectiveEnd, in: dateZone)
            var item = CalendarItem(id: "system-event:\(event.calendarItemIdentifier):\(start.timeIntervalSinceReferenceDate)",
                                    kind: .event, title: event.title ?? "无标题日程", date: from.key,
                                    endDate: to.key, repeatRule: RepeatRule.none, allDay: allDay,
                                    note: event.notes ?? "", linkedSource: event.calendar?.title ?? "系统日历")
            if !allDay {
                let adjustedEnd = max(finish, start.addingTimeInterval(60))
                item.start = CivilDay.timeKey(start, in: calendar)
                item.end = CivilDay.timeKey(adjustedEnd, in: calendar)
                item.endDate = CivilDay.localDay(containing: adjustedEnd, in: timeZone).key
            }
            return item
        }
    }

    @MainActor
    static func reminders(_ store: EKEventStore, calendars: [EKCalendar],
                          in timeZone: TimeZone) async -> (dated: [CalendarItem], undated: [String]) {
        let predicate = store.predicateForReminders(in: calendars)
        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        var dated: [CalendarItem] = []
        var undated: [String] = []
        let calendar = CivilDay.localCalendar(in: timeZone)
        for reminder in fetched where !reminder.isCompleted {
            let title = reminder.title ?? "无标题提醒"
            guard let due = reminder.dueDateComponents ?? reminder.startDateComponents,
                  let instant = instant(from: due, in: timeZone) else {
                undated.append(title)
                continue
            }
            let day = CivilDay.localDay(containing: instant, in: timeZone)
            let time = due.hour.map { _ in CivilDay.timeKey(instant, in: calendar) }
            var item = CalendarItem(id: "system-reminder:\(reminder.calendarItemIdentifier)",
                                    kind: .event, title: title, date: day.key, endDate: day.key,
                                    repeatRule: RepeatRule.none, allDay: time == nil, note: reminder.notes ?? "",
                                    linkedSource: reminder.calendar?.title ?? "系统提醒事项",
                                    reminderTime: time, isSystemReminder: true)
            if let time {
                let finish = instant.addingTimeInterval(60)
                let endDay = CivilDay.localDay(containing: finish, in: timeZone)
                item.start = time
                item.end = endDay == day ? CivilDay.timeKey(finish, in: calendar) : "00:00"
                item.endDate = endDay.key
            }
            dated.append(item)
        }
        return (dated, undated.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    private static func instant(from input: DateComponents, in timeZone: TimeZone) -> Date? {
        var calendar = input.calendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = input.hour == nil ? timeZone : (input.timeZone ?? timeZone)
        var parts = input
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        return calendar.date(from: parts)
    }

}

struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: CalendarStore
    @ObservedObject var importer: SystemImport
    let day: CivilDay

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SystemSource.allCases) { source in
                        Toggle(isOn: binding(for: source)) {
                            Label(source.title, systemImage: source.icon)
                        }
                        .disabled(importer.requesting != nil)
                        if needsSettings(source) {
                            Button("在系统设置中授权") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                } footer: {
                    Text("会显示 iPhone 系统日历和提醒事项里的记录，包括已同步到系统的其他 App。源记录在原 App 中编辑。")
                }
                Section("文件与跨设备") {
                    NavigationLink {
                        CalendarTransferSheet(kind: .backup)
                    } label: {
                        Label("备份与恢复", systemImage: "externaldrive")
                    }
                    .accessibilityIdentifier("calendar-backup")
                    NavigationLink {
                        CalendarTransferSheet(kind: .calendar)
                    } label: {
                        Label("导入 .ics 日历", systemImage: "doc")
                    }
                    NavigationLink {
                        XiaomiCalendarSheet(importer: importer, day: day)
                    } label: {
                        Label("小米手机日历", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("xiaomi-calendar-source")
                }
                ForEach(SystemSource.allCases) { source in
                    if importer.enabled.contains(source), importer.allowed(source),
                       let lists = importer.lists[source], !lists.isEmpty {
                        Section(source.listTitle) {
                            ForEach(lists) { list in
                                Toggle(isOn: Binding(
                                    get: { importer.listEnabled(list, source: source) },
                                    set: { value in Task { await importer.setList(list, source: source, enabled: value, store: store) } }
                                )) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(list.title)
                                        if !list.account.isEmpty {
                                            Text(list.account).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if !importer.enabled.isEmpty {
                    Section {
                        Button {
                            Task { await importer.refresh(around: day, store: store) }
                        } label: {
                            Label("立即同步", systemImage: "arrow.clockwise")
                        }
                        .disabled(importer.isRefreshing)
                        if importer.isRefreshing {
                            ProgressView("同步中")
                        } else if let latest = importer.lastRefresh {
                            LabeledContent("最近同步") { Text(latest, style: .relative) }
                        }
                        if let message = importer.message {
                            Text(message).foregroundStyle(.secondary)
                        }
                    }
                } else if let message = importer.message {
                    Text(message).foregroundStyle(.secondary)
                }
                if !importer.undated.isEmpty {
                    Section {
                        ForEach(Array(importer.undated.enumerated()), id: \.offset) { _, title in
                            Label(title, systemImage: "bell")
                        }
                    } header: {
                        Text("未设日期的提醒")
                    } footer: {
                        Text("在提醒事项里设置日期后，就会出现在日历中。")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { CalendarTheme.background }
            .navigationTitle("导入与同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func binding(for source: SystemSource) -> Binding<Bool> {
        Binding(
            get: { importer.enabled.contains(source) && importer.allowed(source) },
            set: { value in Task { await importer.setEnabled(value, source: source, store: store) } }
        )
    }

    private func needsSettings(_ source: SystemSource) -> Bool {
        importer.access[source] == .denied || importer.access[source] == .restricted || importer.access[source] == .writeOnly
    }
}

private struct XiaomiCalendarSheet: View {
    @EnvironmentObject private var store: CalendarStore
    @Environment(\.openURL) private var openURL
    @ObservedObject var importer: SystemImport
    let day: CivilDay

    var body: some View {
        Form {
            Section("通过共同账户同步") {
                Text("在小米手机上，将要同步的日程保存到 Google 或 Exchange 日历账户。")
                Text("在 iPhone 的「设置 → App → 日历 → 日历账户」中添加同一账户并开启日历。")
                Button(importer.enabled.contains(.calendars) ? "刷新系统日历" : "允许读取系统日历") {
                    Task {
                        if importer.enabled.contains(.calendars), importer.allowed(.calendars) {
                            await importer.refresh(around: day, store: store)
                        } else {
                            await importer.setEnabled(true, source: .calendars, store: store)
                        }
                    }
                }
                .disabled(importer.isRefreshing || importer.requesting != nil)
                if importer.access[.calendars] == .denied || importer.access[.calendars] == .restricted {
                    Button("打开 App 权限设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                if let message = importer.message { Text(message).foregroundStyle(.secondary) }
                if importer.allowed(.calendars), importer.enabled.contains(.calendars) {
                    Text("回到「导入与同步」，可以选择要显示的日历。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("迁移小米云中的日程") {
                Text("小米账户日历暂时无法直接连接。已有 .ics 文件时，可以导入本 App。")
                NavigationLink("导入 .ics 文件") { CalendarTransferSheet(kind: .calendar) }
                Link("打开小米云服务", destination: URL(string: "https://i.mi.com/")!)
            }
        }
        .scrollContentBackground(.hidden)
        .background { CalendarTheme.background }
        .navigationTitle("小米手机日历")
        .navigationBarTitleDisplayMode(.inline)
    }
}
