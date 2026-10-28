import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

/// Keeps the library's games in Spotlight. Only what changed since the last run is re-indexed.
enum Spotlight {
    static let domain = "games"

    /// What decides whether an indexed game is still up to date.
    struct Entry: Hashable {
        let game: Game
        let cover: URL?

        var signature: String { [game.title, game.systemID, cover?.path ?? ""].joined(separator: "\u{1F}") }
    }

    /// Ids to add or refresh, and ids to remove, going from `indexed` (id → signature) to `entries`.
    static func changes(from indexed: [String: String], to entries: [Entry]) -> (index: [Entry], remove: [String]) {
        let current = Set(entries.map(\.game.id))
        let index = entries.filter { indexed[$0.game.id] != $0.signature }
        let remove = indexed.keys.filter { !current.contains($0) }.sorted()
        return (index, remove)
    }

    private static var stateFile: URL { Paths.support.appendingPathComponent("spotlight.json") }

    static func sync(_ games: [Game]) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        await Task.detached(priority: .utility) {
            let entries = games.map { Entry(game: $0, cover: Artwork.cachedFile(for: $0)) }
            let indexed = (try? Data(contentsOf: stateFile))
                .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            let (toIndex, toRemove) = changes(from: indexed, to: entries)
            guard !toIndex.isEmpty || !toRemove.isEmpty else { return }

            let index = CSSearchableIndex.default()
            var state = indexed
            do {
                if !toRemove.isEmpty {
                    try await index.deleteSearchableItems(withIdentifiers: toRemove)
                    toRemove.forEach { state[$0] = nil }
                }
                for start in stride(from: 0, to: toIndex.count, by: 200) {
                    let batch = toIndex[start..<min(start + 200, toIndex.count)]
                    try await index.indexSearchableItems(batch.map(item))
                    batch.forEach { state[$0.game.id] = $0.signature }
                }
            } catch {
                // Spotlight may be busy or turned off; whatever was not saved is retried next time.
            }
            if let data = try? JSONEncoder().encode(state) {
                try? data.write(to: stateFile, options: .atomic)
            }
        }.value
    }

    private static func item(_ entry: Entry) -> CSSearchableItem {
        let game = entry.game
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = game.title
        attributes.displayName = game.title
        attributes.contentDescription = [game.system.name, game.region].compactMap(\.self).joined(separator: " · ")
        attributes.keywords = [game.system.name, game.system.shortName]
        if let cover = entry.cover { attributes.thumbnailData = Thumbnail.jpeg(from: cover, maxSize: 180) }
        let item = CSSearchableItem(uniqueIdentifier: game.id, domainIdentifier: domain, attributeSet: attributes)
        // Items expire after a month unless told otherwise; games stay until they leave the library.
        item.expirationDate = .distantFuture
        return item
    }
}

/// Small JPEG copies of box art for Spotlight and the widget.
enum Thumbnail {
    static func jpeg(from file: URL, maxSize: CGFloat) -> Data? {
        guard let image = NSImage(contentsOf: file) else { return nil }
        return jpeg(from: image, maxSize: maxSize)
    }

    static func jpeg(from image: NSImage, maxSize: CGFloat) -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSize / CGFloat(max(source.width, source.height)))
        let width = max(1, Int(CGFloat(source.width) * scale)), height = max(1, Int(CGFloat(source.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
