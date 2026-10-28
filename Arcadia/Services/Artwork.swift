import AppKit
import CryptoKit

/// Box art from the game folder or package (PlayStation icons) or thumbnails.libretro.com, cached on disk.
actor Artwork {
    static let shared = Artwork()

    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func image(for game: Game) async -> NSImage? {
        let key = game.id as NSString
        if let cached = memory.object(forKey: key) { return cached }
        if let task = inFlight[game.id] { return await task.value }

        let task = Task { await Self.load(game) }
        inFlight[game.id] = task
        let image = await task.value
        inFlight[game.id] = nil
        if let image { memory.setObject(image, forKey: key) }
        return image
    }

    private static func load(_ game: Game) async -> NSImage? {
        if game.system.gameIsFolder, let icon = PlayStationFolder.icon(in: game.url) {
            return NSImage(contentsOf: icon)
        }
        guard game.system.thumbnails != nil || VitaGame.isPackage(game.url) else { return nil }

        let digest = key(for: game)
        let cached = Paths.artwork.appendingPathComponent(digest + ".png")
        let missing = Paths.artwork.appendingPathComponent(digest + ".none")
        if let image = NSImage(contentsOf: cached) { return image }
        if FileManager.default.fileExists(atPath: missing.path) { return nil }

        // A Vita package's icon is inside it; it is copied out once.
        if VitaGame.isPackage(game.url), let data = VitaGame.packageIcon(game.url), let image = NSImage(data: data) {
            try? data.write(to: cached)
            return image
        }

        for name in candidateNames(game) {
            guard let repo = game.system.thumbnails, let url = thumbnailURL(repo: repo, name: name),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data) else { continue }
            try? data.write(to: cached)
            return image
        }
        FileManager.default.createFile(atPath: missing.path, contents: nil)
        return nil
    }

    /// A file-name-safe key for a game, used to name cached images.
    nonisolated static func key(for game: Game) -> String {
        SHA256.hash(data: Data(game.id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The box art already on disk, without downloading anything.
    nonisolated static func cachedFile(for game: Game) -> URL? {
        if game.system.gameIsFolder, let icon = PlayStationFolder.icon(in: game.url) { return icon }
        let cached = Paths.artwork.appendingPathComponent(key(for: game) + ".png")
        return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
    }

    /// The file name first; then common regions, for files without tags.
    private static func candidateNames(_ game: Game) -> [String] {
        var names = [game.fileTitle]
        if game.title == game.fileTitle {
            names += ["\(game.title) (USA)", "\(game.title) (Europe)", "\(game.title) (World)", "\(game.title) (Japan)"]
        }
        return names
    }

    private static func thumbnailURL(repo: String, name: String) -> URL? {
        // libretro replaces these characters with underscores in file names.
        let safe = String(name.map { "&*/:`<>?\\|\"".contains($0) ? "_" : $0 })
        var components = URLComponents()
        components.scheme = "https"
        components.host = "thumbnails.libretro.com"
        components.path = "/\(repo)/Named_Boxarts/\(safe).png"
        return components.url
    }
}
