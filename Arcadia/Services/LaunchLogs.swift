import Foundation

/// What each emulator printed while it ran, kept in ~/Library/Logs/Arcadia so a game that
/// refuses to start can be looked into.
enum LaunchLogs {
    /// Older logs are deleted when a new one starts.
    static let keep = 20

    static var folder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Arcadia", isDirectory: true)
    }

    /// `<emulator>-<yyyy-MM-dd-HHmmss>.log`, in local time.
    static func fileName(emulator: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(emulator)-\(formatter.string(from: date)).log"
    }

    /// Creates a log that starts with what was launched, and deletes all but the newest `keep`.
    static func create(emulator: String, command: [String], in folder: URL = folder, date: Date = .now) -> URL? {
        let manager = FileManager.default
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        var url = folder.appendingPathComponent(fileName(emulator: emulator, date: date))
        var attempt = 2
        while manager.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(fileName(emulator: emulator, date: date)
                .replacingOccurrences(of: ".log", with: "-\(attempt).log"))
            attempt += 1
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let header = """
        Arcadia \(version), \(Date.ISO8601FormatStyle(timeZone: .current).format(date))
        \(command.map(quoted).joined(separator: " "))

        """
        guard manager.createFile(atPath: url.path, contents: Data(header.utf8)) else { return nil }
        prune(folder, keep: keep)
        return url
    }

    /// Logs in `folder`, newest first.
    static func all(in folder: URL = folder) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        func created(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        return files.filter { $0.pathExtension == "log" }
            .map { ($0, created($0)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lastPathComponent > $1.0.lastPathComponent }
            .map(\.0)
    }

    static func prune(_ folder: URL = folder, keep: Int = keep) {
        for old in all(in: folder).dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }

    /// A handle that appends to the log, for a process's standard output and error.
    static func appendingHandle(_ log: URL) -> FileHandle? {
        let descriptor = open(log.path, O_WRONLY | O_APPEND)
        return descriptor < 0 ? nil : FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Arguments that make `open` send the app's output to the log; it appends.
    static func openArguments(_ log: URL?) -> [String] {
        log.map { ["--stdout", $0.path, "--stderr", $0.path] } ?? []
    }

    /// The end of a log, at most `limit` bytes, for showing on screen.
    static func tail(of log: URL, limit: Int = 1_000_000) -> (text: String, truncated: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return ("", false) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(limit) ? size - UInt64(limit) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return (String(decoding: data, as: UTF8.self), start > 0)
    }

    private static func quoted(_ argument: String) -> String {
        argument.contains(where: { $0 == " " || $0 == "'" || $0 == "\"" })
            ? "'\(argument.replacingOccurrences(of: "'", with: "'\\''"))'" : argument
    }
}
