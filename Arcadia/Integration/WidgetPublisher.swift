import AppKit
import SwiftUI
import WidgetKit

/// Writes the recently played games and their covers into the App Group for the "Continue Playing" widget.
enum WidgetPublisher {
    /// The widget shows at most this many games.
    static let limit = 3

    @MainActor
    static func snapshot(of library: Library) -> ContinuePlayingSnapshot {
        let items = library.recentlyPlayed.prefix(limit).map { game in
            let record = library.record(game)
            return ContinuePlayingSnapshot.Item(
                id: game.id, title: game.title, systemName: game.system.name,
                systemShortName: game.system.shortName, systemSymbol: game.system.symbol,
                systemColors: game.system.colors.map(\.hexValue),
                lastPlayed: record.lastPlayed ?? .distantPast, playTime: record.playTime)
        }
        return ContinuePlayingSnapshot(items: Array(items))
    }

    /// Writes the recently played games and their covers, then reloads the widget when anything changed.
    @MainActor
    static func publish(_ library: Library, to folder: URL? = SharedContainer.url) async {
        guard let folder else { return }
        let snapshot = snapshot(of: library)
        var covers: [Game: NSImage] = [:]
        for game in library.recentlyPlayed.prefix(limit) {
            covers[game] = await Artwork.shared.image(for: game)
        }
        let changed = await Task.detached(priority: .utility) { () -> Bool in
            var snapshot = snapshot
            return write(&snapshot, covers: covers, to: folder)
        }.value
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Saves covers that are missing, removes old ones and writes the JSON. Returns whether the JSON changed.
    nonisolated static func write(_ snapshot: inout ContinuePlayingSnapshot, covers: [Game: NSImage], to folder: URL) -> Bool {
        let manager = FileManager.default
        let coversFolder = folder.appendingPathComponent(ContinuePlayingSnapshot.coversFolder, isDirectory: true)
        try? manager.createDirectory(at: coversFolder, withIntermediateDirectories: true)

        var keep: Set<String> = []
        for index in snapshot.items.indices {
            guard let (game, image) = covers.first(where: { $0.key.id == snapshot.items[index].id }) else { continue }
            let name = Artwork.key(for: game) + ".jpg"
            let file = coversFolder.appendingPathComponent(name)
            if !manager.fileExists(atPath: file.path) {
                guard let data = Thumbnail.jpeg(from: image, maxSize: 360), (try? data.write(to: file, options: .atomic)) != nil
                else { continue }
            }
            snapshot.items[index].cover = name
            keep.insert(name)
        }
        for file in (try? manager.contentsOfDirectory(atPath: coversFolder.path)) ?? [] where !keep.contains(file) {
            try? manager.removeItem(at: coversFolder.appendingPathComponent(file))
        }

        let target = folder.appendingPathComponent(ContinuePlayingSnapshot.fileName)
        guard let data = try? snapshot.encoded() else { return false }
        if (try? Data(contentsOf: target)) == data { return false }
        return (try? data.write(to: target, options: .atomic)) != nil
    }
}

extension Color {
    /// The color as 0xRRGGBB in sRGB.
    var hexValue: UInt32 {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return channel(color.redComponent) << 16 | channel(color.greenComponent) << 8 | channel(color.blueComponent)
    }
}
