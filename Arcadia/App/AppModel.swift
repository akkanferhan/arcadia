import SwiftUI
import Observation

enum SidebarItem: Hashable {
    case home
    case favorites
    case system(String)
    case emulators
}

/// Shared app state: the library, emulators, the running game and navigation.
@MainActor
@Observable
final class AppModel {
    let library = Library()
    let emulators = EmulatorManager()
    let launcher = Launcher()

    var selection: SidebarItem? = .home
    var search = ""
    var showOnboarding: Bool
    var problem: Problem?

    struct Problem: Identifiable {
        let id = UUID()
        let message: String
        var missing: Emulator?
    }

    init() {
        showOnboarding = !library.hasFolder
        // `-page snes`, `-page emulators` etc. opens a page directly (handy for development).
        switch UserDefaults.standard.string(forKey: "page") {
        case nil: break
        case "favorites": selection = .favorites
        case "emulators": selection = .emulators
        case let id?: selection = GameSystem.with(id: id).map { .system($0.id) } ?? .home
        }
        Task { await library.scan() }
    }

    func play(_ game: Game) {
        Task {
            do {
                try await launcher.launch(game, emulators: emulators, library: library)
            } catch Launcher.Failure.emulatorMissing(let emulator) {
                problem = Problem(message: String(localized: "\(emulator.name) plays \(game.system.name) games. Install it now? It's free and takes about a minute."),
                                  missing: emulator)
            } catch {
                problem = Problem(message: error.localizedDescription)
            }
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
