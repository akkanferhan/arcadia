import AppKit
import Observation

/// A choice in a TV Mode menu.
enum TVMenuAction: Equatable {
    case play(Game)
    case toggleFavorite(Game)
    case search
    case exitTVMode
    case installEmulator(id: String)
    case installRosetta(Game?)
    case close
}

/// Runs TV Mode: routes controller and keyboard input to the navigator and carries out its effects.
@MainActor
@Observable
final class TVModeController {
    var navigator = TVNavigator()
    /// The options for a game or a problem to confirm; it takes all input while shown.
    var menu: TVMenu<TVMenuAction>?
    /// Counts presses that went nowhere, so the focused item can shake.
    private(set) var bumps = 0
    let gamepads = TVGamepadInput()

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored weak var window: NSWindow?
    /// Closes TV Mode; set by the window.
    @ObservationIgnored var onExit: () -> Void = {}

    func start(model: AppModel) {
        self.model = model
        gamepads.onCommand = { [weak self] command in self?.handle(command, fromKeyboard: false) }
        gamepads.start()
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return event }
            let window = event.window.map(ObjectIdentifier.init)
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let own = self.window, window == ObjectIdentifier(own),
                      let command = TVKeyMap.command(keyCode: keyCode, characters: characters,
                                                     searching: self.navigator.isSearching && self.menu == nil)
                else { return false }
                self.handle(command, fromKeyboard: true)
                return true
            }
            return handled ? nil : event
        }
    }

    func stop() {
        gamepads.stop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Takes the library's current shelves.
    func update(_ shelves: [TVShelf]) {
        navigator.focus.update(shelves)
    }

    func handle(_ command: TVCommand, fromKeyboard: Bool) {
        guard let model else { return }
        // While a game runs the controller belongs to the emulator.
        if model.launcher.running != nil || model.launcher.preparing != nil { return }

        if var menu {
            switch command {
            case .move(let direction):
                if !menu.move(direction) { bumps += 1 }
                self.menu = menu
            case .select:
                if let action = menu.action { perform(action) }
            case .back, .options:
                close()
            default:
                break
            }
            return
        }

        switch navigator.handle(command) {
        case .none: break
        case .bump: bumps += 1
        case .play(let game): model.play(game)
        case .toggleFavorite(let game): model.library.toggleFavorite(game)
        case .options(let game): showOptions(for: game)
        case .exit: onExit()
        }
    }

    func showOptions(for game: Game?) {
        var actions: [TVMenuAction] = []
        if let game {
            actions.append(.play(game))
            actions.append(.toggleFavorite(game))
        }
        actions += [.search, .exitTVMode]
        menu = TVMenu(title: game?.title ?? String(localized: "TV Mode"),
                      message: game.map { $0.system.name }, actions: actions)
    }

    /// Shows the problem from the last launch as a TV menu.
    func showProblem(_ problem: AppModel.Problem) {
        var actions: [TVMenuAction] = []
        if let emulator = problem.missing {
            actions.append(.installEmulator(id: emulator.id))
        } else if problem.needsRosetta {
            actions.append(.installRosetta(problem.game))
        }
        actions.append(.close)
        let title = problem.missing != nil ? String(localized: "Almost ready")
            : problem.needsRosetta ? String(localized: "Rosetta needed")
            : String(localized: "Couldn't start the game")
        menu = TVMenu(title: title, message: problem.message, actions: actions)
    }

    func perform(_ action: TVMenuAction) {
        guard let model else { return }
        close()
        switch action {
        case .play(let game): model.play(game)
        case .toggleFavorite(let game): model.library.toggleFavorite(game)
        case .search: _ = navigator.handle(.search)
        case .exitTVMode: onExit()
        case .installEmulator(let id): if let emulator = Emulator.with(id: id) { model.emulators.install(emulator) }
        case .installRosetta(let game): model.installRosetta(then: game)
        case .close: break
        }
    }

    func close() {
        menu = nil
        model?.problem = nil
    }

    /// Brings TV Mode back to the front after the emulator quits.
    func returnToFront() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
