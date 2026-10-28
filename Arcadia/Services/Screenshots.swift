import AppKit
import CryptoKit

/// In-game snapshots and title screens from thumbnails.libretro.com, cached next to the box art.
actor Screenshots {
    static let shared = Screenshots()

    enum Kind: String, CaseIterable {
        case snap = "Named_Snaps"
        case title = "Named_Titles"
    }

    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func image(_ kind: Kind, for game: Game) async -> NSImage? {
        let key = "\(kind.rawValue)|\(game.id)"
        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task { await Self.load(kind, game) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    private static func load(_ kind: Kind, _ game: Game) async -> NSImage? {
        guard let repo = game.system.thumbnails else { return nil }
        let digest = SHA256.hash(data: Data("\(kind.rawValue)|\(game.id)".utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = Paths.artwork.appendingPathComponent(digest + ".png")
        let missing = Paths.artwork.appendingPathComponent(digest + ".none")
        if let image = NSImage(contentsOf: cached) { return image }
        if FileManager.default.fileExists(atPath: missing.path) { return nil }

        var reachable = false
        for name in candidateNames(game) {
            guard let url = url(repo: repo, kind: kind, name: name),
                  let (data, response) = try? await URLSession.shared.data(from: url) else { continue }
            reachable = true
            guard (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else { continue }
            try? data.write(to: cached)
            return image
        }
        // Offline: try again next time instead of remembering a miss.
        if reachable { FileManager.default.createFile(atPath: missing.path, contents: nil) }
        return nil
    }

    private static func candidateNames(_ game: Game) -> [String] {
        var names = [game.fileTitle]
        if game.title == game.fileTitle {
            names += ["\(game.title) (USA)", "\(game.title) (Europe)", "\(game.title) (World)", "\(game.title) (Japan)"]
        }
        return names
    }

    private static func url(repo: String, kind: Kind, name: String) -> URL? {
        // libretro replaces these characters with underscores in file names.
        let safe = String(name.map { "&*/:`<>?\\|\"".contains($0) ? "_" : $0 })
        var components = URLComponents()
        components.scheme = "https"
        components.host = "thumbnails.libretro.com"
        components.path = "/\(repo)/\(kind.rawValue)/\(safe).png"
        return components.url
    }
}
