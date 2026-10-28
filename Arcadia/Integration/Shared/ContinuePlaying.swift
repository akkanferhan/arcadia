import Foundation

// Shared by Arcadia and its widget extension.

/// The App Group container Arcadia shares with its widget.
enum SharedContainer {
    /// Team-prefixed, so a Developer ID–signed app can use it without a provisioning profile.
    static let groupID = "43THU6L26P.dev.ferhanakkan.Arcadia"

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }
}

/// The recently played games, as written by Arcadia for the "Continue Playing" widget.
struct ContinuePlayingSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        /// The game's id in Arcadia (its path on disk).
        let id: String
        let title: String
        let systemName: String
        let systemShortName: String
        let systemSymbol: String
        /// The system's colors as 0xRRGGBB, for covers that have no box art.
        let systemColors: [UInt32]
        let lastPlayed: Date
        let playTime: TimeInterval
        /// File name of the cover thumbnail inside `coversFolder`.
        var cover: String?
    }

    var items: [Item] = []

    static let fileName = "continue-playing.json"
    static let coversFolder = "Covers"

    static func load(from folder: URL) -> ContinuePlayingSnapshot? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? decoder.decode(ContinuePlayingSnapshot.self, from: data)
    }

    func encoded() throws -> Data { try Self.encoder.encode(self) }

    func coverURL(for item: Item, in folder: URL) -> URL? {
        item.cover.map { folder.appendingPathComponent(Self.coversFolder, isDirectory: true).appendingPathComponent($0) }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Links into Arcadia: `arcadia://play?game=<id>` starts a game, `arcadia://open?game=<id>` shows it.
/// Without a game, `play` continues the last played game and `open` just brings Arcadia forward.
enum ArcadiaLink: Equatable {
    case play(game: String?)
    case open(game: String?)

    static let scheme = "arcadia"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let game = components.queryItems?.first { $0.name == "game" }?.value.flatMap { $0.isEmpty ? nil : $0 }
        switch components.host?.lowercased() {
        case "play": self = .play(game: game)
        case "open", nil, "": self = .open(game: game)
        default: return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        let game: String?
        switch self {
        case .play(let id): components.host = "play"; game = id
        case .open(let id): components.host = "open"; game = id
        }
        if let game {
            // Game ids are paths, which may hold `&`, `=`, `+` or `#`; encode everything but the basics.
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
            components.percentEncodedQuery = "game=" + (game.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        return components.url!
    }
}
