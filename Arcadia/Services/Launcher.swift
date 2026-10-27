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
    private var process: Process?
    private var payload: URL?
    private var startedAt = Date.now

    var fullscreen = UserDefaults.standard.object(forKey: "fullscreen") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fullscreen, forKey: "fullscreen") }
    }

    var quality = GraphicsQuality(rawValue: UserDefaults.standard.string(forKey: "graphicsQuality") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "graphicsQuality") }
    }

    enum Failure: LocalizedError {
        case emulatorMissing(Emulator)
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .emulatorMissing(let emulator): String(localized: "\(emulator.name) is not installed yet.")
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

        preparing = game
        defer { preparing = nil; preparingStatus = nil }

        let target = game.system.gameIsFolder
            ? PlayStationFolder.bootFile(in: game.url, systemID: game.systemID)
            : game.url
        var request = LaunchRequest(game: target, fullscreen: fullscreen)
        if let core = player.core {
            request.core = try await emulators.core(core)
        }
        // Arcadia's tuned settings are written before every launch, so emulator menus never matter.
        let context = PresetContext(emulator: emulator, system: game.system, game: target, core: request.core,
                                    install: emulators.payloadURL(emulator.id)!, bios: library.biosFolder,
                                    scale: quality.scale, fullscreen: fullscreen) { [weak self] status in
            Task { @MainActor in self?.preparingStatus = status }
        }
        let preset = try await Presets.apply(context)
        let arguments = preset.arguments + emulator.arguments(request)

        let process = Process()
        if payload.pathExtension == "app" {
            // LaunchServices brings the app to the front and handles Rosetta; -W waits until it quits.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            let environment = preset.environment.sorted { $0.key < $1.key }.flatMap { ["--env", "\($0.key)=\($0.value)"] }
            process.arguments = ["-W", "-n"] + environment + ["-a", payload.path, "--args"] + arguments
        } else {
            process.executableURL = payload
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(preset.environment) { $1 }
            process.currentDirectoryURL = preset.workingDirectory ?? payload.deletingLastPathComponent()
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.finished(library: library) }
        }
        try process.run()
        self.process = process
        self.payload = payload
        startedAt = .now
        running = game
    }

    func stop() {
        guard running != nil, let payload else { return }
        // `open -W` does not forward signals, so quit the emulator by its path.
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-f", payload.path])
        process?.terminate()
    }

    private func finished(library: Library) {
        if let game = running { library.recordSession(game, started: startedAt) }
        running = nil
        process = nil
    }
}
