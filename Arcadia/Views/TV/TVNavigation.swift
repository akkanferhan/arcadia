import Foundation

// The focus and command model behind TV Mode. Nothing here touches the UI, so it is unit-tested.

/// A step on the D-pad, the left stick or the arrow keys.
enum TVDirection: Equatable, CaseIterable {
    case up, down, left, right

    /// The direction a stick or D-pad points to, or nil inside the dead zone. The dominant axis wins.
    /// While a direction is held it stays held down to a lower threshold, so a wobbly stick doesn't stutter.
    static func resolve(x: Float, y: Float, held: TVDirection? = nil,
                        press: Float = 0.5, release: Float = 0.3) -> TVDirection? {
        if let held, held.amount(x: x, y: y) >= release { return held }
        guard max(abs(x), abs(y)) >= press else { return nil }
        if abs(x) > abs(y) { return x > 0 ? .right : .left }
        return y > 0 ? .up : .down
    }

    /// How far the stick leans this way; GameController's y axis points up.
    private func amount(x: Float, y: Float) -> Float {
        switch self {
        case .up: y
        case .down: -y
        case .left: -x
        case .right: x
        }
    }
}

/// What the player asked for, from a controller or the keyboard.
enum TVCommand: Equatable {
    case move(TVDirection)
    /// A on a controller, Return on the keyboard.
    case select
    /// B on a controller, Esc on the keyboard.
    case back
    /// X on a controller, F on the keyboard.
    case favorite
    /// Y on a controller; opens or closes the on-screen keyboard.
    case search
    /// Menu/Start on a controller, Space on the keyboard.
    case options
    /// Letters typed on a hardware keyboard while searching.
    case type(String)
    case deleteBackward
}

/// What TV Mode should do after a command.
enum TVEffect: Equatable {
    case none
    /// Nothing lies that way; the focused item shakes.
    case bump
    case play(Game)
    case toggleFavorite(Game)
    case options(Game?)
    case exit
}

/// One horizontal row of games.
struct TVShelf: Identifiable, Equatable {
    enum Kind: Hashable {
        case continuePlaying
        case favorites
        case system(String)
        case results
    }

    let kind: Kind
    let games: [Game]
    var id: Kind { kind }

    /// Continue Playing, Favorites, then one shelf per console; or the matches while searching.
    static func make(games: [Game], recentlyPlayed: [Game], favorites: [Game], query: String = "") -> [TVShelf] {
        let query = query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let matches = games.filter { $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return matches.isEmpty ? [] : [TVShelf(kind: .results, games: matches)]
        }
        var shelves: [TVShelf] = []
        if !recentlyPlayed.isEmpty { shelves.append(TVShelf(kind: .continuePlaying, games: Array(recentlyPlayed.prefix(15)))) }
        if !favorites.isEmpty { shelves.append(TVShelf(kind: .favorites, games: favorites)) }
        var bySystem: [String: [Game]] = [:]
        for game in games { bySystem[game.systemID, default: []].append(game) }
        for system in GameSystem.all {
            if let games = bySystem[system.id] { shelves.append(TVShelf(kind: .system(system.id), games: games)) }
        }
        return shelves
    }
}

/// Which game is focused. Every shelf remembers its own position, like on Apple TV.
struct TVFocus: Equatable {
    private(set) var shelves: [TVShelf] = []
    private(set) var row = 0
    private var columns: [TVShelf.Kind: Int] = [:]

    init(shelves: [TVShelf] = []) {
        self.shelves = shelves
    }

    var shelf: TVShelf? { shelves.indices.contains(row) ? shelves[row] : nil }

    var column: Int {
        guard let shelf, !shelf.games.isEmpty else { return 0 }
        return min(columns[shelf.kind] ?? 0, shelf.games.count - 1)
    }

    var game: Game? {
        guard let shelf, shelf.games.indices.contains(column) else { return nil }
        return shelf.games[column]
    }

    /// The remembered position in a shelf, for drawing rows that aren't focused.
    func column(in shelf: TVShelf) -> Int {
        min(columns[shelf.kind] ?? 0, max(shelf.games.count - 1, 0))
    }

    /// Moves one step; false when nothing lies that way.
    @discardableResult
    mutating func move(_ direction: TVDirection) -> Bool {
        guard let shelf else { return false }
        switch direction {
        case .left:
            guard column > 0 else { return false }
            columns[shelf.kind] = column - 1
        case .right:
            guard column + 1 < shelf.games.count else { return false }
            columns[shelf.kind] = column + 1
        case .up:
            guard row > 0 else { return false }
            row -= 1
        case .down:
            guard row + 1 < shelves.count else { return false }
            row += 1
        }
        return true
    }

    /// Focuses a game directly, e.g. after a click.
    mutating func focus(row: Int, column: Int) {
        guard shelves.indices.contains(row), shelves[row].games.indices.contains(column) else { return }
        self.row = row
        columns[shelves[row].kind] = column
    }

    /// Back to the first shelf, keeping each shelf's position.
    mutating func top() {
        row = 0
    }

    /// Forgets a shelf's position, so it starts at its first game.
    mutating func reset(_ kind: TVShelf.Kind) {
        columns[kind] = nil
    }

    /// Takes new shelves (after a scan, a new favorite or a search) and keeps the focus on the same
    /// game in the same shelf when it is still there.
    mutating func update(_ newShelves: [TVShelf]) {
        guard newShelves != shelves else { return }
        let kind = shelf?.kind
        let game = game
        shelves = newShelves
        guard !newShelves.isEmpty else { row = 0; return }
        if let kind, let index = newShelves.firstIndex(where: { $0.kind == kind }) {
            row = index
            if let game, let column = newShelves[index].games.firstIndex(of: game) {
                columns[kind] = column
            }
        } else {
            row = min(row, newShelves.count - 1)
        }
    }
}

/// The on-screen keyboard used to search with a controller.
struct TVKeyboard: Equatable {
    enum Key: Equatable {
        case character(Character)
        case space
        case delete
        case done
    }

    static let rows: [[Key]] = [
        "ABCDEFGHIJKLM".map { .character($0) },
        "NOPQRSTUVWXYZ".map { .character($0) },
        "0123456789".map { .character($0) } + [.space, .delete, .done],
    ]

    private(set) var row = 0
    private(set) var column = 0

    var key: Key { Self.rows[row][column] }

    /// Moves one key; false at the edges.
    @discardableResult
    mutating func move(_ direction: TVDirection) -> Bool {
        switch direction {
        case .left:
            guard column > 0 else { return false }
            column -= 1
        case .right:
            guard column + 1 < Self.rows[row].count else { return false }
            column += 1
        case .up:
            guard row > 0 else { return false }
            row -= 1
            column = min(column, Self.rows[row].count - 1)
        case .down:
            guard row + 1 < Self.rows.count else { return false }
            row += 1
            column = min(column, Self.rows[row].count - 1)
        }
        return true
    }
}

/// A vertical list of choices, such as the options for a game.
struct TVMenu<Action: Equatable>: Equatable {
    var title: String
    var message: String?
    var actions: [Action]
    private(set) var index = 0

    init(title: String, message: String? = nil, actions: [Action]) {
        self.title = title
        self.message = message
        self.actions = actions
    }

    var action: Action? { actions.indices.contains(index) ? actions[index] : nil }

    @discardableResult
    mutating func move(_ direction: TVDirection) -> Bool {
        switch direction {
        case .up, .left:
            guard index > 0 else { return false }
            index -= 1
        case .down, .right:
            guard index + 1 < actions.count else { return false }
            index += 1
        }
        return true
    }
}

/// Turns commands into focus changes and effects.
struct TVNavigator: Equatable {
    var focus = TVFocus()
    private(set) var query = ""
    /// Shown while searching with the on-screen keyboard.
    private(set) var keyboard: TVKeyboard?

    var isSearching: Bool { keyboard != nil }

    mutating func handle(_ command: TVCommand) -> TVEffect {
        if keyboard != nil { return handleKeyboard(command) }

        switch command {
        case .move(let direction):
            if focus.move(direction) { return .none }
            if direction == .up, !query.isEmpty {
                keyboard = TVKeyboard()
                return .none
            }
            return .bump
        case .select:
            return focus.game.map { .play($0) } ?? .bump
        case .back:
            if !query.isEmpty {
                setQuery("")
            } else if focus.row > 0 {
                focus.top()
            } else {
                return .exit
            }
            return .none
        case .favorite:
            return focus.game.map { .toggleFavorite($0) } ?? .bump
        case .search:
            keyboard = TVKeyboard()
            return .none
        case .options:
            return .options(focus.game)
        case .type(let text):
            keyboard = TVKeyboard()
            setQuery(query + text)
            return .none
        case .deleteBackward:
            return .none
        }
    }

    private mutating func handleKeyboard(_ command: TVCommand) -> TVEffect {
        switch command {
        case .move(let direction):
            if keyboard?.move(direction) == true { return .none }
            if direction == .down, !focus.shelves.isEmpty {
                keyboard = nil
                return .none
            }
            return .bump
        case .select:
            switch keyboard?.key {
            case .character(let character): setQuery(query + String(character))
            case .space: if !query.isEmpty, !query.hasSuffix(" ") { setQuery(query + " ") }
            case .delete: deleteBackward()
            case .done, nil: keyboard = nil
            }
            return .none
        case .back, .search:
            keyboard = nil
            return .none
        case .type(let text):
            setQuery(query + text)
            return .none
        case .deleteBackward:
            deleteBackward()
            return .none
        case .favorite, .options:
            return .none
        }
    }

    private mutating func deleteBackward() {
        guard !query.isEmpty else { return }
        setQuery(String(query.dropLast()))
    }

    private mutating func setQuery(_ text: String) {
        query = text
        focus.reset(.results)
    }
}
