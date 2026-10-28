import Foundation
import Observation

/// The iCloud Drive folder of the signed-in account.
enum ICloudDrive {
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

    /// iCloud Drive is usable when its folder exists and can be written to. Signing out of
    /// iCloud or turning iCloud Drive off removes the folder.
    static func isAvailable(root: URL = defaultRoot) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &folder) && folder.boolValue
            && FileManager.default.isWritableFile(atPath: root.path)
    }
}

/// Keeps every emulator's saves in iCloud Drive (`Arcadia/Saves/<emulator>/…`) when the player
/// turns it on. Save folders become links into iCloud Drive, so presets keep their paths.
@MainActor
@Observable
final class SaveSync {
    static let shared = SaveSync()

    private let root: URL
    private let defaults: UserDefaults
    private let locations: () -> [SaveLocation]
    private let files: any UbiquitousFiles
    private static let key = "syncSavesWithICloud"

    private(set) var isEnabled: Bool
    private(set) var isAvailable: Bool
    /// Moving saves in or out of iCloud Drive.
    private(set) var isWorking = false
    private(set) var lastError: String?
    /// Saves that differed on both sides during the last move; the older versions were backed up.
    private(set) var lastConflicts = 0

    let backupRoot: URL
    var engine: SaveSyncEngine {
        SaveSyncEngine(cloudRoot: root.appendingPathComponent("Arcadia/Saves", isDirectory: true),
                       backupRoot: backupRoot, files: files)
    }

    init(root: URL = ICloudDrive.defaultRoot,
         backupRoot: URL = Paths.support.appendingPathComponent("Save Backups", isDirectory: true),
         defaults: UserDefaults = .standard,
         files: any UbiquitousFiles = SystemUbiquitousFiles(),
         locations: @escaping () -> [SaveLocation] = { SaveLocation.all() }) {
        self.root = root
        self.backupRoot = backupRoot
        self.defaults = defaults
        self.files = files
        self.locations = locations
        isEnabled = defaults.bool(forKey: Self.key)
        isAvailable = ICloudDrive.isAvailable(root: root)
    }

    func refreshAvailability() {
        isAvailable = ICloudDrive.isAvailable(root: root)
    }

    enum Failure: LocalizedError {
        case unavailable, busy
        var errorDescription: String? {
            switch self {
            case .unavailable:
                String(localized: "Your saves are kept in iCloud Drive, which isn't available right now. Sign in to iCloud and turn on iCloud Drive, or turn off save sync in Arcadia's settings.")
            case .busy:
                String(localized: "Arcadia is still moving your saves. Try again when it's done.")
            }
        }
    }

    /// Turns sync on (moves local saves into iCloud Drive) or off (copies them back).
    /// The setting only changes when every folder moved.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled, !isWorking else { return }
        refreshAvailability()
        if enabled, !isAvailable { return }
        isWorking = true
        lastError = nil
        lastConflicts = 0
        defer { isWorking = false }

        let engine = engine
        let all = locations()
        let date = Date.now
        do {
            let conflicts = try await Task.detached { () async throws -> Int in
                var conflicts = 0
                if enabled {
                    // Folders that do not exist yet are linked at their emulator's first launch.
                    for location in all where FileManager.default.fileExists(atPath: location.local.path) {
                        conflicts += try engine.link(location, date: date).conflicts.count
                    }
                } else {
                    for location in all where engine.isLinked(location) {
                        try await engine.download([engine.cloudFolder(for: location)], timeout: .seconds(120))
                        conflicts += try engine.unlink(location, date: date).conflicts.count
                    }
                }
                return conflicts
            }.value
            lastConflicts = conflicts
            isEnabled = enabled
            defaults.set(enabled, forKey: Self.key)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Before a launch: links the emulator's save folders and waits for cloud-only saves to download.
    func prepare(emulatorID: String, report: @Sendable (LocalizedStringResource) -> Void,
                 progress: @escaping @Sendable (Double) -> Void) async throws {
        guard isEnabled else { return }
        guard !isWorking else { throw Failure.busy }
        refreshAvailability()
        guard isAvailable else { throw Failure.unavailable }
        let engine = engine
        let ours = locations().filter { $0.emulatorID == emulatorID }
        guard !ours.isEmpty else { return }
        let date = Date.now
        let conflicts = try await Task.detached {
            try ours.reduce(0) { $0 + (try engine.link($1, date: date).conflicts.count) }
        }.value
        if conflicts > 0 { lastConflicts = conflicts }
        let folders = ours.map(engine.cloudFolder(for:))
        if !engine.pendingDownloads(in: folders).isEmpty {
            report("Downloading your saves from iCloud Drive…")
            try await engine.download(folders, progress: progress)
        }
    }
}
