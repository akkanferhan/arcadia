import Foundation
import Observation

/// Starts games in their emulator and tracks the one that is running.
@MainActor
@Observable
final class Launcher {
    private(set) var running: Game?
    private(set) var preparing: Game?
    private var process: Process?
    private var payload: URL?
    private var startedAt = Date.now

    var fullscreen = UserDefaults.standard.object(forKey: "fullscreen") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fullscreen, forKey: "fullscreen") }
    }

    enum Failure: LocalizedError {
        case emulatorMissing(Emulator)
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .emulatorMissing(let emulator): "\(emulator.name) is not installed yet."
            case .alreadyRunning: "Another game is already running."
            }
        }
    }

    func launch(_ game: Game, emulators: EmulatorManager, library: Library) async throws {
        guard running == nil else { throw Failure.alreadyRunning }
        let emulator = Emulator.with(id: game.system.emulatorID)!
        guard let payload = emulators.payloadURL(emulator.id) else { throw Failure.emulatorMissing(emulator) }

        preparing = game
        defer { preparing = nil }

        let target = game.system.gameIsFolder
            ? PlayStationFolder.bootFile(in: game.url, systemID: game.systemID)
            : game.url
        var request = LaunchRequest(game: target, fullscreen: fullscreen)
        var arguments: [String]
        if let core = game.system.core {
            request.core = try await emulators.core(core)
            arguments = emulator.arguments(request)
            arguments.insert("--appendconfig=\(try retroArchConfig(bios: library.biosFolder).path)", at: 0)
        } else {
            arguments = emulator.arguments(request)
        }

        let process = Process()
        if payload.pathExtension == "app" {
            // LaunchServices brings the app to the front and handles Rosetta; -W waits until it quits.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-W", "-n", "-a", payload.path, "--args"] + arguments
        } else {
            process.executableURL = payload
            process.arguments = arguments
            process.currentDirectoryURL = payload.deletingLastPathComponent()
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

    /// Points RetroArch at the library's BIOS folder.
    private func retroArchConfig(bios: URL) throws -> URL {
        let url = Paths.support.appendingPathComponent("retroarch-arcadia.cfg")
        let config = """
        system_directory = "\(bios.path)"
        pause_nonactive = "false"
        """
        try config.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
