import SwiftUI
import Observation

enum SidebarItem: Hashable {
    case home
    case favorites
    case system(String)
    case collection(UUID)
    case emulators
}

/// Shared app state: the library, emulators, the running game and navigation.
@MainActor
@Observable
final class AppModel {
    let library = Library()
    let emulators = EmulatorManager()
    let launcher = Launcher()
    let finder = GameFinder()
    let compressor = DiscCompressor()
    let metadata = Metadata()
    let collections = Collections()

    var selection: SidebarItem? = .home
    var search = ""
    var showOnboarding: Bool
    var showFinder = false
    var showSaveSpace = false
    /// The game whose details sheet is open.
    var details: Game?
    var problem: Problem?
    /// True while the TV Mode window is open; it shows problems itself then.
    var isTVModeActive = false
    /// The launch log shown in a sheet.
    var shownLog: LaunchLog?

    struct Problem: Identifiable {
        let id = UUID()
        let message: String
        var missing: Emulator?
        var needsRosetta = false
        var game: Game?
        /// The emulator's output, for a game that closed right after starting.
        var log: URL?
    }

    init() {
        showOnboarding = !library.hasFolder
        launcher.onUnexpectedExit = { [weak self] game in
            let bios = BiosRule.rule(for: game.systemID) != nil
            self?.problem = Problem(message: bios
                ? String(localized: "\(game.title) closed right after starting. Check that the game file is complete and that the console's BIOS is in place.")
                : String(localized: "\(game.title) closed right after starting. Check that the game file is complete and not damaged."),
                log: self?.launcher.lastLog)
        }
        // Emulator updates wait until no game is running or starting.
        emulators.mayUpdateInBackground = { [launcher] in launcher.running == nil && launcher.preparing == nil }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            emulators.startUpdateChecks()
        }
        // `-page snes`, `-page emulators` etc. opens a page directly (handy for development).
        switch UserDefaults.standard.string(forKey: "page") {
        case nil: break
        case "favorites": selection = .favorites
        case "emulators": selection = .emulators
        case let id?: selection = GameSystem.with(id: id).map { .system($0.id) } ?? .home
        }
        // `-saveSpace YES` opens Save Disk Space right away (handy for development).
        showSaveSpace = UserDefaults.standard.bool(forKey: "saveSpace")
        // `-failedLaunchLog <file>` shows the failed-start alert for a log (handy for development).
        if let path = UserDefaults.standard.string(forKey: "failedLaunchLog") {
            let log = URL(fileURLWithPath: path)
            problem = Problem(message: String(localized: "\(log.lastPathComponent) closed right after starting. Check that the game file is complete and not damaged."),
                              log: log)
        }
        // `-findGamesIn <folder>` searches only that folder right away (handy for development).
        if let folder = UserDefaults.standard.string(forKey: "findGamesIn") {
            let url = URL(fileURLWithPath: folder)
            showFinder = true
            Task { [finder, library] in
                await library.scan()
                finder.start(in: [url], library: library)
            }
        } else {
            Task { await library.scan() }
        }
    }

    func play(_ game: Game) {
        Task {
            do {
                try await launcher.launch(game, emulators: emulators, library: library)
            } catch Launcher.Failure.emulatorMissing(let emulator) {
                problem = Problem(message: String(localized: "\(emulator.name) plays \(game.system.name) games. Install it now? It's free and takes about a minute."),
                                  missing: emulator)
            } catch let failure as Launcher.Failure {
                if case .rosettaMissing = failure {
                    problem = Problem(message: failure.localizedDescription, needsRosetta: true, game: game)
                } else {
                    problem = Problem(message: failure.localizedDescription)
                }
            } catch {
                problem = Problem(message: error.localizedDescription)
            }
        }
    }

    /// Installs Rosetta, then starts the game that needed it.
    func installRosetta(then game: Game?) {
        Task {
            guard await Rosetta.install() else { return }
            if let game { play(game) }
        }
    }

    /// Copies dropped game files into a system's folder.
    func importGames(_ urls: [URL], into system: GameSystem) {
        let folder = library.folder(for: system)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task {
            await Task.detached {
                for url in urls {
                    let target = folder.appendingPathComponent(url.lastPathComponent)
                    guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                    try? FileManager.default.copyItem(at: url, to: target)
                }
            }.value
            await library.scan()
        }
    }

    /// Copies dropped BIOS files into place. Returns the names it did not recognise.
    func importBios(_ urls: [URL]) -> [String] {
        var unknown: [String] = []
        for url in urls {
            guard let target = Bios.destination(for: url, bios: library.biosFolder) else {
                unknown.append(url.lastPathComponent)
                continue
            }
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: url, to: target)
        }
        return unknown
    }

    /// Installs the emulator for every system that has games.
    func installNeededEmulators() {
        let ids = Set(library.stockedSystems.map { Bios.player(for: $0, bios: library.biosFolder).emulator.id })
        for emulator in Emulator.all where ids.contains(emulator.id) && !emulators.isInstalled(emulator.id) {
            emulators.install(emulator)
        }
    }
}
