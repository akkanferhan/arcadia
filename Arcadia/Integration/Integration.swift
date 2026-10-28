import AppIntents
import CoreSpotlight
import SwiftUI

/// Connects Arcadia to Spotlight, Shortcuts, Siri and the widget.
@MainActor
final class Integration {
    private static var current: Integration?

    private let model: AppModel
    private var pending: Task<Void, Never>?
    private var gameIDs: [String] = []

    private init(model: AppModel) {
        self.model = model
    }

    /// Call once at launch.
    static func start(_ model: AppModel) {
        AppDependencyManager.shared.add(dependency: model)
        // Unit tests run inside the app; keep them away from the real Spotlight index and widget.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let integration = Integration(model: model)
        current = integration
        integration.observe()
    }

    /// Syncs whenever a scan finishes or a session is recorded.
    private func observe() {
        let library = model.library
        withObservationTracking {
            _ = library.games
            _ = library.records
            _ = library.isScanning
        } onChange: { [weak self] in
            Task { @MainActor in self?.changed() }
        }
    }

    private func changed() {
        observe()
        guard !model.library.isScanning else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            // Several changes often arrive together; sync once they settle.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    private func sync() async {
        let library = model.library
        let games = library.games
        let ids = games.map(\.id)
        if ids != gameIDs {
            gameIDs = ids
            ArcadiaShortcuts.updateAppShortcutParameters()
        }
        await Spotlight.sync(games)
        await WidgetPublisher.publish(library)
    }
}

// MARK: - Opening games from outside

extension AppModel {
    /// The game with this id, waiting for the library when Arcadia was just launched.
    func game(withID id: String) async -> Game? {
        if let game = library.games.first(where: { $0.id == id }) { return game }
        await library.scan()
        return library.games.first { $0.id == id }
    }

    /// The most recently played game, waiting for the library when Arcadia was just launched.
    func lastPlayedGame() async -> Game? {
        if library.games.isEmpty { await library.scan() }
        return library.recentlyPlayed.first
    }

    /// Brings Arcadia forward with the game on screen.
    /// Brings Arcadia forward on the game's console page, optionally with its details open.
    func reveal(_ game: Game, showingDetails: Bool = false) {
        NSApp.activate()
        search = ""
        selection = .system(game.systemID)
        if showingDetails { details = game }
    }

    func open(_ link: ArcadiaLink) {
        Task {
            switch link {
            case .play(let id):
                let found = if let id { await game(withID: id) } else { await lastPlayedGame() }
                guard let game = found else { return }
                reveal(game)
                play(game)
            case .open(let id):
                NSApp.activate()
                if let id, let game = await game(withID: id) { reveal(game, showingDetails: true) }
            }
        }
    }
}

extension View {
    /// Handles `arcadia://` links and Spotlight results in this window.
    func handlesArcadiaLinks(_ model: AppModel) -> some View {
        onOpenURL { url in
            if let link = ArcadiaLink(url: url) { model.open(link) }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                model.open(.play(game: id))
            }
        }
        // Reuse the open window instead of opening a new one for every link.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }
}
