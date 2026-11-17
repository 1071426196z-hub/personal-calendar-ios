import ActivityKit
import SwiftUI

@MainActor
enum CalendarLiveActivities {
    static func nextTime(for item: CalendarItem, store: CalendarStore, since now: Date = .now) -> Date? {
        if item.isTimed, (item.repeatRule ?? .none) == .none, let start = item.startInstant {
            return start > now ? start : nil
        }
        var day = CivilDay.localDay(containing: now, in: store.timeZone)
        for _ in 0..<3 {
            guard let next = store.engine.nextOccurrence(of: item, onOrAfter: day), next.supported else { return nil }
            let time = item.isTimed ? (item.start ?? "09:00") : "09:00"
            if let target = next.instant(at: time, in: store.timeZone), target > now { return target }
            day = next.adding(1)
        }
        return nil
    }

    static func isScheduled(for id: String) -> Bool {
        Activity<CalendarLiveAttributes>.activities.contains { $0.attributes.itemID == id }
    }

    static func start(for item: CalendarItem, target: Date) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw LiveError.disabled }
        let now = Date.now
        guard target > now else { throw LiveError.past }
        await stop(for: item.id)

        let start = target.addingTimeInterval(-30 * 60)
        let attributes = CalendarLiveAttributes(itemID: item.id)
        let content = ActivityContent(state: CalendarLiveAttributes.ContentState(title: item.title,
                                       begins: max(now, start), target: target), staleDate: target)
        if start > .now {
            let alert = AlertConfiguration(title: "日历倒计时已开始", body: "在锁屏或灵动岛查看剩余时间。", sound: .default)
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil,
                                     style: .standard, alertConfiguration: alert, startDate: start)
        } else {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    static func stop(for id: String) async {
        for activity in Activity<CalendarLiveAttributes>.activities where activity.attributes.itemID == id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func reconcile(_ store: CalendarStore) async {
        for activity in Activity<CalendarLiveAttributes>.activities {
            let state = activity.content.state
            let current = store.allItems.first { $0.id == activity.attributes.itemID }
            if let current, current.title == state.title, nextTime(for: current, store: store) == state.target { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private enum LiveError: LocalizedError {
        case disabled, past

        var errorDescription: String? {
            switch self {
            case .disabled: "请在系统设置中允许本 App 的实时活动。"
            case .past: "这条事项的时间已过。"
            }
        }
    }
}
