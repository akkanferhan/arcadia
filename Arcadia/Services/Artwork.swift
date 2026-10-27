import AppKit
import CryptoKit

/// Box art from the game folder (PS3/PS4/PS5 icons) or thumbnails.libretro.com, cached on disk.
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
        guard let repo = game.system.thumbnails else { return nil }

        let digest = SHA256.hash(data: Data(game.id.utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = Paths.artwork.appendingPathComponent(digest + ".png")
        let missing = Paths.artwork.appendingPathComponent(digest + ".none")
        if let image = NSImage(contentsOf: cached) { return image }
        if FileManager.default.fileExists(atPath: missing.path) { return nil }

        for name in candidateNames(game) {
            guard let url = thumbnailURL(repo: repo, name: name),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data) else { continue }
            try? data.write(to: cached)
            return image
        }
        FileManager.default.createFile(atPath: missing.path, contents: nil)
        return nil
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
