import Foundation
import Observation

/// Starts games in their emulator and tracks the one that is running.
@MainActor
@Observable
final class Launcher {
    private(set) var running: Game?
    private(set) var preparing: Game?
    /// What Arcadia is doing before the game starts, such as downloading firmware.
    private(set) var preparingStatus: LocalizedStringResource?
    /// Progress of a long download before the game starts, from 0 to 1.
    private(set) var preparingProgress: Double?
    /// Called when an emulator quits on its own within seconds of starting.
    var onUnexpectedExit: (Game) -> Void = { _ in }
    /// The output of the most recent launch, in ~/Library/Logs/Arcadia.
    private(set) var lastLog: URL?
    private var process: Process?
    private var payload: URL?
    private var startedAt = Date.now
    private var stoppedByPlayer = false

    /// A session shorter than this that the player did not end means the emulator gave up.
    private static let crashThreshold: TimeInterval = 8

    var fullscreen = UserDefaults.standard.object(forKey: "fullscreen") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fullscreen, forKey: "fullscreen") }
    }

    var quality = GraphicsQuality(rawValue: UserDefaults.standard.string(forKey: "graphicsQuality") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "graphicsQuality") }
    }

    enum Failure: LocalizedError {
        case emulatorMissing(Emulator)
        case rosettaMissing(Emulator)
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .emulatorMissing(let emulator): String(localized: "\(emulator.name) is not installed yet.")
            case .rosettaMissing(let emulator):
                String(localized: "\(emulator.name) is only made for Intel Macs, so it needs Rosetta, Apple's free translator. Install it now?")
            case .alreadyRunning: String(localized: "Another game is already running.")
            }
        }
    }

    func launch(_ game: Game, emulators: EmulatorManager, library: Library) async throws {
        guard running == nil else { throw Failure.alreadyRunning }
        // Without a real BIOS some systems play through a core with a built-in one.
        let player = Bios.player(for: game.system, bios: library.biosFolder)
        let emulator = player.emulator
        guard let payload = emulators.payloadURL(emulator.id) else { throw Failure.emulatorMissing(emulator) }
        if emulator.needsRosetta, !Rosetta.isInstalled { throw Failure.rosettaMissing(emulator) }

        preparing = game
        defer { preparing = nil; preparingStatus = nil; preparingProgress = nil }

        let target = game.system.gameIsFolder
            ? PlayStationFolder.bootFile(in: game.url, systemID: game.systemID)
            : game.url
        var request = LaunchRequest(game: target, fullscreen: fullscreen)
        if let core = player.core {
            request.core = try await emulators.core(core)
        }
        // Arcadia's tuned settings are written before every launch, so emulator menus never matter.
        let gamepads = await Gamepads.connected()
        var context = PresetContext(emulator: emulator, system: game.system, game: target, core: request.core,
                                    install: emulators.payloadURL(emulator.id)!, bios: library.biosFolder,
                                    scale: quality.scale, fullscreen: fullscreen, gamepads: gamepads,
                                    report: { [weak self] status in
                                        Task { @MainActor in
                                            self?.preparingStatus = status
                                            self?.preparingProgress = nil
                                        }
                                    },
                                    progress: { [weak self] value in
                                        Task { @MainActor in self?.preparingProgress = value }
                                    })
        context.achievements = RetroAchievements.shared.settings
        // With iCloud sync on, saves must be linked and downloaded before the emulator reads them.
        try await SaveSync.shared.prepare(emulatorID: emulator.id, report: context.report, progress: context.progress)
        let preset = try await Presets.apply(context)
        let arguments = preset.arguments + emulator.arguments(request)

        // Everything the emulator prints goes to a log, shown when a game fails to start.
        let log = LaunchLogs.create(emulator: emulator.id, command: [payload.path] + arguments)
        let process = Process()
        if payload.pathExtension == "app" {
            // LaunchServices brings the app to the front and handles Rosetta; -W waits until it quits.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            let environment = preset.environment.sorted { $0.key < $1.key }.flatMap { ["--env", "\($0.key)=\($0.value)"] }
            process.arguments = ["-W", "-n"] + LaunchLogs.openArguments(log) + environment
                + ["-a", payload.path, "--args"] + arguments
        } else {
            process.executableURL = payload
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(preset.environment) { $1 }
            process.currentDirectoryURL = preset.workingDirectory ?? payload.deletingLastPathComponent()
        }
        // Bare executables write straight into the log; for apps this catches `open`'s own errors.
        if let log, let handle = LaunchLogs.appendingHandle(log) {
            process.standardOutput = handle
            process.standardError = handle
        }
        lastLog = log
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.finished(library: library) }
        }
        try process.run()
        self.process = process
        self.payload = payload
        startedAt = .now
        stoppedByPlayer = false
        running = game
    }

    func stop() {
        guard running != nil, let payload else { return }
        stoppedByPlayer = true
        // `open -W` does not forward signals, so quit the emulator by its path.
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-f", payload.path])
        process?.terminate()
    }

    private func finished(library: Library) {
        guard let game = running else { return }
        let duration = Date.now.timeIntervalSince(startedAt)
        running = nil
        process = nil
        if duration < Self.crashThreshold, !stoppedByPlayer {
            onUnexpectedExit(game)
        } else {
            library.recordSession(game, started: startedAt)
        }
    }
}

/// Apple's translator for Intel apps. Only emulators without an Apple silicon build need it.
enum Rosetta {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
    }

    /// Installs Rosetta; macOS asks for an administrator password.
    static func install() async -> Bool {
        await Task.detached {
            let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
    }
}
