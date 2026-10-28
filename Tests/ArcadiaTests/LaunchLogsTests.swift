import Foundation
import Testing
@testable import Arcadia

@Suite struct LaunchLogsTests {
    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    @Test func namesLogsByEmulatorAndTime() {
        #expect(LaunchLogs.fileName(emulator: "duckstation", date: date("2026-10-28 09:05:07"))
            == "duckstation-2026-10-28-090507.log")
        #expect(LaunchLogs.folder.path.hasSuffix("/Library/Logs/Arcadia"))
    }

    @Test func startsWithTheCommandAndNeverOverwrites() throws {
        let folder = TemporaryFolder()
        let when = date("2026-10-28 10:00:00")
        let first = try #require(LaunchLogs.create(emulator: "dolphin", command: ["/Apps/Dolphin.app", "-e", "/Games/My Game.iso"],
                                                   in: folder.url, date: when))
        let second = try #require(LaunchLogs.create(emulator: "dolphin", command: ["x"], in: folder.url, date: when))
        #expect(first.lastPathComponent == "dolphin-2026-10-28-100000.log")
        #expect(second.lastPathComponent == "dolphin-2026-10-28-100000-2.log")
        let header = try String(contentsOf: first, encoding: .utf8)
        #expect(header.hasPrefix("Arcadia "))
        #expect(header.contains("/Apps/Dolphin.app -e '/Games/My Game.iso'\n"))
    }

    @Test func keepsOnlyTheNewestLogs() throws {
        let folder = TemporaryFolder()
        for minute in 0..<25 {
            let file = folder.write("old-\(minute).log", text: "x")
            try FileManager.default.setAttributes([.creationDate: date("2026-10-01 10:\(String(format: "%02d", minute)):00")],
                                                  ofItemAtPath: file.path)
        }
        folder.write("notes.txt", text: "not a log")
        let new = try #require(LaunchLogs.create(emulator: "cemu", command: ["cemu"], in: folder.url))
        let logs = LaunchLogs.all(in: folder.url)
        #expect(logs.count == LaunchLogs.keep)
        #expect(logs.first?.lastPathComponent == new.lastPathComponent)
        #expect(logs.last?.lastPathComponent == "old-6.log")
        #expect(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("notes.txt").path))
    }

    @Test func capturesOutputOfBareExecutables() throws {
        let folder = TemporaryFolder()
        let log = try #require(LaunchLogs.create(emulator: "test", command: ["/bin/sh"], in: folder.url))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "echo out one; echo err one >&2; echo out two"]
        let handle = try #require(LaunchLogs.appendingHandle(log))
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.hasPrefix("Arcadia "))
        #expect(text.hasSuffix("\nout one\nerr one\nout two\n"))
    }

    @Test func appsLogThroughOpen() {
        let log = URL(fileURLWithPath: "/tmp/a b.log")
        #expect(LaunchLogs.openArguments(log) == ["--stdout", "/tmp/a b.log", "--stderr", "/tmp/a b.log"])
        #expect(LaunchLogs.openArguments(nil).isEmpty)
    }

    @Test func showsOnlyTheEndOfLongLogs() {
        let folder = TemporaryFolder()
        let file = folder.write("long.log", text: String(repeating: "a", count: 100) + "END")
        let tail = LaunchLogs.tail(of: file, limit: 10)
        #expect(tail.text == "aaaaaaaEND")
        #expect(tail.truncated)
        #expect(LaunchLogs.tail(of: file).truncated == false)
    }
}
