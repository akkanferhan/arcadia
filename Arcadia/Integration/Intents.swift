import AppIntents
import AppKit

/// A game in the library, for Shortcuts and Siri.
struct GameEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Game", numericFormat: "\(placeholder: .int) games")
    static let defaultQuery = GameQuery()

    let id: String
    let title: String
    let systemName: String
    let cover: URL?

    init(_ game: Game) {
        id = game.id
        title = game.title
        systemName = game.system.name
        cover = Artwork.cachedFile(for: game)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title),
                              subtitle: LocalizedStringResource(stringLiteral: systemName),
                              image: cover.map { DisplayRepresentation.Image(url: $0) })
    }
}

struct GameQuery: EntityStringQuery {
    @Dependency private var model: AppModel

    /// Siri understands games by these names; recently played ones come first.
    static let suggestionLimit = 500

    @MainActor
    func entities(for identifiers: [String]) async throws -> [GameEntity] {
        var games: [Game] = []
        for id in identifiers {
            if let game = await model.game(withID: id) { games.append(game) }
        }
        return games.map(GameEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [GameEntity] {
        await loadLibrary()
        return Self.games(matching: string, in: model.library.games).map(GameEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [GameEntity] {
        await loadLibrary()
        return Self.suggestions(recent: model.library.recentlyPlayed, all: model.library.games).map(GameEntity.init)
    }

    @MainActor
    private func loadLibrary() async {
        if model.library.games.isEmpty { await model.library.scan() }
    }

    /// Games whose title, file name or system matches every word of `text`, best matches first.
    static func games(matching text: String, in games: [Game]) -> [Game] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return games }
        let matches = games.filter { game in
            let haystack = [game.title, game.fileTitle, game.system.name, game.system.shortName].joined(separator: " ")
            return words.allSatisfy { haystack.localizedStandardContains($0) }
        }
        // Titles that start with the text, then the rest.
        return matches.filter { $0.title.localizedLowercase.hasPrefix(text.localizedLowercase) }
            + matches.filter { !$0.title.localizedLowercase.hasPrefix(text.localizedLowercase) }
    }

    static func suggestions(recent: [Game], all: [Game]) -> [Game] {
        let recentIDs = Set(recent.map(\.id))
        return Array((recent + all.filter { !recentIDs.contains($0.id) }).prefix(suggestionLimit))
    }
}

enum GameIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notFound
    case nothingPlayed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound: "That game is no longer in your library."
        case .nothingPlayed: "You haven't played any games in Arcadia yet."
        }
    }
}

struct PlayGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Game"
    static let description = IntentDescription("Opens Arcadia and starts a game from your library.")
    static let openAppWhenRun = true

    @Parameter(title: "Game", requestValueDialog: "Which game do you want to play?")
    var game: GameEntity

    @Dependency private var model: AppModel

    init() {}

    init(game: GameEntity) {
        self.game = game
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$game)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let found = await model.game(withID: game.id) else { throw GameIntentError.notFound }
        model.reveal(found)
        model.play(found)
        return .result()
    }
}

struct ContinuePlayingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Playing"
    static let description = IntentDescription("Opens Arcadia and starts the game you played last.")
    static let openAppWhenRun = true

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let game = await model.lastPlayedGame() else { throw GameIntentError.nothingPlayed }
        model.reveal(game)
        model.play(game)
        return .result()
    }
}

struct ArcadiaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayGameIntent(), phrases: [
            "Play \(\.$game) in \(.applicationName)",
            "Start \(\.$game) in \(.applicationName)",
            "Play a game in \(.applicationName)",
        ], shortTitle: "Play Game", systemImageName: "play.fill")

        AppShortcut(intent: ContinuePlayingIntent(), phrases: [
            "Continue playing in \(.applicationName)",
            "Resume my game in \(.applicationName)",
        ], shortTitle: "Continue Playing", systemImageName: "gamecontroller.fill")
    }

    static let shortcutTileColor: ShortcutTileColor = .purple
}
