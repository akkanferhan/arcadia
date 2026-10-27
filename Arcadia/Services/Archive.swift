import Foundation

/// Unpacks the archive formats emulators ship in, using tools built into macOS.
enum Archive {
    private static let archiveSuffixes = [".dmg", ".zip", ".7z", ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".tar"]

    static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return archiveSuffixes.contains { name.hasSuffix($0) }
    }

    static func extract(_ archive: URL, into folder: URL) async throws {
        let name = archive.lastPathComponent.lowercased()
        if name.hasSuffix(".dmg") {
            try await extractDiskImage(archive, into: folder)
        } else if name.hasSuffix(".zip") {
            try await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        } else {
            // bsdtar reads tar, xz, bzip2 and 7z.
            try await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", folder.path])
        }
    }

    private static func extractDiskImage(_ image: URL, into folder: URL) async throws {
        let mount = Paths.downloads.appendingPathComponent("mount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mount) }
        try await Shell.run("/usr/bin/hdiutil",
                            ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        do {
            let apps = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }
            for app in apps {
                try await Shell.run("/usr/bin/ditto", [app.path, folder.appendingPathComponent(app.lastPathComponent).path])
            }
        } catch {
            _ = try? await Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            throw error
        }
        try await Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
    }

    /// Finds the app bundle (or bare executable) inside an extracted download,
    /// unpacking nested archives along the way.
    static func findPayload(in folder: URL, named name: String) async throws -> URL? {
        for _ in 0..<3 {
            if let app = find(in: folder, where: { $0.pathExtension == "app" }) { return app }
            let nested = all(in: folder).filter(isArchive)
            guard !nested.isEmpty else { break }
            for archive in nested {
                try await extract(archive, into: archive.deletingLastPathComponent())
                try FileManager.default.removeItem(at: archive)
            }
        }
        let wanted = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return find(in: folder) { url in
            let file = url.lastPathComponent.lowercased().filter { $0.isLetter || $0.isNumber }
            return file == wanted && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    /// Breadth-first, so the outermost `.app` wins over helper apps nested inside it.
    private static func find(in folder: URL, where match: (URL) -> Bool) -> URL? {
        var queue = [folder]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            let children = (try? FileManager.default.contentsOfDirectory(
                at: current, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if match(child) { return child }
                if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                   child.pathExtension != "app" {
                    queue.append(child)
                }
            }
        }
        return nil
    }

    private static func all(in folder: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
        return (enumerator?.allObjects as? [URL]) ?? []
    }
}
