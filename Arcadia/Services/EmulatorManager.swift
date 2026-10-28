import Foundation
import Observation

/// An emulator that is on disk and ready to launch.
struct Installation: Codable, Equatable {
    let version: String
    /// Path of the `.app` bundle or executable, relative to the emulator's folder.
    let payload: String
    let installedAt: Date
    /// The exact download, when the source tells it apart from the version (see `AvailableVersion`).
    var revision: String? = nil
}

enum InstallStage: Equatable {
    case resolving, downloading, installing

    var title: LocalizedStringResource {
        switch self {
        case .resolving: "Finding latest version"
        case .downloading: "Downloading"
        case .installing: "Installing"
        }
    }
}

enum InstallState: Equatable {
    case notInstalled
    case working(stage: InstallStage, progress: Double?)
    case installed(Installation)
    case failed(String)

    var installation: Installation? {
        if case .installed(let installation) = self { return installation }
        return nil
    }

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}

/// Downloads, installs and removes emulators, and keeps their install state.
@MainActor
@Observable
final class EmulatorManager {
    private(set) var states: [String: InstallState] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Newest versions found by the last update check, by emulator id.
    private(set) var latest: [String: AvailableVersion] = [:]
    private(set) var isCheckingForUpdates = false
    private(set) var lastUpdateCheck: Date?
    private var updateLoop: Task<Void, Never>?
    /// Whether a background update may start now; AppModel says no while a game is running.
    var mayUpdateInBackground: () -> Bool = { true }

    // `bool(forKey:)` also reads `-updateEmulatorsAutomatically NO` launch arguments.
    var updatesAutomatically = UserDefaults.standard.object(forKey: "updateEmulatorsAutomatically") == nil
        || UserDefaults.standard.bool(forKey: "updateEmulatorsAutomatically") {
        didSet {
            UserDefaults.standard.set(updatesAutomatically, forKey: "updateEmulatorsAutomatically")
            installUpdatesInBackground()
        }
    }

    init() {
        for emulator in Emulator.all {
            states[emulator.id] = Self.readInstallation(emulator.id).map(InstallState.installed) ?? .notInstalled
        }
        lastUpdateCheck = UserDefaults.standard.object(forKey: "emulatorUpdatesCheckedAt") as? Date
        if let data = UserDefaults.standard.data(forKey: "emulatorUpdates"),
           let saved = try? JSONDecoder().decode([String: AvailableVersion].self, from: data) {
            latest = saved
        }
    }

    func state(_ id: String) -> InstallState { states[id] ?? .notInstalled }

    func isInstalled(_ id: String) -> Bool { state(id).installation != nil }

    /// The `.app` bundle or executable that starts the emulator.
    func payloadURL(_ id: String) -> URL? {
        guard let installation = state(id).installation else { return nil }
        return Paths.emulator(id).appendingPathComponent(installation.payload)
    }

    /// A `quiet` install (a background update) that fails leaves the working version in place.
    func install(_ emulator: Emulator, quiet: Bool = false) {
        guard !state(emulator.id).isWorking else { return }
        states[emulator.id] = .working(stage: .resolving, progress: nil)
        tasks[emulator.id] = Task {
            do {
                let installation = try await performInstall(emulator)
                states[emulator.id] = .installed(installation)
                setLatest(AvailableVersion(version: installation.version, revision: installation.revision), for: emulator.id)
            } catch is CancellationError {
                states[emulator.id] = Self.readInstallation(emulator.id).map(InstallState.installed) ?? .notInstalled
            } catch {
                let previous = quiet ? Self.readInstallation(emulator.id) : nil
                states[emulator.id] = previous.map(InstallState.installed) ?? .failed(error.localizedDescription)
            }
            tasks[emulator.id] = nil
        }
    }

    func cancel(_ id: String) { tasks[id]?.cancel() }

    func uninstall(_ id: String) {
        try? FileManager.default.removeItem(at: Paths.emulator(id))
        states[id] = .notInstalled
    }

    // MARK: Installing

    private struct Release {
        let url: URL
        let version: String
        var revision: String?
    }

    private func performInstall(_ emulator: Emulator) async throws -> Installation {
        let id = emulator.id
        states[id] = .working(stage: .resolving, progress: nil)
        let release = try await resolve(emulator)

        states[id] = .working(stage: .downloading, progress: 0)
        let archive = Paths.downloads.appendingPathComponent(release.url.lastPathComponent)
        defer { try? FileManager.default.removeItem(at: archive) }
        _ = try await Downloader.download(release.url, to: archive) { value in
            Task { @MainActor in
                guard case .working(let stage, _) = self.states[id], stage == .downloading else { return }
                self.states[id] = .working(stage: .downloading, progress: value)
            }
        }
        try Task.checkCancellation()

        states[id] = .working(stage: .installing, progress: nil)
        let staging = Paths.downloads.appendingPathComponent("\(id)-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try await Archive.extract(archive, into: staging)
        guard let payload = try await Archive.findPayload(in: staging, named: emulator.name) else {
            throw InstallError.noAppInArchive
        }
        let relative = String(payload.path.dropFirst(staging.path.count + 1))

        // Keep RetroArch cores and portable save data (SharpEmu's `user`) across updates.
        let target = Paths.emulator(id)
        for folder in ["cores", "user"] {
            let old = target.appendingPathComponent(folder)
            if FileManager.default.fileExists(atPath: old.path) {
                try? FileManager.default.moveItem(at: old, to: staging.appendingPathComponent(folder))
            }
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: staging, to: target)
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])

        let installation = Installation(version: release.version, payload: relative, installedAt: .now,
                                        revision: release.revision)
        let data = try JSONEncoder().encode(installation)
        try data.write(to: target.appendingPathComponent("arcadia.json"))
        return installation
    }

    private func resolve(_ emulator: Emulator) async throws -> Release {
        var lastError: Error = InstallError.noDownload
        for source in emulator.sources {
            do {
                switch source {
                case let .github(repo, asset, includePrereleases):
                    return try await Self.githubRelease(repo: repo, asset: asset, includePrereleases: includePrereleases)
                case .retroarch:
                    return try await Self.retroarchRelease()
                case .dolphin:
                    return try await Self.dolphinRelease()
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func githubRelease(repo: String, asset pattern: String, includePrereleases: Bool) async throws -> Release {
        struct GitHubRelease: Decodable {
            struct Asset: Decodable {
                let id: Int
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let assets: [Asset]
        }
        let path = includePrereleases ? "releases?per_page=10" : "releases/latest"
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/\(path)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError.noDownload }
        let releases = includePrereleases
            ? try JSONDecoder().decode([GitHubRelease].self, from: data)
            : [try JSONDecoder().decode(GitHubRelease.self, from: data)]
        let regex = try Regex(pattern)
        for release in releases {
            if let asset = release.assets.first(where: { $0.name.contains(regex) }) {
                return Release(url: asset.browser_download_url, version: release.tag_name, revision: String(asset.id))
            }
        }
        throw InstallError.noDownload
    }

    private static func retroarchRelease() async throws -> Release {
        let base = "https://buildbot.libretro.com/stable/"
        let (data, _) = try await URLSession.shared.data(from: URL(string: base)!)
        let html = String(decoding: data, as: UTF8.self)
        let versions = html.matches(of: #/(\d+)\.(\d+)\.(\d+)\//#).map {
            (Int($0.1)!, Int($0.2)!, Int($0.3)!)
        }
        guard let newest = versions.max(by: { $0 < $1 }) else { throw InstallError.noDownload }
        let version = "\(newest.0).\(newest.1).\(newest.2)"
        return Release(url: URL(string: "\(base)\(version)/apple/osx/universal/RetroArch_Metal.dmg")!, version: version)
    }

    private static func dolphinRelease() async throws -> Release {
        struct Update: Decodable {
            struct Artifact: Decodable {
                let system: String
                let url: URL
            }
            let shortrev: String
            let hash: String?
            let artifacts: [Artifact]
        }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://dolphin-emu.org/update/latest/beta")!)
        let update = try JSONDecoder().decode(Update.self, from: data)
        guard let mac = update.artifacts.first(where: { $0.system.hasPrefix("macOS") }) else {
            throw InstallError.noDownload
        }
        return Release(url: mac.url, version: update.shortrev, revision: update.hash)
    }

    private static func readInstallation(_ id: String) -> Installation? {
        let folder = Paths.emulator(id)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("arcadia.json")),
              let installation = try? JSONDecoder().decode(Installation.self, from: data),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent(installation.payload).path)
        else { return nil }
        return installation
    }

    // MARK: Updates

    /// Whether a newer version than the installed one is available.
    func hasUpdate(_ id: String) -> Bool {
        guard let installation = state(id).installation, let available = latest[id] else { return false }
        return EmulatorUpdates.isNewer(available, than: installation)
    }

    var updateCount: Int { Emulator.all.filter { hasUpdate($0.id) }.count }

    /// Checks once now, then about once a day for as long as Arcadia runs.
    func startUpdateChecks() {
        guard updateLoop == nil else { return }
        updateLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdates()
                self?.installUpdatesInBackground()
                // Hourly wake-ups also catch updates that waited for a game to end.
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    /// Looks up the newest version of every installed emulator. Without `force`, does nothing
    /// when the last check was less than a day ago.
    func checkForUpdates(force: Bool = false) async {
        guard !isCheckingForUpdates, force || EmulatorUpdates.isCheckDue(lastCheck: lastUpdateCheck) else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        var reached = false
        for emulator in Emulator.all where isInstalled(emulator.id) && !state(emulator.id).isWorking {
            guard let release = try? await resolve(emulator) else { continue }
            reached = true
            setLatest(AvailableVersion(version: release.version, revision: release.revision), for: emulator.id)
        }
        // Offline: try again at the next wake-up instead of waiting a day.
        guard reached else { return }
        lastUpdateCheck = .now
        UserDefaults.standard.set(lastUpdateCheck, forKey: "emulatorUpdatesCheckedAt")
    }

    /// Installs every available update.
    func installUpdates(quiet: Bool = false) {
        for emulator in Emulator.all where hasUpdate(emulator.id) { install(emulator, quiet: quiet) }
    }

    /// Installs available updates when automatic updates are on and no game is running.
    func installUpdatesInBackground() {
        guard updatesAutomatically, mayUpdateInBackground() else { return }
        installUpdates(quiet: true)
    }

    private func setLatest(_ available: AvailableVersion, for id: String) {
        latest[id] = available
        if let data = try? JSONEncoder().encode(latest) {
            UserDefaults.standard.set(data, forKey: "emulatorUpdates")
        }
    }

    // MARK: RetroArch cores

    /// Downloads a libretro core the first time a system needs it.
    func core(_ name: String) async throws -> URL {
        let folder = Paths.emulator("retroarch").appendingPathComponent("cores", isDirectory: true)
        let core = folder.appendingPathComponent("\(name)_libretro.dylib")
        if FileManager.default.fileExists(atPath: core.path) { return core }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = URL(string: "https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/\(name)_libretro.dylib.zip")!
        let zip = Paths.downloads.appendingPathComponent(url.lastPathComponent)
        defer { try? FileManager.default.removeItem(at: zip) }
        _ = try await Downloader.download(url, to: zip) { _ in }
        try await Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        guard FileManager.default.fileExists(atPath: core.path) else { throw InstallError.noDownload }
        return core
    }
}

enum InstallError: LocalizedError {
    case noDownload
    case noAppInArchive

    var errorDescription: String? {
        switch self {
        case .noDownload: String(localized: "No macOS download was found. Check your connection and try again.")
        case .noAppInArchive: String(localized: "The download did not contain a Mac app.")
        }
    }
}
