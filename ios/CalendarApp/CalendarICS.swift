import Foundation

enum CalendarICS {
    struct Import {
        let items: [CalendarItem]
        let skipped: Int
    }

    private struct Property {
        let name: String
        let parameters: [String: String]
        let value: String

        init?(_ line: String) {
            var quoted = false
            guard let separator = line.indices.first(where: { index in
                if line[index] == "\"" { quoted.toggle() }
                return line[index] == ":" && !quoted
            }) else { return nil }
            let fields = line[..<separator].split(separator: ";")
            guard let name = fields.first else { return nil }
            self.name = name.uppercased()
            value = String(line[line.index(after: separator)...])
            var parameters: [String: String] = [:]
            for field in fields.dropFirst() {
                let pair = field.split(separator: "=", maxSplits: 1)
                if pair.count == 2 {
                    parameters[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            self.parameters = parameters
        }
    }

    private struct EventDate {
        let day: CivilDay
        let time: String?
        let instant: Date?
        let zone: TimeZone?
    }

    static func read(_ data: Data, displayTimeZone: TimeZone) throws -> Import {
        guard let text = String(data: data, encoding: .utf8) else { throw CalendarTransferError.invalidCalendar }
        let lines = unfolded(text)
        guard lines.first?.uppercased() == "BEGIN:VCALENDAR", lines.last?.uppercased() == "END:VCALENDAR" else {
            throw CalendarTransferError.invalidCalendar
        }

        var events: [[String: Property]] = []
        var current: [String: Property]?
        var nested = 0
        for line in lines {
            guard let property = Property(line) else { continue }
            if property.name == "BEGIN" && property.value.uppercased() == "VEVENT" {
                current = [:]
                nested = 0
            } else if current != nil {
                switch (property.name, property.value.uppercased()) {
                case ("END", "VEVENT") where nested == 0:
                    if let current { events.append(current) }
                    current = nil
                case ("BEGIN", _): nested += 1
                case ("END", _): nested = max(0, nested - 1)
                default:
                    if nested == 0 { current?[property.name] = property }
                }
            }
        }

        let exceptions = Set(events.compactMap { event in event["RECURRENCE-ID"] == nil ? nil : event["UID"]?.value })
        let imported = events.compactMap { event -> CalendarItem? in
            guard let uid = event["UID"]?.value, !uid.isEmpty, !exceptions.contains(uid),
                  event["STATUS"]?.value.uppercased() != "CANCELLED" else { return nil }
            return makeItem(event, uid: uid, displayTimeZone: displayTimeZone)
        }
        return Import(items: imported, skipped: events.count - imported.count)
    }

    private static func makeItem(_ fields: [String: Property], uid: String, displayTimeZone: TimeZone) -> CalendarItem? {
        guard let property = fields["DTSTART"], let start = date(property),
              fields["EXDATE"] == nil, fields["RDATE"] == nil,
              let repeatRule = rule(fields["RRULE"], start: start) else { return nil }

        let summary = fields["SUMMARY"].map { unescape($0.value) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (summary?.isEmpty == false ? summary : nil) ?? "未命名日程"
        let notes = [fields["DESCRIPTION"], fields["LOCATION"]].compactMap { $0 }.map { unescape($0.value) }
        var item = CalendarItem(kind: .event, title: title, date: start.day.key, repeatRule: repeatRule,
                                allDay: start.time == nil, note: notes.joined(separator: "\n"), calendarImportID: uid)

        let end: EventDate?
        if let finish = fields["DTEND"] {
            guard let parsed = date(finish, inheritedZone: start.zone), (parsed.time == nil) == (start.time == nil) else { return nil }
            end = parsed
        } else {
            guard fields["DURATION"] == nil else { return nil }
            end = nil
        }

        guard let time = start.time else {
            let last = end?.day.adding(-1) ?? start.day
            guard last >= start.day, last.supported else { return nil }
            item.endDate = last.key
            return item
        }

        let startInstant = start.instant ?? start.day.instant(at: time, in: CivilDay.calendar.timeZone)
        guard let startInstant else { return nil }
        let finish: Date
        if let end, let endTime = end.time {
            guard let instant = end.instant ?? end.day.instant(at: endTime, in: CivilDay.calendar.timeZone),
                  (start.zone == nil) == (end.zone == nil), instant > startInstant else { return nil }
            finish = instant
        } else {
            finish = startInstant.addingTimeInterval(60)
        }
        let calendar = CivilDay.localCalendar(in: start.zone == nil ? CivilDay.calendar.timeZone : displayTimeZone)
        let first = CivilDay.localDay(containing: startInstant, in: calendar.timeZone)
        let last = CivilDay.localDay(containing: finish, in: calendar.timeZone)
        guard first.supported, last.supported else { return nil }
        item.date = first.key
        item.endDate = last.key
        item.start = CivilDay.timeKey(startInstant, in: calendar)
        item.end = CivilDay.timeKey(finish, in: calendar)
        if start.zone != nil {
            item.startInstant = startInstant
            item.endInstant = finish
        }
        return item
    }

    private static func date(_ property: Property, inheritedZone: TimeZone? = nil) -> EventDate? {
        let raw = property.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(raw)
        guard characters.count >= 8 else { return nil }
        let dateKey = String(characters[0..<4]) + "-" + String(characters[4..<6]) + "-" + String(characters[6..<8])
        guard let day = CivilDay(dateKey), day.supported else { return nil }
        if characters.count == 8 { return EventDate(day: day, time: nil, instant: nil, zone: nil) }
        let utc = characters.last == "Z"
        guard characters.count == (utc ? 16 : 15), characters[8] == "T",
              let second = Int(String(characters[13..<15])), (0..<60).contains(second) else { return nil }
        let time = String(characters[9..<11]) + ":" + String(characters[11..<13])
        let zone: TimeZone?
        if utc { zone = CivilDay.calendar.timeZone }
        else if let id = property.parameters["TZID"] {
            guard let declared = TimeZone(identifier: id) else { return nil }
            zone = declared
        } else { zone = inheritedZone }
        guard let minute = day.instant(at: time, in: zone ?? CivilDay.calendar.timeZone) else { return nil }
        return EventDate(day: day, time: time, instant: zone == nil ? nil : minute.addingTimeInterval(Double(second)), zone: zone)
    }

    private static func rule(_ property: Property?, start: EventDate) -> RepeatRule? {
        guard let property else { return RepeatRule.none }
        let pieces = property.value.lowercased().split(separator: ";")
        guard let frequency = pieces.first(where: { $0.hasPrefix("freq=") }),
              let rule = RepeatRule(rawValue: String(frequency.dropFirst(5))), rule != .none,
              pieces.allSatisfy({ $0 == frequency || $0 == "interval=1" }), start.zone == nil else { return nil }
        if rule == .monthly && start.day.day > 28 { return nil }
        if rule == .yearly && start.day.month == 2 && start.day.day == 29 { return nil }
        return rule
    }

    private static func unfolded(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            if (line.first == " " || line.first == "\t"), let last = lines.indices.last {
                lines[last].append(contentsOf: line.dropFirst())
            } else {
                lines.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")))
            }
        }
        return lines
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var escaped = false
        for character in value {
            if escaped {
                result.append(character == "n" || character == "N" ? "\n" : character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        if escaped { result.append("\\") }
        return result
    }
}
