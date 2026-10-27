import Foundation

/// Controller mappings for emulators that bind one specific device by name or GUID
/// (Dolphin, Cemu, RPCS3) or by raw joystick numbers (melonDS). Player 1 gets the first
/// connected controller; without one, each emulator keeps its keyboard defaults.
extension Presets {
    // MARK: Dolphin

    /// Dolphin's own "SDL Gamepad" profile, used if the installed Dolphin lacks it.
    private static let dolphinGameCubeProfile: [(String, String)] = [
        ("Buttons/A", "`Button A`"), ("Buttons/B", "`Button B`"), ("Buttons/X", "`Button X`"),
        ("Buttons/Y", "`Button Y`"), ("Buttons/Z", "`Shoulder R`"), ("Buttons/Start", "`Start`"),
        ("Main Stick/Up", "`Left Y+`"), ("Main Stick/Down", "`Left Y-`"),
        ("Main Stick/Left", "`Left X-`"), ("Main Stick/Right", "`Left X+`"), ("Main Stick/Calibration", "100.00"),
        ("C-Stick/Up", "`Right Y+`"), ("C-Stick/Down", "`Right Y-`"),
        ("C-Stick/Left", "`Right X-`"), ("C-Stick/Right", "`Right X+`"), ("C-Stick/Calibration", "100.00"),
        ("Triggers/L", "`Trigger L`"), ("Triggers/R", "`Trigger R`"),
        ("Triggers/L-Analog", "`Trigger L`"), ("Triggers/R-Analog", "`Trigger R`"),
        ("D-Pad/Up", "`Pad N`"), ("D-Pad/Down", "`Pad S`"), ("D-Pad/Left", "`Pad W`"), ("D-Pad/Right", "`Pad E`"),
        ("Rumble/Motor", "`Motor L` | `Motor R`"),
    ]

    /// A Wii Remote with Nunchuk on a gamepad: right stick points, left stick is the Nunchuk.
    private static let dolphinWiimote: [(String, String)] = [
        ("Source", "1"), ("Extension", "Nunchuk"),
        ("Buttons/A", "`Button A`"), ("Buttons/B", "`Trigger R`"), ("Buttons/1", "`Button X`"),
        ("Buttons/2", "`Button Y`"), ("Buttons/-", "`Back`"), ("Buttons/+", "`Start`"), ("Buttons/Home", "`Guide`"),
        ("D-Pad/Up", "`Pad N`"), ("D-Pad/Down", "`Pad S`"), ("D-Pad/Left", "`Pad W`"), ("D-Pad/Right", "`Pad E`"),
        ("IR/Up", "`Right Y+`"), ("IR/Down", "`Right Y-`"), ("IR/Left", "`Right X-`"), ("IR/Right", "`Right X+`"),
        ("Shake/X", "`Button B`"), ("Shake/Y", "`Button B`"), ("Shake/Z", "`Button B`"),
        ("Nunchuk/Buttons/C", "`Shoulder L`"), ("Nunchuk/Buttons/Z", "`Trigger L`"),
        ("Nunchuk/Stick/Up", "`Left Y+`"), ("Nunchuk/Stick/Down", "`Left Y-`"),
        ("Nunchuk/Stick/Left", "`Left X-`"), ("Nunchuk/Stick/Right", "`Left X+`"),
        ("Rumble/Motor", "`Motor L` | `Motor R`"),
    ]

    static func dolphinControllers(_ context: PresetContext, config: URL) throws {
        let files = ["GCPadNew.ini", "WiimoteNew.ini", "Hotkeys.ini"].map { config.appendingPathComponent($0) }
        guard let pad = context.gamepads.first else {
            // Missing files make Dolphin fall back to its keyboard defaults.
            for file in files { try? FileManager.default.removeItem(at: file) }
            return
        }
        // Dolphin names SDL devices "SDL/<index among same-named devices>/<SDL gamepad name>".
        let device = ("Device", "SDL/0/\(pad.name)")

        let bundled = context.install.appendingPathComponent("Contents/Resources/Sys/Profiles/GCPad/SDL Gamepad.ini")
        var gameCube = dolphinGameCubeProfile
        if let text = try? String(contentsOf: bundled, encoding: .utf8) {
            let lines = text.components(separatedBy: .newlines).compactMap { line -> (String, String)? in
                guard let equals = line.firstIndex(of: "="), !line.hasPrefix("[") else { return nil }
                return (line[..<equals].trimmingCharacters(in: .whitespaces),
                        line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces))
            }
            if !lines.isEmpty { gameCube = lines }
        }

        try INIFile.update(files[0]) { $0.replaceSection("GCPad1", with: [device] + gameCube) }
        try INIFile.update(files[1]) { $0.replaceSection("Wiimote1", with: [device] + dolphinWiimote) }
        // Select + Start stops the game, which quits Dolphin in batch mode.
        try INIFile.update(files[2]) { $0.replaceSection("Hotkeys", with: [device, ("General/Stop", "`Back` & `Start`")]) }
    }

    // MARK: Cemu

    /// Wii U GamePad buttons (Cemu mapping IDs) to SDL gamepad button IDs as Cemu reads them.
    private static let cemuMappings: [(Int, Int)] = [
        (1, 1), (2, 0), (3, 3), (4, 2), (5, 9), (6, 10), (7, 42), (8, 43), (9, 6), (10, 4),
        (11, 11), (12, 12), (13, 13), (14, 14), (15, 7), (16, 8),
        (17, 45), (18, 39), (19, 44), (20, 38), (21, 47), (22, 41), (23, 46), (24, 40), (27, 5),
    ]

    static func cemuControllers(_ context: PresetContext) throws {
        guard let pad = context.gamepads.first else { return }
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let range = "<deadzone>0.25</deadzone><range>1</range>"
        let mappings = cemuMappings.map { "<entry><mapping>\($0.0)</mapping><button>\($0.1)</button></entry>" }.joined()
        // Cemu identifies SDL controllers as "<index among same-GUID devices>_<GUID>".
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <emulated_controller>
        <type>Wii U GamePad</type>
        <toggle_display>0</toggle_display>
        <controller>
        <api>SDLController</api>
        <uuid>0_\(pad.guid)</uuid>
        <display_name>\(escaped(pad.name))</display_name>
        <rumble>0</rumble>
        <axis>\(range)</axis>
        <rotation>\(range)</rotation>
        <trigger>\(range)</trigger>
        <mappings>\(mappings)</mappings>
        </controller>
        </emulated_controller>

        """
        let file = applicationSupport.appendingPathComponent("Cemu/controllerProfiles/controller0.xml")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try xml.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: RPCS3

    /// RPCS3 fills in the SDL button layout itself once it knows the device.
    static func rpcs3Controllers(_ context: PresetContext, root: URL) throws {
        let file = root.appendingPathComponent("input_configs/global/Default.yml")
        guard let pad = context.gamepads.first else {
            try? FileManager.default.removeItem(at: file) // RPCS3 then uses the keyboard
            return
        }
        let name = pad.name.replacingOccurrences(of: "\"", with: "\\\"")
        let yaml = """
        Player 1 Input:
          Handler: SDL
          Device: "\(name) 1"

        """
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: melonDS

    /// melonDS binds raw SDL joystick inputs: a button or hat in the low 16 bits (0xFFFF for
    /// none) and optionally an axis as 0x10000 | axis << 24 | direction << 20.
    static func melonDSJoystick(_ pad: Gamepad?) -> [(String, Int)] {
        let names = ["A", "B", "X", "Y", "L", "R", "Select", "Start", "Up", "Down", "Left", "Right"]
        guard let pad else { return names.map { ($0, -1) } }

        func button(_ button: SDL_GamepadButton) -> Int {
            switch pad.buttons[button] {
            case .button(let index): index
            case .hat(let hat, let mask): 0x100 | (hat << 4) | mask
            default: 0xFFFF
            }
        }
        func stick(_ axis: SDL_GamepadAxis, negative: Bool) -> Int {
            guard case .axis(let index) = pad.axes[axis] else { return 0 }
            return 0x10000 | (index << 24) | ((negative ? 1 : 0) << 20)
        }
        func combined(_ code: Int, _ axis: Int) -> Int {
            code == 0xFFFF && axis == 0 ? -1 : code | axis
        }
        // Nintendo layout: A is the right face button, B the bottom one.
        let codes: [String: Int] = [
            "A": button(SDL_GAMEPAD_BUTTON_EAST), "B": button(SDL_GAMEPAD_BUTTON_SOUTH),
            "X": button(SDL_GAMEPAD_BUTTON_NORTH), "Y": button(SDL_GAMEPAD_BUTTON_WEST),
            "L": button(SDL_GAMEPAD_BUTTON_LEFT_SHOULDER), "R": button(SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER),
            "Select": button(SDL_GAMEPAD_BUTTON_BACK), "Start": button(SDL_GAMEPAD_BUTTON_START),
            "Up": combined(button(SDL_GAMEPAD_BUTTON_DPAD_UP), stick(SDL_GAMEPAD_AXIS_LEFTY, negative: true)),
            "Down": combined(button(SDL_GAMEPAD_BUTTON_DPAD_DOWN), stick(SDL_GAMEPAD_AXIS_LEFTY, negative: false)),
            "Left": combined(button(SDL_GAMEPAD_BUTTON_DPAD_LEFT), stick(SDL_GAMEPAD_AXIS_LEFTX, negative: true)),
            "Right": combined(button(SDL_GAMEPAD_BUTTON_DPAD_RIGHT), stick(SDL_GAMEPAD_AXIS_LEFTX, negative: false)),
        ]
        return names.map { ($0, codes[$0] == 0xFFFF ? -1 : codes[$0]!) }
    }
}
