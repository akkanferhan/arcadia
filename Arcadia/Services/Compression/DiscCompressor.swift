import Foundation
import Observation

/// Which games can be shrunk, and into what. A game qualifies only when its system's emulator
/// also plays the compressed format, so the result stays playable.
struct CompressionPlan: Equatable, Sendable {
    let format: DiscImageFormat

    /// Disc formats Arcadia can write, per system, with the extensions they replace.
    private static let rules: [(systemID: String, sources: Set<String>, format: DiscImageFormat)] = [
        ("psp", ["iso"], .cso),
        ("ps2", ["iso"], .cso),
        ("gc", ["iso", "gcm"], .gcz),
    ]

    static func plan(for game: Game) -> CompressionPlan? {
        guard let system = GameSystem.with(id: game.systemID), !system.gameIsFolder else { return nil }
        let ext = game.url.pathExtension.lowercased()
        guard let rule = rules.first(where: { $0.systemID == system.id && $0.sources.contains(ext) }),
              system.extensions.contains(rule.format.fileExtension) else { return nil }
        return CompressionPlan(format: rule.format)
    }

    /// Systems with something to compress, for the explanation on the Save Disk Space screen.
    static var supportedSystems: [GameSystem] {
        GameSystem.all.filter { system in rules.contains { $0.systemID == system.id } }
    }
}

/// Where a compression job stands.
enum CompressionStage: Equatable {
    case queued
    case compressing(Double)
    case verifying(Double)
    case finished(saved: Int64, originalKept: Bool)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .queued, .compressing, .verifying: true
        case .finished, .failed: false
        }
    }
}

/// Size of a game on disk and what compressing it would likely save.
struct CompressionEstimate: Equatable {
    let size: Int64
    /// `nil` until the estimate is ready.
    var compressed: Int64?

    var savings: Int64? { compressed.map { max(size - $0, 0) } }

    /// Worth offering: at least 5% and 16 MB smaller.
    var worthIt: Bool {
        guard let savings else { return false }
        return savings >= 16 * 1024 * 1024 && Double(savings) >= Double(size) * 0.05
    }
}

enum CompressionError: LocalizedError {
    case alreadyExists(String)
    case notEnoughSpace
    case playing

    var errorDescription: String? {
        switch self {
        case .alreadyExists(let name): String(localized: "\(name) already exists next to the game.")
        case .notEnoughSpace: String(localized: "There is not enough free space on the drive to write the compressed copy.")
        case .playing: String(localized: "Quit the game before compressing it.")
        }
    }
}

/// Shrinks disc images losslessly, one game at a time, and swaps them in only once verified.
@MainActor
@Observable
final class DiscCompressor {
    private(set) var stages: [String: CompressionStage] = [:]
    private(set) var estimates: [String: CompressionEstimate] = [:]
    /// Games queued since the screen was last cleared, so finished ones stay listed.
    private(set) var jobs: [Game] = []
    private var queue: [Game] = []
    private var current: Game?
    private var worker: Task<Void, Never>?
    private var estimating: Task<Void, Never>?

    /// Set by the game context menu so the Save Disk Space screen opens on that game.
    var focus: Game?

    var isWorking: Bool { current != nil }

    func stage(_ game: Game) -> CompressionStage? { stages[game.id] }

    /// Total saved by the jobs finished since launch.
    var savedSoFar: Int64 {
        stages.values.reduce(0) { total, stage in
            if case .finished(let saved, _) = stage { return total + saved }
            return total
        }
    }

    // MARK: Estimating

    /// Measures sizes and estimates savings for games not measured yet.
    func estimate(_ games: [Game]) {
        let pending = games.filter { estimates[$0.id] == nil && CompressionPlan.plan(for: $0) != nil }
        guard !pending.isEmpty else { return }
        for game in pending {
            estimates[game.id] = CompressionEstimate(size: Self.size(of: game))
        }
        let previous = estimating
        estimating = Task {
            await previous?.value
            for game in pending {
                guard let plan = CompressionPlan.plan(for: game) else { continue }
                let source = game.url.resolvingSymlinksInPath()
                let compressed = await Task.detached(priority: .utility) {
                    try? DiscImageCodec.estimatedSize(of: source, format: plan.format)
                }.value
                if Task.isCancelled { return }
                if let compressed { estimates[game.id]?.compressed = Int64(compressed) }
            }
        }
    }

    nonisolated static func size(of game: Game) -> Int64 {
        (try? DiscImageCodec.fileSize(game.url.resolvingSymlinksInPath())).map(Int64.init) ?? 0
    }

    // MARK: Jobs

    func compress(_ games: [Game], library: Library, launcher: Launcher) {
        for game in games where CompressionPlan.plan(for: game) != nil && stages[game.id]?.isActive != true {
            stages[game.id] = .queued
            queue.append(game)
            if !jobs.contains(game) { jobs.append(game) }
        }
        guard worker == nil else { return }
        worker = Task {
            while !queue.isEmpty {
                let game = queue.removeFirst()
                current = game
                await run(game, library: library, launcher: launcher)
                current = nil
            }
            worker = nil
            await library.scan()
        }
    }

    func cancel(_ game: Game) {
        if current == game {
            jobTask?.cancel()
        } else {
            queue.removeAll { $0 == game }
            stages[game.id] = nil
            jobs.removeAll { $0 == game }
        }
    }

    func cancelAll() {
        for game in queue { stages[game.id] = nil }
        queue.removeAll()
        jobTask?.cancel()
    }

    /// Forgets finished and failed jobs, e.g. when the screen is closed.
    func clearFinished() {
        stages = stages.filter { $0.value.isActive }
        jobs.removeAll { stages[$0.id] == nil }
    }

    private var jobTask: Task<Replacement.Outcome, Error>?

    private func run(_ game: Game, library: Library, launcher: Launcher) async {
        guard let plan = CompressionPlan.plan(for: game) else { return }
        guard launcher.running != game, launcher.preparing != game else {
            stages[game.id] = .failed(CompressionError.playing.localizedDescription)
            return
        }
        stages[game.id] = .compressing(0)
        let id = game.id
        let expected = estimates[game.id]?.compressed
        let report: @Sendable (CompressionStage) -> Void = { [weak self] stage in
            Task { @MainActor in
                guard let self, self.stages[id]?.isActive == true else { return }
                self.stages[id] = stage
            }
        }
        let task = Task.detached(priority: .userInitiated) {
            try Replacement.perform(game.url, format: plan.format, expectedSize: expected, report: report)
        }
        jobTask = task
        do {
            let outcome = try await task.value
            library.moveRecord(from: game.id, to: outcome.newGameURL.path)
            stages[game.id] = .finished(saved: outcome.saved, originalKept: outcome.originalKept)
            estimates[game.id] = nil
        } catch is CancellationError {
            stages[game.id] = nil
        } catch {
            stages[game.id] = .failed(error.localizedDescription)
        }
        jobTask = nil
        await library.scan()
    }
}

/// The file work of one job: compress beside the real file, verify, then swap it in.
enum Replacement {
    struct Outcome: Sendable {
        /// The game's new path in the library (the new link, for games added in place).
        let newGameURL: URL
        let compressedURL: URL
        let saved: Int64
        /// The original could not be moved to the Trash (for example on a network drive).
        let originalKept: Bool
    }

    /// `gameURL` is the file in the library; it may be a link to the real file elsewhere.
    /// `trash` moves the original away once the copy is proven; tests replace it.
    static func perform(_ gameURL: URL, format: DiscImageFormat, expectedSize: Int64?,
                        trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                        report: @escaping @Sendable (CompressionStage) -> Void) throws -> Outcome {
        let manager = FileManager.default
        let isLink = (try? gameURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        let source = gameURL.resolvingSymlinksInPath()
        let destination = source.deletingPathExtension().appendingPathExtension(format.fileExtension)
        let newGameURL = isLink ? gameURL.deletingPathExtension().appendingPathExtension(format.fileExtension) : destination
        for url in Set([destination, newGameURL]) where manager.fileExists(atPath: url.path) {
            throw CompressionError.alreadyExists(url.lastPathComponent)
        }

        let folder = source.deletingLastPathComponent()
        let originalSize = Int64(try DiscImageCodec.fileSize(source))
        let needed = (expectedSize ?? originalSize) + 64 * 1024 * 1024
        if let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free > 0, free < needed {
            throw CompressionError.notEnoughSpace
        }

        // Hidden and without a game extension, so a library scan never lists the half-written file.
        let partial = folder.appendingPathComponent(".\(destination.lastPathComponent).arcadia-partial")
        try? manager.removeItem(at: partial)
        var finished = false
        defer { if !finished { try? manager.removeItem(at: partial) } }

        let original = try DiscImageCodec.compress(source, to: partial, format: format) { report(.compressing($0)) }
        report(.verifying(0))
        let copy = try DiscImageCodec.contentDigest(of: partial) { report(.verifying($0)) }
        guard copy == original else { throw DiscImageError.mismatch }
        try Task.checkCancellation()

        try manager.moveItem(at: partial, to: destination)
        finished = true
        if isLink {
            try manager.createSymbolicLink(at: newGameURL, withDestinationURL: destination)
            try? manager.removeItem(at: gameURL)
        }
        let originalKept = (try? trash(source)) == nil
        let compressedSize = Int64(try DiscImageCodec.fileSize(destination))
        return Outcome(newGameURL: newGameURL, compressedURL: destination,
                       saved: originalKept ? 0 : originalSize - compressedSize, originalKept: originalKept)
    }
}
