import Foundation
import Observation

/// A named, user-made list of games.
struct GameCollection: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// `Game.id` values, in the order they were added.
    var gameIDs: [String]
    var created: Date

    init(id: UUID = UUID(), name: String, gameIDs: [String] = [], created: Date = .now) {
        self.id = id
        self.name = name
        self.gameIDs = gameIDs
        self.created = created
    }
}

/// The user's collections, saved as JSON in Arcadia's support folder.
@MainActor
@Observable
final class Collections {
    private(set) var all: [GameCollection] = []
    /// The name sheet being shown: a new collection or a rename.
    var prompt: Prompt?

    enum Prompt: Identifiable {
        case create(adding: [Game])
        case rename(UUID)

        var id: String {
            switch self {
            case .create(let games): "create:" + games.map(\.id).joined(separator: "|")
            case .rename(let id): "rename:" + id.uuidString
            }
        }
    }

    @ObservationIgnored private let file: URL

    init(file: URL = Paths.collections) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([GameCollection].self, from: data) {
            all = saved
        }
    }

    func collection(_ id: UUID) -> GameCollection? { all.first { $0.id == id } }

    /// The collection's games that are still in the library, in the order they were added.
    func games(in id: UUID, from library: [Game]) -> [Game] {
        guard let collection = collection(id) else { return [] }
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return collection.gameIDs.compactMap { byID[$0] }
    }

    func contains(_ game: Game, in id: UUID) -> Bool { collection(id)?.gameIDs.contains(game.id) == true }

    @discardableResult
    func create(named name: String, adding games: [Game] = []) -> GameCollection {
        var collection = GameCollection(name: Self.tidy(name))
        for game in games where !collection.gameIDs.contains(game.id) { collection.gameIDs.append(game.id) }
        all.append(collection)
        save()
        return collection
    }

    func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].name = name
        save()
    }

    func delete(_ id: UUID) {
        all.removeAll { $0.id == id }
        save()
    }

    func add(_ games: [Game], to id: UUID) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        for game in games where !all[index].gameIDs.contains(game.id) { all[index].gameIDs.append(game.id) }
        save()
    }

    func remove(_ game: Game, from id: UUID) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].gameIDs.removeAll { $0 == game.id }
        save()
    }

    func toggle(_ game: Game, in id: UUID) {
        contains(game, in: id) ? remove(game, from: id) : add([game], to: id)
    }

    /// Collections sorted by name for menus and the sidebar.
    var sorted: [GameCollection] {
        all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func tidy(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Collection") : trimmed
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
