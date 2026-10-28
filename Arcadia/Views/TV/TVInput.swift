import AppKit
import GameController
import Observation

/// Reads every connected controller through the GameController framework and turns its
/// buttons into TV Mode commands. Directions repeat while they are held.
@MainActor
@Observable
final class TVGamepadInput {
    private(set) var isConnected = false
    /// Called for every command; set by TV Mode.
    @ObservationIgnored var onCommand: (TVCommand) -> Void = { _ in }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var held: TVDirection?
    @ObservationIgnored private var repeatTask: Task<Void, Never>?

    /// Wait before a held direction starts repeating, then the time between steps.
    static let repeatDelay: Duration = .milliseconds(420)
    static let repeatInterval: Duration = .milliseconds(110)

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        for controller in GCController.controllers() { detach(controller) }
        setHeld(nil)
    }

    private func refresh() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        pads.forEach(attach)
        isConnected = !pads.isEmpty
        if pads.isEmpty { setHeld(nil) }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main
        let buttons: [(GCControllerButtonInput?, TVCommand)] = [
            (pad.buttonA, .select), (pad.buttonB, .back), (pad.buttonX, .favorite),
            (pad.buttonY, .search), (pad.buttonMenu, .options), (pad.buttonOptions, .options),
        ]
        for (button, command) in buttons {
            button?.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { self?.send(command) }
            }
        }
        let moved: GCControllerDirectionPadValueChangedHandler = { [weak self, weak pad] _, _, _ in
            MainActor.assumeIsolated {
                guard let pad else { return }
                self?.directionChanged(pad)
            }
        }
        pad.dpad.valueChangedHandler = moved
        pad.leftThumbstick.valueChangedHandler = moved
    }

    private func detach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        for button in [pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY, pad.buttonMenu, pad.buttonOptions] {
            button?.pressedChangedHandler = nil
        }
        pad.dpad.valueChangedHandler = nil
        pad.leftThumbstick.valueChangedHandler = nil
    }

    private func directionChanged(_ pad: GCExtendedGamepad) {
        // The D-pad wins over the stick when both are used.
        let dpad = TVDirection.resolve(x: pad.dpad.xAxis.value, y: pad.dpad.yAxis.value,
                                       held: held, press: 0.5, release: 0.5)
        let stick = TVDirection.resolve(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value, held: held)
        setHeld(dpad ?? stick)
    }

    private func setHeld(_ direction: TVDirection?) {
        guard direction != held else { return }
        held = direction
        repeatTask?.cancel()
        repeatTask = nil
        guard let direction else { return }
        send(.move(direction))
        repeatTask = Task { [weak self] in
            try? await Task.sleep(for: Self.repeatDelay)
            while !Task.isCancelled {
                self?.send(.move(direction))
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
    }

    private func send(_ command: TVCommand) {
        NSCursor.setHiddenUntilMouseMoves(true)
        onCommand(command)
    }
}

/// The keyboard equivalents of the controller buttons.
enum TVKeyMap {
    enum Key: UInt16 {
        case `return` = 36, tab = 48, space = 49, delete = 51, escape = 53, enter = 76
        case forwardDelete = 117, left = 123, right = 124, down = 125, up = 126
    }

    /// The command for a key press, or nil to let the system handle it.
    /// While searching, letters, digits and spaces type and Return closes the keyboard.
    static func command(keyCode: UInt16, characters: String?, searching: Bool) -> TVCommand? {
        switch Key(rawValue: keyCode) {
        case .left: return .move(.left)
        case .right: return .move(.right)
        case .up: return .move(.up)
        case .down: return .move(.down)
        case .return, .enter: return searching ? .search : .select
        case .escape: return .back
        case .delete, .forwardDelete: return searching ? .deleteBackward : nil
        case .space: return searching ? .type(" ") : .options
        case .tab: return searching ? nil : .options
        case nil: break
        }
        guard let characters, characters.count == 1, let character = characters.first else { return nil }
        if searching {
            return character.isLetter || character.isNumber ? .type(String(character)) : nil
        }
        switch character.lowercased() {
        case "f": return .favorite
        case "/", "s": return .search
        default: return nil
        }
    }
}
