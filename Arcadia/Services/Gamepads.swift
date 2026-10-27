import Foundation

/// A connected game controller as SDL, and therefore most emulators, sees it.
struct Gamepad {
    /// SDL's gamepad name, e.g. "PS5 Controller". Dolphin and RPCS3 identify devices by it.
    let name: String
    /// SDL's joystick GUID string; Cemu identifies devices by it.
    let guid: String
    /// The raw joystick input behind each standard gamepad button and axis, for emulators
    /// (melonDS) that bind raw joystick inputs.
    let buttons: [SDL_GamepadButton: RawInput]
    let axes: [SDL_GamepadAxis: RawInput]

    enum RawInput: Equatable {
        case button(Int)
        case axis(Int)
        case hat(Int, mask: Int)
    }
}

extension SDL_GamepadButton: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

extension SDL_GamepadAxis: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

enum Gamepads {
    /// Reads connected controllers, then releases them so the emulator can take over.
    @MainActor
    static func connected() async -> [Gamepad] {
        guard SDL_InitSubSystem(SDL_INIT_GAMEPAD) else { return [] }
        defer { SDL_QuitSubSystem(SDL_INIT_GAMEPAD) }

        // Bluetooth and HID controllers are discovered over the first few hundred milliseconds.
        for _ in 0..<8 {
            SDL_UpdateGamepads()
            try? await Task.sleep(for: .milliseconds(50))
        }

        var count: Int32 = 0
        guard let ids = SDL_GetGamepads(&count) else { return [] }
        defer { SDL_free(ids) }

        return (0..<Int(count)).compactMap { index in
            let id = ids[index]
            let name = SDL_GetGamepadNameForID(id).map { String(cString: $0) } ?? "Gamepad"
            var guid = [CChar](repeating: 0, count: 33)
            SDL_GUIDToString(SDL_GetJoystickGUIDForID(id), &guid, Int32(guid.count))

            var buttons: [SDL_GamepadButton: Gamepad.RawInput] = [:]
            var axes: [SDL_GamepadAxis: Gamepad.RawInput] = [:]
            if let pad = SDL_OpenGamepad(id) {
                var bindingCount: Int32 = 0
                if let bindings = SDL_GetGamepadBindings(pad, &bindingCount) {
                    for i in 0..<Int(bindingCount) {
                        guard let binding = bindings[i]?.pointee else { continue }
                        let input: Gamepad.RawInput? = switch binding.input_type {
                        case SDL_GAMEPAD_BINDTYPE_BUTTON: .button(Int(binding.input.button))
                        case SDL_GAMEPAD_BINDTYPE_AXIS: .axis(Int(binding.input.axis.axis))
                        case SDL_GAMEPAD_BINDTYPE_HAT: .hat(Int(binding.input.hat.hat), mask: Int(binding.input.hat.hat_mask))
                        default: nil
                        }
                        guard let input else { continue }
                        if binding.output_type == SDL_GAMEPAD_BINDTYPE_BUTTON {
                            buttons[binding.output.button] = input
                        } else if binding.output_type == SDL_GAMEPAD_BINDTYPE_AXIS {
                            axes[binding.output.axis.axis] = input
                        }
                    }
                    SDL_free(bindings)
                }
                SDL_CloseGamepad(pad)
            }
            return Gamepad(name: name, guid: String(cString: guid), buttons: buttons, axes: axes)
        }
    }
}
