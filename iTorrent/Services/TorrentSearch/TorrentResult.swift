//
//  TorrentResult.swift
//  iTorrent
//
//  Created by iTorrent Enhanced
//

import Foundation

enum SearchCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case movies = "Movies"
    case tv = "TV"
    case games = "Games"
    case music = "Music"
    case apps = "Apps"
    case anime = "Anime"

    var id: String { rawValue }

    var leetPath: String? {
        switch self {
        case .all:    return nil
        case .movies: return "Movies"
        case .tv:     return "TV"
        case .games:  return "Games"
        case .music:  return "Music"
        case .apps:   return "Apps"
        case .anime:  return "Anime"
        }
    }

    var pirateBayCat: String? {
        switch self {
        case .all:    return nil
        case .movies: return "200"
        case .tv:     return "200"
        case .games:  return "400"
        case .music:  return "100"
        case .apps:   return "300"
        case .anime:  return "200"
        }
    }

    var systemImage: String {
        switch self {
        case .all:    return "magnifyingglass"
        case .movies: return "film"
        case .tv:     return "tv"
        case .games:  return "gamecontroller"
        case .music:  return "music.note"
        case .apps:   return "arrow.down.app"
        case .anime:  return "sparkles.tv"
        }
    }
}

struct TorrentResult {
    let title: String
    let size: String
    let seeders: Int
    let leechers: Int
    let magnetLink: String
}
