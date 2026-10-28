import Foundation

/// Copies one folder of saves into another without ever losing a file.
///
/// - A file missing at the destination is copied.
/// - Identical files are left alone.
/// - When both sides differ, the newer file ends up at the destination and the other one
///   is copied into `backups` under the same relative path. Nothing is overwritten
///   without a backup, and the source is never changed.
struct SaveMerge {
    /// Where losing versions of conflicting files go, mirroring their relative paths.
    let backups: URL
    var fileManager: FileManager = .default

    struct Report: Equatable {
        /// Relative paths copied to the destination (new or newer files).
        var copied: [String] = []
        /// Relative paths whose losing version went to the backups folder.
        var conflicts: [String] = []
    }

    enum Failure: LocalizedError, Equatable {
        /// An iCloud placeholder that still has to be downloaded.
        case notDownloaded(String)
        var errorDescription: String? {
            switch self {
            case .notDownloaded(let name):
                String(localized: "“\(name)” hasn't finished downloading from iCloud Drive yet. Try again in a moment.")
            }
        }
    }

    /// Files macOS and iCloud create on their own; never worth syncing.
    static func isIgnored(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasSuffix(".nosync")
    }

    /// Old-style iCloud placeholders are named `.<name>.icloud`.
    static func placeholderName(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    @discardableResult
    func merge(_ source: URL, into destination: URL) throws -> Report {
        var report = Report()
        try FileCoordination.createFolder(destination, fileManager: fileManager)
        try merge(source, into: destination, relative: "", report: &report)
        return report
    }

    private func merge(_ source: URL, into destination: URL, relative: String, report: inout Report) throws {
        let items = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for item in items {
            let name = item.lastPathComponent
            if Self.isIgnored(name) { continue }
            if let real = Self.placeholderName(name) { throw Failure.notDownloaded(real) }
            let path = relative.isEmpty ? name : relative + "/" + name
            let target = destination.appendingPathComponent(name)
            let sourceKind = kind(of: item)
            let targetKind = kind(of: target)

            switch (sourceKind, targetKind) {
            case (_, .missing):
                try FileCoordination.copy(item, to: target, fileManager: fileManager)
                report.copied.append(path)
            case (.folder, .folder):
                try merge(item, into: target, relative: path, report: &report)
            case (.file, .file):
                if fileManager.contentsEqual(atPath: item.path, andPath: target.path) { continue }
                if modified(item) > modified(target) {
                    try backUp(target, path)
                    try FileCoordination.replace(target, with: item, fileManager: fileManager)
                    report.copied.append(path)
                } else {
                    try backUp(item, path)
                }
                report.conflicts.append(path)
            default:
                // A folder on one side and a file on the other: keep the destination, back up the source.
                try backUp(item, path)
                report.conflicts.append(path)
            }
        }
    }

    private enum Kind { case missing, file, folder }

    private func kind(of url: URL) -> Kind {
        var isFolder: ObjCBool = false
        // Symbolic links are treated as files and copied as links.
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true { return .file }
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isFolder) else { return .missing }
        return isFolder.boolValue ? .folder : .file
    }

    private func modified(_ url: URL) -> Date {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    }

    /// Copies a losing version into the backups folder; an earlier backup with the same
    /// path gets a numbered sibling instead of being replaced.
    private func backUp(_ item: URL, _ path: String) throws {
        var target = backups.appendingPathComponent(path)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var number = 2
        let base = target.deletingPathExtension().lastPathComponent, ext = target.pathExtension
        while fileManager.fileExists(atPath: target.path) || (try? target.checkResourceIsReachable()) == true {
            let name = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            target = target.deletingLastPathComponent().appendingPathComponent(name)
            number += 1
        }
        try FileCoordination.copy(item, to: target, fileManager: fileManager)
    }
}

/// File operations that tell iCloud Drive (and any other file presenter) what is happening,
/// so a sync never reads a half-written save.
enum FileCoordination {
    private static func coordinate(reading source: URL?, writing target: URL, options: NSFileCoordinator.WritingOptions,
                                   _ body: (URL?, URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var bodyError: Error?
        if let source {
            coordinator.coordinate(readingItemAt: source, options: [.withoutChanges], writingItemAt: target,
                                   options: options, error: &coordinationError) { read, write in
                do { try body(read, write) } catch { bodyError = error }
            }
        } else {
            coordinator.coordinate(writingItemAt: target, options: options, error: &coordinationError) { write in
                do { try body(nil, write) } catch { bodyError = error }
            }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }

    static func copy(_ source: URL, to target: URL, fileManager: FileManager = .default) throws {
        try coordinate(reading: source, writing: target, options: []) { read, write in
            try fileManager.createDirectory(at: write.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: read ?? source, to: write)
        }
    }

    /// Replaces `target` with a copy of `source`; a failure leaves `target` as it was.
    static func replace(_ target: URL, with source: URL, fileManager: FileManager = .default) throws {
        try coordinate(reading: source, writing: target, options: .forReplacing) { read, write in
            let temporary = write.deletingLastPathComponent()
                .appendingPathComponent(".\(write.lastPathComponent).arcadia-\(UUID().uuidString)")
            try fileManager.copyItem(at: read ?? source, to: temporary)
            do {
                _ = try fileManager.replaceItemAt(write, withItemAt: temporary)
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        }
    }

    static func createFolder(_ url: URL, fileManager: FileManager = .default) throws {
        var isFolder: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue { return }
        try coordinate(reading: nil, writing: url, options: []) { _, write in
            try fileManager.createDirectory(at: write, withIntermediateDirectories: true)
        }
    }
}
