import Foundation
import Observation

/// The games in the library folder plus favorites and play history.
@MainActor
@Observable
final class Library {
    private(set) var games: [Game] = []
    private(set) var records: [String: GameRecord] = [:]
    private(set) var isScanning = false
    /// Rescans when games are copied into or removed from the folder.
    @ObservationIgnored private var watcher: FolderWatcher?

    var folder: URL {
        didSet {
            UserDefaults.standard.set(folder.path, forKey: "libraryFolder")
            watcher?.watch(folder)
            Task { await scan() }
        }
    }

    var hasFolder: Bool { UserDefaults.standard.string(forKey: "libraryFolder") != nil }

    init() {
        folder = UserDefaults.standard.string(forKey: "libraryFolder").map { URL(fileURLWithPath: $0) }
            ?? Paths.defaultLibrary
        if let data = try? Data(contentsOf: Paths.records),
           let saved = try? JSONDecoder().decode([String: GameRecord].self, from: data) {
            records = saved
        }
        let watcher = FolderWatcher { [weak self] in Task { await self?.scan() } }
        if hasFolder { watcher.watch(folder) }
        self.watcher = watcher
    }

    var biosFolder: URL { folder.appendingPathComponent("bios", isDirectory: true) }

    func folder(for system: GameSystem) -> URL { folder.appendingPathComponent(system.id, isDirectory: true) }

    func games(for system: GameSystem) -> [Game] { games.filter { $0.systemID == system.id } }

    func count(for system: GameSystem) -> Int { games.reduce(0) { $0 + ($1.systemID == system.id ? 1 : 0) } }

    var favorites: [Game] { games.filter { record($0).favorite } }

    var recentlyPlayed: [Game] {
        games.filter { record($0).lastPlayed != nil }
            .sorted { record($0).lastPlayed! > record($1).lastPlayed! }
    }

    /// Systems that have at least one game, in catalog order.
    var stockedSystems: [GameSystem] {
        let ids = Set(games.map(\.systemID))
        return GameSystem.all.filter { ids.contains($0.id) }
    }

    func record(_ game: Game) -> GameRecord { records[game.id] ?? GameRecord() }

    func toggleFavorite(_ game: Game) {
        records[game.id, default: GameRecord()].favorite.toggle()
        save()
    }

    func recordSession(_ game: Game, started: Date) {
        records[game.id, default: GameRecord()].lastPlayed = started
        records[game.id, default: GameRecord()].playTime += Date.now.timeIntervalSince(started)
        save()
    }

    /// Keeps favorites and play time when a game's file is replaced, e.g. by a compressed copy.
    func moveRecord(from oldID: String, to newID: String) {
        guard oldID != newID, let record = records.removeValue(forKey: oldID) else { return }
        records[newID] = record
        save()
    }

    /// Creates one folder per system plus a `bios` folder.
    func createFolders() {
        for system in GameSystem.all {
            try? FileManager.default.createDirectory(at: folder(for: system), withIntermediateDirectories: true)
        }
        for sub in ["", "ps1", "ps2", "ps3", "psvita", "xbox"] {
            try? FileManager.default.createDirectory(at: biosFolder.appendingPathComponent(sub),
                                                     withIntermediateDirectories: true)
        }
    }

    func scan() async {
        isScanning = true
        let root = folder
        games = await Task.detached { Self.scan(root) }.value
        isScanning = false
    }

    private func save() {
        let records = records
        Task.detached {
            if let data = try? JSONEncoder().encode(records) {
                try? data.write(to: Paths.records, options: .atomic)
            }
        }
    }

    // MARK: Scanning

    nonisolated static func scan(_ root: URL) -> [Game] {
        GameSystem.all.flatMap { system in
            scan(root.appendingPathComponent(system.id, isDirectory: true), system: system)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    nonisolated private static func scan(_ folder: URL, system: GameSystem) -> [Game] {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }

        if system.gameIsFolder {
            return children.compactMap { url in
                if isDirectory(url) {
                    return Game(url: url, systemID: system.id, title: PlayStationFolder.title(in: url))
                }
                guard system.extensions.contains(url.pathExtension.lowercased()) else { return nil }
                // A Vita package carries its real title inside.
                return Game(url: url, systemID: system.id,
                            title: VitaGame.isPackage(url) ? PlayStationFolder.title(in: url) : nil)
            }
        }

        // Files may sit directly in the system folder or one folder deeper.
        var files: [URL] = []
        for child in children {
            if isDirectory(child) {
                files += (try? manager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])) ?? []
            } else {
                files.append(child)
            }
        }
        files = files.filter { system.extensions.contains($0.pathExtension.lowercased()) }

        // A multi-disc .m3u playlist hides the discs it lists.
        let playlists = files.filter { $0.pathExtension.lowercased() == "m3u" }
        let playlistTitles = playlists.map { Game.tidy($0.deletingPathExtension().lastPathComponent) }
        if !playlists.isEmpty {
            files = files.filter { file in
                file.pathExtension.lowercased() == "m3u"
                    || !playlistTitles.contains(Game.tidy(file.deletingPathExtension().lastPathComponent))
            }
        }
        return files.map { Game(url: $0, systemID: system.id) }
    }

    /// Follows links, so game folders added in place by "Find Games" count as folders.
    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
