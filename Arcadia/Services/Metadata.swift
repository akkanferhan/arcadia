import Foundation
import Observation

extension Paths {
    /// Downloaded game metadata: libretro-database indexes and Wikipedia summaries.
    static var metadata: URL {
        let url = support.appendingPathComponent("Metadata", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var collections: URL { support.appendingPathComponent("collections.json") }
}

/// Genre, developer, publisher, year and players from libretro-database, downloaded per system on demand.
@MainActor
@Observable
final class Metadata {
    private(set) var indexes: [String: MetadataIndex] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private let folder: URL

    /// Indexes older than this are refreshed when online.
    static let maxAge: TimeInterval = 30 * 24 * 3600

    init(folder: URL = Paths.metadata) {
        self.folder = folder
    }

    func info(for game: Game) -> GameInfo? { indexes[game.systemID]?.info(for: game) }

    /// Loads the cached index of each system, downloading it when missing or old.
    func load<S: Sequence>(_ systemIDs: S) async where S.Element == String {
        await withTaskGroup(of: Void.self) { group in
            for id in Set(systemIDs) {
                group.addTask { await self.load(id) }
            }
        }
    }

    func load(_ systemID: String) async {
        guard !loading.contains(systemID), let system = GameSystem.with(id: systemID),
              let name = system.thumbnails else { return }
        if let index = indexes[systemID], Date.now.timeIntervalSince(index.fetched) < Self.maxAge { return }
        loading.insert(systemID)
        defer { loading.remove(systemID) }

        let file = folder.appendingPathComponent("\(systemID).json")
        let cached = await Task.detached { () -> MetadataIndex? in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(MetadataIndex.self, from: data)
        }.value
        if let cached { indexes[systemID] = cached }
        if let cached, Date.now.timeIntervalSince(cached.fetched) < Self.maxAge { return }

        // Offline: keep whatever was cached and try again next time.
        guard let fresh = await Self.download(database: name) else { return }
        indexes[systemID] = fresh
        await Task.detached {
            if let data = try? JSONEncoder().encode(fresh) { try? data.write(to: file, options: .atomic) }
        }.value
    }

    /// Downloads the `metadat` files of one libretro playlist. Nil when the network failed.
    nonisolated static func download(database name: String) async -> MetadataIndex? {
        let results = await withTaskGroup(of: (Int, String?, Bool).self) { group in
            for (offset, field) in MetadataIndex.fields.enumerated() {
                group.addTask {
                    guard let url = datURL(folder: field.folder, database: name) else { return (offset, nil, true) }
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        // 404: the database has no such file for this system; that is an answer too.
                        guard status == 200 else { return (offset, nil, status == 404) }
                        return (offset, String(decoding: data, as: UTF8.self), true)
                    } catch {
                        return (offset, nil, false)
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        guard results.allSatisfy(\.2) else { return nil }
        var index = MetadataIndex()
        for (offset, text, _) in results.sorted(by: { $0.0 < $1.0 }) {
            if let text { index.add(text, field: MetadataIndex.fields[offset]) }
        }
        return index
    }

    nonisolated static func datURL(folder: String, database name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "raw.githubusercontent.com"
        components.path = "/libretro/libretro-database/master/metadat/\(folder)/\(name).dat"
        return components.url
    }
}
