import Foundation
import Observation

/// Searches folders and drives for games and adds them to the library in place, as links.
@MainActor
@Observable
final class GameFinder {
    struct Found: Identifiable, Hashable {
        let url: URL
        var systemID: String?
        var companions: [URL] = []
        /// Decided from folder names only, or not at all.
        var needsReview = false
        var selected = true
        /// The real name, for PlayStation game folders.
        var name: String?

        var id: String { url.path }
        var title: String { name ?? Game.tidy(url.deletingPathExtension().lastPathComponent) }
    }

    enum Phase: Equatable {
        case idle, scanning, done, adding
    }

    private(set) var phase = Phase.idle
    private(set) var currentFolder = ""
    private(set) var scannedFiles = 0
    var found: [Found] = []
    private var task: Task<Void, Never>?

    /// Places worth searching: the home folder and every connected drive.
    static var suggestedLocations: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey],
                                                            options: [.skipHiddenVolumes]) ?? []
        return [home] + volumes.filter { $0.path != "/" }
    }

    func start(in locations: [URL], library: Library) {
        task?.cancel()
        phase = .scanning
        found = []
        scannedFiles = 0
        let existing = Set(library.games.map { $0.url.resolvingSymlinksInPath().path })
        let skip = [library.folder.resolvingSymlinksInPath().path]

        task = Task {
            let stream = AsyncStream<Progress> { continuation in
                let worker = Task.detached(priority: .utility) {
                    Self.search(locations, skipping: skip, report: { continuation.yield($0) })
                    continuation.finish()
                }
                continuation.onTermination = { _ in worker.cancel() }
            }
            for await progress in stream {
                switch progress {
                case .folder(let path, let files):
                    currentFolder = path
                    scannedFiles = files
                case .found(let item):
                    if !existing.contains(item.url.resolvingSymlinksInPath().path) { found.append(item) }
                }
            }
            if !Task.isCancelled { phase = .done }
        }
    }

    func reset() {
        task?.cancel()
        phase = .idle
        found = []
    }

    func cancel() {
        task?.cancel()
        phase = found.isEmpty ? .idle : .done
    }

    /// Links the selected games into their system folders; nothing is copied or moved.
    func add(to library: Library) async -> Int {
        phase = .adding
        let items = found.filter { $0.selected && $0.systemID != nil }
        let root = library.folder
        let added = await Task.detached {
            var count = 0
            for item in items {
                let folder = root.appendingPathComponent(item.systemID!, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for (index, source) in ([item.url] + item.companions).enumerated() {
                    let link = folder.appendingPathComponent(source.lastPathComponent)
                    guard !FileManager.default.fileExists(atPath: link.path) else { continue }
                    if (try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)) != nil, index == 0 {
                        count += 1
                    }
                }
            }
            return count
        }.value
        await library.scan()
        phase = .idle
        found = []
        return added
    }

    // MARK: Searching

    private enum Progress: Sendable {
        case folder(String, files: Int)
        case found(Found)
    }

    /// Folders that never hold games, or that Arcadia must not look into.
    nonisolated private static let skippedNames: Set<String> = [
        "Library", "Applications", ".Trash", "node_modules", ".git", "DerivedData", "Pods", ".build",
        "System", "private", "usr", "bin", "sbin", "opt", "cores", "Volumes",
    ]

    nonisolated private static func search(_ locations: [URL], skipping skipped: [String],
                                           report: @Sendable (Progress) -> Void) {
        var files = 0, folders = 0
        var seen = Set<String>()
        for location in locations {
            guard let enumerator = FileManager.default.enumerator(
                at: location, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                if values?.isSymbolicLink == true { continue }
                let path = url.path
                guard seen.insert(path).inserted else { enumerator.skipDescendants(); continue }

                if values?.isDirectory == true {
                    if skippedNames.contains(url.lastPathComponent) || skipped.contains(where: { path.hasPrefix($0) }) {
                        enumerator.skipDescendants()
                        continue
                    }
                    folders += 1
                    if folders % 40 == 0 { report(.folder(path, files: files)) }
                    if let system = GameIdentifier.identifyFolder(url) {
                        report(.found(Found(url: url, systemID: system, name: PlayStationFolder.title(in: url))))
                        enumerator.skipDescendants()
                    }
                    continue
                }

                files += 1
                // Cue sheets are tiny text files; anything else that small is not a game.
                let ext = url.pathExtension.lowercased()
                guard GameIdentifier.isCandidate(url), ext == "cue" || (values?.fileSize ?? 0) >= 1024 else { continue }
                switch GameIdentifier.identify(url) {
                case .game(let match):
                    // Skip formats the system's emulator cannot open.
                    guard GameSystem.with(id: match.systemID)?.extensions.contains(ext) == true else { continue }
                    report(.found(Found(url: url, systemID: match.systemID, companions: match.companions,
                                        needsReview: match.guessed,
                                        name: VitaGame.isPackage(url) ? PlayStationFolder.title(in: url) : nil)))
                case .unknown:
                    report(.found(Found(url: url, systemID: nil, needsReview: true, selected: false)))
                case .ignore:
                    break
                }
            }
        }
    }
}
