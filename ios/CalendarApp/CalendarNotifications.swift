import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class CalendarNotificationDelegate: NSObject, UIApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    struct Route {
        let itemID: String
        let day: CivilDay?
    }

    @Published private(set) var route: Route?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        guard let itemID = info["calendarItem"] as? String else { return }
        let dayKey = info["day"] as? String
        await MainActor.run { self.route = Route(itemID: itemID, day: dayKey.flatMap(CivilDay.init)) }
    }

    func clearRoute() { route = nil }
}

@MainActor
final class CalendarNotifications {
    static let shared = CalendarNotifications()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "personal-calendar-notice-"
    private var refreshing = false
    private var refreshNeeded = false

    func requestPermission(for store: CalendarStore) async {
        if (await center.notificationSettings()).authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        refresh(store)
    }

    func refresh(_ store: CalendarStore) {
        refreshNeeded = true
        guard !refreshing else { return }
        refreshing = true
        Task {
            while refreshNeeded {
                refreshNeeded = false
                await updateRequests(for: store)
            }
            refreshing = false
        }
    }

    private func updateRequests(for store: CalendarStore) async {
        let status = (await center.notificationSettings()).authorizationStatus
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        guard !refreshNeeded else { return }

        let allowed = status == .authorized || status == .provisional || status == .ephemeral
        let desired = allowed ? plannedRequests(for: store, now: .now) : []
        let previous = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        let obsolete = Set(previous.keys).subtracting(desired.map(\.identifier))
        center.removePendingNotificationRequests(withIdentifiers: Array(obsolete))

        for request in desired {
            guard !refreshNeeded else { return }
            if let old = previous[request.identifier], sameNotice(old, request) { continue }
            do {
                try await center.add(request)
            } catch {
                // A replaced reminder with an obsolete date must not fire if the replacement fails.
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            }
        }
    }

    private func sameNotice(_ old: UNNotificationRequest, _ new: UNNotificationRequest) -> Bool {
        guard let oldTrigger = old.trigger as? UNCalendarNotificationTrigger,
              let newTrigger = new.trigger as? UNCalendarNotificationTrigger else { return false }
        return oldTrigger.dateComponents == newTrigger.dateComponents && oldTrigger.repeats == newTrigger.repeats &&
            old.content.title == new.content.title && old.content.body == new.content.body
    }

    private func plannedRequests(for store: CalendarStore, now: Date) -> [UNNotificationRequest] {
        let calendar = CivilDay.localCalendar(in: store.timeZone)
        let today = CivilDay.localDay(containing: now, in: store.timeZone)
        var candidates: [(date: Date, request: UNNotificationRequest)] = []

        for saved in store.items {
            guard let reminder = saved.reminder else { continue }
            let item = saved.localized(in: store.timeZone)
            var day = today
            var scheduled = 0
            let count = item.kind == .event && item.repeatRule == .daily ? 30 : 8
            for _ in 0..<(count + 3) {
                guard let occurrence = store.engine.nextOccurrence(of: item, onOrAfter: day), occurrence.supported else { break }
                day = occurrence.adding(1)
                guard let time = item.reminderFireDate(on: occurrence, in: calendar), time > now else { continue }
                if scheduled == 0, let repeating = repeatingTrigger(for: item, on: time, in: calendar) {
                    let request = makeRequest(for: item, day: nil, reminder: reminder, trigger: repeating)
                    candidates.append((time, request))
                    break
                }
                var date = CivilDay.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
                date.timeZone = CivilDay.calendar.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
                candidates.append((time, makeRequest(for: item, day: occurrence, reminder: reminder, trigger: trigger)))
                scheduled += 1
                if scheduled == count { break }
            }
        }

        return candidates.sorted { ($0.date, $0.request.identifier) < ($1.date, $1.request.identifier) }
            .prefix(60).map(\.request)
    }

    private func repeatingTrigger(for item: CalendarItem, on date: Date, in calendar: Calendar) -> UNCalendarNotificationTrigger? {
        guard item.kind == .event, let rule = item.repeatRule, rule == .daily || rule == .weekly else { return nil }
        let fields: Set<Calendar.Component> = rule == .weekly ? [.weekday, .hour, .minute] : [.hour, .minute]
        let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents(fields, from: date), repeats: true)
        guard let next = trigger.nextTriggerDate(), abs(next.timeIntervalSince(date)) < 1 else { return nil }
        return trigger
    }

    private func makeRequest(for item: CalendarItem, day: CivilDay?, reminder: CalendarReminder,
                             trigger: UNCalendarNotificationTrigger) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = [item.displayKind, day?.label, reminder.title].compactMap { $0 }.joined(separator: " · ")
        content.sound = .default
        content.threadIdentifier = "calendar-" + item.kind.rawValue
        content.userInfo = ["calendarItem": item.id]
        if let day { content.userInfo["day"] = day.key }
        return UNNotificationRequest(identifier: prefix + item.id + "/" + (day?.key ?? "repeat"), content: content, trigger: trigger)
    }
}
