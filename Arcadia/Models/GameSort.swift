import Foundation

/// How a grid page orders its games.
enum GameSort: String, CaseIterable, Identifiable {
    case name
    case recentlyPlayed
    case mostPlayed
    case recentlyAdded
    case releaseYear

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .name: "Name"
        case .recentlyPlayed: "Recently Played"
        case .mostPlayed: "Most Played"
        case .recentlyAdded: "Recently Added"
        case .releaseYear: "Release Year"
        }
    }

    var symbol: String {
        switch self {
        case .name: "textformat"
        case .recentlyPlayed: "clock"
        case .mostPlayed: "flame"
        case .recentlyAdded: "tray.and.arrow.down"
        case .releaseYear: "calendar"
        }
    }
}

/// Narrows a grid page to a genre, decade or number of players.
struct GameFilter: Equatable {
    var genre: String?
    /// First year of the decade, e.g. 1990.
    var decade: Int?
    /// At least this many players at once; 1 means single-player games only.
    var players: Int?

    var isActive: Bool { genre != nil || decade != nil || players != nil }

    func matches(_ info: GameInfo?) -> Bool {
        if let genre, info?.genre != genre { return false }
        if let decade {
            guard let year = info?.year, year / 10 * 10 == decade else { return false }
        }
        if let players {
            guard let most = info?.players else { return false }
            if players == 1 ? most != 1 : most < players { return false }
        }
        return true
    }

    /// The player counts offered as filters: single-player only, then "2+", "3+" and "4+".
    static let playerChoices = [1, 2, 3, 4]
}

/// What sorting and filtering need to know about each game.
struct GameFacts {
    var record: (Game) -> GameRecord
    var info: (Game) -> GameInfo?
    var added: (Game) -> Date?

    /// Sorts and filters games. Ties, and games without the sorted value, fall back to name order.
    func arrange(_ games: [Game], by sort: GameSort, filter: GameFilter = GameFilter()) -> [Game] {
        let kept = filter.isActive ? games.filter { filter.matches(info($0)) } : games
        let byName = kept.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        func descending<Value: Comparable>(_ value: (Game) -> Value?) -> [Game] {
            let values = byName.map(value)
            return byName.indices.sorted { lhs, rhs in
                switch (values[lhs], values[rhs]) {
                case let (left?, right?) where left != right: return left > right
                case (.some, nil): return true
                case (nil, .some): return false
                default: return lhs < rhs
                }
            }
            .map { byName[$0] }
        }
        switch sort {
        case .name: return byName
        case .recentlyPlayed: return descending { record($0).lastPlayed }
        case .mostPlayed: return descending { record($0).playTime > 0 ? record($0).playTime : nil }
        case .recentlyAdded: return descending(added)
        case .releaseYear: return descending { info($0)?.year }
        }
    }

    /// Genres, decades and player counts known for these games, for the filter menus.
    func choices(for games: [Game]) -> (genres: [String], decades: [Int], players: [Int]) {
        let infos = games.compactMap(info)
        let genres = Set(infos.compactMap(\.genre)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let decades = Set(infos.compactMap(\.year).map { $0 / 10 * 10 }).sorted()
        let players = GameFilter.playerChoices.filter { count in
            infos.contains { GameFilter(players: count).matches($0) }
        }
        return (genres, decades, players)
    }
}

/// When a game arrived in the library, read from the file system once and remembered.
@MainActor
enum GameDates {
    private static var cache: [String: Date] = [:]

    static func added(_ game: Game) -> Date? {
        if let date = cache[game.id] { return date }
        let values = try? game.url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        let date = values?.addedToDirectoryDate ?? values?.creationDate
        if let date { cache[game.id] = date }
        return date
    }
}
