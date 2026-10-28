import CoreServices
import Foundation
import Testing
@testable import Arcadia

@MainActor
@Suite struct FolderWatcherTests {
    /// Waits up to `timeout` for `condition`.
    private func eventually(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test func reportsGamesCopiedIntoSubfolders() async {
        let folder = TemporaryFolder()
        folder.folder("snes")
        try? await Task.sleep(for: .milliseconds(500)) // let FSEvents report the folder's creation first
        var changes = 0
        let watcher = FolderWatcher(delay: .milliseconds(600)) { changes += 1 }
        watcher.watch(folder.url)
        try? await Task.sleep(for: .milliseconds(300)) // the stream starts after a moment

        // A burst of files is one rescan.
        for name in ["One", "Two", "Three"] {
            folder.write("snes/Game \(name).sfc", text: "x")
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(await eventually { changes > 0 })
        try? await Task.sleep(for: .milliseconds(800))
        #expect(changes == 1)

        try? FileManager.default.removeItem(at: folder.url.appendingPathComponent("snes/Game One.sfc"))
        #expect(await eventually { changes == 2 })

        watcher.stop()
        folder.write("snes/Game Four.sfc", text: "x")
        try? await Task.sleep(for: .milliseconds(800))
        #expect(changes == 2)
    }

    @Test func ignoresHiddenFilesAndContentChanges() {
        // A library inside a hidden folder still counts; only hidden items inside it are skipped.
        let folder = TemporaryFolder()
        let root = folder.folder(".config/Games")
        let real = FolderWatcher.realPath(root)
        #expect(real.hasPrefix("/private/")) // the temporary folder lives in /var, a link
        let created = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
        let modified = FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        #expect(FolderWatcher.matters(path: "\(real)/snes/Mario.sfc", flags: created, in: root))
        #expect(!FolderWatcher.matters(path: "\(real)/snes/.DS_Store", flags: created, in: root))
        #expect(!FolderWatcher.matters(path: "\(real)/.hidden/Mario.sfc", flags: created, in: root))
        #expect(!FolderWatcher.matters(path: "\(real)/snes/Mario.sfc", flags: modified, in: root))
        #expect(FolderWatcher.matters(path: real,
                                      flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged), in: root))
    }
}
