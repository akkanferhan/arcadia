import Foundation

/// Arcadia's folders on disk.
enum Paths {
    static let support: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arcadia", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var emulators: URL { folder("Emulators") }
    static var artwork: URL { folder("Artwork") }
    static var downloads: URL { folder("Downloads") }
    static var records: URL { support.appendingPathComponent("records.json") }

    static func emulator(_ id: String) -> URL { emulators.appendingPathComponent(id, isDirectory: true) }

    /// Settings, saves and memory cards of one emulator, kept apart from the emulator's own app.
    static func data(_ id: String) -> URL {
        let url = folder("Data").appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var defaultLibrary: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Games", isDirectory: true)
    }

    private static func folder(_ name: String) -> URL {
        let url = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Runs command-line tools that ship with macOS.
enum Shell {
    struct Failure: LocalizedError {
        let command: String
        let output: String
        var errorDescription: String? { "\(command) failed: \(output)" }
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw Failure(command: URL(fileURLWithPath: tool).lastPathComponent, output: output)
            }
            return output
        }.value
    }
}
