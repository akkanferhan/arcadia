import Foundation
import Testing
@testable import Arcadia

private extension TemporaryFolder {
    @discardableResult
    func write(_ path: String, text: String, modified: Date) -> URL {
        let file = write(path, text: text)
        try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        return file
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url.appendingPathComponent(path).path) }

    func isLink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.appendingPathComponent(path).path)) != nil
    }

    /// Relative paths of every file below `path`, following a link at `path` itself.
    func files(_ path: String) -> [String] {
        let root = url.appendingPathComponent(path).resolvingSymlinksInPath()
        let depth = root.pathComponents.count
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        return (enumerator?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .map { $0.resolvingSymlinksInPath().pathComponents.dropFirst(depth).joined(separator: "/") }
            .sorted()
    }
}

private let old = Date(timeIntervalSince1970: 1_700_000_000)
private let new = Date(timeIntervalSince1970: 1_750_000_000)

@Suite struct SaveMergeTests {
    @Test func copiesMissingFilesAndFoldersAndLeavesTheSourceAlone() throws {
        let folder = TemporaryFolder()
        folder.write("local/snes/Mario.srm", text: "mario", modified: old)
        folder.write("local/gba/Zelda.sav", text: "zelda")
        folder.write("local/.DS_Store", text: "junk")
        folder.write("cloud/psx/Card.mcd", text: "card")
        let report = try SaveMerge(backups: folder.url.appendingPathComponent("backups"))
            .merge(folder.url.appendingPathComponent("local"), into: folder.url.appendingPathComponent("cloud"))

        #expect(folder.files("cloud") == ["gba/Zelda.sav", "psx/Card.mcd", "snes/Mario.srm"])
        #expect(folder.read("cloud/snes/Mario.srm") == "mario")
        #expect(report.copied.sorted() == ["gba", "snes"])
        #expect(report.conflicts.isEmpty)
        #expect(folder.files("local") == [".DS_Store", "gba/Zelda.sav", "snes/Mario.srm"])
        #expect(!folder.exists("backups"))
        // Copies keep their dates, which later merges compare.
        let date = try FileManager.default.attributesOfItem(atPath: folder.url.appendingPathComponent("cloud/snes/Mario.srm").path)[.modificationDate] as? Date
        #expect(date == old)
    }

    @Test func identicalFilesAreNotConflicts() throws {
        let folder = TemporaryFolder()
        folder.write("a/Card.mcd", text: "same", modified: new)
        folder.write("b/Card.mcd", text: "same", modified: old)
        let report = try SaveMerge(backups: folder.url.appendingPathComponent("backups"))
            .merge(folder.url.appendingPathComponent("a"), into: folder.url.appendingPathComponent("b"))
        #expect(report == .init())
        #expect(!folder.exists("backups"))
    }

    @Test func newerSourceReplacesOlderDestinationAndBacksItUp() throws {
        let folder = TemporaryFolder()
        folder.write("local/snes/Mario.srm", text: "newer", modified: new)
        folder.write("cloud/snes/Mario.srm", text: "older", modified: old)
        let report = try SaveMerge(backups: folder.url.appendingPathComponent("backups"))
            .merge(folder.url.appendingPathComponent("local"), into: folder.url.appendingPathComponent("cloud"))
        #expect(folder.read("cloud/snes/Mario.srm") == "newer")
        #expect(folder.read("backups/snes/Mario.srm") == "older")
        #expect(folder.read("local/snes/Mario.srm") == "newer")
        #expect(report.conflicts == ["snes/Mario.srm"])
        #expect(report.copied == ["snes/Mario.srm"])
    }

    @Test func olderSourceNeverOverwritesNewerDestination() throws {
        let folder = TemporaryFolder()
        folder.write("local/Mario.srm", text: "older", modified: old)
        folder.write("cloud/Mario.srm", text: "newer", modified: new)
        let report = try SaveMerge(backups: folder.url.appendingPathComponent("backups"))
            .merge(folder.url.appendingPathComponent("local"), into: folder.url.appendingPathComponent("cloud"))
        #expect(folder.read("cloud/Mario.srm") == "newer")
        #expect(folder.read("backups/Mario.srm") == "older")
        #expect(report.conflicts == ["Mario.srm"])
        #expect(report.copied.isEmpty)
    }

    @Test func sameDateDifferentContentKeepsDestinationAndBacksUpSource() throws {
        let folder = TemporaryFolder()
        folder.write("local/Mario.srm", text: "mine", modified: old)
        folder.write("cloud/Mario.srm", text: "theirs", modified: old)
        try SaveMerge(backups: folder.url.appendingPathComponent("backups"))
            .merge(folder.url.appendingPathComponent("local"), into: folder.url.appendingPathComponent("cloud"))
        #expect(folder.read("cloud/Mario.srm") == "theirs")
        #expect(folder.read("backups/Mario.srm") == "mine")
    }

    @Test func fileAgainstFolderBacksUpTheSource() throws {
        let folder = TemporaryFolder()
        folder.write("local/GC/USA", text: "a file")
        folder.write("cloud/GC/USA/Card A/save.gci", text: "card")
        let report = try SaveMerge(backups: folder.url.appendingPathComponent("backups"))
            .merge(folder.url.appendingPathComponent("local"), into: folder.url.appendingPathComponent("cloud"))
        #expect(folder.read("cloud/GC/USA/Card A/save.gci") == "card")
        #expect(folder.read("backups/GC/USA") == "a file")
        #expect(report.conflicts == ["GC/USA"])
    }

    @Test func existingBackupsAreNeverReplaced() throws {
        let folder = TemporaryFolder()
        folder.write("backups/Mario.srm", text: "first backup")
        folder.write("local/Mario.srm", text: "older", modified: old)
        folder.write("cloud/Mario.srm", text: "newer", modified: new)
        try SaveMerge(backups: folder.url.appendingPathComponent("backups"))
            .merge(folder.url.appendingPathComponent("local"), into: folder.url.appendingPathComponent("cloud"))
        #expect(folder.read("backups/Mario.srm") == "first backup")
        #expect(folder.read("backups/Mario 2.srm") == "older")
    }

    @Test func cloudPlaceholdersStopTheMerge() throws {
        let folder = TemporaryFolder()
        folder.write("cloud/.Mario.srm.icloud", text: "placeholder")
        #expect(throws: SaveMerge.Failure.notDownloaded("Mario.srm")) {
            try SaveMerge(backups: folder.url.appendingPathComponent("backups"))
                .merge(folder.url.appendingPathComponent("cloud"), into: folder.url.appendingPathComponent("local"))
        }
        #expect(SaveMerge.placeholderName(".icloud") == nil)
        #expect(SaveMerge.placeholderName("Card.mcd") == nil)
    }
}

/// Stands in for iCloud: listed files stay cloud-only until polled `rounds` times after a download starts.
private final class FakeCloud: UbiquitousFiles, @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [String: Int]
    private(set) var started: Set<String> = []
    private let rounds: Int

    init(pending: [String], rounds: Int) {
        remaining = Dictionary(uniqueKeysWithValues: pending.map { ($0, rounds) })
        self.rounds = rounds
    }

    func needsDownload(_ url: URL) -> Bool {
        lock.withLock {
            let name = url.lastPathComponent
            guard let left = remaining[name] else { return false }
            if started.contains(name) {
                if left <= 1 { remaining[name] = nil; return false }
                remaining[name] = left - 1
            }
            return true
        }
    }

    func startDownloading(_ url: URL) throws {
        _ = lock.withLock { started.insert(url.lastPathComponent) }
    }
}

@Suite struct SaveSyncEngineTests {
    private func setUp(_ folder: TemporaryFolder, files: any UbiquitousFiles = SystemUbiquitousFiles())
        -> (SaveSyncEngine, SaveLocation) {
        let engine = SaveSyncEngine(cloudRoot: folder.url.appendingPathComponent("iCloud/Arcadia/Saves"),
                                    backupRoot: folder.url.appendingPathComponent("Backups"), files: files)
        let location = SaveLocation(emulatorID: "retroarch", local: folder.url.appendingPathComponent("Data/retroarch/saves"),
                                    cloudPath: "saves")
        return (engine, location)
    }

    @Test func linkingMovesSavesIntoICloudAndLeavesALink() throws {
        let folder = TemporaryFolder()
        let (engine, location) = setUp(folder)
        folder.write("Data/retroarch/saves/snes/Mario.srm", text: "mario")
        folder.write("Data/retroarch/saves/gba/Zelda.sav", text: "zelda")

        try engine.link(location)
        #expect(folder.isLink("Data/retroarch/saves"))
        #expect(engine.isLinked(location))
        #expect(folder.files("iCloud/Arcadia/Saves/retroarch/saves") == ["gba/Zelda.sav", "snes/Mario.srm"])
        // The emulator still finds its saves at the old path.
        #expect(folder.read("Data/retroarch/saves/snes/Mario.srm") == "mario")
        #expect(!folder.exists("Data/retroarch/.saves.arcadia-moving"))
        // Linking again changes nothing.
        try engine.link(location)
        #expect(folder.read("Data/retroarch/saves/snes/Mario.srm") == "mario")
    }

    @Test func linkingMergesWithSavesFromAnotherMac() throws {
        let folder = TemporaryFolder()
        let (engine, location) = setUp(folder)
        folder.write("Data/retroarch/saves/Mario.srm", text: "this Mac, newer", modified: new)
        folder.write("Data/retroarch/saves/Zelda.srm", text: "this Mac, older", modified: old)
        folder.write("iCloud/Arcadia/Saves/retroarch/saves/Mario.srm", text: "other Mac, older", modified: old)
        folder.write("iCloud/Arcadia/Saves/retroarch/saves/Zelda.srm", text: "other Mac, newer", modified: new)
        folder.write("iCloud/Arcadia/Saves/retroarch/saves/Metroid.srm", text: "other Mac only")

        let report = try engine.link(location, date: old)
        #expect(Set(report.conflicts) == ["Mario.srm", "Zelda.srm"])
        #expect(folder.read("Data/retroarch/saves/Mario.srm") == "this Mac, newer")
        #expect(folder.read("Data/retroarch/saves/Zelda.srm") == "other Mac, newer")
        #expect(folder.read("Data/retroarch/saves/Metroid.srm") == "other Mac only")
        let backups = engine.backupFolder(for: location, date: old).path.dropFirst(folder.url.path.count + 1)
        #expect(folder.read("\(backups)/Mario.srm") == "other Mac, older")
        #expect(folder.read("\(backups)/Zelda.srm") == "this Mac, older")
    }

    @Test func missingFoldersAreLinkedEmpty() throws {
        let folder = TemporaryFolder()
        let (engine, location) = setUp(folder)
        try engine.link(location)
        #expect(folder.isLink("Data/retroarch/saves"))
        // Presets create their system folders through the link.
        try FileManager.default.createDirectory(at: location.local.appendingPathComponent("snes"), withIntermediateDirectories: true)
        #expect(folder.exists("iCloud/Arcadia/Saves/retroarch/saves/snes"))
    }

    @Test func aFileWhereAFolderBelongsIsLeftAlone() throws {
        let folder = TemporaryFolder()
        let (engine, location) = setUp(folder)
        folder.write("Data/retroarch/saves", text: "not a folder")
        #expect(throws: SaveSyncEngine.Failure.self) { try engine.link(location) }
        #expect(folder.read("Data/retroarch/saves") == "not a folder")
        #expect(!folder.isLink("Data/retroarch/saves"))
    }

    @Test func foreignLinksAreReplacedWithoutTouchingTheirFolder() throws {
        let folder = TemporaryFolder()
        let (engine, location) = setUp(folder)
        folder.write("Elsewhere/Mario.srm", text: "mario")
        try FileManager.default.createDirectory(at: location.local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: location.local, withDestinationURL: folder.url.appendingPathComponent("Elsewhere"))
        try engine.link(location)
        #expect(engine.isLinked(location))
        #expect(folder.read("iCloud/Arcadia/Saves/retroarch/saves/Mario.srm") == "mario")
        #expect(folder.read("Elsewhere/Mario.srm") == "mario")
    }

    @Test func unlinkingCopiesSavesBackAndKeepsTheICloudCopy() throws {
        let folder = TemporaryFolder()
        let (engine, location) = setUp(folder)
        folder.write("Data/retroarch/saves/snes/Mario.srm", text: "mario")
        try engine.link(location)
        // Played some more while synced.
        try "mario, later".write(to: location.local.appendingPathComponent("snes/Mario.srm"), atomically: true, encoding: .utf8)
        try "states".write(to: location.local.appendingPathComponent("snes/Mario.state"), atomically: true, encoding: .utf8)

        try engine.unlink(location)
        #expect(!folder.isLink("Data/retroarch/saves"))
        #expect(folder.read("Data/retroarch/saves/snes/Mario.srm") == "mario, later")
        #expect(folder.read("Data/retroarch/saves/snes/Mario.state") == "states")
        #expect(folder.read("iCloud/Arcadia/Saves/retroarch/saves/snes/Mario.srm") == "mario, later")
        #expect(!folder.exists("Data/retroarch/.saves.arcadia-restoring"))
        // Unlinking a real folder does nothing.
        try engine.unlink(location)
        #expect(folder.read("Data/retroarch/saves/snes/Mario.srm") == "mario, later")
    }

    @Test func unlinkingWithoutICloudLeavesAnEmptyFolder() throws {
        let folder = TemporaryFolder()
        let (engine, location) = setUp(folder)
        try engine.link(location)
        try FileManager.default.removeItem(at: folder.url.appendingPathComponent("iCloud"))
        try engine.unlink(location)
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: location.local.path, isDirectory: &isFolder) && isFolder.boolValue)
        #expect(!folder.isLink("Data/retroarch/saves"))
    }

    @Test func unlinkingStopsAtUndownloadedFilesAndKeepsTheLink() throws {
        let folder = TemporaryFolder()
        let (engine, location) = setUp(folder)
        try engine.link(location)
        folder.write("iCloud/Arcadia/Saves/retroarch/saves/.Mario.srm.icloud", text: "")
        #expect(throws: SaveMerge.Failure.self) { try engine.unlink(location) }
        #expect(engine.isLinked(location))
        #expect(!folder.exists("Data/retroarch/.saves.arcadia-restoring"))
    }

    @Test func downloadWaitsForCloudOnlyFiles() async throws {
        let folder = TemporaryFolder()
        let cloud = FakeCloud(pending: ["Mario.srm", "Zelda.srm"], rounds: 3)
        let (engine, location) = setUp(folder, files: cloud)
        folder.write("iCloud/Arcadia/Saves/retroarch/saves/Mario.srm", text: "")
        folder.write("iCloud/Arcadia/Saves/retroarch/saves/Zelda.srm", text: "")
        folder.write("iCloud/Arcadia/Saves/retroarch/saves/Local.srm", text: "")
        let target = engine.cloudFolder(for: location)
        #expect(engine.pendingDownloads(in: [target]).count == 2)
        try await engine.download([target], timeout: .seconds(5), poll: .milliseconds(10))
        #expect(cloud.started == ["Mario.srm", "Zelda.srm"])
        #expect(engine.pendingDownloads(in: [target]).isEmpty)
    }

    @Test func downloadGivesUpAfterTheTimeout() async throws {
        let folder = TemporaryFolder()
        let cloud = FakeCloud(pending: ["Mario.srm"], rounds: 1_000_000)
        let (engine, location) = setUp(folder, files: cloud)
        folder.write("iCloud/Arcadia/Saves/retroarch/saves/Mario.srm", text: "")
        await #expect(throws: SaveSyncEngine.Failure.self) {
            try await engine.download([engine.cloudFolder(for: location)], timeout: .milliseconds(50), poll: .milliseconds(10))
        }
    }

    @Test func saveLocationsAreDistinctAndInsideArcadiasFolders() {
        let data = URL(fileURLWithPath: "/data")
        let support = URL(fileURLWithPath: "/support")
        let all = SaveLocation.all(data: { data.appendingPathComponent($0) }, applicationSupport: support)
        let cloud = all.map { "\($0.emulatorID)/\($0.cloudPath)" }
        #expect(Set(cloud).count == all.count)
        #expect(Set(all.map(\.local)).count == all.count)
        for location in all {
            #expect(location.local.path.hasPrefix("/data/\(location.emulatorID)/") || location.local.path.hasPrefix("/support/"))
        }
        #expect(!all.contains { $0.emulatorID == "xemu" })
    }
}

@MainActor
@Suite struct SaveSyncTests {
    private final class Fixture {
        let folder = TemporaryFolder()
        let defaults = MemoryDefaults()
        var iCloud: URL { folder.url.appendingPathComponent("iCloud Drive") }
        var locations: [SaveLocation] {
            [SaveLocation(emulatorID: "duckstation", local: folder.url.appendingPathComponent("Data/duckstation/memcards"),
                          cloudPath: "memcards"),
             SaveLocation(emulatorID: "ppsspp", local: folder.url.appendingPathComponent("Data/ppsspp/SAVEDATA"),
                          cloudPath: "SAVEDATA")]
        }
        @MainActor func sync() -> SaveSync {
            let locations = locations
            return SaveSync(root: iCloud, backupRoot: folder.url.appendingPathComponent("Backups"), defaults: defaults,
                            locations: { locations })
        }
    }

    @Test func staysOffWithoutICloudDrive() async {
        let fixture = Fixture()
        fixture.folder.write("Data/duckstation/memcards/Card.mcd", text: "card")
        let sync = fixture.sync()
        #expect(!sync.isAvailable)
        await sync.setEnabled(true)
        #expect(!sync.isEnabled)
        #expect(!fixture.folder.isLink("Data/duckstation/memcards"))
    }

    @Test func turningOnMovesSavesAndTurningOffCopiesThemBack() async throws {
        let fixture = Fixture()
        fixture.folder.folder("iCloud Drive")
        fixture.folder.write("Data/duckstation/memcards/Card.mcd", text: "card")
        let sync = fixture.sync()
        #expect(sync.isAvailable)

        await sync.setEnabled(true)
        #expect(sync.isEnabled)
        #expect(sync.lastError == nil)
        #expect(fixture.defaults.bool(forKey: "syncSavesWithICloud"))
        #expect(fixture.folder.isLink("Data/duckstation/memcards"))
        #expect(fixture.folder.read("iCloud Drive/Arcadia/Saves/duckstation/memcards/Card.mcd") == "card")
        // PPSSPP has not run yet, so it is linked at its first launch.
        #expect(!fixture.folder.exists("Data/ppsspp/SAVEDATA"))
        try await sync.prepare(emulatorID: "ppsspp", report: { _ in }, progress: { _ in })
        #expect(fixture.folder.isLink("Data/ppsspp/SAVEDATA"))

        await sync.setEnabled(false)
        #expect(!sync.isEnabled)
        #expect(!fixture.folder.isLink("Data/duckstation/memcards"))
        #expect(fixture.folder.read("Data/duckstation/memcards/Card.mcd") == "card")
        #expect(fixture.folder.read("iCloud Drive/Arcadia/Saves/duckstation/memcards/Card.mcd") == "card")
        #expect(!fixture.defaults.bool(forKey: "syncSavesWithICloud"))
        // Turned off, launches leave the folders alone.
        try await sync.prepare(emulatorID: "duckstation", report: { _ in }, progress: { _ in })
        #expect(!fixture.folder.isLink("Data/duckstation/memcards"))
    }

    @Test func launchesFailClearlyWhenICloudDriveGoesAway() async throws {
        let fixture = Fixture()
        fixture.folder.folder("iCloud Drive")
        let sync = fixture.sync()
        await sync.setEnabled(true)
        try FileManager.default.removeItem(at: fixture.iCloud)
        await #expect(throws: SaveSync.Failure.self) {
            try await sync.prepare(emulatorID: "duckstation", report: { _ in }, progress: { _ in })
        }
        // Turning sync off still works and leaves real folders behind.
        await sync.setEnabled(false)
        #expect(!sync.isEnabled)
    }
}
