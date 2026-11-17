import ActivityKit
import Foundation

struct CalendarLiveAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let begins: Date
        let target: Date
    }

    let itemID: String

    var link: URL? {
        var components = URLComponents()
        components.scheme = "personalglasscalendar"
        components.host = "item"
        components.queryItems = [URLQueryItem(name: "id", value: itemID)]
        return components.url
    }
}
