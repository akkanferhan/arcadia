import Foundation

/// Asks iCloud Drive about files that may still be in the cloud only.
protocol UbiquitousFiles: Sendable {
    /// True when the file has no usable local copy yet.
    func needsDownload(_ url: URL) -> Bool
    func startDownloading(_ url: URL) throws
}

struct SystemUbiquitousFiles: UbiquitousFiles {
    func needsDownload(_ url: URL) -> Bool {
        if SaveMerge.placeholderName(url.lastPathComponent) != nil { return true }
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true,
              let status = values.ubiquitousItemDownloadingStatus else { return false }
        // `.downloaded` is an older local copy, still fine to play offline.
        return status == .notDownloaded
    }

    func startDownloading(_ url: URL) throws {
        var target = url
        if let real = SaveMerge.placeholderName(url.lastPathComponent) {
            target = url.deletingLastPathComponent().appendingPathComponent(real)
        }
        try FileManager.default.startDownloadingUbiquitousItem(at: target)
    }
}

/// Moves save folders into iCloud Drive and back. Every step copies before it removes,
/// so an interruption leaves the saves where they were.
struct SaveSyncEngine: Sendable {
    /// `Arcadia/Saves` inside iCloud Drive.
    let cloudRoot: URL
    /// Conflict backups, one dated folder per move.
    let backupRoot: URL
    var files: any UbiquitousFiles = SystemUbiquitousFiles()

    enum Failure: LocalizedError {
        case notAFolder(URL)
        case downloadTimedOut
        var errorDescription: String? {
            switch self {
            case .notAFolder(let url):
                String(localized: "Arcadia expected a folder at \(url.path(percentEncoded: false)) but found a file.")
            case .downloadTimedOut:
                String(localized: "Your saves are still downloading from iCloud Drive. Check your internet connection and try again.")
            }
        }
    }

    func cloudFolder(for location: SaveLocation) -> URL {
        cloudRoot.appendingPathComponent(location.emulatorID, isDirectory: true)
            .appendingPathComponent(location.cloudPath, isDirectory: true)
    }

    /// A fresh dated folder for the conflicts of one move.
    func backupFolder(for location: SaveLocation, date: Date = .now) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = formatter.string(from: date)
        return backupRoot.appendingPathComponent(stamp, isDirectory: true)
            .appendingPathComponent(location.emulatorID, isDirectory: true)
            .appendingPathComponent(location.cloudPath, isDirectory: true)
    }

    private var fileManager: FileManager { .default }

    private func linkDestination(_ url: URL) -> URL? {
        guard let path = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        return URL(fileURLWithPath: path, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
    }

    private func isFolder(_ url: URL) -> Bool {
        var folder: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &folder) && folder.boolValue
    }

    /// True when the local folder already is a link into iCloud Drive.
    func isLinked(_ location: SaveLocation) -> Bool {
        linkDestination(location.local)?.path == cloudFolder(for: location).standardizedFileURL.path
    }

    /// Moves the local saves into iCloud Drive and leaves a link in their place.
    /// Conflicting files keep the newer version in iCloud Drive and back up the other.
    @discardableResult
    func link(_ location: SaveLocation, date: Date = .now) throws -> SaveMerge.Report {
        let cloud = cloudFolder(for: location)
        let local = location.local
        try FileCoordination.createFolder(cloud)
        if isLinked(location) { return .init() }

        let merge = SaveMerge(backups: backupFolder(for: location, date: date))
        var report = SaveMerge.Report()
        if let other = linkDestination(local) {
            // A link Arcadia did not make: bring in what it points to, leave that folder alone.
            if isFolder(other) { report = try merge.merge(other, into: cloud) }
            try fileManager.removeItem(at: local)
        } else if fileManager.fileExists(atPath: local.path) {
            guard isFolder(local) else { throw Failure.notAFolder(local) }
            report = try merge.merge(local, into: cloud)
            // Everything is in iCloud Drive now; swap the folder for the link, keeping it until the link exists.
            let staging = local.deletingLastPathComponent().appendingPathComponent(".\(local.lastPathComponent).arcadia-moving")
            try? fileManager.removeItem(at: staging)
            try fileManager.moveItem(at: local, to: staging)
            do {
                try fileManager.createSymbolicLink(at: local, withDestinationURL: cloud)
            } catch {
                try? fileManager.moveItem(at: staging, to: local)
                throw error
            }
            try? fileManager.removeItem(at: staging)
            return report
        }
        try fileManager.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: local, withDestinationURL: cloud)
        return report
    }

    /// Copies the saves from iCloud Drive back into a real local folder. The iCloud copy stays,
    /// so other Macs keep them. Files must be downloaded first (see `download`).
    @discardableResult
    func unlink(_ location: SaveLocation, date: Date = .now) throws -> SaveMerge.Report {
        let local = location.local
        guard let destination = linkDestination(local) else { return .init() }
        let merge = SaveMerge(backups: backupFolder(for: location, date: date))
        let staging = local.deletingLastPathComponent().appendingPathComponent(".\(local.lastPathComponent).arcadia-restoring")
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var report = SaveMerge.Report()
        do {
            // A missing iCloud folder (signed out of iCloud) just leaves an empty local folder.
            if isFolder(destination) { report = try merge.merge(destination, into: staging) }
            try fileManager.removeItem(at: local)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        do {
            try fileManager.moveItem(at: staging, to: local)
        } catch {
            try? fileManager.createSymbolicLink(at: local, withDestinationURL: destination)
            throw error
        }
        return report
    }

    /// Files in the folders that are still in the cloud only.
    func pendingDownloads(in folders: [URL]) -> [URL] {
        folders.flatMap { folder -> [URL] in
            guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil, options: []) else { return [] }
            return enumerator.compactMap { $0 as? URL }.filter { files.needsDownload($0) }
        }
    }

    /// Starts downloading every cloud-only file in the folders and waits until all are local.
    func download(_ folders: [URL], timeout: Duration = .seconds(60), poll: Duration = .milliseconds(500),
                  progress: @Sendable (Double) -> Void = { _ in }) async throws {
        let existing = folders.filter(isFolder)
        var pending = pendingDownloads(in: existing)
        guard !pending.isEmpty else { return }
        let total = Double(pending.count)
        for file in pending { try? files.startDownloading(file) }
        let deadline = ContinuousClock.now + timeout
        while !pending.isEmpty {
            progress(1 - Double(pending.count) / total)
            guard ContinuousClock.now < deadline else { throw Failure.downloadTimedOut }
            try await Task.sleep(for: poll)
            // Placeholders are replaced by the real file, so look again rather than at the old names.
            pending = pendingDownloads(in: existing)
        }
        progress(1)
    }
}
