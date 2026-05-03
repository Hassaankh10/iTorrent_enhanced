//
//  AnalyticsService.swift
//  iTorrent
//

import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

enum AnalyticsService {
    static func log(_ event: Event) {
#if canImport(FirebaseAnalytics)
        Analytics.logEvent(event.name, parameters: event.parameters)
#endif
    }
}

extension AnalyticsService {
    enum Event {
        case torrentAdded(name: String)
        case torrentRemoved
        case searchPerformed(query: String)
        case magnetOpened
        case torrentFileOpened
        case rssOpened

        var name: String {
            switch self {
            case .torrentAdded: return "torrent_added"
            case .torrentRemoved: return "torrent_removed"
            case .searchPerformed: return "search_performed"
            case .magnetOpened: return "magnet_opened"
            case .torrentFileOpened: return "torrent_file_opened"
            case .rssOpened: return "rss_opened"
            }
        }

        var parameters: [String: Any]? {
            switch self {
            case .torrentAdded(let name):
                return ["torrent_name": name]
            case .searchPerformed(let query):
                return ["query_length": query.count]
            default:
                return nil
            }
        }
    }
}
